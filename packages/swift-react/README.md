# @theleftbit/swift-react

React primitives for consuming Swift ViewModels compiled to WebAssembly (via
[JavaScriptKit BridgeJS](https://github.com/swiftwasm/JavaScriptKit)). The **React tier of
BSWInterfaceKit** — the same role `AsyncView` plays on iOS and Android.

- **`useViewModel(create)`** — owns a bridged ViewModel's lifecycle: creates it once the Swift
  runtime is up, re-renders on every `@Observable` change (push via `subscribe`), and `release()`s it
  on unmount. Components never touch subscribe/release.
- **`<AsyncView>`** — renders loading / error / ready.

```tsx
import { useViewModel, AsyncView, type SwiftObject } from "@theleftbit/swift-react"

interface MyBridge extends SwiftObject { readonly counter: number; bump(): void }

function Screen() {
    const state = useViewModel<MyBridge>((swift) => swift.createMyBridge())
    return (
        <AsyncView state={state}>
            {(vm) => <button onClick={() => vm.bump()}>Count {vm.counter}</button>}
        </AsyncView>
    )
}
```

**Contract:** the host app publishes `window.swiftReady: Promise<exports>` from a boot script that
loads the wasm bundle and calls `bootstrapSwiftRuntime()` once. See the
[BSWDemo](https://github.com/theleftbit/BSWDemo) sample for the full setup.

> Peer dependency: `react >= 18`. Build with `npm run build` (emits `dist/` + types).
