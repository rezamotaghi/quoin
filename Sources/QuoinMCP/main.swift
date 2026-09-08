// QuoinMCP: the stdio shim that makes the running Quoin.app an
// MCP server. MCP clients (Claude Code, Claude Desktop, etc.) launch this
// executable and speak MCP over stdin/stdout; each tool call is forwarded as
// one JSON line over the app's unix socket (AgentServer) and the reply is
// returned as the tool result. The shim is stateless: if the app isn't
// running (or agent_server is off), every tool reports that instead of
// failing silently.
//
// Beyond tools (Amendment 2) the shim is self-describing: every tool carries
// annotations (read-only or not; never destructive, because every write is
// one undoable buffer edit) and an output schema; the open buffers are also
// readable as resources (quoin://buffer, quoin://buffer/<absolute path>),
// and three prompts package the editing choreographies.
//
// Register with Claude Code:
//   claude mcp add quoin -- /path/to/Quoin.app/Contents/MacOS/QuoinMCP
import EditorCore
import Foundation
import MCP

// MARK: - Socket client (fresh connection per request: simple and robust)

enum EditorSocketError: Error, CustomStringConvertible {
    case notRunning
    case protocolError(String)

    var description: String {
        switch self {
        case .notRunning:
            "Quoin is not running (or its agent_server setting is off)."
        case .protocolError(let message):
            "Quoin agent endpoint error: \(message)"
        }
    }
}

enum EditorSocket {
    static let socketPath = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Quoin/agent.sock").path

    /// A connected socket to the app, or notRunning.
    static func connect() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EditorSocketError.notRunning }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            _ = socketPath.utf8CString.withUnsafeBytes { bytes in
                raw.copyBytes(from: bytes.prefix(raw.count - 1))
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw EditorSocketError.notRunning
        }
        return fd
    }

    static func write(_ data: Data, to fd: Int32) throws {
        var sent = 0
        let total = data.count
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            while sent < total {
                let n = Foundation.write(fd, raw.baseAddress!.advanced(by: sent), total - sent)
                guard n > 0 else { throw EditorSocketError.notRunning }
                sent += n
            }
        }
    }

    static func call(method: String, params: [String: AgentJSON]? = nil) throws -> AgentJSON {
        let fd = try connect()
        defer { close(fd) }
        guard let request = AgentWire.encodeLine(AgentRequest(id: 1, method: method, params: params)) else {
            throw EditorSocketError.protocolError("could not encode request")
        }
        try write(request, to: fd)

        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while !received.contains(0x0A) {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { throw EditorSocketError.notRunning }
            received.append(contentsOf: chunk[0..<n])
        }
        let line = received.prefix(while: { $0 != 0x0A })
        guard let response = AgentWire.decode(AgentResponse.self, from: Data(line)) else {
            throw EditorSocketError.protocolError("unparseable response")
        }
        if let error = response.error { throw EditorSocketError.protocolError(error) }
        return response.result ?? .null
    }
}

// MARK: - Tool definitions

/// JSON Schema fragments for tool arguments.
enum ArgType {
    case string
    case integer
    /// Offsets and line numbers were declared as strings in 1.0; accepting
    /// both keeps every existing client working while new ones send integers.
    case integerOrString

    func schema(_ description: String) -> Value {
        switch self {
        case .string: .object(["type": "string", "description": .string(description)])
        case .integer: .object(["type": "integer", "description": .string(description)])
        case .integerOrString: .object(["type": .array(["integer", "string"]), "description": .string(description)])
        }
    }
}

struct ArgSpec {
    let name: String
    let description: String
    let type: ArgType
    let required: Bool
}

func arg(_ name: String, _ description: String, type: ArgType = .string, required: Bool = false) -> ArgSpec {
    ArgSpec(name: name, description: description, type: type, required: required)
}

let pathArg = arg("path", "Absolute file path of the open document. Omit for the frontmost document.")

// Output schema vocabulary.
let stringType: Value = .object(["type": "string"])
let nullableStringType: Value = .object(["type": .array(["string", "null"])])
let boolType: Value = .object(["type": "boolean"])
let intType: Value = .object(["type": "integer"])

/// A JSON Schema object whose properties are all present in every result.
func objectSchema(_ properties: [String: Value]) -> Value {
    .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(properties.keys.sorted().map { .string($0) }),
    ])
}

func arrayOf(_ items: Value) -> Value {
    .object(["type": "array", "items": items])
}

let documentSchema = objectSchema(["path": nullableStringType, "display_name": stringType, "dirty": boolType, "front": boolType])
let commandSchema = objectSchema(["id": stringType, "title": stringType, "keybinding": nullableStringType, "agent_runnable": boolType])
let okSchema: [String: Value] = ["ok": boolType]

struct ShimTool {
    let tool: Tool
    let method: String
    let arguments: [String]
    /// Wire results that are arrays go under this key in structuredContent
    /// (the spec requires an object there).
    let structuredKey: String?
}

func makeTool(_ name: String, _ description: String, method: String, arguments: [ArgSpec] = [],
              readOnly: Bool, idempotent: Bool? = nil, output: [String: Value], structuredKey: String? = nil) -> ShimTool {
    var properties: [String: Value] = [:]
    for spec in arguments { properties[spec.name] = spec.type.schema(spec.description) }
    let input: Value = .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(arguments.filter(\.required).map { .string($0.name) }),
    ])
    // No tool is destructive: every write is one undoable buffer edit and
    // never touches disk; the commit-class commands are refused by the app.
    let annotations = Tool.Annotations(
        readOnlyHint: readOnly,
        destructiveHint: readOnly ? nil : false,
        idempotentHint: idempotent,
        openWorldHint: false
    )
    return ShimTool(
        tool: Tool(name: name, description: description, inputSchema: input,
                   annotations: annotations, outputSchema: objectSchema(output)),
        method: method,
        arguments: arguments.map(\.name),
        structuredKey: structuredKey
    )
}

let tools: [ShimTool] = [
    makeTool("quoin_list_open_documents",
             "List documents open in Quoin: path (null for unsaved), display name, dirty flag, and which is frontmost.",
             method: "list_open_documents", readOnly: true,
             output: ["documents": arrayOf(documentSchema)], structuredKey: "documents"),
    makeTool("quoin_read_buffer",
             "Read the LIVE buffer of an open document, including unsaved edits (what the user currently sees, which may differ from the file on disk). For a large file prefer quoin_read_lines.",
             method: "read_buffer", arguments: [pathArg], readOnly: true,
             output: ["path": nullableStringType, "dirty": boolType, "can_undo": boolType, "line_count": intType, "text": stringType]),
    makeTool("quoin_read_lines",
             "Read lines from...to (1-based, inclusive) of an open document's LIVE buffer, plus its total line count. The token-cheap way to look at part of a file.",
             method: "read_lines",
             arguments: [arg("from", "First line, 1-based. Default 1.", type: .integer),
                         arg("to", "Last line, inclusive. Default: the last line.", type: .integer),
                         pathArg],
             readOnly: true,
             output: ["path": nullableStringType, "from": intType, "to": intType, "total_lines": intType, "text": stringType]),
    makeTool("quoin_get_selection",
             "Get the current selection(s) of an open document as UTF-16 offsets, plus the primary selection's text.",
             method: "get_selection", arguments: [pathArg], readOnly: true,
             output: ["selections": arrayOf(objectSchema(["anchor": intType, "head": intType])), "primary_text": stringType]),
    makeTool("quoin_open_file",
             "Open a file in Quoin (creates a tab or fronts the existing one), optionally jumping to a 1-based line.",
             method: "open_file",
             arguments: [arg("path", "Absolute file path to open.", required: true),
                         arg("line", "1-based line number to reveal.", type: .integerOrString)],
             readOnly: false, idempotent: true, output: okSchema),
    makeTool("quoin_replace_selection",
             "Replace the user's current selection with new text (e.g. a grammar-corrected version). Lands in the buffer as one undoable edit, left selected; nothing is saved to disk until the user saves.",
             method: "replace_selection",
             arguments: [arg("text", "Replacement text.", required: true), pathArg],
             readOnly: false, idempotent: true, output: okSchema),
    makeTool("quoin_apply_edit",
             "Replace an explicit UTF-16 offset range (anchor..head, as returned by quoin_get_selection) with new text. One undoable buffer edit; disk untouched until the user saves.",
             method: "apply_edit",
             arguments: [arg("anchor", "UTF-16 start offset.", type: .integerOrString, required: true),
                         arg("head", "UTF-16 end offset.", type: .integerOrString, required: true),
                         arg("text", "Replacement text.", required: true),
                         pathArg],
             readOnly: false, idempotent: false, output: okSchema),
    makeTool("quoin_replace_lines",
             "Rewrite lines from...to (1-based, inclusive) with new text; the neighbors keep their lines and the text needs no trailing newline. One undoable buffer edit, left selected; disk untouched until the user saves.",
             method: "replace_lines",
             arguments: [arg("from", "First line to replace, 1-based.", type: .integer, required: true),
                         arg("to", "Last line to replace, inclusive.", type: .integer, required: true),
                         arg("text", "The new content of those lines.", required: true),
                         pathArg],
             readOnly: false, idempotent: true, output: okSchema),
    makeTool("quoin_set_text",
             "Replace an open document's ENTIRE buffer (e.g. a fully proofread rewrite). One undoable edit; the user reviews and saves. Prefer quoin_replace_lines, quoin_apply_edit, or quoin_replace_selection for smaller changes.",
             method: "set_text",
             arguments: [arg("text", "The full new document text.", required: true), pathArg],
             readOnly: false, idempotent: true, output: okSchema),
    makeTool("quoin_run_command",
             "Run a Quoin command by id (see quoin_list_commands), e.g. edit.undo or view.toggleMarkdownPreview. Commit-class commands (save, save as, revert, close, quit) are refused: those are the human's.",
             method: "run_command",
             arguments: [arg("id", "Command id from quoin_list_commands.", required: true)],
             readOnly: false, idempotent: false, output: okSchema),
    makeTool("quoin_list_commands",
             "List every command Quoin can run, with ids, titles, keybindings, and whether an agent may run it (agent_runnable is false for the commit-class commands).",
             method: "list_commands", readOnly: true,
             output: ["commands": arrayOf(commandSchema)], structuredKey: "commands"),
]

// MARK: - Resources: the same state, addressable

enum ResourceURI {
    static let documents = "quoin://documents"
    static let buffer = "quoin://buffer"
    static let selection = "quoin://selection"

    /// quoin://buffer followed by the absolute path: quoin://buffer/Users/me/notes.md
    static func buffer(path: String) -> String { buffer + path }
    static func selection(path: String) -> String { selection + path }

    /// (kind, absolute path or nil for "the front document"); nil if not ours.
    static func parse(_ uri: String) -> (kind: String, path: String?)? {
        if uri == documents { return ("documents", nil) }
        for (kind, prefix) in [("buffer", buffer), ("selection", selection)] {
            if uri == prefix { return (kind, nil) }
            if uri.hasPrefix(prefix + "/") { return (kind, String(uri.dropFirst(prefix.count))) }
        }
        return nil
    }
}

func mimeType(forPath path: String?) -> String {
    switch ((path ?? "") as NSString).pathExtension.lowercased() {
    case "md", "markdown", "mdown": "text/markdown"
    case "json", "jsonc": "application/json"
    default: "text/plain"
    }
}

func field(_ name: String, of json: AgentJSON) -> AgentJSON? {
    if case .object(let object) = json { object[name] } else { nil }
}

// MARK: - Prompts: the editing choreographies

struct ShimPrompt: Sendable {
    let prompt: Prompt
    let text: @Sendable ([String: String]) -> String
}

let prompts: [ShimPrompt] = [
    ShimPrompt(
        prompt: Prompt(name: "proofread-selection", title: "Proofread the selection",
                       description: "Fix grammar, spelling, and clarity in the text the user has selected in Quoin, in place, as one undoable edit."),
        text: { _ in
            """
            The user has selected text in Quoin, the editor whose buffers you can edit over MCP.
            1. Call quoin_get_selection. If primary_text is empty, ask the user to select the passage first and stop.
            2. Correct grammar, spelling, punctuation, and clarity only. Keep the meaning, the voice, the formatting, and the line breaks. Do not add or remove content.
            3. Call quoin_replace_selection with the corrected text. It lands in the buffer as one undoable edit, left selected, and nothing is saved to disk.
            4. Tell the user in two or three lines what you changed, that the edit is selected in Quoin and unsaved, and that one Cmd+Z reverts it entirely. Saving is theirs; never try to save.
            """
        }
    ),
    ShimPrompt(
        prompt: Prompt(name: "review-buffer", title: "Review the front document",
                       description: "Read the frontmost buffer and report issues by line number, proposing edits without applying them.",
                       arguments: [Prompt.Argument(name: "focus", description: "What to look for: grammar, structure, dead code, consistency. Default: whatever matters most for this kind of file.", required: false)]),
        text: { arguments in
            let focus = arguments["focus"].flatMap { $0.isEmpty ? nil : $0 } ?? "whatever matters most for this kind of file"
            return """
            Review the document the user has in front of them in Quoin. Focus: \(focus).
            1. Call quoin_list_open_documents to see which document is front and whether it has unsaved edits, then quoin_read_buffer (or quoin_read_lines in windows when line_count is large) to read the LIVE text, unsaved edits included.
            2. Report findings as a short list, each with its line number and a one-line proposed fix. Lead with the finding that matters most.
            3. Apply nothing. If the user asks for a fix, use quoin_replace_lines or quoin_apply_edit for that finding only, and remind them it is one undoable, unsaved edit.
            """
        }
    ),
    ShimPrompt(
        prompt: Prompt(name: "undo-tour", title: "Show the undo contract",
                       description: "A one-minute demonstration: apply a small edit to the front document, then walk the user through undoing it in one step."),
        text: { _ in
            """
            Demonstrate Quoin's contract: the agent proposes, the human disposes.
            1. Call quoin_list_open_documents and note whether the front document is dirty, then quoin_read_lines for lines 1 to 5.
            2. Make one small, obviously reversible edit with quoin_replace_lines on line 1 (for example, append " (edited by an agent)"). Say exactly what you changed and that it is selected in the editor.
            3. Ask the user to press Cmd+Z once. Then call quoin_read_buffer and confirm the text is back and, if the buffer was clean before, that dirty is false again. Point out that disk was never touched: nothing is saved until they press Cmd+S.
            """
        }
    ),
]

// MARK: - Push: buffer-change events over one persistent connection

/// The one long-lived socket connection a host's subscriptions ride on. The
/// request path stays one-shot; this connection sends `subscribe` once and
/// then only listens. Each `buffer_changed` line becomes a
/// notifications/resources/updated for every subscribed URI it matches
/// (quoin://buffer follows the front document, quoin://buffer/<path> one file).
final class EventStream: @unchecked Sendable {
    private let server: Server
    private let lock = NSLock()
    private var uris: Set<String> = []
    private var fd: Int32 = -1

    init(server: Server) {
        self.server = server
    }

    func subscribe(_ uri: String) throws {
        lock.lock()
        defer { lock.unlock() }
        uris.insert(uri)
        guard fd < 0 else { return }
        let socket = try EditorSocket.connect()
        guard let line = AgentWire.encodeLine(AgentRequest(id: 0, method: "subscribe")) else {
            close(socket)
            throw EditorSocketError.protocolError("could not encode subscribe")
        }
        do {
            try EditorSocket.write(line, to: socket)
        } catch {
            close(socket)
            throw error
        }
        fd = socket
        Thread.detachNewThread { [weak self] in self?.readLoop(socket) }
    }

    func unsubscribe(_ uri: String) {
        lock.lock()
        defer { lock.unlock() }
        uris.remove(uri)
    }

    private func readLoop(_ socket: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(socket, &chunk, chunk.count)
            guard n > 0 else { break }
            buffer.append(contentsOf: chunk[0..<n])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                // The subscribe reply (an id, no event) decodes to nil here.
                if let event = AgentWire.decode(AgentEvent.self, from: line), event.event == "buffer_changed" {
                    deliver(event)
                }
            }
        }
        close(socket)
        lock.lock()
        fd = -1
        lock.unlock()
    }

    private func deliver(_ event: AgentEvent) {
        lock.lock()
        let matches = uris.filter { uri in
            if uri == ResourceURI.buffer { return event.front }
            if let path = event.path { return uri == ResourceURI.buffer(path: path) }
            return false
        }
        lock.unlock()
        let server = self.server
        for uri in matches {
            Task { try? await server.notify(ResourceUpdatedNotification.message(.init(uri: uri))) }
        }
    }
}

// MARK: - Value <-> AgentJSON bridges (both are plain JSON models)

func agentJSON(from value: Value) -> AgentJSON? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(AgentJSON.self, from: data)
}

func value(from json: AgentJSON) -> Value {
    switch json {
    case .null: .null
    case .bool(let v): .bool(v)
    case .int(let v): .int(v)
    case .double(let v): .double(v)
    case .string(let v): .string(v)
    case .array(let v): .array(v.map(value(from:)))
    case .object(let v): .object(v.mapValues(value(from:)))
    }
}

func jsonText(_ json: AgentJSON) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(json) else { return "null" }
    return String(data: data, encoding: .utf8) ?? "null"
}

// MARK: - Server

let server = Server(
    name: "quoin",
    version: "1.1.0",
    instructions: "Bridge to the running Quoin.app: read open buffers (unsaved edits included) and selections, open files at lines, edit buffers as single undoable steps, and run editor commands. The agent proposes in the buffer; only the human saves, reverts, closes, or quits.",
    capabilities: .init(
        prompts: .init(listChanged: false),
        resources: .init(subscribe: true, listChanged: false),
        tools: .init(listChanged: false)
    )
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: tools.map(\.tool))
}

await server.withMethodHandler(CallTool.self) { parameters in
    guard let shimTool = tools.first(where: { $0.tool.name == parameters.name }) else {
        return CallTool.Result(content: [.text(text: "unknown tool: \(parameters.name)", annotations: nil, _meta: nil)], isError: true)
    }
    var params: [String: AgentJSON] = [:]
    for name in shimTool.arguments {
        if let value = parameters.arguments?[name], let converted = agentJSON(from: value) {
            params[name] = converted
        }
    }
    do {
        let result = try EditorSocket.call(method: shimTool.method, params: params.isEmpty ? nil : params)
        let structured: Value
        if case .array = result, let key = shimTool.structuredKey {
            structured = .object([key: value(from: result)])
        } else {
            structured = value(from: result)
        }
        return try CallTool.Result(content: [.text(text: jsonText(result), annotations: nil, _meta: nil)], structuredContent: structured)
    } catch {
        return CallTool.Result(content: [.text(text: "\(error)", annotations: nil, _meta: nil)], isError: true)
    }
}

await server.withMethodHandler(ListResources.self) { _ in
    var resources = [
        Resource(name: "documents", uri: ResourceURI.documents,
                 description: "Open documents: path, display name, dirty flag, and which is frontmost.",
                 mimeType: "application/json"),
        Resource(name: "buffer", uri: ResourceURI.buffer,
                 description: "Live text of the frontmost document, unsaved edits included.",
                 mimeType: "text/plain"),
        Resource(name: "selection", uri: ResourceURI.selection,
                 description: "Selections (UTF-16 offsets) and the primary selection's text of the frontmost document.",
                 mimeType: "application/json"),
    ]
    if let documents = try? EditorSocket.call(method: "list_open_documents"), case .array(let items) = documents {
        for case .object(let document) in items {
            guard let path = document["path"]?.stringValue else { continue } // untitled: no address yet
            let name = document["display_name"]?.stringValue ?? (path as NSString).lastPathComponent
            resources.append(Resource(name: name, uri: ResourceURI.buffer(path: path),
                                      description: "Live buffer of \(path), unsaved edits included.",
                                      mimeType: mimeType(forPath: path)))
            resources.append(Resource(name: "\(name) selection", uri: ResourceURI.selection(path: path),
                                      description: "Selection in \(path).",
                                      mimeType: "application/json"))
        }
    }
    return ListResources.Result(resources: resources)
}

await server.withMethodHandler(ListResourceTemplates.self) { _ in
    ListResourceTemplates.Result(templates: [
        Resource.Template(uriTemplate: "quoin://buffer{+path}", name: "buffer",
                          description: "Live buffer of the open document at an absolute path (unsaved edits included).",
                          mimeType: "text/plain"),
        Resource.Template(uriTemplate: "quoin://selection{+path}", name: "selection",
                          description: "Selection of the open document at an absolute path.",
                          mimeType: "application/json"),
    ])
}

await server.withMethodHandler(ReadResource.self) { parameters in
    guard let parsed = ResourceURI.parse(parameters.uri) else {
        throw MCPError.invalidParams("unknown resource: \(parameters.uri)")
    }
    let pathParams: [String: AgentJSON]? = parsed.path.map { ["path": .string($0)] }
    do {
        switch parsed.kind {
        case "documents":
            let result = try EditorSocket.call(method: "list_open_documents")
            return ReadResource.Result(contents: [.text(jsonText(result), uri: parameters.uri, mimeType: "application/json")])
        case "buffer":
            let result = try EditorSocket.call(method: "read_buffer", params: pathParams)
            let text = field("text", of: result)?.stringValue ?? ""
            let path = parsed.path ?? field("path", of: result)?.stringValue
            return ReadResource.Result(contents: [.text(text, uri: parameters.uri, mimeType: mimeType(forPath: path))])
        default:
            let result = try EditorSocket.call(method: "get_selection", params: pathParams)
            return ReadResource.Result(contents: [.text(jsonText(result), uri: parameters.uri, mimeType: "application/json")])
        }
    } catch let error as EditorSocketError {
        throw MCPError.internalError(error.description)
    }
}

let events = EventStream(server: server)

await server.withMethodHandler(ResourceSubscribe.self) { parameters in
    guard let parsed = ResourceURI.parse(parameters.uri), parsed.kind == "buffer" else {
        throw MCPError.invalidParams("only buffer resources can be subscribed: \(parameters.uri)")
    }
    do {
        try events.subscribe(parameters.uri)
    } catch let error as EditorSocketError {
        throw MCPError.internalError(error.description)
    }
    return Empty()
}

await server.withMethodHandler(ResourceUnsubscribe.self) { parameters in
    events.unsubscribe(parameters.uri)
    return Empty()
}

await server.withMethodHandler(ListPrompts.self) { _ in
    ListPrompts.Result(prompts: prompts.map(\.prompt))
}

await server.withMethodHandler(GetPrompt.self) { parameters in
    guard let shimPrompt = prompts.first(where: { $0.prompt.name == parameters.name }) else {
        throw MCPError.invalidParams("unknown prompt: \(parameters.name)")
    }
    return GetPrompt.Result(
        description: shimPrompt.prompt.description,
        messages: [.user(.text(text: shimPrompt.text(parameters.arguments ?? [:])))]
    )
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
