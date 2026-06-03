import CryptoKit
import Foundation
import Synchronization

package final class OpenVAFInstallationCache: Sendable {
    private let installations = Mutex<[String: OpenVAFInstallation]>([:])

    package init() {}

    package func installation(for executableURL: URL) -> OpenVAFInstallation? {
        guard let key = key(for: executableURL) else { return nil }
        return installations.withLock { $0[key] }
    }

    package func store(_ installation: OpenVAFInstallation) {
        guard let key = key(for: installation.executableURL) else { return }
        installations.withLock { $0[key] = installation }
    }

    private func key(for executableURL: URL) -> String? {
        let path = executableURL.standardizedFileURL.path
        guard let digest = digestHex(of: executableURL) else { return nil }
        return lengthPrefixed(path) + lengthPrefixed(digest)
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
