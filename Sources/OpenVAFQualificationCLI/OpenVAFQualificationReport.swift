import Foundation

struct OpenVAFQualificationReport: Sendable, Codable {
    var executablePath: String
    var executableSHA256: String
    var successResultPath: String
    var failureResultPath: String
    var timeoutResultPath: String
    var upstreamResultPaths: [String]
}
