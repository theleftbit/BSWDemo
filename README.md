# BSWDemo

**One Swift `ViewModel`, two front-ends: a native SwiftUI app and a React website.**

This sample takes a single `@Observable` view model — written once in Swift, using
[BSWFoundation](https://github.com/theleftbit/BSWFoundation) for networking and storage — and drives
**both** a native iOS app *and* a browser app from it. The web version compiles the very same Swift
to **WebAssembly** ([SwiftWasm](https://swiftwasm.org)) and lets **React** render the UI.

No logic is duplicated. The IP lookup (`APIClient`), the persisted counter (`UserDefaults` /
`localStorage`), and the live-updating random number all live in one place and run unchanged on
both platforms.

## Architecture

```
DemoCore.ViewModel          shared logic: APIClient, storage, @Observable state
│                           (no UI, no platform assumptions — runs on Apple AND wasm)
├─ DemoUI      SwiftUI  ───► BSWDemo.app        (native iOS/macOS)
└─ DemoBridge  JS glue  ───► BSWDemoReact       (React website, Swift compiled to wasm)
```

- **`DemoCore`** — the reusable `ViewModel` + API definitions. Platform-agnostic.
- **`DemoUI`** — a SwiftUI `ContentView` bound to the view model. Apple platforms only.
- **`DemoBridge`** — a headless wasm executable that exposes the *same* view model to JavaScript
  over a small `globalThis` contract. Renders nothing itself.
- **`BSWDemoReact`** — a Vite + React + TypeScript app that renders the UI from the state
  `DemoBridge` pushes, and calls back into Swift on user actions.

## Repo layout

| Path | What |
|---|---|
| `BSWDemo.xcodeproj` / `BSWDemo/` | The native app shell (`@main`), wired to the local `BSWDemoKit` package |
| `BSWDemoKit/` | The Swift package: `DemoCore`, `DemoUI`, `DemoBridge` targets |
| `BSWDemoReact/` | The React website that reuses `DemoBridge` |

---

## Part 1 — Run the native app (the easy part)

**Requires Xcode 26 or later** (the UI uses iOS 26 SwiftUI APIs such as `.safeAreaBar`).

1. Open `BSWDemo.xcodeproj`.
2. Xcode resolves the Swift packages automatically — the local `BSWDemoKit`, and `BSWFoundation`
   pulled from its `feature/wasm-port` branch. (First resolve needs network access.)
3. Pick an iOS 26 simulator and hit **Run** (⌘R).

That's it — this is a standard SPM-backed app.

---

## Part 2 — Run the React website (Swift → WebAssembly)

This is the interesting part. You'll compile `DemoBridge` to wasm, then serve a React app that loads
it. If you've never built for wasm before, it's three commands after a one-time SDK install.

### Prerequisites

- **A WebAssembly Swift SDK that matches your toolchain.** Check your version with
  `swift --version`, then install the matching wasm SDK. Follow
  [swift.org's WebAssembly guide](https://www.swift.org/documentation/articles/wasm-getting-started.html)
  for the current URL + checksum (BSWFoundation's
  [README](https://github.com/theleftbit/BSWFoundation/tree/feature/wasm-port#webassembly--browser-support)
  has a worked example). The install looks like:

  ```sh
  swift sdk install <url-for-your-version> --checksum <checksum>
  ```

  Verify it's registered and note the **SDK id** (used below):

  ```sh
  swift sdk list        # e.g. swift-6.3.2-RELEASE_wasm
  ```

- **[Node.js](https://nodejs.org) 18+** — for the Vite dev server.

### Build the Swift → wasm bundle

The React app expects the compiled bundle in `BSWDemoReact/public/swift/` (git-ignored — it's a
build artifact). Generate it with the [PackageToJS](https://github.com/swiftwasm/JavaScriptKit)
plugin that JavaScriptKit ships. **From the repo root:**

```sh
swift package --package-path BSWDemoKit \
  --swift-sdk swift-6.3.2-RELEASE_wasm \
  --disable-sandbox \
  js --use-cdn --product DemoBridge \
  --output BSWDemoReact/public/swift
```

> Replace `swift-6.3.2-RELEASE_wasm` with the id from your `swift sdk list`.
> `--use-cdn` fetches the small `@bjorn3/browser_wasi_shim` runtime from a CDN so you don't need to
> install it. This produces a **debug** bundle (~80 MB) — fine for local dev. For a deployable,
> compressed build see [Shrinking the bundle](#shrinking-the-bundle) below.

### Serve it

```sh
cd BSWDemoReact
npm install
npm run dev
```

Open the printed URL (default **http://localhost:5173**). You should see the IP address, a counter,
and a random number that ticks every second — all produced by the Swift view model — plus a
**Bump Counter** button that drives `ViewModel.bump()` in Swift and re-renders React.

### Production build

`npm run build` outputs a static site to `BSWDemoReact/dist/` (the wasm bundle and loader are copied
in). Serve that folder with any static host.

---

## How the bridge works

The Swift and JavaScript sides meet over a tiny contract on `globalThis`:

- The React app (in [`BSWDemoReact/src/App.tsx`](BSWDemoReact/src/App.tsx)) registers three
  callbacks: `__swiftDemoUpdate(state)`, `__onSwiftDemoReady(controller)`, `__onSwiftDemoError(msg)`.
- [`BSWDemoReact/public/boot-swift.js`](BSWDemoReact/public/boot-swift.js) loads the wasm module via
  a `<script type="module">` (this sidesteps Vite trying to transform a `/public` asset).
- [`DemoBridge/main.swift`](BSWDemoKit/Sources/DemoBridge/main.swift) builds the `ViewModel`, pushes
  its state to `__swiftDemoUpdate` on every change (via `Observable.stream(for:)`), and exposes
  `SwiftDemo.bump()` for React to call.

React never touches a Swift object directly — it only reads pushed state and sends intent back.
See the key files:

- Shared model — [`DemoCore/ViewModel.swift`](BSWDemoKit/Sources/DemoCore/ViewModel.swift)
- SwiftUI view — [`DemoUI/ContentView.swift`](BSWDemoKit/Sources/DemoUI/ContentView.swift)
- JS bridge — [`DemoBridge/main.swift`](BSWDemoKit/Sources/DemoBridge/main.swift)
- React view — [`BSWDemoReact/src/App.tsx`](BSWDemoReact/src/App.tsx)

## Notes & caveats

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
