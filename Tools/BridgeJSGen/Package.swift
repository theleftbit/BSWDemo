// swift-tools-version: 6.2
import PackageDescription

// Proof-of-concept generator: reads `// SKIP @bridge` markers (the SAME ones Skip uses for Android)
// and emits BridgeJS `@JS` wrappers, so a shared type is exported to WebAssembly/JS too.
// This is the WASM analog of the `skipstone` plugin.
let package = Package(
    name: "BridgeJSGen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"999.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BridgeJSGen",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        )
    ]
)
