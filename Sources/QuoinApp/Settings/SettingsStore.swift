import AppKit
import EditorCore
import os

extension Notification.Name {
    /// Posted after the merged settings change (user file edited on disk).
    static let editorSettingsDidChange = Notification.Name("editorSettingsDidChange")
}

/// Loads settings (defaults layer + user layer) and hot-reloads when the
/// user's file changes on disk, Sublime-style: edit settings.jsonc in any
/// editor, watch the running app update.
///
/// Layers, lowest first:
///   1. EditorSettings() code defaults (always present)
///   2. default-settings.jsonc shipped in the app bundle (same values,
///      but the readable documented copy; absent under plain `swift run`)
///   3. ~/Library/Application Support/Quoin/settings.jsonc (the user)
@MainActor
final class SettingsStore {

    static let shared = SettingsStore()

    /// Thread-safe mirror of `settings.hotExit`, for the one AppKit query
    /// that arrives on background queues: NSDocument.autosavesInPlace during
    /// save preservation (crash-log-verified, 2026-07-08). Everything else
    /// reads `settings` on the main actor; do not grow this pattern without
    /// the same evidence.
    nonisolated static let hotExitMirror = OSAllocatedUnfairLock(initialState: EditorSettings().hotExit)

    private(set) var settings = EditorSettings() {
        didSet {
            let hotExit = settings.hotExit
            Self.hotExitMirror.withLock { $0 = hotExit }
        }
    }

    /// ~/Library/Application Support/Quoin/settings.jsonc
    let userFileURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Quoin/settings.jsonc")

    private var watcher: DispatchSourceFileSystemObject?

    func loadAndWatch() {
        // Make sure the directory exists so the user (and the watcher) have
        // a place to look, and drop a commented starter file on first run.
        let dir = userFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: userFileURL.path) {
            let starter = "// Quoin user settings (JSONC). Overrides the defaults key-by-key.\n// Same key names as Sublime Text. Saved changes apply to the running app.\n{\n}\n"
            try? starter.write(to: userFileURL, atomically: true, encoding: .utf8)
        }
        reload(notify: false)
        watchUserFile()
    }

    private func reload(notify: Bool) {
        var layers: [String] = []
        if let bundled = Bundle.main.url(forResource: "default-settings", withExtension: "jsonc"),
           let text = try? String(contentsOf: bundled, encoding: .utf8) {
            layers.append(text)
        }
        if let user = try? String(contentsOf: userFileURL, encoding: .utf8) {
            layers.append(user)
        }
        let merged = EditorSettings.merging(jsoncLayers: layers)
        guard merged != settings || !notify else { return }
        settings = merged
        if notify {
            NotificationCenter.default.post(name: .editorSettingsDidChange, object: nil)
        }
    }

    /// Kernel-level file watching: O_EVTONLY opens the file just for events,
    /// and the DispatchSource fires on writes. Editors that save atomically
    /// (write temp file, swap it in) replace the inode, which arrives as
    /// .rename/.delete, so on those we re-open the new file and keep watching.
    private func watchUserFile() {
        watcher?.cancel()
        watcher = nil
        let fd = open(userFileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let events = self.watcher?.data ?? []
                self.reload(notify: true)
                if events.contains(.rename) || events.contains(.delete) {
                    self.watchUserFile() // inode gone: re-attach to the new file
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
