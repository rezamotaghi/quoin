import AppKit
import EditorCore

/// App-level menu commands: the settings-backed toggles (View, Theme, Font,
/// the Agent menu switches), the Agent menu's status and setup helpers, and
/// Help links. A toggle never keeps its own state: it writes the user's
/// settings file and the normal hot-reload path repaints every window, so the
/// file remains the single source of truth and the checkmarks read from it.
extension AppDelegate: NSUserInterfaceValidations {

    private var settings: EditorSettings { SettingsStore.shared.settings }

    private func write(_ key: String, _ jsonValue: String) {
        SettingsStore.shared.setUserSetting(key, jsonValue: jsonValue)
    }

    // MARK: Quoin

    /// Quoin > About: the standard panel, with an empty build string so it
    /// reads "Version 1.1.0" and not "Version 1.1.0 (1.1.0)". AppKit prints
    /// CFBundleVersion in parentheses whenever it is non-empty, equal to the
    /// marketing version or not (checked on the live panel 2026-09-09).
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.version: ""])
    }

    /// Quoin > Settings: the user's settings.jsonc, in the editor itself.
    @objc func openSettings(_ sender: Any?) {
        NSDocumentController.shared.openDocument(withContentsOf: SettingsStore.shared.userFileURL, display: true) { _, _, _ in }
    }

    // MARK: View

    @objc func toggleWordWrap(_ sender: Any?) {
        write("word_wrap", settings.wordWrap ? "false" : "true")
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        write("line_numbers", settings.lineNumbers ? "false" : "true")
    }

    /// Tags in menu order: 0 none, 1 selection, 2 all (Sublime's draw_white_space).
    @objc func setWhitespaceMode(_ sender: Any?) {
        let value = switch (sender as? NSMenuItem)?.tag ?? 1 {
        case 0: "[]"
        case 2: "[\"all\"]"
        default: "[\"selection\"]"
        }
        write("draw_white_space", value)
    }

    /// The tag is the width.
    @objc func setTabWidth(_ sender: Any?) {
        guard let width = (sender as? NSMenuItem)?.tag, width > 0 else { return }
        write("tab_size", String(width))
    }

    @objc func fontLarger(_ sender: Any?) { write("font_size", Self.jsonNumber(min(settings.fontSize + 1, 72))) }
    @objc func fontSmaller(_ sender: Any?) { write("font_size", Self.jsonNumber(max(settings.fontSize - 1, 6))) }
    @objc func fontReset(_ sender: Any?) { write("font_size", Self.jsonNumber(EditorSettings().fontSize)) }

    /// Tags in menu order: 0 auto, 1 light, 2 dark.
    @objc func setTheme(_ sender: Any?) {
        let value = switch (sender as? NSMenuItem)?.tag ?? 0 {
        case 1: "\"light\""
        case 2: "\"dark\""
        default: "\"auto\""
        }
        write("theme", value)
    }

    private static func jsonNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    // MARK: Agent

    @objc func toggleAgentServer(_ sender: Any?) {
        write("agent_server", settings.agentServer ? "false" : "true")
    }

    @objc func toggleFollowAgentEdits(_ sender: Any?) {
        write("follow_agent_edits", settings.followAgentEdits ? "false" : "true")
    }

    /// The one line that connects Claude Code to this very bundle.
    static var mcpSetupCommand: String {
        "claude mcp add quoin -- \"\(Bundle.main.bundlePath)/Contents/MacOS/QuoinMCP\""
    }

    @objc func copyAgentSetupCommand(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.mcpSetupCommand, forType: .string)
    }

    @objc func showAgentStatus(_ sender: Any?) {
        let server = AgentServer.shared
        let alert = NSAlert()
        alert.messageText = server.isListening ? "Agent server is on" : "Agent server is off"
        alert.informativeText = """
        Socket: \(server.socketURL.path)
        Agent edits this session: \(server.editCount)
        Every agent edit is one undo step; nothing reaches disk until you save. Save, revert, close, and quit are never agent-runnable.

        Connect Claude Code with:
        \(Self.mcpSetupCommand)
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy Setup Command")
        if alert.runModal() == .alertSecondButtonReturn {
            copyAgentSetupCommand(nil)
        }
    }

    // MARK: Help

    @objc func openGitHub(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/rezamotaghi/quoin")!)
    }

    @objc func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/rezamotaghi/quoin/issues/new/choose")!)
    }

    @objc func openReleaseNotes(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/rezamotaghi/quoin/blob/main/CHANGELOG.md")!)
    }

    // MARK: Validation: the checkmarks read the settings

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action, let menuItem = item as? NSMenuItem else { return true }
        if action == #selector(toggleWordWrap(_:)) {
            menuItem.state = settings.wordWrap ? .on : .off
        } else if action == #selector(toggleLineNumbers(_:)) {
            menuItem.state = settings.lineNumbers ? .on : .off
        } else if action == #selector(setWhitespaceMode(_:)) {
            let mode = switch settings.whitespaceMode {
            case .none: 0
            case .selection: 1
            case .all: 2
            }
            menuItem.state = mode == menuItem.tag ? .on : .off
        } else if action == #selector(setTabWidth(_:)) {
            menuItem.state = settings.tabSize == menuItem.tag ? .on : .off
        } else if action == #selector(setTheme(_:)) {
            let index = switch settings.theme {
            case "light": 1
            case "dark": 2
            default: 0
            }
            menuItem.state = index == menuItem.tag ? .on : .off
        } else if action == #selector(toggleAgentServer(_:)) {
            menuItem.state = settings.agentServer ? .on : .off
        } else if action == #selector(toggleFollowAgentEdits(_:)) {
            menuItem.state = settings.followAgentEdits ? .on : .off
        }
        return true
    }
}
