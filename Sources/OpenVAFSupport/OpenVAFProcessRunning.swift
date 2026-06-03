import Foundation

package protocol OpenVAFProcessRunning: Sendable {
    func run(_ command: OpenVAFProcessCommand) async throws -> OpenVAFProcessResult
}
