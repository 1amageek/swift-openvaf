import Foundation

/// Runtime configuration for invoking OpenVAF.
public struct OpenVAFConfiguration: Sendable {
    public var executable: OpenVAFExecutable
    public var compileTimeout: Duration
    public var availabilityTimeout: Duration
    public var terminationGrace: Duration
    public var processEnvironment: [String: String]?
    public var compilerArguments: [String]
    public var keepsFailedWorkingDirectories: Bool

    public init(
        executable: OpenVAFExecutable = .environment(variable: "OPENVAF_BIN", fallbackName: "openvaf"),
        compileTimeout: Duration = .seconds(300),
        availabilityTimeout: Duration = .seconds(10),
        terminationGrace: Duration = .seconds(2),
        processEnvironment: [String: String]? = nil,
        compilerArguments: [String] = [],
        keepsFailedWorkingDirectories: Bool = false
    ) {
        self.executable = executable
        self.compileTimeout = compileTimeout
        self.availabilityTimeout = availabilityTimeout
        self.terminationGrace = terminationGrace
        self.processEnvironment = processEnvironment
        self.compilerArguments = compilerArguments
        self.keepsFailedWorkingDirectories = keepsFailedWorkingDirectories
    }
}
