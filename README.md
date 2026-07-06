# BSWDemo

**One Swift `ViewModel`, two front-ends — with the web bridge *generated* from an annotation.**

This sample takes a single `@Observable` view model — written once in Swift, using
[BSWFoundation](https://github.com/theleftbit/BSWFoundation) for networking and storage — and drives
**both** a native iOS app *and* a browser app from it. The web version compiles the very same Swift
to **WebAssembly** ([SwiftWasm](https://swiftwasm.org)) and lets **React** render the UI.

No logic is duplicated. And the Swift↔JS bridge isn't hand-written: you mark the view model with a
`// SKIP @bridge` comment — the *same* annotation [Skip](https://skip.tools) uses to bridge Swift to
Android — and a small generator emits the WebAssembly bridge. **Annotate once, bridge to both.**

## Architecture

```
DemoCore.ViewModel              shared logic: APIClient, storage, @Observable state
│   // SKIP @bridge             (no UI, no platform assumptions — runs on Apple AND wasm)
├─ DemoUI       SwiftUI    ───► BSWDemo.app      (native iOS/macOS)
└─ DemoBridge   generated  ───► BSWDemoReact     (React website; Swift compiled to wasm)
        ▲
        └─ BridgeJSGen reads the marker → @JS wrapper → BridgeJS → typed .d.ts
```

- **`DemoCore`** — the reusable `ViewModel` + API definitions. Platform-agnostic; the `ViewModel`
  carries an inert `// SKIP @bridge` marker.
- **`DemoUI`** — a SwiftUI `ContentView` bound to the view model. Apple platforms only.
- **`DemoBridge`** — a headless wasm executable. Its JS-facing `@JS` wrapper is **generated** (not
  hand-written) from the marker, then turned into a typed JS/TS API by
  [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit)'s **BridgeJS** plugin.
- **`BSWDemoReact`** — a Vite + React + TypeScript app that constructs the generated
  `ViewModelBridge` and renders its state.
- **`Tools/BridgeJSGen`** — a small SwiftSyntax generator: reads `// SKIP @bridge` markers and emits
  `@JS` wrappers. The WASM analog of Skip's `skipstone`. (Proof of concept — see caveats.)

## Repo layout

| Path | What |
|---|---|
| `BSWDemo.xcodeproj` / `BSWDemo/` | The native app shell (`@main`), wired to the local `BSWDemoKit` package |
| `BSWDemoKit/` | The Swift package: `DemoCore`, `DemoUI`, `DemoBridge` targets |
| `BSWDemoReact/` | The Vite + React app that renders the generated bridge |
| `Tools/BridgeJSGen/` | The marker → `@JS` wrapper generator |

---

## Part 1 — Run the native app (the easy part)

**Requires Xcode 26 or later** (the UI uses iOS 26 SwiftUI APIs such as `.safeAreaBar`).

1. Open `BSWDemo.xcodeproj`.
2. Xcode resolves the Swift packages automatically — the local `BSWDemoKit`, and `BSWFoundation`
   pulled from its `feature/wasm-port` branch. (First resolve needs network access.)
3. Pick an iOS 26 simulator and hit **Run** (⌘R).

That's it — a standard SPM-backed app. The `// SKIP @bridge` marker is a plain comment, so it has no
effect here.

---

## Part 2 — Run the React website (Swift → WebAssembly)

### Prerequisites

- **A WebAssembly Swift SDK that matches your toolchain.** Check your version with
  `swift --version`, then install the matching wasm SDK — see
  [swift.org's WebAssembly guide](https://www.swift.org/documentation/articles/wasm-getting-started.html)
  for the current URL + checksum (BSWFoundation's
  [README](https://github.com/theleftbit/BSWFoundation/tree/feature/wasm-port#webassembly--browser-support)
  has a worked example). Then note the **SDK id**:

  ```sh
  swift sdk list        # e.g. swift-6.3.2-RELEASE_wasm
  ```

- **[Node.js](https://nodejs.org) 18+** — for the Vite dev server.

### Build the Swift → wasm bundle

Two steps: generate the bridge from the marker, then compile to wasm. **From the repo root:**

```sh
# 1. Generate the @JS wrapper from the `// SKIP @bridge` marker on DemoCore.ViewModel.
swift run --package-path Tools/BridgeJSGen BridgeJSGen \
  BSWDemoKit/Sources/DemoCore/ViewModel.swift \
  BSWDemoKit/Sources/DemoBridge/Generated/ViewModelBridge.swift \
  DemoCore

# 2. Compile DemoBridge to wasm; BridgeJS generates the typed JS/TS bindings automatically.
swift package --package-path BSWDemoKit \
  --swift-sdk swift-6.3.2-RELEASE_wasm \
  --disable-sandbox \
  js --use-cdn --product DemoBridge \
  --output BSWDemoReact/public/swift
```

> Replace `swift-6.3.2-RELEASE_wasm` with the id from your `swift sdk list`.
> Both `DemoBridge/Generated/` and `BSWDemoReact/public/swift/` are git-ignored build artifacts —
> regenerate them, don't commit. `--use-cdn` fetches the small `@bjorn3/browser_wasi_shim` runtime
> from a CDN. This is a **debug** bundle (~80 MB) — fine for local dev; see
> [Shrinking the bundle](#shrinking-the-bundle) for deploys.

### Serve it

```sh
cd BSWDemoReact
npm install
npm run dev
```

Open the printed URL (default **http://localhost:5173**): the IP address, a counter, and a
random number that ticks every second — all produced by the Swift view model through the generated
bridge — plus a **Bump Counter** button that drives `ViewModel.bump()` in Swift.

### Production build

`npm run build` outputs a static site to `BSWDemoReact/dist/` (the wasm bundle and loader are copied
in). Serve that folder with any static host.

---

## Using the Swift ViewModel from React

From the JavaScript side there are just three things: **initialize the runtime**, **get a Swift
object**, **call it**. All of it is typed — BridgeJS emits a `.d.ts` describing the exported API.

### The `ViewModel`, bridged

The Swift model ([`DemoCore/ViewModel.swift`](BSWDemoKit/Sources/DemoCore/ViewModel.swift)), reduced
to its public surface:

```swift
// SKIP @bridge
@Observable @MainActor
public final class ViewModel {
    public var ipAddress: String         // fetched once at init
    public var randomNumber: Int         // changes on a timer
    public var counter: Int { get set }  // persisted (localStorage on wasm)
    public init() async throws           // does the network fetch
    public func bump()
}
```

…is what JavaScript sees (generated `bridge-js.d.ts`):

```ts
declare function bootstrapSwiftRuntime(): void
declare function createViewModelBridge(): Promise<ViewModelBridge>

interface ViewModelBridge {
    readonly ipAddress: string      // public var ipAddress: String
    readonly counter: number        // public var counter: Int
    readonly randomNumber: number   // public var randomNumber: Int
    bump(): void                    // public func bump()
    release(): void                 // free the Swift object (no GC across wasm)
}
```

How the surface maps:

| Swift | JavaScript / TypeScript |
|---|---|
| `public var x: String` / `Int` | `readonly x: string` / `number` — pull-only, so poll for live values |
| `public func bump()` | `bump(): void` |
| `public init() async throws` | `createViewModelBridge(): Promise<ViewModelBridge>` — the async init stays one code path |
| the class instance | a `SwiftHeapObject` handle; call `release()` when done |

> Only the **public** surface crosses; `private`/`@ObservationIgnored` members (the property-wrapper
> storage, the timer `Task`) stay inside Swift. `@MainActor` is handled by the generated wrapper.

### 1. Initialize the Swift runtime (once, at launch)

The compiled Swift is an ES module (`/swift/index.js`) whose `init()` instantiates the wasm and
returns the exported API. In a Vite app, load it from a **`/public` module** — Vite won't let you
`import()` a `/public` file from your `src` code, so a tiny boot script sidesteps that:

```js
// BSWDemoReact/public/boot-swift.js — referenced from index.html via
// <script type="module" src="/boot-swift.js"></script>
import { init } from "/swift/index.js"

window.viewModelBridge = (async () => {
    const { exports } = await init()               // instantiate the wasm module
    exports.bootstrapSwiftRuntime()                // install Swift's concurrency runtime — ONCE
    return await exports.createViewModelBridge()   // build a Swift object (step 2)
})()
```

`bootstrapSwiftRuntime()` is the one-time, per-app-launch step (it installs the JS event-loop
executor Swift concurrency needs). Call it once, before anything async.

### 2. Make a Swift object available

`exports.createViewModelBridge()` is an async factory: it constructs the Swift `ViewModel` (which
does a network fetch on init) and hands back a JS object.

```ts
const vm = await exports.createViewModelBridge()   // vm: ViewModelBridge
```

`vm` is a live handle to the Swift instance. Our boot script stashes the `Promise<ViewModelBridge>`
on `window.viewModelBridge` so React can `await` it.

### 3. Read state and call methods

The object is fully typed (straight from the generated `.d.ts`):

```ts
interface ViewModelBridge {
    readonly ipAddress: string     // Swift String  → string
    readonly counter: number       // Swift Int     → number
    readonly randomNumber: number
    bump(): void                   // calls Swift ViewModel.bump()
    release(): void                // free the Swift object when you're done with it
}
```

- **Read** properties directly — `vm.counter`, `vm.ipAddress`. They're **pull-only** (read on
  demand), so for live values you poll.
- **Call** methods directly — `vm.bump()`.
- **Release** with `vm.release()` when the object is no longer needed (it holds a Swift heap
  allocation; there's no GC across the wasm boundary).

Putting it together in React:

```tsx
useEffect(() => {
    let timer: number
    window.viewModelBridge!.then((vm) => {
        const read = () => setState({ ip: vm.ipAddress, counter: vm.counter, random: vm.randomNumber })
        read()
        timer = window.setInterval(read, 500)   // poll — BridgeJS getters don't push
    })
    return () => clearInterval(timer)
}, [])

// in the view:  <button onClick={() => vm.bump()}>Bump</button>
```

That's the whole surface: `init()` + `bootstrapSwiftRuntime()` once, `createViewModelBridge()` to get
an object, then plain typed property reads and method calls. Working version:
[`boot-swift.js`](BSWDemoReact/public/boot-swift.js) and [`App.tsx`](BSWDemoReact/src/App.tsx).

> **Adding more to the API?** Everything above is generated from the `// SKIP @bridge` marker — see
> [How the bridge works](#how-the-bridge-works-marker-driven) for the Swift side.

---

## How the bridge works (marker-driven)

The web bridge is **generated**, not hand-written — the DX mirrors Skip's Android bridging:

1. **Mark the model.** `DemoCore.ViewModel` carries a `// SKIP @bridge` comment. It's inert to the
   Swift compiler, so it neither couples `DemoCore` to JavaScriptKit nor affects the iOS build —
   exactly like Skip's marker for Android.
2. **Generate the wrapper.** [`Tools/BridgeJSGen`](Tools/BridgeJSGen) (a SwiftSyntax tool) reads the
   marker and emits a `@JS`-annotated wrapper into the wasm-only `DemoBridge` target — an async
   `createViewModelBridge()` factory, typed getters, and `bump()`.
3. **Generate the bindings.** JavaScriptKit's **BridgeJS** plugin turns the `@JS` wrapper into wasm
   exports plus a typed TypeScript `.d.ts`:
   ```ts
   interface ViewModelBridge { readonly ipAddress: string; readonly counter: number; bump(): void }
   function bootstrapSwiftRuntime(): void
   function createViewModelBridge(): Promise<ViewModelBridge>
   ```
4. **Consume it from JS.** The React app calls `init()` + `bootstrapSwiftRuntime()`, then
   `createViewModelBridge()`, then reads the typed getters and calls `bump()` — see
   [Using the Swift ViewModel from React](#using-the-swift-viewmodel-from-react).

Design notes:
- The `@MainActor` view model stays fully main-actor; the generated wrapper is a nonisolated,
  `@unchecked Sendable` facade that hops to the main actor (safe — wasm is single-threaded).
- `bootstrapSwiftRuntime()` installs the JS event-loop executor **once per app launch** — the WASM
  analog of Skip's `ProcessInfo.launch(_:)`, not per-object.
- The `ViewModel` keeps its single `init() async throws`; the generated `create…` factory is the
  bridged construction path (mirrors Skip's `create(...)` pattern).

Key files:
- Shared model (marked) — [`DemoCore/ViewModel.swift`](BSWDemoKit/Sources/DemoCore/ViewModel.swift)
- SwiftUI view — [`DemoUI/ContentView.swift`](BSWDemoKit/Sources/DemoUI/ContentView.swift)
- Generator — [`Tools/BridgeJSGen`](Tools/BridgeJSGen/Sources/BridgeJSGen/main.swift)
- React view — [`BSWDemoReact/src/App.tsx`](BSWDemoReact/src/App.tsx)

## Notes & caveats

- **`BridgeJSGen` is a proof of concept.** It handles marked classes with public typed properties
  (read-only getters), no-arg `Void` methods, and an async initializer. Methods with arguments,
  richer types, and structs/enums would need more work. A production setup would wire it as a SwiftPM
  **build-tool plugin** (like `skipstone`) so it regenerates on every build — then nothing generated
  ever lands in git.
- **Reactivity is pull-based:** BridgeJS getters are read-on-demand, so the React app polls them. A
  push path (a `subscribe(onChange:)` closure) is possible — BridgeJS supports closures — but isn't
  wired here.
- **`BridgeJS` is experimental** (JavaScriptKit) — APIs may change.
- **The `BSWFoundation` dependency points at the `feature/wasm-port` branch** while WASM support is
  in review. Swap it to a released version once merged (`BSWDemoKit/Package.swift`).
- **`UserDefaultsBacked<Int>` isn't available on wasm** (only `Bool`/`String`); the view model uses
  `CodableUserDefaultsBacked`, which works everywhere (`localStorage` in the browser).
- **`localStorage` is not secure storage** — fine for a demo counter, not for secrets.

### Shrinking the bundle

The debug wasm is large. For a real deploy, build in release with
[Binaryen](https://github.com/WebAssembly/binaryen)'s `wasm-opt` on your `PATH`, then serve with
brotli/gzip — this drops the served size dramatically (~80 MB → ~12 MB). Add `-c release` to the
`js` command above. See BSWFoundation's
[Production builds & binary size](https://github.com/theleftbit/BSWFoundation/tree/feature/wasm-port#production-builds--binary-size)
for the details.
