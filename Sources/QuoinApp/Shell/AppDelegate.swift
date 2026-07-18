import AppKit
import CommandKit
import EditorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Our NSDocumentController subclass must be instantiated before anything
    // touches NSDocumentController.shared: AppKit adopts the FIRST instance
    // created as the shared one.
    private let documentController = DocumentController()

    private var appearanceObservation: NSKeyValueObservation?

    /// The folder Cmd+P indexes (File > Open Folder). Falls back to the
    /// frontmost document's folder when none is open.
    private(set) var projectRoot: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.loadAndWatch()
        Self.applyAppearance(SettingsStore.shared.settings)
        Self.applyHotExit(SettingsStore.shared.settings)
        AgentServer.shared.applySettings(SettingsStore.shared.settings)
        MainMenu.registerCommands(in: CommandRegistry.shared)
        NSApp.mainMenu = MainMenu.build(from: CommandRegistry.shared)

        NotificationCenter.default.addObserver(
            forName: .editorSettingsDidChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Self.applyAppearance(SettingsStore.shared.settings)
                Self.applyHotExit(SettingsStore.shared.settings)
                AgentServer.shared.applySettings(SettingsStore.shared.settings)
            }
        }
    }

    // quoin://open?file=/abs/path&line=42 (the quoin CLI builds these).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "quoin", url.host == "open",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let file = components.queryItems?.first(where: { $0.name == "file" })?.value
            else { continue }
            let line = components.queryItems?.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: file), display: true) { document, _, _ in
                if let line, let wc = document?.windowControllers.first as? DocumentWindowController {
                    wc.reveal(line: line)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()

        // theme "auto": when macOS flips between light and dark mid-session,
        // recolor every window. Reuse the settings-changed notification: the
        // same listeners (panes, previews) must react the same way.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.old, .new]) { _, change in
            // Listeners re-apply NSApp.appearance, which re-fires this
            // observation; only a REAL flip may propagate or we'd loop.
            guard change.oldValue?.name != change.newValue?.name else { return }
            Task { @MainActor in
                NotificationCenter.default.post(name: .editorSettingsDidChange, object: nil)
            }
        }
    }

    // A document app keeps running with no windows (so Cmd+N/Cmd+O still work).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Launching with nothing to open (or clicking the Dock icon with no
    // windows) creates an untitled document, like every Mac editor.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Palette actions (registry commands send these selectors here;
    // the app delegate is the tail of the responder chain)

    @objc func showCommandPalette(_ sender: Any?) {
        let items = CommandRegistry.shared.all.map { command in
            PaletteItem(title: command.title, subtitle: command.defaultKeybinding) {
                CommandRegistry.shared.run(command.id)
            }
        }
        PaletteController.shared.show(items: items, placeholder: "Command Palette")
    }

    @objc func showFilePalette(_ sender: Any?) {
        let root = projectRoot
            ?? (NSDocumentController.shared.currentDocument as? TextDocument)?.fileURL?.deletingLastPathComponent()
        guard let root else {
            NSSound.beep() // nothing to index yet: no folder, no saved document
            return
        }
        let paths = ProjectIndexer.files(under: root, settings: SettingsStore.shared.settings)
        let items = paths.map { relative in
            PaletteItem(title: relative, subtitle: nil) {
                let url = root.appendingPathComponent(relative)
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
        let scope = projectRoot == nil
            ? "\(root.lastPathComponent) (current file's folder; File > Open Folder widens this)"
            : root.lastPathComponent
        PaletteController.shared.show(
            items: items,
            placeholder: "Goto Anything in \(scope)",
            emptyHint: "No match in \(root.lastPathComponent). File > Open Folder sets the project to search."
        )
    }

    // Help > Quickstart Guide: the bundled QUICKSTART.md opens in the
    // editor itself (our own Markdown highlighting + Cmd+Shift+M preview).
    @objc func openQuickstartGuide(_ sender: Any?) {
        guard let url = Bundle.main.url(forResource: "QUICKSTART", withExtension: "md") else {
            NSSound.beep()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectRoot = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    // Window chrome appearance. "auto" = nil = follow the OS; the editor
    // colors follow along via Theme.isDark (scheme files, Phase 3).
    static func applyAppearance(_ settings: EditorSettings) {
        NSApp.appearance = switch settings.theme {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    // hot_exit: quitting must reopen the same windows on relaunch.
    // NSQuitAlwaysKeepsWindows is the per-app switch for macOS's own
    // window restoration; setting it in OUR defaults domain wins over the
    // user's system-wide "close windows when quitting" preference. Together
    // with TextDocument.autosavesInPlace it restores unsaved buffers too.
    static func applyHotExit(_ settings: EditorSettings) {
        if settings.hotExit {
            UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        } else {
            UserDefaults.standard.removeObject(forKey: "NSQuitAlwaysKeepsWindows")
        }
    }
}
