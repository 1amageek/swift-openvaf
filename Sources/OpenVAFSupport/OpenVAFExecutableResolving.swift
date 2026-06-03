import Foundation

package protocol OpenVAFExecutableResolving: Sendable {
    func resolve(
        _ executable: OpenVAFExecutable,
        environment: [String: String]
    ) throws(OpenVAFError) -> URL
}
