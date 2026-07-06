import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import { fileURLToPath } from "node:url"

export default defineConfig({
    plugins: [react()],
    resolve: {
        alias: {
            // For the demo, resolve the package to its source (no build step). A real app would
            // `npm install @theleftbit/swift-react` and get the published build instead.
            "@theleftbit/swift-react": fileURLToPath(
                new URL("../packages/swift-react/src/index.tsx", import.meta.url),
            ),
        },
    },
})
