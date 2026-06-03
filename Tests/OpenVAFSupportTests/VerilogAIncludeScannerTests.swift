import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("Verilog-A include scanner", .timeLimit(.minutes(1)))
struct VerilogAIncludeScannerTests {
    @Test("Scanner preserves comment markers inside quoted include paths")
    func scannerPreservesCommentMarkersInsideQuotedIncludePaths() throws {
        let sandbox = try TemporaryDirectory(name: "include-comment-markers")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        try """
`include "models//defs.inc"
`include "literal/*name*/.inc"
`include "escaped\\"quote.inc"
""".write(to: sourceURL, atomically: true, encoding: .utf8)

        let paths = try VerilogAIncludeScanner.includePaths(in: sourceURL)

        #expect(paths == [
            "models//defs.inc",
            "literal/*name*/.inc",
            "escaped\"quote.inc",
        ])
    }

    @Test("Scanner ignores include directives inside comments")
    func scannerIgnoresIncludeDirectivesInsideComments() throws {
        let sandbox = try TemporaryDirectory(name: "include-comments")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        try """
// `include "line-comment.inc"
/*
`include "block-comment.inc"
*/
`include "active.inc" // trailing comment
""".write(to: sourceURL, atomically: true, encoding: .utf8)

        let paths = try VerilogAIncludeScanner.includePaths(in: sourceURL)

        #expect(paths == ["active.inc"])
    }

    @Test("Scanner handles CRLF without duplicate include paths")
    func scannerHandlesCRLFWithoutDuplicateIncludePaths() throws {
        let sandbox = try TemporaryDirectory(name: "include-crlf")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        try Data("`include \"a.inc\"\r\n`include \"b.inc\"\r\n".utf8).write(to: sourceURL)

        let paths = try VerilogAIncludeScanner.includePaths(in: sourceURL)

        #expect(paths == ["a.inc", "b.inc"])
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
}
