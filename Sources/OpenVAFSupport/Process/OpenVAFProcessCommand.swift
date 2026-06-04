import Foundation

#if OpenVAFCLI

package struct OpenVAFProcessCommand: Sendable, Equatable {
    package let executableURL: URL
    package let arguments: [String]
    package let environment: [String: String]?
    package let workingDirectory: URL
    package let timeout: Duration
    package let terminationGrace: Duration

    package init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL,
        timeout: Duration,
        terminationGrace: Duration
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }
}

#endif
