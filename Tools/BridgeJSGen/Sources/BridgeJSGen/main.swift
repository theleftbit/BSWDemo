import Foundation
import SwiftParser
import SwiftSyntax

// BridgeJSGen — proof of concept.
//
// Reads a Swift file, finds classes marked `// SKIP @bridge` or `// SKIP @bridgeMembers` (the SAME
// inert comment markers Polymarket already uses to bridge types to Android via Skip), and generates
// a BridgeJS `@JS` wrapper for each — so the type is exported to WebAssembly/JavaScript too.
// Annotate once, bridge to both. This is the WASM analog of the `skipstone` build plugin.
//
// Usage: BridgeJSGen <input.swift> <output.swift> [ModuleToImport]

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: BridgeJSGen <input.swift> <output.swift> [Module]\n".utf8))
    exit(2)
}
let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let moduleToImport = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "DemoCore"

let source = try String(contentsOfFile: inputPath, encoding: .utf8)
let tree = Parser.parse(source: source)

func isMarked(_ trivia: Trivia) -> Bool {
    let text = trivia.description
    return text.contains("SKIP @bridge") || text.contains("SKIP @bridgeMembers")
}

// Primitive default so a nonisolated getter can return before the model is built.
func defaultValue(for type: String) -> String {
    switch type {
    case "Int", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return "0"
    case "Double", "Float", "CGFloat": return "0"
    case "Bool": return "false"
    case "String": return "\"\""
    default: return "nil"  // optionals / reference types — refine per type in a real tool
    }
}

var wrappers: [String] = []

for stmt in tree.statements {
    guard let cls = stmt.item.as(ClassDeclSyntax.self), isMarked(cls.leadingTrivia) else { continue }
    let name = cls.name.text

    var props: [(name: String, type: String)] = []
    var methods: [String] = []
    var hasAsyncInit = false

    for member in cls.memberBlock.members {
        let decl = member.decl
        if let v = decl.as(VariableDeclSyntax.self) {
            let mods = v.modifiers.map(\.name.text)
            guard mods.contains("public"), !mods.contains("static") else { continue }
            for b in v.bindings {
                guard let id = b.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let type = b.typeAnnotation?.type.trimmedDescription else { continue }
                props.append((id, type))
            }
        } else if let f = decl.as(FunctionDeclSyntax.self) {
            let mods = f.modifiers.map(\.name.text)
            guard mods.contains("public"), !mods.contains("static") else { continue }
            let noParams = f.signature.parameterClause.parameters.isEmpty
            let isAsync = f.signature.effectSpecifiers?.asyncSpecifier != nil
            let returnsVoid = f.signature.returnClause == nil
            if noParams, !isAsync, returnsVoid { methods.append(f.name.text) }
        } else if let i = decl.as(InitializerDeclSyntax.self) {
            if i.signature.effectSpecifiers?.asyncSpecifier != nil { hasAsyncInit = true }
        }
    }

    // Async factory — mirrors the `create(...)` pattern: the model keeps its single async init code
    // path, exposed to JS as a Promise. The wrapper is nonisolated (BridgeJS emits nonisolated
    // thunks) and @unchecked Sendable so the getters may hop to the main actor to touch the
    // @MainActor model; safe because wasm is single-threaded (every call lands on the one thread).
    let effect = hasAsyncInit ? " async" : ""
    let build = hasAsyncInit ? "try? await \(name)()" : "\(name)()"
    var w = ""
    w += "@JS func create\(name)Bridge()\(effect) -> \(name)Bridge {\n"
    w += "    let bridge = \(name)Bridge()\n"
    w += "    bridge.model = \(build)\n"
    w += "    return bridge\n"
    w += "}\n\n"
    w += "@JS class \(name)Bridge: @unchecked Sendable {\n"
    w += "    fileprivate var model: \(name)?\n"
    w += "    init() {}\n"
    for p in props {
        w += "    @JS var \(p.name): \(p.type) { MainActor.assumeIsolated { model?.\(p.name) ?? \(defaultValue(for: p.type)) } }\n"
    }
    for m in methods {
        w += "    @JS func \(m)() { MainActor.assumeIsolated { model?.\(m)() } }\n"
    }
    // Push: stream each observed property (via BSWFoundation's Observable.stream) and invoke the JS
    // callback on change — so consumers get real reactivity instead of polling.
    w += "\n    /// Push: invokes `onChange` whenever an observed property changes, so JS re-reads.\n"
    w += "    @JS func subscribe(_ onChange: @escaping () -> Void) {\n"
    w += "        let cb = __BridgeCallback(run: onChange)\n"
    w += "        MainActor.assumeIsolated {\n"
    w += "            guard let model else { return }\n"
    for p in props {
        w += "            Task { @MainActor in for await _ in model.stream(for: \\.\(p.name)) { cb.run() } }\n"
    }
    w += "        }\n"
    w += "    }\n"
    w += "}\n"
    wrappers.append(w)
    FileHandle.standardError.write(Data("  \(name) -> \(name)Bridge: \(props.count) props, \(methods.count) methods, asyncInit=\(hasAsyncInit)\n".utf8))
}

// Emitted once (not per type): the app-launch bootstrap, analogous to Android's ProcessInfo.launch.
let bootstrap = wrappers.isEmpty ? "" : """
/// Call once at app launch (the WASM analog of Android's `ProcessInfo.launch(_:)`), before creating
/// any bridged object — installs the JS event-loop executor so Swift concurrency can run.
@JS func bootstrapSwiftRuntime() {
    JavaScriptEventLoop.installGlobalExecutor()
}

// Boxes a non-Sendable JS callback so it can cross into the observation Tasks (wasm is single-threaded).
private struct __BridgeCallback: @unchecked Sendable { let run: () -> Void }


"""
let output = """
// Generated by BridgeJSGen from `// SKIP @bridge` markers. DO NOT EDIT.
#if os(WASI)
import JavaScriptKit
import JavaScriptEventLoop
import BSWFoundation
import \(moduleToImport)

\(bootstrap)\(wrappers.joined(separator: "\n"))
#endif

"""
try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
FileHandle.standardError.write(Data("Wrote \(wrappers.count) wrapper(s) to \(outputPath)\n".utf8))
