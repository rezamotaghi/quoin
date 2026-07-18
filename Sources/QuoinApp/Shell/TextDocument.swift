import AppKit
import EditorCore

/// One open file. NSDocument supplies the machinery (save panels, dirty
/// tracking, revert, recents, autosave); this subclass converts bytes <->
/// String, applies save-time transforms, and creates its window controller.
///
/// Dirty state works through the undo manager: the editor view registers its
/// undo actions with this document's UndoManager (see DocumentWindowController),
/// and NSDocument watches that manager to flip the window's dirty dot and
/// enable Save automatically.
@objc(TextDocument)
final class TextDocument: NSDocument {

    /// The document model. The live view is pushed into this on save and
    /// pulled from it on open/revert.
    var text: String = ""

    /// detect_indentation result for this file (true = spaces, false = tabs,
    /// nil = undecided/disabled): drives the pane's tab-translation override.
    var detectedIndentUsesSpaces: Bool?

    /// True only while an explicit Save/Save As is writing, so autosave
    /// (hot exit) never mutates the buffer with save-time transforms.
    private var isExplicitSave = false

    override nonisolated class var autosavesInPlace: Bool {
        // hot_exit: autosave-in-place is what lets unsaved work survive
        // quit-and-relaunch without dialogs. AppKit queries this from
        // BACKGROUND queues during save preservation
        // (_preserveContentsIfNecessaryAfterWriting, crash 2026-07-08), so
        // it must stay nonisolated and read only the lock-guarded mirror.
        SettingsStore.hotExitMirror.withLock { $0 }
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: - Agent edits (undoable, buffer-only)
    //
    // Agent writes are a proper document-level undoable operation we fully
    // control, NOT STTextView's internal undo. Why: STTextView's undo
    // range-arithmetic corrupted full-buffer replaces, and its change-count
    // propagation to NSDocument didn't fire for programmatic edits (both
    // found by Reza 2026-07-12). Here we capture the exact old text, do the
    // swap with STTextView's undo registration suppressed, and register the
    // one correct inverse ourselves. Result: one Cmd+Z reverts the agent
    // exactly, and the dirty dot tracks in both directions. Disk is never
    // touched; the user's save is the only thing that writes.

    /// Replace a UTF-16 range with text as a single undoable buffer edit.
    /// Returns false if the range is out of bounds.
    @discardableResult
    func replaceTextUndoable(range: Range<Int>, with newText: String) -> Bool {
        guard let wc = windowControllers.first as? DocumentWindowController else { return false }
        let length = (wc.currentText as NSString).length
        guard range.lowerBound >= 0, range.upperBound <= length, range.lowerBound <= range.upperBound else { return false }
        let oldText = (wc.currentText as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
        applyUndoableReplace(range: range, newText: newText, oldText: oldText, in: wc)
        return true
    }

    private func applyUndoableReplace(range: Range<Int>, newText: String, oldText: String, in wc: DocumentWindowController) {
        // The inverse edit: replace what we're about to insert with what was
        // there. Registered before the swap; the closure re-registers its
        // own inverse (redo) when it runs, the standard NSUndoManager dance.
        let newRange = range.lowerBound..<(range.lowerBound + (newText as NSString).length)
        // AppKit runs undo on the main thread; the closure signature is
        // nonisolated, so assert it.
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                guard let wc = doc.windowControllers.first as? DocumentWindowController else { return }
                doc.applyUndoableReplace(range: newRange, newText: oldText, oldText: newText, in: wc)
            }
        }
        undoManager?.setActionName("AI Edit")

        let undoing = undoManager?.isUndoing ?? false
        let redoing = undoManager?.isRedoing ?? false

        // Suppress STTextView's own undo registration for this swap.
        undoManager?.disableUndoRegistration()
        wc.replaceBufferText(in: range, with: newText)
        undoManager?.enableUndoRegistration()

        // NSDocument doesn't auto-count these programmatic edits, so count
        // explicitly and symmetrically: do -> dirtier, undo -> cleaner.
        if undoing { updateChangeCount(.changeUndone) }
        else if redoing { updateChangeCount(.changeRedone) }
        else { updateChangeCount(.changeDone) }

        wc.showEditedRange(newRange)
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping ((any Error)?) -> Void) {
        isExplicitSave = saveOperation == .saveOperation || saveOperation == .saveAsOperation
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            self?.isExplicitSave = false
            completionHandler(error)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        if let wc = windowControllers.first as? DocumentWindowController {
            wc.prepareForSave()
            text = wc.currentText
        }
        if isExplicitSave {
            let settings = SettingsStore.shared.settings
            let transformed = SaveTransforms.apply(
                to: text,
                trimTrailingWhitespace: settings.trimsTrailingWhitespaceOnSave,
                ensureFinalNewline: settings.ensureNewlineAtEOFOnSave
            )
            if transformed != text {
                text = transformed
                // Keep the buffer identical to what lands on disk.
                (windowControllers.first as? DocumentWindowController)?.documentTextDidReload()
            }
        }
        return Data(text.utf8) // default_encoding: UTF-8
    }

    // The SDK marks read(from:) nonisolated because documents CAN opt into
    // concurrent opening; we don't (canConcurrentlyReadDocuments stays
    // false), so every read arrives on the main thread and we assert that.
    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            if let decoded = String(data: data, encoding: .utf8) {
                text = decoded
            } else if let decoded = String(data: data, encoding: Self.encoding(named: SettingsStore.shared.settings.fallbackEncoding)) {
                text = decoded
            } else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError, userInfo: [
                    NSLocalizedDescriptionKey: "This file could not be decoded as text (tried UTF-8 and the fallback encoding).",
                ])
            }
            detectedIndentUsesSpaces = SettingsStore.shared.settings.detectIndentation
                ? IndentationDetector.usesSpaces(in: text)
                : nil
            // On revert, the window already exists: push the fresh text into it.
            for wc in windowControllers {
                (wc as? DocumentWindowController)?.documentTextDidReload()
            }
        }
    }

    // reload_file_on_change: NSDocument is an NSFilePresenter, so the system
    // tells us when another program writes our file. If the buffer is clean,
    // reload silently (Sublime behavior); if it has unsaved edits, keep them.
    override nonisolated func presentedItemDidChange() {
        Task { @MainActor [weak self] in
            self?.reloadIfChangedOnDisk()
        }
    }

    private func reloadIfChangedOnDisk() {
        guard SettingsStore.shared.settings.reloadFileOnChange,
              let url = fileURL else { return }
        // Our own saves also ping the presenter; skip when disk matches what
        // we last read/wrote.
        let diskDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let diskDate, diskDate != fileModificationDate else { return }
        if isDocumentEdited {
            // Unsaved edits + a changed disk file: never auto-resolve.
            // Surface the conflict and let Reza pick (Amendment 1).
            (windowControllers.first as? DocumentWindowController)?.showDiskConflictBanner()
            return
        }
        try? revert(toContentsOf: url, ofType: fileType ?? DocumentController.textDocumentType)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // A code editor saves to any extension; don't let the panel force .txt.
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    /// Map a settings-file encoding name to a Foundation encoding.
    static func encoding(named name: String) -> String.Encoding {
        switch name.lowercased() {
        case "utf-8": .utf8
        case "utf-16", "utf-16 le": .utf16LittleEndian
        case "utf-16 be": .utf16BigEndian
        case "windows-1252", "western (windows 1252)": .windowsCP1252
        case "iso-8859-1", "western (iso 8859-1)": .isoLatin1
        case "macintosh", "western (mac roman)": .macOSRoman
        default: .windowsCP1252
        }
    }
}
