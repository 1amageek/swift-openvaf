import CryptoKit
import Foundation
import Synchronization

package final class OpenVAFInstallationCache: Sendable {
    package struct Snapshot: Sendable, Equatable {
        fileprivate let executableURL: URL
        fileprivate let key: String
    }

    private let installations = Mutex<[String: OpenVAFInstallation]>([:])

    package init() {}

    package func snapshot(for executableURL: URL) -> Snapshot? {
        let standardizedURL = executableURL.standardizedFileURL
        guard let digest = digestHex(of: standardizedURL) else { return nil }
        let key = lengthPrefixed(standardizedURL.path) + lengthPrefixed(digest)
        return Snapshot(executableURL: standardizedURL, key: key)
    }

    package func installation(for snapshot: Snapshot) -> OpenVAFInstallation? {
        installations.withLock { $0[snapshot.key] }
    }

    package func store(_ installation: OpenVAFInstallation, forStable snapshot: Snapshot) {
        guard installation.executableURL.standardizedFileURL == snapshot.executableURL,
              self.snapshot(for: installation.executableURL) == snapshot else {
            return
        }
        installations.withLock { $0[snapshot.key] = installation }
    }

    private func digestHex(of executableURL: URL) -> String? {
        guard let stream = InputStream(url: executableURL) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let byteCount = buffer.withUnsafeMutableBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return 0 }
                return stream.read(baseAddress, maxLength: pointer.count)
            }

            if byteCount > 0 {
                buffer.withUnsafeBufferPointer { pointer in
                    guard let baseAddress = pointer.baseAddress else { return }
                    let rawBuffer = UnsafeRawBufferPointer(start: baseAddress, count: byteCount)
                    hasher.update(bufferPointer: rawBuffer)
                }
                continue
            }

            if byteCount == 0 {
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }

            return nil
        }
    }

    private func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}
