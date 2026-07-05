import { useEffect, useRef, useState } from "react"

/// Mirrors the state the Swift `DemoCore.ViewModel` pushes over the JS bridge.
type DemoState = { ipAddress: string; counter: number; randomNumber: number }

interface SwiftDemoController {
    bump(): void
}

export function App() {
    const [state, setState] = useState<DemoState | null>(null)
    const [error, setError] = useState<string | null>(null)
    const swift = useRef<SwiftDemoController | null>(null)
    const started = useRef(false)

    useEffect(() => {
        if (started.current) return // guard against a second dev-mode invocation
        started.current = true

        const w = window as unknown as Record<string, unknown>
        // The Swift bridge (DemoBridge) calls these; register them before booting the module.
        w.__swiftDemoUpdate = (s: DemoState) => setState(s)
        w.__onSwiftDemoReady = (controller: SwiftDemoController) => { swift.current = controller }
        w.__onSwiftDemoError = (message: string) => setError(message)

        // The Swift ViewModel (compiled to WebAssembly) is booted by /public/boot-swift.js, loaded
        // as a <script type="module"> in index.html. It calls the callbacks registered above.
    }, [])

    if (error) {
        return <p style={{ color: "crimson", fontFamily: "system-ui" }}>Failed to load: {error}</p>
    }
    if (!state) {
        return <p style={{ fontFamily: "system-ui", margin: "2rem" }}>Loading Swift / WebAssembly…</p>
    }

    return (
        <main style={{ fontFamily: "system-ui, sans-serif", margin: "2rem", maxWidth: 480 }}>
            <h1>BSWDemo — React + Swift/WASM</h1>
            <p><em>React renders the UI; the Swift <code>ViewModel</code> (compiled to WebAssembly) does the work.</em></p>
            <dl>
                <dt style={{ fontWeight: 600 }}>IP Address</dt>
                <dd style={{ margin: "0 0 1rem" }}>{state.ipAddress}</dd>
                <dt style={{ fontWeight: 600 }}>Counter</dt>
                <dd style={{ margin: "0 0 1rem" }}>{state.counter}</dd>
                <dt style={{ fontWeight: 600 }}>Random number</dt>
                <dd style={{ margin: "0 0 1rem" }}>{state.randomNumber}</dd>
            </dl>
            <button onClick={() => swift.current?.bump()} style={{ padding: "0.5rem 1rem", fontSize: "1rem" }}>
                Bump Counter
            </button>
        </main>
    )
}
