// swift-tools-version: 6.2
import PackageDescription

// Shared code for the BSWDemo sample, extracted so the same `ViewModel` powers both the
// SwiftUI app (DemoUI) and a React website (via the DemoBridge WASM target).
let package = Package(
    name: "BSWDemoKit",
    // iOS 26 / macOS 26: DemoUI's ContentView uses `.safeAreaBar`, a SwiftUI 26 API.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DemoCore", targets: ["DemoCore"]),
        .library(name: "DemoUI", targets: ["DemoUI"]),
        .executable(name: "DemoBridge", targets: ["DemoBridge"]),
    ],
    dependencies: [
        // WASM support lives on this branch until it's merged; swap to a version afterwards.
        .package(url: "https://github.com/theleftbit/BSWFoundation.git", branch: "feature/wasm-port"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.56.1"),
    ],
    targets: [
        // Platform-agnostic: the reusable ViewModel + API definitions. Runs on Apple and wasm.
        .target(
            name: "DemoCore",
            dependencies: [
                .product(name: "BSWFoundation", package: "BSWFoundation"),
            ]
        ),
        // The SwiftUI front-end (Apple only).
        .target(
            name: "DemoUI",
            dependencies: [
                "DemoCore",
                // For `Observable.stream(for:)` used by the view.
                .product(name: "BSWFoundation", package: "BSWFoundation"),
            ]
        ),
        // A headless bridge: exposes the same ViewModel to JavaScript so a React (or any JS)
        // front-end can drive it. Renders nothing itself.
        .executableTarget(
            name: "DemoBridge",
            dependencies: [
                "DemoCore",
                .product(name: "BSWFoundation", package: "BSWFoundation"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [
                // BridgeJS-generated glue relies on @_extern(wasm).
                .enableExperimentalFeature("Extern")
            ],
            plugins: [
                // Generates Swift<->JS bindings + a TypeScript .d.ts from the @JS-annotated surface.
                .plugin(name: "BridgeJS", package: "JavaScriptKit")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
