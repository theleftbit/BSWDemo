import { useEffect, useRef, useState } from "react"

/// The typed API BridgeJS generated for the Swift `ViewModelBridge` (see bridge-js.d.ts).
interface ViewModelBridge {
    readonly ipAddress: string
    readonly counter: number
    readonly randomNumber: number
    bump(): void
    subscribe(onChange: () => void): void   // push: Swift calls back on every @Observable change
    release(): void
}

/// The subset of the generated bridge exports this app uses. `createViewModelBridge()` can be
/// called as many times as you need instances.
interface SwiftExports {
    createViewModelBridge(): Promise<ViewModelBridge>
}

type Snapshot = { ipAddress: string; counter: number; randomNumber: number }

// Set once by /public/boot-swift.js after the Swift runtime is bootstrapped (once per app launch).
declare global {
    interface Window { swiftReady?: Promise<SwiftExports> }
}

// The boot module and React mount race; poll briefly for the promise, then await it.
function whenSwiftReady(): Promise<SwiftExports> {
    if (window.swiftReady) return window.swiftReady
    return new Promise((resolve) => {
        const id = setInterval(() => {
            if (window.swiftReady) {
                clearInterval(id)
                resolve(window.swiftReady)
            }
        }, 20)
    })
}

export function App() {
    const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
    const [error, setError] = useState<string | null>(null)
    const vm = useRef<ViewModelBridge | null>(null)

    useEffect(() => {
        whenSwiftReady()
            .then((swift) => swift.createViewModelBridge()) // runtime already up → just create an instance
            .then((bridge) => {
                vm.current = bridge
                const read = () =>
                    setSnapshot({ ipAddress: bridge.ipAddress, counter: bridge.counter, randomNumber: bridge.randomNumber })
                read()                 // initial snapshot
                bridge.subscribe(read) // push — Swift calls read() on every @Observable change (no polling)
            })
            .catch((e) => setError(String(e)))
    }, [])

    if (error) {
        return <p style={{ color: "crimson", fontFamily: "system-ui" }}>Failed to load: {error}</p>
    }
    if (!snapshot) {
        return <p style={{ fontFamily: "system-ui", margin: "2rem" }}>Loading Swift / WebAssembly…</p>
    }

    return (
        <main style={{ fontFamily: "system-ui, sans-serif", margin: "2rem", maxWidth: 480 }}>
            <h1>BSWDemo — React + Swift/WASM</h1>
            <p><em>React renders the UI; the Swift <code>ViewModel</code> (compiled to WebAssembly via BridgeJS) does the work.</em></p>
            <dl>
                <dt style={{ fontWeight: 600 }}>IP Address</dt>
                <dd style={{ margin: "0 0 1rem" }}>{snapshot.ipAddress}</dd>
                <dt style={{ fontWeight: 600 }}>Counter</dt>
                <dd style={{ margin: "0 0 1rem" }}>{snapshot.counter}</dd>
                <dt style={{ fontWeight: 600 }}>Random number</dt>
                <dd style={{ margin: "0 0 1rem" }}>{snapshot.randomNumber}</dd>
            </dl>
            <button
                onClick={() => vm.current?.bump()}
                style={{ padding: "0.5rem 1rem", fontSize: "1rem" }}
            >
                Bump Counter
            </button>
        </main>
    )
}
