#if os(WASI)
import BSWFoundation
import DemoCore
import JavaScriptKit
import JavaScriptEventLoop

// Exposes the *same* DemoCore.ViewModel to JavaScript so a React (or any JS) front-end can render
// it. The Swift side owns the logic and state; JS is only the view.
//
// JS interop contract (all on `globalThis`):
//   - the front-end sets `__swiftDemoUpdate(state)`  — called with { ipAddress, counter, randomNumber }
//     on init and on every change.
//   - the front-end sets `__onSwiftDemoReady(controller)` — called once when ready.
//   - `SwiftDemo.bump()` — bump the counter.

@MainActor private var retainedClosures: [JSClosure] = []

@main
struct DemoBridge {
    static func main() {
        JavaScriptEventLoop.installGlobalExecutor()
        Task { await bootstrap() }
    }
}

@MainActor
private func pushState(_ viewModel: ViewModel) {
    guard let update = JSObject.global.__swiftDemoUpdate.function else { return }
    let state = JSObject.global.Object.function!.new()
    state.ipAddress = .string(viewModel.ipAddress)
    state.counter = .number(Double(viewModel.counter))
    state.randomNumber = .number(Double(viewModel.randomNumber))
    _ = update(state.jsValue)
}

@MainActor
private func bootstrap() async {
    let viewModel: ViewModel
    do {
        viewModel = try await ViewModel()
    } catch {
        if let onError = JSObject.global.__onSwiftDemoError.function {
            _ = onError("\(error)")
        }
        return
    }

    let controller = JSObject.global.Object.function!.new()
    let bump = JSClosure { _ in
        MainActor.assumeIsolated { viewModel.bump() }
        return .undefined
    }
    retainedClosures.append(bump)
    controller.bump = bump.jsValue
    JSObject.global.SwiftDemo = controller.jsValue

    // Initial state, then signal readiness.
    pushState(viewModel)
    if let onReady = JSObject.global.__onSwiftDemoReady.function {
        _ = onReady(controller.jsValue)
    }

    // Push fresh state to JS whenever the observable ViewModel changes.
    Task { for await _ in viewModel.stream(for: \.counter) { pushState(viewModel) } }
    Task { for await _ in viewModel.stream(for: \.randomNumber) { pushState(viewModel) } }
}

#else

@main
struct DemoBridge {
    static func main() {
        print("DemoBridge targets WebAssembly; build it with the wasm SDK.")
    }
}

#endif
