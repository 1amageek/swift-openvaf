import Foundation
import Synchronization

package final class OpenVAFInstallationCache: Sendable {
    private let installations = Mutex<[String: OpenVAFInstallation]>([:])

    package init() {}

    package func installation(for executableURL: URL) -> OpenVAFInstallation? {
        installations.withLock { $0[key(for: executableURL)] }
    }

    package func store(_ installation: OpenVAFInstallation) {
        installations.withLock { $0[key(for: installation.executableURL)] = installation }
    }

    private func key(for executableURL: URL) -> String {
        executableURL.standardizedFileURL.path
    }
}
