import Foundation

/// Request to compile one Verilog-A source file into one OSDI library.
public struct OpenVAFCompilationRequest: Sendable, Equatable {
    public let sourceURL: URL
    public let outputDirectory: URL
    public let outputFileName: String?
    public let includeRootDirectory: URL?

    public init(
        sourceURL: URL,
        outputDirectory: URL,
        outputFileName: String? = nil,
        includeRootDirectory: URL? = nil
    ) {
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.outputFileName = outputFileName
        self.includeRootDirectory = includeRootDirectory
    }
}
