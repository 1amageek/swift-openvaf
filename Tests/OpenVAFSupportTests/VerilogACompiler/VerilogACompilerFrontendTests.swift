import Foundation
import Testing
@testable import VerilogACompiler

#if VerilogACompiler

@Suite("VerilogACompilerFrontend", .timeLimit(.minutes(1)))
struct VerilogACompilerFrontendTests {
    @Test("Compiler frontend exposes in-process parsing backend")
    func compilerFrontendExposesInProcessParsingBackend() {
        let parser: any VerilogAParsing = VerilogACompilerFrontend()

        #expect(parser.implementation == .inProcess)
    }

    @Test("Parser extracts resistor module structure")
    func parserExtractsResistorModuleStructure() throws {
        let source = VerilogASourceBuffer(string: Self.resistorModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(result.modules.count == 1)
        #expect(module.name(in: result.source) == "resistor")
        #expect(module.portNames(in: result.source) == ["p", "n"])
        #expect(module.parameters.count == 1)
        #expect(module.declarations.count == 2)
        #expect(module.analogBlockRanges.count == 1)

        let parameter = try #require(module.parameters.first)
        #expect(result.source.string(in: parameter.nameRange) == "resistance")
        #expect(parameter.typeRange.map { result.source.string(in: $0) } == "real")
        #expect(parameter.valueRange.map { result.source.string(in: $0) } == "1.0")

        let declarationKinds = module.declarations.map(\.kind)
        #expect(declarationKinds == [.inoutPort, .electrical])
        #expect(module.declarations[0].nameRanges.map { result.source.string(in: $0) } == ["p", "n"])
        #expect(module.declarations[1].nameRanges.map { result.source.string(in: $0) } == ["p", "n"])

        let analogSource = result.source.string(in: module.analogBlockRanges[0])
        #expect(analogSource.contains("analog begin"))
        #expect(analogSource.contains("I(p, n)"))
    }

    @Test("Lexer stores token source ranges")
    func lexerStoresTokenSourceRanges() throws {
        let source = VerilogASourceBuffer(string: "module resistor; endmodule\n")
        var lexer = VerilogALexer(buffer: source)
        let result = lexer.lexAll()

        #expect(result.diagnostics.isEmpty)
        let identifier = try #require(result.tokens.first { token in
            token.kind == .identifier
        })

        #expect(identifier.range == VerilogASourceRange(lowerBound: 7, upperBound: 15))
        #expect(source.string(in: identifier.range) == "resistor")
    }

    @Test("Lexer handles comments, escaped identifiers, exponents, and escaped strings")
    func lexerHandlesCommonTokenForms() throws {
        let source = VerilogASourceBuffer(string: """
// line comment
module \\escaped.name ;
    parameter real gain = 1.0e-3;
    parameter real offset = .5E+2;
    parameter real scale_factor = 1_000.0;
    analog begin
        $display("value=\\\"%g\\\"", gain);
    end
endmodule
""")
        var lexer = VerilogALexer(buffer: source)
        let result = lexer.lexAll()

        #expect(result.diagnostics.isEmpty)
        #expect(lexemes(of: .identifier, in: result.tokens, source: source).contains("\\escaped.name"))
        #expect(lexemes(of: .number, in: result.tokens, source: source).contains("1.0e-3"))
        #expect(lexemes(of: .number, in: result.tokens, source: source).contains(".5E+2"))
        #expect(lexemes(of: .number, in: result.tokens, source: source).contains("1_000.0"))
        #expect(lexemes(of: .stringLiteral, in: result.tokens, source: source).contains("\"value=\\\"%g\\\"\""))
    }

    @Test("Lexer reports unterminated block comment")
    func lexerReportsUnterminatedBlockComment() throws {
        let source = VerilogASourceBuffer(string: "module broken; /* no terminator\nendmodule\n")
        var lexer = VerilogALexer(buffer: source)
        let result = lexer.lexAll()

        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Unterminated block comment")
    }

    @Test("Parser extracts inline port declarations and skips attributes")
    func parserExtractsInlinePortDeclarationsAndSkipsAttributes() throws {
        let source = VerilogASourceBuffer(string: Self.inlinePortModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.name(in: result.source) == "inline_ports")
        #expect(module.portNames(in: result.source) == ["out", "input_node", "reference"])
        let declarations = module.declarations
        #expect(declarations.map(\.kind) == [.output, .input, .inoutPort])
        if declarations.count == 3 {
            #expect(names(in: declarations[0], source: result.source) == ["out"])
            #expect(names(in: declarations[1], source: result.source) == ["input_node"])
            #expect(names(in: declarations[2], source: result.source) == ["reference"])
        }
    }

    @Test("Parser skips attributes whose names match Verilog-A keywords")
    func parserSkipsAttributesWhoseNamesMatchVerilogAKeywords() throws {
        let source = VerilogASourceBuffer(string: Self.keywordAttributeModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(result.modules.count == 1)
        #expect(module.name(in: result.source) == "keyword_attributes")
        #expect(module.parameters.map { result.source.string(in: $0.nameRange) } == ["gain"])
        #expect(module.declarations.map(\.kind) == [.real])
        #expect(names(in: module.declarations[0], source: result.source) == ["state"])

        let function = try #require(module.functions.first)
        #expect(function.name(in: result.source) == "scale")
        #expect(function.declarations.map(\.kind) == [.input, .real])
        #expect(names(in: function.declarations[0], source: result.source) == ["x"])
        #expect(names(in: function.declarations[1], source: result.source) == ["x"])
    }

    @Test("Parser skips attributes inside parameter declarators")
    func parserSkipsAttributesInsideParameterDeclarators() throws {
        let source = VerilogASourceBuffer(string: Self.parameterAttributeModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.parameters.map { result.source.string(in: $0.nameRange) } == [
            "gain",
            "offset",
        ])
        #expect(module.parameters.map { $0.typeRange.map { result.source.string(in: $0) } } == [
            "real",
            "real",
        ])
        #expect(module.parameters.map { $0.valueRange.map { result.source.string(in: $0) } } == [
            "1.0",
            "2.0",
        ])
    }

    @Test("Parser extracts declarator names without qualifier special cases")
    func parserExtractsDeclaratorNamesWithoutQualifierSpecialCases() throws {
        let source = VerilogASourceBuffer(string: Self.qualifiedDeclarationsModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.portNames(in: result.source) == ["bus", "reference", "branch_name"])
        #expect(module.declarations.map(\.kind) == [
            .inoutPort,
            .inoutPort,
            .inoutPort,
            .electrical,
            .electrical,
            .electrical,
        ])
        #expect(module.declarations.count == 6)
        if module.declarations.count == 6 {
            #expect(names(in: module.declarations[0], source: result.source) == ["reference"])
            #expect(names(in: module.declarations[1], source: result.source) == ["bulk"])
            #expect(names(in: module.declarations[2], source: result.source) == ["reference"])
            #expect(names(in: module.declarations[3], source: result.source) == ["sense"])
            #expect(names(in: module.declarations[4], source: result.source) == ["bus"])
            #expect(names(in: module.declarations[5], source: result.source) == ["branch_name"])
        }
    }

    @Test("Parser captures nested analog block range")
    func parserCapturesNestedAnalogBlockRange() throws {
        let source = VerilogASourceBuffer(string: Self.nestedAnalogModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        let analogRange = try #require(module.analogBlockRanges.first)
        let analogSource = result.source.string(in: analogRange)

        #expect(analogSource.contains("analog begin"))
        #expect(analogSource.contains("begin"))
        #expect(analogSource.contains("if"))
        #expect(analogSource.hasSuffix("end"))
    }

    @Test("Parser extracts analog functions and variable declarations")
    func parserExtractsAnalogFunctionsAndVariableDeclarations() throws {
        let source = VerilogASourceBuffer(string: Self.functionAndVariableModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.declarations.count == 4)
        #expect(module.declarations.map(\.kind) == [.real, .integer, .integer, .string])
        #expect(names(in: module.declarations[0], source: result.source) == ["voltage"])
        #expect(names(in: module.declarations[1], source: result.source) == ["mode", "nextMode"])
        #expect(names(in: module.declarations[2], source: result.source) == ["compactMode"])
        #expect(names(in: module.declarations[3], source: result.source) == ["label"])

        let function = try #require(module.functions.first)
        #expect(module.functions.count == 1)
        #expect(function.name(in: result.source) == "gain")
        #expect(function.returnTypeRange.map { result.source.string(in: $0) } == "real")
        #expect(function.declarations.map(\.kind) == [.input, .output, .real, .integer])
        #expect(names(in: function.declarations[0], source: result.source) == ["x", "scale"])
        #expect(names(in: function.declarations[1], source: result.source) == ["y"])
        #expect(names(in: function.declarations[2], source: result.source) == ["x", "scale", "y"])
        #expect(names(in: function.declarations[3], source: result.source) == ["iterations"])
    }

    @Test("Parser extracts parameter declarators without constraint text in values")
    func parserExtractsParameterDeclaratorsWithoutConstraintTextInValues() throws {
        let source = VerilogASourceBuffer(string: Self.parameterConstraintModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.parameters.map { result.source.string(in: $0.nameRange) } == [
            "gain",
            "offset",
            "mode",
            "nextMode",
        ])
        #expect(module.parameters.map { $0.valueRange.map { result.source.string(in: $0) } } == [
            "1.0",
            "$simparam(\"offset\", 2m)",
            "1",
            "2",
        ])
    }

    @Test("Parser extracts dimensioned parameter declarators")
    func parserExtractsDimensionedParameterDeclarators() throws {
        let source = VerilogASourceBuffer(string: Self.dimensionedParameterModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.parameters.map { result.source.string(in: $0.nameRange) } == [
            "coefficients",
            "matrix",
            "mode",
        ])
        #expect(module.parameters.map { $0.typeRange.map { result.source.string(in: $0) } } == [
            "real",
            "real",
            "integer",
        ])
        #expect(module.parameters.map { $0.valueRange.map { result.source.string(in: $0) } } == [
            "1.0",
            "$simparam(\"matrix\", 2m)",
            "1",
        ])
    }

    @Test("Parser keeps brace expression commas inside parameter values")
    func parserKeepsBraceExpressionCommasInsideParameterValues() throws {
        let source = VerilogASourceBuffer(string: Self.braceParameterValueModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.parameters.map { result.source.string(in: $0.nameRange) } == [
            "pair",
            "nested",
            "next",
        ])
        #expect(module.parameters.map { $0.valueRange.map { result.source.string(in: $0) } } == [
            "{1, 2}",
            "{{1, 2}, {3, 4}}",
            "3",
        ])
    }

    @Test("Parser ignores inactive preprocessor conditional declarations")
    func parserIgnoresInactivePreprocessorConditionalDeclarations() throws {
        let source = VerilogASourceBuffer(string: Self.preprocessorConditionalModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.name(in: result.source) == "preprocessor_conditionals")
        #expect(module.parameters.map { result.source.string(in: $0.nameRange) } == [
            "activeParameter",
        ])
        #expect(module.declarations.map(\.kind) == [
            .real,
            .integer,
        ])
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["shown"],
            ["missingDefault"],
        ])
    }

    @Test("Parser ignores inactive preprocessor module boundaries")
    func parserIgnoresInactivePreprocessorModuleBoundaries() throws {
        let source = VerilogASourceBuffer(string: Self.inactivePreprocessorModuleBoundaryModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["kept"])
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
    }

    @Test("Preprocessor treats comments before directives as whitespace")
    func preprocessorTreatsCommentsBeforeDirectivesAsWhitespace() throws {
        let source = VerilogASourceBuffer(string: Self.commentPrefixedConditionalModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
    }

    @Test("Preprocessor handles UTF-8 byte order mark before first directive")
    func preprocessorHandlesUTF8ByteOrderMarkBeforeFirstDirective() throws {
        let source = VerilogASourceBuffer(string: Self.byteOrderMarkedConditionalModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
    }

    @Test("Preprocessor preserves line-start macro invocations")
    func preprocessorPreservesLineStartMacroInvocations() throws {
        let source = VerilogASourceBuffer(string: Self.lineStartMacroInvocationModel)
        var lexer = VerilogALexer(buffer: source)
        let lexed = lexer.lexAll()
        var preprocessor = VerilogAPreprocessor(buffer: source, tokens: lexed.tokens)
        let result = preprocessor.process()

        #expect(result.diagnostics.isEmpty)
        let lexemes = result.tokens.map { source.string(in: $0.range) }
        #expect(lexemes.contains("MODEL_STATEMENT"))
        #expect(lexemes.contains("UNKNOWN_DECL"))
        #expect(!lexemes.contains("include"))
        #expect(!lexemes.contains("\"defs.vams\""))
        #expect(!lexemes.contains("define"))
    }

    @Test("Preprocessor consumes continued directive bodies")
    func preprocessorConsumesContinuedDirectiveBodies() throws {
        let source = VerilogASourceBuffer(string: Self.continuedDirectiveBodyModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["continued_directive"])
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
    }

    @Test("Parser treats line-start macro invocations as opaque lines")
    func parserTreatsLineStartMacroInvocationsAsOpaqueLines() throws {
        let source = VerilogASourceBuffer(string: Self.opaqueMacroInvocationModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["macro_invocation_boundary"])
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
        let analogSource = result.source.string(in: try #require(module.analogBlockRanges.first))
        #expect(analogSource.contains("MODEL_ANALOG"))
        #expect(analogSource.contains("I(visible)"))
    }

    @Test("Parser treats multiline line-start macro invocations as opaque")
    func parserTreatsMultilineLineStartMacroInvocationsAsOpaque() throws {
        let source = VerilogASourceBuffer(string: Self.multilineOpaqueMacroInvocationModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["multiline_macro_invocation"])
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
        let analogSource = result.source.string(in: try #require(module.analogBlockRanges.first))
        #expect(analogSource.contains("MODEL_ANALOG"))
        #expect(analogSource.contains("I(visible)"))
    }

    @Test("Parser bounds recovery for unterminated line-start macro invocations")
    func parserBoundsRecoveryForUnterminatedLineStartMacroInvocations() throws {
        let source = VerilogASourceBuffer(string: Self.unterminatedOpaqueMacroInvocationModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["unterminated_macro_invocation"])
        let module = try #require(result.modules.first)
        #expect(module.declarations.map { names(in: $0, source: result.source) } == [
            ["visible"],
        ])
        let analogSource = result.source.string(in: try #require(module.analogBlockRanges.first))
        #expect(analogSource.contains("I(visible)"))
        #expect(analogSource.hasSuffix("end"))
    }

    @Test("Parser treats comment-prefixed line-start macro invocations as opaque")
    func parserTreatsCommentPrefixedLineStartMacroInvocationsAsOpaque() throws {
        let source = VerilogASourceBuffer(string: Self.commentPrefixedOpaqueMacroInvocationModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["comment_prefixed_macro"])
        let module = try #require(result.modules.first)
        let analogSource = result.source.string(in: try #require(module.analogBlockRanges.first))
        #expect(analogSource.contains("MODEL_ANALOG"))
        #expect(analogSource.contains("I(visible)"))
    }

    @Test("Parser keeps syntax that follows an object-like line-start macro")
    func parserKeepsSyntaxThatFollowsObjectLikeLineStartMacro() throws {
        let source = VerilogASourceBuffer(string: Self.objectLikeMacroPrefixModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["object_like_macro_prefix"])
        let module = try #require(result.modules.first)
        let analogSource = result.source.string(in: try #require(module.analogBlockRanges.first))
        #expect(analogSource.contains("I(visible) <+ 1"))
        #expect(analogSource.contains("I(visible) <+ 2"))
    }

    @Test("Parser captures analog initial and analog case ranges")
    func parserCapturesAnalogInitialAndAnalogCaseRanges() throws {
        let source = VerilogASourceBuffer(string: Self.analogInitialAndCaseModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.analogBlockRanges.count == 2)

        let analogSources = module.analogBlockRanges.map { result.source.string(in: $0) }
        #expect(analogSources[0].contains("analog initial begin"))
        #expect(analogSources[0].hasSuffix("end"))
        #expect(analogSources[1].contains("analog case"))
        #expect(analogSources[1].hasSuffix("endcase"))
    }

    @Test("Parser captures compound analog statement ranges")
    func parserCapturesCompoundAnalogStatementRanges() throws {
        let source = VerilogASourceBuffer(string: Self.compoundAnalogStatementModel)
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.analogBlockRanges.count == 1)

        let analogSource = result.source.string(in: try #require(module.analogBlockRanges.first))
        #expect(analogSource.contains("analog if"))
        #expect(analogSource.contains("I(out) <+ 1"))
        #expect(analogSource.contains("I(out) <+ 2"))
        #expect(analogSource.contains("I(out) <+ 3"))
        #expect(analogSource.hasSuffix("end"))
    }

    @Test("Parser reads multiple modules")
    func parserReadsMultipleModules() throws {
        let source = VerilogASourceBuffer(string: """
module first(a);
    input a;
endmodule

module second(p, n);
    inout p, n;
    electrical p, n;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)

        #expect(result.diagnostics.isEmpty)
        #expect(result.modules.map { $0.name(in: result.source) } == ["first", "second"])
        #expect(result.modules[0].portNames(in: result.source) == ["a"])
        #expect(result.modules[1].portNames(in: result.source) == ["p", "n"])
    }

    @Test("Parser reports missing endmodule")
    func parserReportsMissingEndmodule() throws {
        let source = VerilogASourceBuffer(string: "module missing;\n")
        let result = VerilogACompilerFrontend().parse(source)

        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected 'endmodule'")
    }

    @Test("Parser reports missing module name")
    func parserReportsMissingModuleName() throws {
        let source = VerilogASourceBuffer(string: "module ; endmodule\n")
        let result = VerilogACompilerFrontend().parse(source)

        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected module name")
    }

    @Test("Parser reports missing parameter name once")
    func parserReportsMissingParameterNameOnce() throws {
        let source = VerilogASourceBuffer(string: "module broken; parameter real = 1; endmodule\n")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected parameter name"])
    }

    @Test("Parser reports missing parameter default value")
    func parserReportsMissingParameterDefaultValue() throws {
        let source = VerilogASourceBuffer(string: "module broken; parameter real gain = ; endmodule\n")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected parameter default value"])
    }

    @Test("Parser reports unterminated attributes")
    func parserReportsUnterminatedAttributes() throws {
        let source = VerilogASourceBuffer(string: "module broken; (* parameter = 1\n")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages.contains("Expected '*)' to close attribute"))
        #expect(messages.contains("Expected 'endmodule'"))
    }

    @Test("Parser reports unterminated analog block")
    func parserReportsUnterminatedAnalogBlock() throws {
        let source = VerilogASourceBuffer(string: """
module broken(p, n);
    inout p, n;
    electrical p, n;
    analog begin
        I(p, n) <+ 0.0;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)

        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected 'end' for analog block")
    }

    @Test("Parser recovers at module boundary after unterminated analog block")
    func parserRecoversAtModuleBoundaryAfterUnterminatedAnalogBlock() throws {
        let source = VerilogASourceBuffer(string: """
module broken;
    analog begin
        value = 1;
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected 'end' for analog block"])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
    }

    @Test("Parser recovers at module boundary after unterminated analog function")
    func parserRecoversAtModuleBoundaryAfterUnterminatedAnalogFunction() throws {
        let source = VerilogASourceBuffer(string: """
module broken;
    analog function real gain;
        input x;
        real x;
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected 'endfunction'"])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
        #expect(result.modules.first?.functions.map { $0.name(in: result.source) } == ["gain"])
    }

    @Test("Parser recovers at module boundary after unterminated analog case")
    func parserRecoversAtModuleBoundaryAfterUnterminatedAnalogCase() throws {
        let source = VerilogASourceBuffer(string: """
module broken;
    analog case (mode)
        0: value = 1;
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected 'endcase' for analog case statement"])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
    }

    @Test("Parser recovers at module boundary after parameter missing semicolon")
    func parserRecoversAtModuleBoundaryAfterParameterMissingSemicolon() throws {
        let source = VerilogASourceBuffer(string: """
module broken;
    parameter real gain = 1.0
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected ';' after parameter declaration"])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
        #expect(result.modules.first?.parameters.map { result.source.string(in: $0.nameRange) } == ["gain"])
    }

    @Test("Parser recovers at module boundary after declaration missing semicolon")
    func parserRecoversAtModuleBoundaryAfterDeclarationMissingSemicolon() throws {
        let source = VerilogASourceBuffer(string: """
module broken;
    electrical p
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected ';' after declaration"])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
        #expect(result.modules.first?.declarations.first.map { names(in: $0, source: result.source) } == ["p"])
    }

    @Test("Parser recovers at semicolon after unterminated declarator range")
    func parserRecoversAtSemicolonAfterUnterminatedDeclaratorRange() throws {
        let source = VerilogASourceBuffer(string: """
module broken;
    parameter real coefficients[0:2 = 1.0;
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == ["Expected closing delimiter before declarator terminator"])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
        #expect(result.modules.first?.parameters.map { result.source.string(in: $0.nameRange) } == ["coefficients"])
    }

    @Test("Parser recovers module header at semicolon after unterminated port range")
    func parserRecoversModuleHeaderAtSemicolonAfterUnterminatedPortRange() throws {
        let source = VerilogASourceBuffer(string: """
module broken(input electrical bus[0:1;
endmodule

module recovered;
endmodule
""")
        let result = VerilogACompilerFrontend().parse(source)
        let messages = result.diagnostics.map(\.message)

        #expect(messages == [
            "Expected closing delimiter before declarator terminator",
            "Expected ')' after module port list",
        ])
        #expect(result.modules.map { $0.name(in: result.source) } == ["broken", "recovered"])
    }

    @Test("Lexer reports unterminated string literal")
    func lexerReportsUnterminatedStringLiteral() throws {
        let source = VerilogASourceBuffer(string: "`include \"unterminated.inc\nmodule model; endmodule\n")
        var lexer = VerilogALexer(buffer: source)
        let result = lexer.lexAll()

        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Unterminated string literal")
    }

    @Test("Parser reads source from file")
    func parserReadsSourceFromFile() async throws {
        let sandbox = try TemporaryDirectory(name: "swift-openvaf-parser-file")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("resistor.va")
        try Data(Self.resistorModel.utf8).write(to: sourceURL)

        let result = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)

        #expect(result.source.sourceURL == sourceURL)
        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        #expect(module.name(in: result.source) == "resistor")
    }

    @Test("Parser rejects non-file source URLs before reading")
    func parserRejectsNonFileSourceURLsBeforeReading() throws {
        let sourceURL = URL(string: "https://example.com/model.va")!

        #expect(throws: VerilogASourceError.invalidSourceURL(
            operation: "validate source",
            path: sourceURL.absoluteString,
            message: "URL must use the file scheme"
        )) {
            _ = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)
        }
    }

    @Test("Parser rejects non-local file source URL hosts before reading")
    func parserRejectsNonLocalFileSourceURLHostsBeforeReading() throws {
        let sourceURL = URL(string: "file://example.com/tmp/model.va")!

        #expect(throws: VerilogASourceError.invalidSourceURL(
            operation: "validate source",
            path: sourceURL.absoluteString,
            message: "File URL host must be empty or localhost"
        )) {
            _ = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)
        }
    }

    @Test("Parser rejects source paths containing NUL before reading")
    func parserRejectsSourcePathsContainingNULBeforeReading() throws {
        let sourceURL = URL(string: "file:///tmp/model%00.va")!

        #expect(throws: VerilogASourceError.invalidSourceURL(
            operation: "validate source",
            path: sourceURL.path(percentEncoded: true),
            message: "File URL path must not contain NUL"
        )) {
            _ = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)
        }
    }

    private static let resistorModel = """
`include "disciplines.vams"

module resistor(p, n);
    inout p, n;
    electrical p, n;

    parameter real resistance = 1.0;

    analog begin
        I(p, n) <+ V(p, n) / resistance;
    end
endmodule
"""

    private static let inlinePortModel = """
module inline_ports(output out, input electrical input_node, (* kept = "yes" *) inout electrical ground reference);
    parameter real gain = 1.0;
    analog begin
        I(out, reference) <+ gain * V(input_node, reference);
    end
endmodule
"""

    private static let keywordAttributeModel = """
(* module = "ignored" *) module keyword_attributes;
    (* parameter = "ignored" *) parameter real gain = 1.0;
    (* real = "ignored" *) real state;

    (* analog = "ignored" *) analog function real scale;
        (* input = "ignored" *) input x;
        (* real = "ignored" *) real x;
        begin
            scale = x * gain;
        end
    endfunction
endmodule
"""

    private static let parameterAttributeModel = """
module parameter_attributes;
    parameter (* category = "numeric" *) real (* units = "V" *) gain (* label = "primary" *) = 1.0 from [0:inf],
        (* category = "numeric" *) offset = 2.0 exclude 0;
endmodule
"""

    private static let qualifiedDeclarationsModel = """
module qualified(bus[upper:lower], inout electrical ground reference, branch (p, n) branch_name);
    inout ground bulk;
    inout electrical ground reference = fallback;
    electrical sense;
    electrical bus[upper:lower];
    electrical branch (p, n) branch_name;
endmodule
"""

    private static let nestedAnalogModel = """
module nested_analog(p, n);
    inout p, n;
    electrical p, n;
    parameter real resistance = 1.0;
    analog begin
        begin
            if (resistance > 0.0) begin
                I(p, n) <+ V(p, n) / resistance;
            end
        end
    end
endmodule
"""

    private static let functionAndVariableModel = """
module function_and_variables;
    real voltage = 1.0;
    integer mode = 0, nextMode;
    int compactMode;
    string label;

    analog function real gain;
        input x, scale;
        output y;
        real x, scale, y;
        integer iterations;
        begin
            gain = x * scale;
        end
    endfunction
endmodule
"""

    private static let analogInitialAndCaseModel = """
module analog_initial_and_case;
    parameter integer mode = 0;
    real value;

    analog initial begin
        value = 0;
    end

    analog case (mode)
        0: value = 1;
        default: begin
            value = 2;
        end
    endcase
endmodule
"""

    private static let compoundAnalogStatementModel = """
module compound_analog_statement;
    real out;

    analog if (out > 0) begin
        I(out) <+ 1;
        I(out) <+ 2;
    end else begin
        I(out) <+ 3;
    end
endmodule
"""

private static let parameterConstraintModel = """
module parameter_constraints;
    parameter real gain = 1.0 from [0:inf], offset = $simparam("offset", 2m) exclude 0;
    parameter integer mode = 1, nextMode = 2;
endmodule
"""

    private static let dimensionedParameterModel = """
module dimensioned_parameters;
    parameter real coefficients[0:2] = 1.0 from [0:inf],
        matrix[0:1][0:1] = $simparam("matrix", 2m) exclude 0;
    parameter integer mode[3:0] = 1;
endmodule
"""

    private static let braceParameterValueModel = """
module brace_parameter_values;
    parameter real pair = {1, 2}, nested = {{1, 2}, {3, 4}}, next = 3;
endmodule
"""

    private static let preprocessorConditionalModel = """
module preprocessor_conditionals;
`ifdef OPVARS
    real hidden;
`else
    real shown;
`endif
`define ENABLED
`ifdef ENABLED
    parameter real activeParameter = 1.0;
`endif
`ifndef MISSING
    integer missingDefault;
`endif
endmodule
"""

    private static let inactivePreprocessorModuleBoundaryModel = """
module kept;
`ifdef DISABLED
endmodule
module ghost;
    real hidden;
endmodule
`endif
    real visible;
endmodule
"""

    private static let commentPrefixedConditionalModel = """
module comment_prefixed_conditional;
    real visible;
/* guard */ `ifdef HIDDEN
    real hidden;
`endif
endmodule
"""

    private static let byteOrderMarkedConditionalModel = "\u{FEFF}" + """
`define ENABLED
module byte_order_marked_conditional;
`ifdef ENABLED
    real visible;
`else
    real hidden;
`endif
endmodule
"""

    private static let lineStartMacroInvocationModel = """
`define MODEL_GAIN 1
`MODEL_STATEMENT
`include "defs.vams"
module line_start_macro;
`UNKNOWN_DECL
endmodule
"""

    private static let continuedDirectiveBodyModel = #"""
`define MODEL_BODY \
endmodule \
module ghost;
module continued_directive;
    real visible;
endmodule
"""#

    private static let opaqueMacroInvocationModel = """
module macro_invocation_boundary;
`MODEL_DECL(endmodule, begin, end)
    real visible;
    analog begin
`MODEL_ANALOG(end, endmodule)
        I(visible) <+ 1;
    end
endmodule
"""

    private static let commentPrefixedOpaqueMacroInvocationModel = """
module comment_prefixed_macro;
    real visible;
    analog begin
/* generated */ `MODEL_ANALOG(
    end,
    endmodule
)
        I(visible) <+ 1;
    end
endmodule
"""

    private static let objectLikeMacroPrefixModel = """
module object_like_macro_prefix;
    real visible;
    analog begin
`MODEL begin
        I(visible) <+ 1;
    end
        I(visible) <+ 2;
    end
endmodule
"""

    private static let multilineOpaqueMacroInvocationModel = """
module multiline_macro_invocation;
`MODEL_DECL(
    endmodule,
    begin,
    end
)
    real visible;
    analog begin
`MODEL_ANALOG(
    end,
    endmodule
)
        I(visible) <+ 1;
    end
endmodule
"""

    private static let unterminatedOpaqueMacroInvocationModel = """
module unterminated_macro_invocation;
`MODEL_DECL(endmodule, begin
    real visible;
    analog begin
`MODEL_ANALOG(end, endmodule
        I(visible) <+ 1;
    end
endmodule
"""
}

private func lexemes(
    of kind: VerilogATokenKind,
    in tokens: [VerilogAToken],
    source: VerilogASourceBuffer
) -> [String] {
    tokens.compactMap { token in
        token.kind == kind ? source.string(in: token.range) : nil
    }
}

private func names(
    in declaration: VerilogADeclaration,
    source: VerilogASourceBuffer
) -> [String] {
    declaration.nameRanges.map { source.string(in: $0) }
}

private struct TemporaryDirectory {
    let url: URL

    init(name: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenVAFSupportTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Issue.record("Failed to remove temporary directory \(url.path): \(error)")
        }
    }
}

#endif
