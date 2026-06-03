import Foundation

package enum OpenVAFExecutableNameValidator {
    package static func validate(_ name: String) throws(OpenVAFError) {
        guard !name.isEmpty else {
            throw .invalidExecutableName(name, message: "Name must not be empty")
        }

        guard !name.contains("\0") else {
            throw .invalidExecutableName(name, message: "Name must not contain NUL")
        }

        guard name != "." && name != ".." else {
            throw .invalidExecutableName(name, message: "Name must not be a relative path marker")
        }

        guard name == URL(fileURLWithPath: name).lastPathComponent else {
            throw .invalidExecutableName(name, message: "Name must not contain path components")
        }
    }
}
