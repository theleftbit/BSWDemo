import { useEffect, useRef, useState } from "react"

/// The typed API BridgeJS generated for the Swift `ViewModelBridge` (see bridge-js.d.ts).
interface ViewModelBridge {
    readonly ipAddress: string
    readonly counter: number
    readonly randomNumber: number
    bump(): void
}

type Snapshot = { ipAddress: string; counter: number; randomNumber: number }

// Set by /public/boot-swift.js once the wasm module is initialized.
declare global {
    interface Window { viewModelBridge?: Promise<ViewModelBridge> }
}

// The boot module and React mount race; poll briefly for the promise, then await it.
function whenSwiftReady(): Promise<ViewModelBridge> {
    if (window.viewModelBridge) return window.viewModelBridge
    return new Promise((resolve) => {
        const id = setInterval(() => {
            if (window.viewModelBridge) {
                clearInterval(id)
                resolve(window.viewModelBridge)
            }
        }, 20)
    })
}

export function App() {
    const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
    const [error, setError] = useState<string | null>(null)
    const vm = useRef<ViewModelBridge | null>(null)

    const read = (bridge: ViewModelBridge) =>
        setSnapshot({ ipAddress: bridge.ipAddress, counter: bridge.counter, randomNumber: bridge.randomNumber })

    useEffect(() => {
        let timer: number | undefined
        whenSwiftReady()
            .then((bridge) => {
                vm.current = bridge
                read(bridge)
                timer = window.setInterval(() => read(bridge), 500) // BridgeJS getters are pull-only → poll
            })
            .catch((e) => setError(String(e)))
        return () => { if (timer !== undefined) clearInterval(timer) }
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
                onClick={() => { vm.current?.bump(); if (vm.current) read(vm.current) }}
                style={{ padding: "0.5rem 1rem", fontSize: "1rem" }}
            >
                Bump Counter
            </button>
        </main>
    )
}
