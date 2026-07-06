import { type ReactNode, useEffect, useReducer, useRef, useState } from "react"

// React primitives for consuming Swift ViewModels bridged to WASM — the analog of Polymarket's
// `SwiftViewModelUtils` (lifecycle) and MediQuo's `AsyncView` (async init). Components that use
// `useViewModel` never touch bootstrap, `subscribe`, or `release`.

/// A Swift object bridged to JS: it pushes change notifications and must be released (BridgeJS heap
/// objects aren't garbage-collected across the wasm boundary).
export interface SwiftObject {
    subscribe(onChange: () => void): void
    release(): void
}

export type Async<T> =
    | { readonly status: "loading" }
    | { readonly status: "error"; readonly error: unknown }
    | { readonly status: "ready"; readonly value: T }

// The bootstrapped Swift exports, published once by /public/boot-swift.js.
declare global {
    interface Window { swiftReady?: Promise<unknown> }
}

// boot-swift.js and React mount race; poll briefly for the promise, then await it.
function whenSwiftReady(): Promise<any> {
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

/// Owns a Swift ViewModel's lifecycle inside React so components never touch bootstrap / subscribe /
/// release: it creates the model once (async, after the runtime is up), re-renders on every
/// `@Observable` change (push via `subscribe`), and `release()`s it on unmount.
export function useViewModel<VM extends SwiftObject>(create: (swift: any) => Promise<VM>): Async<VM> {
    const [state, setState] = useState<Async<VM>>({ status: "loading" })
    const [, rerender] = useReducer((n: number) => n + 1, 0)
    const vm = useRef<VM | null>(null)

    useEffect(() => {
        let live = true
        whenSwiftReady()
            .then(create)
            .then((model) => {
                if (!live) { model.release(); return } // unmounted mid-create → release now
                vm.current = model
                model.subscribe(rerender)              // push → re-render (getters re-read during render)
                setState({ status: "ready", value: model })
            })
            .catch((error) => { if (live) setState({ status: "error", error }) })
        return () => {
            live = false
            vm.current?.release()                      // release on unmount — consumers never do
            vm.current = null
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [])

    return state
}

/// Renders one of loading / error / ready. The React analog of MediQuo's `AsyncView`.
export function AsyncView<T>({ state, loading, error, children }: {
    state: Async<T>
    loading?: ReactNode
    error?: (error: unknown) => ReactNode
    children: (value: T) => ReactNode
}): ReactNode {
    switch (state.status) {
        case "loading":
            return loading ?? <p style={{ fontFamily: "system-ui", margin: "2rem" }}>Loading Swift / WebAssembly…</p>
        case "error":
            return error?.(state.error) ?? <p style={{ color: "crimson", fontFamily: "system-ui" }}>Failed to load: {String(state.error)}</p>
        case "ready":
            return children(state.value)
    }
}
