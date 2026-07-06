import { AsyncView, useViewModel, type SwiftObject } from "./swift-react"

/// The typed API BridgeJS generated for the Swift `ViewModelBridge` (see bridge-js.d.ts).
/// `subscribe` / `release` come from `SwiftObject` and are handled by `useViewModel`.
interface ViewModelBridge extends SwiftObject {
    readonly ipAddress: string
    readonly counter: number
    readonly randomNumber: number
    bump(): void
}

export function App() {
    // One line: creates the Swift ViewModel, re-renders on every change, releases on unmount.
    const vmState = useViewModel<ViewModelBridge>((swift) => swift.createViewModelBridge())

    return (
        <AsyncView state={vmState}>
            {(vm) => (
                <main style={{ fontFamily: "system-ui, sans-serif", margin: "2rem", maxWidth: 480 }}>
                    <h1>BSWDemo — React + Swift/WASM</h1>
                    <p><em>React renders the UI; the Swift <code>ViewModel</code> (compiled to WebAssembly via BridgeJS) does the work.</em></p>
                    <dl>
                        <dt style={{ fontWeight: 600 }}>IP Address</dt>
                        <dd style={{ margin: "0 0 1rem" }}>{vm.ipAddress}</dd>
                        <dt style={{ fontWeight: 600 }}>Counter</dt>
                        <dd style={{ margin: "0 0 1rem" }}>{vm.counter}</dd>
                        <dt style={{ fontWeight: 600 }}>Random number</dt>
                        <dd style={{ margin: "0 0 1rem" }}>{vm.randomNumber}</dd>
                    </dl>
                    <button onClick={() => vm.bump()} style={{ padding: "0.5rem 1rem", fontSize: "1rem" }}>
                        Bump Counter
                    </button>
                </main>
            )}
        </AsyncView>
    )
}
