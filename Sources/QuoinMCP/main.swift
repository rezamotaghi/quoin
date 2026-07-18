// QuoinMCP: the stdio shim that makes the running Quoin.app an
// MCP server. MCP clients (Claude Code, etc.) launch this executable and
// speak MCP over stdin/stdout; each tool call is forwarded as one JSON line
// over the app's unix socket (AgentServer) and the reply is returned as the
// tool result. The shim is stateless: if the app isn't running (or
// agent_server is off), every tool reports that instead of failing silently.
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

    static func call(method: String, params: [String: AgentJSON]? = nil) throws -> AgentJSON {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EditorSocketError.notRunning }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            _ = socketPath.utf8CString.withUnsafeBytes { bytes in
                raw.copyBytes(from: bytes.prefix(raw.count - 1))
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw EditorSocketError.notRunning }

        guard let request = AgentWire.encodeLine(AgentRequest(id: 1, method: method, params: params)) else {
            throw EditorSocketError.protocolError("could not encode request")
        }
        var sent = 0
        let total = request.count
        try request.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            while sent < total {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), total - sent)
                guard n > 0 else { throw EditorSocketError.notRunning }
                sent += n
            }
        }

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

struct ShimTool {
    let tool: Tool
    let method: String
    let arguments: [String]
}

func makeTool(_ name: String, _ description: String, method: String, arguments: [(String, String, required: Bool)] = []) -> ShimTool {
    var properties: [String: Value] = [:]
    for (argName, argDescription, _) in arguments {
        properties[argName] = .object(["type": "string", "description": .string(argDescription)])
    }
    let schema: Value = .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(arguments.filter(\.required).map { .string($0.0) }),
    ])
    return ShimTool(
        tool: Tool(name: name, title: nil, description: description, inputSchema: schema, outputSchema: nil),
        method: method,
        arguments: arguments.map(\.0)
    )
}

let tools: [ShimTool] = [
    makeTool("quoin_list_open_documents",
             "List documents open in Quoin: path (null for unsaved), display name, dirty flag, and which is frontmost.",
             method: "list_open_documents"),
    makeTool("quoin_read_buffer",
             "Read the LIVE buffer of an open document, including unsaved edits (what the user currently sees, which may differ from the file on disk).",
             method: "read_buffer",
             arguments: [("path", "Absolute file path of the open document. Omit for the frontmost document.", required: false)]),
    makeTool("quoin_get_selection",
             "Get the current selection(s) of an open document as UTF-16 offsets, plus the primary selection's text.",
             method: "get_selection",
             arguments: [("path", "Absolute file path of the open document. Omit for the frontmost document.", required: false)]),
    makeTool("quoin_open_file",
             "Open a file in Quoin (creates a tab or fronts the existing one), optionally jumping to a 1-based line.",
             method: "open_file",
             arguments: [("path", "Absolute file path to open.", required: true),
                         ("line", "1-based line number to reveal.", required: false)]),
    makeTool("quoin_replace_selection",
             "Replace the user's current selection with new text (e.g. a grammar-corrected version). Lands in the buffer as one undoable edit, left selected; nothing is saved to disk until the user saves.",
             method: "replace_selection",
             arguments: [("text", "Replacement text.", required: true),
                         ("path", "Absolute file path of the open document. Omit for the frontmost document.", required: false)]),
    makeTool("quoin_apply_edit",
             "Replace an explicit UTF-16 offset range (anchor..head, as returned by quoin_get_selection) with new text. One undoable buffer edit; disk untouched until the user saves.",
             method: "apply_edit",
             arguments: [("anchor", "UTF-16 start offset.", required: true),
                         ("head", "UTF-16 end offset.", required: true),
                         ("text", "Replacement text.", required: true),
                         ("path", "Absolute file path of the open document. Omit for the frontmost document.", required: false)]),
    makeTool("quoin_set_text",
             "Replace an open document's ENTIRE buffer (e.g. a fully proofread rewrite). One undoable edit; the user reviews and saves. Prefer quoin_apply_edit or quoin_replace_selection for smaller changes.",
             method: "set_text",
             arguments: [("text", "The full new document text.", required: true),
                         ("path", "Absolute file path of the open document. Omit for the frontmost document.", required: false)]),
    makeTool("quoin_run_command",
             "Run a Quoin command by id (see quoin_list_commands), e.g. file.save or view.toggleMarkdownPreview.",
             method: "run_command",
             arguments: [("id", "Command id from quoin_list_commands.", required: true)]),
    makeTool("quoin_list_commands",
             "List every command Quoin can run, with ids, titles, and keybindings.",
             method: "list_commands"),
]

// MARK: - Value <-> AgentJSON bridges (both are plain JSON models)

func agentJSON(from value: Value) -> AgentJSON? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(AgentJSON.self, from: data)
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
    version: "1.0.0",
    instructions: "Bridge to the running Quoin.app: inspect open buffers (including unsaved edits), selections, open files at lines, and run editor commands.",
    capabilities: .init(tools: .init(listChanged: false))
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
        return CallTool.Result(content: [.text(text: jsonText(result), annotations: nil, _meta: nil)])
    } catch {
        return CallTool.Result(content: [.text(text: "\(error)", annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
