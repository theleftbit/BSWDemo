// Boots the Swift/WASM bridge (DemoBridge). Loaded via a <script type="module"> tag in
// index.html so Vite serves this file — and /swift/index.js — as static /public assets and lets
// the browser import them natively, instead of routing them through Vite's module transform.
import { init } from "/swift/index.js"

init().catch((error) => {
    if (typeof window.__onSwiftDemoError === "function") {
        window.__onSwiftDemoError(String(error))
    } else {
        console.error(error)
    }
})
