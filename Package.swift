// swift-tools-version: 6.3
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    exact: "26.812.0"
)

let signoffToolSupportDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/SignoffToolSupport.git",
    exact: "26.812.0"
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
        .executable(
            name: "openvaf-qualification",
            targets: ["OpenVAFQualificationCLI"]
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
        signoffToolSupportDependency,
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            exact: "4.5.1"
        ),
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
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFileSystem", package: "CircuiteFoundation"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
            ]
        ),
        .executableTarget(
            name: "OpenVAFQualificationCLI",
            dependencies: [
                "OpenVAFSupport",
                "VerilogACompiler",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "OpenVAFSupportTests",
            dependencies: [
                "OpenVAFSupport",
                "VerilogACompiler",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
