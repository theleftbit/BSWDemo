import ReactDOM from "react-dom/client"
import { App } from "./App"

// No <React.StrictMode> on purpose: its double-invoked effects would boot the Swift/WASM
// module twice in dev.
ReactDOM.createRoot(document.getElementById("root")!).render(<App />)
