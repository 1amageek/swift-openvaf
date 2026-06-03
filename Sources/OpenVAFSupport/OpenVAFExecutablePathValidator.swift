package enum OpenVAFExecutablePathValidator {
    package static func validate(_ path: String) throws(OpenVAFError) {
        guard !path.isEmpty else {
            throw .invalidConfiguration(
                field: "executable.path",
                message: "Executable path must not be empty"
            )
        }

        guard !path.contains("\0") else {
            throw .invalidConfiguration(
                field: "executable.path",
                message: "Executable path must not contain NUL"
            )
        }
    }
}
