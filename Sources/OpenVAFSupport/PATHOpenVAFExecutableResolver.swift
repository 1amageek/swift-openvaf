import Foundation

package struct PATHOpenVAFExecutableResolver: OpenVAFExecutableResolving {
    package init() {}

    package func resolve(
        _ executable: OpenVAFExecutable,
        environment: [String: String]
    ) throws(OpenVAFError) -> URL {
        switch executable {
        case .environment(let variable, let fallbackName):
            if let configured = environment[variable], !configured.isEmpty {
                return try resolve(rawValue: configured, environment: environment)
            }
            return try resolve(name: fallbackName, environment: environment)
        case .path(let path):
            return try resolvePath(path)
        case .name(let name):
            return try resolve(name: name, environment: environment)
        }
    }

    private func resolve(rawValue: String, environment: [String: String]) throws(OpenVAFError) -> URL {
        if rawValue.contains("/") {
            return try resolvePath(rawValue)
        }
        return try resolve(name: rawValue, environment: environment)
    }

    private func resolvePath(_ path: String) throws(OpenVAFError) -> URL {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw .notExecutable(path: path)
        }
        return url
    }

    private func resolve(name: String, environment: [String: String]) throws(OpenVAFError) -> URL {
        let searchedPaths = searchPaths(from: environment)
        for directory in searchedPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw .executableNotFound(name: name, searchedPaths: searchedPaths)
    }

    private func searchPaths(from environment: [String: String]) -> [String] {
        let path = environment["PATH"] ?? ""
        return path
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
