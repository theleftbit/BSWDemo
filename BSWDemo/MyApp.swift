import SwiftUI
import DemoUI

/// The BSWDemo app shell. Every bit of UI and logic lives in the reusable **BSWDemoKit** package
/// (`DemoUI` + `DemoCore`), so the exact same `ViewModel` also powers the React website
/// (via the `DemoBridge` WASM target).
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
