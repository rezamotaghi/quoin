import AppKit
import CommandKit
import EditorCore
import Network

/// Amendment 1: the app's local agent endpoint. A unix-domain socket (a
/// file-based, this-machine-only channel protected by file permissions; no
/// network exposure) speaking one JSON request/response per line, defined in
/// EditorCore/AgentProtocol.swift.
///
/// Everything answered here goes through the same public seams the UI uses:
/// NSDocumentController for documents, CommandRegistry for actions, the
/// pane's SelectionSet for selection. No privileged backdoor (invariant 6).
@MainActor
final class AgentServer {

    static let shared = AgentServer()

    /// ~/Library/Application Support/Quoin/agent.sock
    let socketURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Quoin/agent.sock")

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    func applySettings(_ settings: EditorSettings) {
        settings.agentServer ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        try? FileManager.default.removeItem(at: socketURL) // stale socket from a previous run
        let parameters = NWParameters.tcp // stream semantics; the endpoint below makes it AF_UNIX
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketURL.path)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {  // listener queue is .main
                self?.accept(connection)
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.drop(connection) }
            if case .cancelled = state { self?.drop(connection) }
        }
        connection.start(queue: .main)
        receiveLoop(connection, buffer: Data())
    }

    private nonisolated func drop(_ connection: NWConnection) {
        Task { @MainActor in
            connections.removeAll { $0 === connection }
        }
    }

    private func receiveLoop(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                // One JSON document per newline-terminated line.
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    self.respond(to: line, on: connection)
                }
                if error != nil || isComplete {
                    connection.cancel()
                    return
                }
                self.receiveLoop(connection, buffer: buffer)
            }
        }
    }

    private func respond(to line: Data, on connection: NWConnection) {
        let response: AgentResponse
        if let request = AgentWire.decode(AgentRequest.self, from: line) {
            response = handle(request)
        } else {
            response = AgentResponse(id: -1, error: "unparseable request line")
        }
        if let data = AgentWire.encodeLine(response) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Methods

    private func handle(_ request: AgentRequest) -> AgentResponse {
        let params = request.params ?? [:]
        switch request.method {
        case "list_open_documents":
            let front = frontDocument()
            let docs = textDocuments().map { doc -> AgentJSON in
                .object([
                    "path": doc.fileURL.map { .string($0.path) } ?? .null,
                    "display_name": .string(doc.displayName ?? ""),
                    "dirty": .bool(doc.isDocumentEdited),
                    "front": .bool(doc === front),
                ])
            }
            return AgentResponse(id: request.id, result: .array(docs))

        case "read_buffer":
            guard let doc = findDocument(path: params["path"]?.stringValue) else {
                return AgentResponse(id: request.id, error: "no such open document")
            }
            let text = (doc.windowControllers.first as? DocumentWindowController)?.currentText ?? doc.text
            return AgentResponse(id: request.id, result: .object([
                "path": doc.fileURL.map { .string($0.path) } ?? .null,
                "dirty": .bool(doc.isDocumentEdited),
                "can_undo": .bool(doc.undoManager?.canUndo ?? false),
                "text": .string(text),
            ]))

        case "get_selection":
            guard let doc = findDocument(path: params["path"]?.stringValue),
                  let wc = doc.windowControllers.first as? DocumentWindowController else {
                return AgentResponse(id: request.id, error: "no such open document")
            }
            let selection = wc.currentSelection
            let ns = wc.currentText as NSString
            let primary = selection.primary
            let clampedLength = max(0, min(primary.range.count, ns.length - primary.lowerBound))
            let selectedText = primary.lowerBound < ns.length
                ? ns.substring(with: NSRange(location: primary.lowerBound, length: clampedLength))
                : ""
            return AgentResponse(id: request.id, result: .object([
                "selections": .array(selection.selections.map {
                    .object(["anchor": .int($0.anchor), "head": .int($0.head)])
                }),
                "primary_text": .string(selectedText),
            ]))

        case "open_file":
            guard let path = params["path"]?.stringValue else {
                return AgentResponse(id: request.id, error: "open_file requires params.path")
            }
            let line = params["line"]?.intValue
            let url = URL(fileURLWithPath: path)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                if let line, let wc = document?.windowControllers.first as? DocumentWindowController {
                    wc.reveal(line: line)
                }
            }
            return AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))

        // Write methods. All land in the BUFFER as one undoable edit each;
        // disk is untouched until the user saves. The inserted text is left
        // selected so the change is visible.
        case "replace_selection":
            guard let text = params["text"]?.stringValue else {
                return AgentResponse(id: request.id, error: "replace_selection requires params.text")
            }
            guard let doc = findDocument(path: params["path"]?.stringValue),
                  let wc = doc.windowControllers.first as? DocumentWindowController else {
                return AgentResponse(id: request.id, error: "no such open document")
            }
            let primary = wc.currentSelection.primary
            guard wc.applyAgentEdit(range: primary.range, text: text) else {
                return AgentResponse(id: request.id, error: "selection out of bounds")
            }
            return AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))

        case "apply_edit":
            guard let anchor = params["anchor"]?.intValue, let head = params["head"]?.intValue,
                  let text = params["text"]?.stringValue else {
                return AgentResponse(id: request.id, error: "apply_edit requires params.anchor, .head, .text")
            }
            guard let doc = findDocument(path: params["path"]?.stringValue),
                  let wc = doc.windowControllers.first as? DocumentWindowController else {
                return AgentResponse(id: request.id, error: "no such open document")
            }
            guard wc.applyAgentEdit(range: min(anchor, head)..<max(anchor, head), text: text) else {
                return AgentResponse(id: request.id, error: "range out of bounds (offsets are UTF-16)")
            }
            return AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))

        case "set_text":
            guard let text = params["text"]?.stringValue else {
                return AgentResponse(id: request.id, error: "set_text requires params.text")
            }
            guard let doc = findDocument(path: params["path"]?.stringValue),
                  let wc = doc.windowControllers.first as? DocumentWindowController else {
                return AgentResponse(id: request.id, error: "no such open document")
            }
            let fullRange = 0..<(wc.currentText as NSString).length
            guard wc.applyAgentEdit(range: fullRange, text: text) else {
                return AgentResponse(id: request.id, error: "buffer replace failed")
            }
            return AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))

        case "run_command":
            guard let id = params["id"]?.stringValue else {
                return AgentResponse(id: request.id, error: "run_command requires params.id")
            }
            guard CommandRegistry.shared.all.contains(where: { $0.id == id }) else {
                return AgentResponse(id: request.id, error: "unknown command id: \(id)")
            }
            CommandRegistry.shared.run(id)
            return AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))

        case "list_commands":
            let commands = CommandRegistry.shared.all.map { command -> AgentJSON in
                .object([
                    "id": .string(command.id),
                    "title": .string(command.title),
                    "keybinding": command.defaultKeybinding.map { .string($0) } ?? .null,
                ])
            }
            return AgentResponse(id: request.id, result: .array(commands))

        default:
            return AgentResponse(id: request.id, error: "unknown method: \(request.method)")
        }
    }

    private func textDocuments() -> [TextDocument] {
        NSDocumentController.shared.documents.compactMap { $0 as? TextDocument }
    }

    /// "The document the user is looking at." NSDocumentController
    /// .currentDocument goes nil whenever the app is INACTIVE, and agents
    /// essentially always ask while the user is focused on their terminal,
    /// so relying on it made every query see no front document. Window
    /// z-order survives deactivation: the top document window is the answer.
    private func frontDocument() -> TextDocument? {
        if let current = NSDocumentController.shared.currentDocument as? TextDocument {
            return current
        }
        for window in NSApp.orderedWindows { // front-to-back; hidden tabs excluded
            if let doc = (window.windowController as? DocumentWindowController)?.document as? TextDocument {
                return doc
            }
        }
        return textDocuments().first
    }

    /// nil/empty path = the frontmost document.
    private func findDocument(path: String?) -> TextDocument? {
        guard let path, !path.isEmpty else { return frontDocument() }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return textDocuments().first { $0.fileURL?.standardizedFileURL.path == standardized }
    }
}
