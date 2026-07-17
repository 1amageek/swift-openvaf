// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "7abcac83517935c9b9f7553d7016d62cffde259d"
    )

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
        .library(
            name: "VerilogACompiler",
            targets: ["VerilogACompiler"]
        ),
    ],
    traits: [
        .trait(
            name: "OpenVAFCLI",
            description: "Enable the external OpenVAF command line compiler wrapper.",
            enabledTraits: []
        ),
        .trait(
            name: "VerilogACompiler",
            description: "Enable the Verilog-A compiler frontend.",
            enabledTraits: []
        ),
        .default(enabledTraits: ["OpenVAFCLI", "VerilogACompiler"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
    ],
    targets: [
        .target(
            name: "VerilogACompiler",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "OpenVAFSupport",
            dependencies: [
                "VerilogACompiler",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "OpenVAFSupportTests",
            dependencies: [
                "OpenVAFSupport",
                "VerilogACompiler",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
