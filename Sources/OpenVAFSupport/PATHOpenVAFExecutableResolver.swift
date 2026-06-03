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
        guard isExecutableRegularFile(at: url) else {
            throw .notExecutable(path: path)
        }
        return url
    }

    private func resolve(name: String, environment: [String: String]) throws(OpenVAFError) -> URL {
        try validateExecutableName(name)

        let searchedPaths = searchPaths(from: environment)
        for directory in searchedPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if isExecutableRegularFile(at: candidate) {
                return candidate
            }
        }
        throw .executableNotFound(name: name, searchedPaths: searchedPaths)
    }

    private func searchPaths(from environment: [String: String]) -> [String] {
        guard let path = environment["PATH"], !path.isEmpty else {
            return []
        }
        return path
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { component in
                component.isEmpty ? "." : String(component)
            }
    }

    private func isExecutableRegularFile(at url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: url.path) else {
            return false
        }

        do {
            let resolvedURL = url.resolvingSymlinksInPath()
            let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true
        } catch {
            return false
        }
    }

    private func validateExecutableName(_ name: String) throws(OpenVAFError) {
        guard !name.isEmpty else {
            throw .invalidExecutableName(name, message: "Name must not be empty")
        }

        guard name != "." && name != ".." else {
            throw .invalidExecutableName(name, message: "Name must not be a relative path marker")
        }

        guard name == URL(fileURLWithPath: name).lastPathComponent else {
            throw .invalidExecutableName(name, message: "Name must not contain path components")
        }
    }
}
