// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-openvaf",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "OpenVAFSupport",
            targets: ["OpenVAFSupport"]
        ),
    ],
    targets: [
        .target(
            name: "OpenVAFSupport"
        ),
        .testTarget(
            name: "OpenVAFSupportTests",
            dependencies: ["OpenVAFSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
