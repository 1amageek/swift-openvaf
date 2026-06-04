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
    targets: [
        .target(
            name: "VerilogACompiler"
        ),
        .target(
            name: "OpenVAFSupport",
            dependencies: ["VerilogACompiler"]
        ),
        .testTarget(
            name: "OpenVAFSupportTests",
            dependencies: [
                "OpenVAFSupport",
                "VerilogACompiler",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
