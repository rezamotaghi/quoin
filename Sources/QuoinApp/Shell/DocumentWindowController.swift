import AppKit
import EditorCore
import SyntaxKit
import WebKit

/// One window (= one native tab) = one document = one editor pane. Owns the
/// pane, wires it to the document (text in/out, undo manager), re-applies
/// settings when the settings file changes on disk, drives syntax coloring,
/// and hosts the optional Markdown preview in a split view.
@MainActor
final class DocumentWindowController: NSWindowController {

    /// All editor panes in this window (Phase 5: 1 or 2). They share ONE
    /// text buffer; panes[0] is primary (saves read from it, reloads write
    /// through it, and the shared storage propagates to the rest).
    private var panes: [any EditorPane] = []
    private var pane: any EditorPane { panes[0] }
    private weak var textDocument: TextDocument?

    // Editor on the left, (optional) rendered Markdown preview on the right.
    private let splitView = NSSplitView()
    private var previewWebView: WKWebView?
    private var previewVisible = false

    /// One debounce for everything derived from the text (colors + preview).
    private var derivedRefreshTask: Task<Void, Never>?

    /// The highlight engine for this document's language (nil = plain text),
    /// rebuilt when the file extension changes.
    private var engine: (any HighlightEngine)?
    private var engineExtension: String?

    init(document: TextDocument) {
        textDocument = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        // Native macOS tabbing: .preferred means "new document windows join
        // the existing window as tabs" without any tab-strip code of ours.
        // The shared identifier is what lets documents group together.
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "QuoinDocument"
        super.init(window: window)
        shouldCascadeWindows = true

        // open_tabs_after_current: insert the new tab right of the active
        // one (Sublime default). Without this AppKit appends at the end.
        if SettingsStore.shared.settings.openTabsAfterCurrent,
           let current = NSApp.mainWindow, current.tabbingIdentifier == window.tabbingIdentifier {
            current.addTabbedWindow(window, ordered: .above)
        }

        let pane = makeEditorPane()
        panes = [pane]
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(pane.rootView)
        window.contentView = splitView
        pane.apply(SettingsStore.shared.settings)
        pane.text = document.text
        pane.translateTabsOverride = document.detectedIndentUsesSpaces
        pane.applyColors(currentPaneColors())
        // Route the view's undo registrations into the document's manager:
        // that single link gives us the dirty dot, Save enabling, and the
        // Undo/Redo menu items tracking edits.
        pane.undoManagerProvider = { [weak document] in document?.undoManager }
        pane.onTextChange = { [weak self] in self?.scheduleDerivedRefresh() }
        pane.onCancel = { [weak self] in self?.closePreviewIfVisible() ?? false }
        window.makeFirstResponder(pane.focusView)

        // Selector-based observation: auto-unregistered when this controller
        // deallocates, so no deinit bookkeeping.
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: .editorSettingsDidChange, object: nil
        )

        refreshDerived() // initial coloring for the just-loaded text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used; windows are built in code") }

    @objc private func settingsDidChange(_ note: Notification) {
        for pane in panes {
            pane.apply(SettingsStore.shared.settings)
            pane.applyColors(currentPaneColors())
        }
        refreshDerived() // theme may have flipped; recolor + re-render
    }

    // MARK: - Split editor (Phase 5)

    /// Two views, one buffer: the second pane adopts the first one's text
    /// storage, so edits, undo, and the dirty dot stay singular.
    @objc func toggleSplitEditor(_ sender: Any?) {
        if panes.count > 1 { removeSecondPane() } else { addSecondPane() }
    }

    private func addSecondPane() {
        let second = makeEditorPane()
        second.apply(SettingsStore.shared.settings)
        second.applyColors(currentPaneColors())
        second.adoptBuffer(of: pane)
        second.translateTabsOverride = pane.translateTabsOverride
        second.undoManagerProvider = { [weak self] in (self?.document as? TextDocument)?.undoManager }
        second.onTextChange = { [weak self] in self?.scheduleDerivedRefresh() }
        second.onCancel = { [weak self] in self?.closePreviewIfVisible() ?? false }
        panes.append(second)
        splitView.insertArrangedSubview(second.rootView, at: 1) // right of the editor, left of any preview
        DispatchQueue.main.async { [weak self] in
            guard let self, let width = self.window?.contentView?.bounds.width else { return }
            self.splitView.setPosition(width / 2, ofDividerAt: 0)
        }
        window?.makeFirstResponder(second.focusView)
        refreshDerived() // paint highlights onto the new pane's layout
    }

    private func removeSecondPane() {
        guard panes.count > 1 else { return }
        let second = panes.removeLast()
        second.rootView.removeFromSuperview()
        second.releaseBuffer(to: pane)
        window?.makeFirstResponder(pane.focusView)
    }

    /// The active scheme's "globals", resolved to colors for the pane.
    private func currentPaneColors() -> PaneColors {
        let globals = Theme.activeScheme.globals
        func color(_ key: String) -> NSColor? { globals[key].flatMap(SchemeStore.color(hex:)) }
        return PaneColors(
            background: color("background"),
            foreground: color("foreground"),
            caret: color("caret"),
            lineHighlight: color("line_highlight"),
            gutterForeground: color("gutter_foreground")
        )
    }

    /// What save writes: the live text in the view.
    var currentText: String { pane.text }

    /// The primary pane's selection (agent endpoint reads this).
    var currentSelection: SelectionSet { pane.selectionSet }

    /// Agent write path: replace a UTF-16 range with text, undoable, buffer
    /// only (nothing touches disk until the user saves). Returns false when
    /// the range is out of bounds. The document owns the undo/dirty logic
    /// (see TextDocument.replaceTextUndoable); this just forwards.
    func applyAgentEdit(range: Range<Int>, text: String) -> Bool {
        textDocument?.replaceTextUndoable(range: range, with: text) ?? false
    }

    /// The raw buffer swap the document's undoable operation drives. Called
    /// with the document's undo registration DISABLED, so STTextView adds no
    /// undo of its own (the document registers the single correct one).
    func replaceBufferText(in range: Range<Int>, with text: String) {
        pane.replaceText(in: range, with: text)
    }

    /// After an agent edit (or its undo/redo), select what changed and
    /// scroll it into view so the change is visible.
    func showEditedRange(_ range: Range<Int>) {
        let length = (pane.text as NSString).length
        let clamped = min(range.lowerBound, length)..<min(range.upperBound, length)
        pane.selectionSet = SelectionSet([Selection(anchor: clamped.lowerBound, head: clamped.upperBound)])
        pane.reveal(offset: clamped.lowerBound)
    }

    /// Put the caret at the start of a 1-based line and scroll it into view
    /// (quoin CLI, quoin:// links, and the agent's open_file all end here).
    func reveal(line: Int) {
        let ns = pane.text as NSString
        var offset = 0
        var current = 1
        while current < line, offset < ns.length {
            offset = NSMaxRange(ns.lineRange(for: NSRange(location: offset, length: 0)))
            current += 1
        }
        pane.selectionSet = SelectionSet([Selection(caretAt: offset)])
        pane.reveal(offset: offset)
    }

    // MARK: - Disk conflict banner (Amendment 1)

    private var conflictAccessory: NSTitlebarAccessoryViewController?

    /// The file changed on disk while this buffer has unsaved edits: the one
    /// case reload_file_on_change refuses to auto-resolve. Show a persistent,
    /// non-modal choice instead of silence.
    func showDiskConflictBanner() {
        guard conflictAccessory == nil else { return }
        let label = NSTextField(labelWithString: "File changed on disk. This buffer has unsaved edits.")
        label.font = .systemFont(ofSize: 11)
        let reload = NSButton(title: "Reload From Disk", target: self, action: #selector(conflictReload))
        let keep = NSButton(title: "Keep My Edits", target: self, action: #selector(conflictKeep))
        for button in [reload, keep] {
            button.controlSize = .small
            button.bezelStyle = .accessoryBarAction
        }
        let stack = NSStackView(views: [label, NSView(), reload, keep])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .bottom
        window?.addTitlebarAccessoryViewController(accessory)
        conflictAccessory = accessory
    }

    private func hideDiskConflictBanner() {
        conflictAccessory?.removeFromParent()
        conflictAccessory = nil
    }

    @objc private func conflictReload() {
        hideDiskConflictBanner()
        guard let document = textDocument, let url = document.fileURL else { return }
        try? document.revert(toContentsOf: url, ofType: document.fileType ?? DocumentController.textDocumentType)
    }

    @objc private func conflictKeep() {
        hideDiskConflictBanner()
    }

    /// Called just before the document snapshots the text for a save, so
    /// pre-save and post-save edits never coalesce into one undo group
    /// (that would make "undo back to saved" lie about dirtiness).
    func prepareForSave() {
        pane.breakUndoCoalescing()
    }

    /// Called by the document after read(from:) when the window already
    /// exists (Revert to Saved, or an external change reload): replace the
    /// view's content, keeping the caret near where it was.
    func documentTextDidReload() {
        guard let document = document as? TextDocument else { return }
        let previousSelection = pane.selectionSet
        pane.text = document.text
        let length = (document.text as NSString).length
        pane.selectionSet = SelectionSet(previousSelection.selections.map {
            Selection(anchor: min($0.anchor, length), head: min($0.head, length))
        }).normalized()
        pane.translateTabsOverride = document.detectedIndentUsesSpaces
        document.undoManager?.removeAllActions()
        refreshDerived()
        // follow_agent_edits: when an outside process (usually an agent)
        // rewrote this file and we reloaded it, surface its tab.
        if SettingsStore.shared.settings.followAgentEdits, let window {
            window.tabGroup?.selectedWindow = window
        }
    }

    // MARK: - Derived content (syntax colors + Markdown preview)

    private var fileExtension: String {
        (textDocument?.fileURL?.pathExtension
            ?? ((textDocument?.displayName ?? "") as NSString).pathExtension).lowercased()
    }

    private var isMarkdownDocument: Bool { ["md", "markdown", "mdown"].contains(fileExtension) }

    /// Typing triggers this; 150ms of quiet triggers the actual work. One
    /// debounce shared by coloring and preview so they never disagree.
    private func scheduleDerivedRefresh() {
        derivedRefreshTask?.cancel()
        derivedRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshDerived()
        }
    }

    private func refreshDerived() {
        applyHighlights()
        renderPreview()
    }

    /// The engine is per-language; rebuild it if the extension changed
    /// (Save As can rename a .txt into a .swift).
    private func ensureEngine() {
        let ext = fileExtension
        guard ext != engineExtension else { return }
        engineExtension = ext
        engine = HighlighterFactory.engine(forFileExtension: ext)
    }

    private func applyHighlights() {
        ensureEngine()
        guard let engine else {
            for pane in panes { pane.applyHighlights([]) }
            return
        }
        let content = pane.text
        engine.setText(content)
        let spans = engine.highlights(in: 0..<(content as NSString).length)
        // SyntaxKit gave semantic names; the active scheme turns them into
        // colors (invariant 5). Unmapped names simply stay foreground.
        let scheme = Theme.activeScheme
        let colored = spans.compactMap { span in
            scheme.hex(forStyle: span.styleName)
                .flatMap(SchemeStore.color(hex:))
                .map { (range: span.range, color: $0) }
        }
        // Rendering attributes live per layout manager, i.e. per pane.
        for pane in panes { pane.applyHighlights(colored) }
    }

    // MARK: - Markdown preview

    /// Escape closes the preview: returns whether there was one to close.
    func closePreviewIfVisible() -> Bool {
        guard previewVisible else { return false }
        toggleMarkdownPreview(nil)
        return true
    }

    @objc func toggleMarkdownPreview(_ sender: Any?) {
        previewVisible.toggle()
        if previewVisible {
            let webView = ensurePreviewWebView()
            splitView.addArrangedSubview(webView)
            // Split 50/50 once the divider exists in layout.
            DispatchQueue.main.async { [weak self] in
                guard let self, let width = self.window?.contentView?.bounds.width else { return }
                self.splitView.setPosition(width / 2, ofDividerAt: 0)
            }
            renderPreview()
        } else {
            previewWebView?.removeFromSuperview()
        }
    }

    private func ensurePreviewWebView() -> WKWebView {
        if let existing = previewWebView { return existing }
        let webView = WKWebView()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // no white flash on load
        previewWebView = webView
        return webView
    }

    private func renderPreview() {
        guard previewVisible, isMarkdownDocument, let webView = previewWebView else { return }
        let html = MarkdownHTML.page(markdown: pane.text, dark: Theme.isDark)
        // baseURL = the document's folder, so relative image paths resolve.
        webView.loadHTMLString(html, baseURL: textDocument?.fileURL?.deletingLastPathComponent())
    }
}

// Menu validation: the preview toggle only makes sense on Markdown files.
extension DocumentWindowController: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleMarkdownPreview(_:)) {
            if let menuItem = item as? NSMenuItem { menuItem.state = previewVisible ? .on : .off }
            return isMarkdownDocument
        }
        return true
    }
}

// "Interact with it": links in the preview open in the browser; everything
// else (the loadHTMLString content itself) renders in place.
extension DocumentWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
