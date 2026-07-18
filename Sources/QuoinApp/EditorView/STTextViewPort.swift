// The ONLY file in the app that may name the rented text view's concrete
// types (invariant 2). Everything here is translation between STTextView's
// world (TextKit 2: NSTextRange/NSTextSelection, opaque NSTextLocation) and
// EditorCore's world (plain UTF-16 integer offsets).
import AppKit
import EditorCore
// SPI: STTextView's plugin surface exposes contentFrame, the rect of the
// internal content view all TextKit segment coordinates are relative to.
// The whitespace overlay must live in that coordinate space (the content
// view sits right of the gutter, so raw textView coords are ~35pt off).
@_spi(Plugins) import STTextView

/// The shell's only way to obtain a pane; swap the rental by changing this
/// one function (plus a new conformance file).
@MainActor
func makeEditorPane() -> any EditorPane {
    STTextViewPort()
}

/// Small subclass for behaviors STTextView has no switches for.
/// copy_with_empty_selection: Cmd+C/Cmd+X with a plain caret acts on the
/// whole line, Sublime style.
private final class EditorTextView: STTextView {

    var copyWithEmptySelection = true

    /// The full line (including its newline) around the caret, as an NSRange.
    private var caretLineRange: NSRange? {
        guard selectedRange().length == 0, let content = text as NSString?, content.length > 0 else { return nil }
        return content.lineRange(for: NSRange(location: min(selectedRange().location, content.length), length: 0))
    }

    private func copyCaretLine() -> NSRange? {
        guard let lineRange = caretLineRange, lineRange.length > 0, let content = text as NSString? else { return nil }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content.substring(with: lineRange), forType: .string)
        return lineRange
    }

    override func copy(_ sender: Any?) {
        if copyWithEmptySelection, copyCaretLine() != nil { return }
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        if copyWithEmptySelection, let lineRange = copyCaretLine() {
            insertText("", replacementRange: lineRange) // undoable delete
            return
        }
        super.cut(sender)
    }

    // MARK: Multi-caret TYPING (Phase 6 fix, found by Reza 2026-07-12).
    // Upstream STTextView inserts at all carets but then collapses the
    // selection to a single caret, so only the first keystroke lands
    // everywhere. We replay the edit per caret (back to front, so earlier
    // offsets stay valid) and re-assert carets from EditorCore's arithmetic.

    /// Set by the port: consulted by cancelOperation before falling through
    /// (the window controller uses it to close the Markdown preview).
    var cancelFallback: (() -> Bool)?

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let selections = utf16SelectionSet.normalized()
        guard replacementRange.location == NSNotFound, selections.selections.count > 1,
              let inserted = string as? String else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        for selection in selections.selections.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            super.insertText(inserted, replacementRange: NSRange(location: selection.lowerBound, length: selection.range.count))
        }
        utf16SelectionSet = MultiCursor.caretsAfterReplacing(selections, insertLength: (inserted as NSString).length)
    }

    override func deleteBackward(_ sender: Any?) {
        let selections = utf16SelectionSet.normalized()
        guard selections.selections.count > 1 else { return super.deleteBackward(sender) }
        let ranges = MultiCursor.backwardDeletionRanges(for: selections)
        guard !ranges.isEmpty else { return }
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            super.insertText("", replacementRange: NSRange(location: range.lowerBound, length: range.count))
        }
        utf16SelectionSet = MultiCursor.caretsAfterDeleting(ranges: ranges, fallback: selections)
    }

    // MARK: Multi-cursor (Phase 6). The algebra lives in EditorCore
    // (MultiCursor, tested); this just moves SelectionSets in and out.

    @objc func selectNextOccurrence(_ sender: Any?) {
        applySelections(MultiCursor.selectingNextOccurrence(in: text ?? "", current: utf16SelectionSet))
    }

    @objc func selectAllOccurrences(_ sender: Any?) {
        applySelections(MultiCursor.selectingAllOccurrences(in: text ?? "", current: utf16SelectionSet))
    }

    private func applySelections(_ set: SelectionSet) {
        utf16SelectionSet = set
        scrollRangeToVisible(NSRange(location: set.primary.lowerBound, length: 0))
    }

    /// Escape, in priority order: collapse many carets to one, then close
    /// transient UI the window controller owns (Markdown preview), then
    /// whatever AppKit wants (find bar dismissal).
    override func cancelOperation(_ sender: Any?) {
        if textLayoutManager.textSelections.flatMap(\.textRanges).count > 1 {
            utf16SelectionSet = MultiCursor.collapsed(utf16SelectionSet)
        } else if cancelFallback?() == true {
            // consumed
        } else {
            super.cancelOperation(sender)
        }
    }
}

// Offset translation shared by the port and EditorTextView's own actions.
private extension STTextView {

    func utf16Offset(of location: any NSTextLocation) -> Int {
        textContentManager.offset(from: textContentManager.documentRange.location, to: location)
    }

    func textRange(fromUTF16 range: Range<Int>) -> NSTextRange? {
        guard let start = textContentManager.location(textContentManager.documentRange.location, offsetBy: range.lowerBound),
              let end = textContentManager.location(textContentManager.documentRange.location, offsetBy: range.upperBound)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    func nsRangeValue(from textRange: NSTextRange) -> NSRange {
        let location = utf16Offset(of: textRange.location)
        let length = textContentManager.offset(from: textRange.location, to: textRange.endLocation)
        return NSRange(location: location, length: length)
    }

    var utf16SelectionSet: SelectionSet {
        get {
            let selections = textLayoutManager.textSelections
                .flatMap(\.textRanges)
                .map { Selection(anchor: utf16Offset(of: $0.location), head: utf16Offset(of: $0.endLocation)) }
            return selections.isEmpty ? SelectionSet() : SelectionSet(selections).normalized()
        }
        set {
            let ranges = newValue.normalized().selections.compactMap { textRange(fromUTF16: $0.range) }
            guard !ranges.isEmpty else { return }
            textLayoutManager.textSelections = ranges.map {
                NSTextSelection(range: $0, affinity: .downstream, granularity: .character)
            }
            needsDisplay = true
        }
    }
}

@MainActor
final class STTextViewPort: NSObject, EditorPane {

    private let scrollView: NSScrollView
    private let textView: EditorTextView
    private var settings = EditorSettings()

    var onTextChange: (() -> Void)?
    var undoManagerProvider: (() -> UndoManager?)?
    var translateTabsOverride: Bool?
    var onCancel: (() -> Bool)? {
        get { textView.cancelFallback }
        set { textView.cancelFallback = newValue }
    }

    private let whitespaceOverlay = WhitespaceOverlay()

    override init() {
        scrollView = EditorTextView.scrollableTextView()
        textView = scrollView.documentView as! EditorTextView
        super.init()
        textView.delegate = self
        textView.allowsUndo = true
        textView.isIncrementalSearchingEnabled = true // live highlight while typing in the find bar
        scrollView.autohidesScrollers = true

        // draw_white_space overlay: sized with the text view, redrawn on
        // scroll (the "all" mode only marks the visible viewport).
        whitespaceOverlay.frame = textView.contentFrame
        textView.addSubview(whitespaceOverlay)
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        // At init TextKit has laid out nothing, so the first mark pass finds
        // zero segments. The text view's frame grows when layout lands (and
        // on window resize/wrap changes): that's the reliable "layout is
        // ready" signal to recompute.
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutChanged),
            name: NSView.frameDidChangeNotification, object: textView
        )
    }

    @objc private func scrolled(_ note: Notification) {
        if settings.whitespaceMode == .all { refreshWhitespaceMarks() }
    }

    @objc private func layoutChanged(_ note: Notification) {
        refreshWhitespaceMarks()
    }

    // MARK: EditorPane

    var rootView: NSView { scrollView }
    var focusView: NSView { textView }

    func apply(_ settings: EditorSettings) {
        self.settings = settings

        let size = settings.fontSize
        // "" means system monospace (SF Mono). A named font that fails to
        // load also falls back there rather than erroring.
        let font: NSFont = settings.fontFace.isEmpty
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont(name: settings.fontFace, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = font

        // Tab stops: one tab = tab_size times the width of a space in the
        // current font, repeating forever (defaultTabInterval).
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let style = NSMutableParagraphStyle()
        style.setParagraphStyle(.default)
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * CGFloat(settings.tabSize)
        textView.defaultParagraphStyle = style

        textView.showsLineNumbers = settings.lineNumbers
        textView.gutterView?.drawSeparator = true
        textView.gutterView?.highlightSelectedLine = settings.highlightLineNumber
        textView.highlightSelectedLine = settings.highlightLine
        textView.copyWithEmptySelection = settings.copyWithEmptySelection

        // widthTracksTextView = the text container follows the view's width,
        // i.e. word wrap. Off means lines run right and we scroll to them.
        textView.widthTracksTextView = settings.wordWrap
        scrollView.hasHorizontalScroller = !settings.wordWrap

        refreshWhitespaceMarks()
    }

    /// Scheme chrome. Colors come from the active scheme file's "globals";
    /// nil roles keep the system defaults.
    func applyColors(_ colors: PaneColors) {
        textView.backgroundColor = colors.background ?? .textBackgroundColor
        textView.textColor = colors.foreground ?? .textColor
        textView.insertionPointColor = colors.caret ?? .textInsertionPointColor
        if let lineHighlight = colors.lineHighlight {
            textView.selectedLineHighlightColor = lineHighlight
            textView.gutterView?.selectedLineHighlightColor = lineHighlight
        }
        if let gutterForeground = colors.gutterForeground {
            textView.gutterView?.textColor = gutterForeground
        }

        // "Lucent": ink at 30% is visible when you look for it, invisible
        // while reading. Derived from the current text color.
        whitespaceOverlay.ink = textView.textColor.withAlphaComponent(0.3)
        refreshWhitespaceMarks()
    }

    // MARK: draw_white_space

    private func refreshWhitespaceMarks() {
        // Track the content view's frame: segment rects are in ITS space,
        // and it moves/grows with the gutter and layout.
        whitespaceOverlay.frame = textView.contentFrame
        whitespaceOverlay.marks = whitespaceMarks()
    }

    private func whitespaceMarks() -> [WhitespaceOverlay.Mark] {
        let mode = settings.whitespaceMode
        guard mode != .none, let content = textView.text as NSString?, content.length > 0 else { return [] }

        var scanRanges: [NSRange] = []
        switch mode {
        case .selection:
            scanRanges = textView.textLayoutManager.textSelections
                .flatMap(\.textRanges)
                .filter { !$0.isEmpty }
                .map { nsRange(from: $0) }
        case .all:
            if let viewport = textView.textLayoutManager.textViewportLayoutController.viewportRange {
                scanRanges = [nsRange(from: viewport)]
            }
        case .none:
            return []
        }

        var marks: [WhitespaceOverlay.Mark] = []
        let docRange = NSRange(location: 0, length: content.length)
        for range in scanRanges {
            let clamped = NSIntersectionRange(range, docRange)
            var i = clamped.location
            while i < NSMaxRange(clamped), marks.count < 4000 { // sanity cap for huge selections
                let c = content.character(at: i)
                if c == 0x20 || c == 0x09, let charRange = textRange(from: i..<(i + 1)) {
                    textView.textLayoutManager.enumerateTextSegments(in: charRange, type: .standard, options: []) { _, frame, _, _ in
                        marks.append(WhitespaceOverlay.Mark(rect: frame, isTab: c == 0x09))
                        return false
                    }
                }
                i += 1
            }
        }
        return marks
    }

    // MARK: Syntax highlighting (rendering attributes)

    func applyHighlights(_ highlights: [(range: Range<Int>, color: NSColor)]) {
        let layoutManager = textView.textLayoutManager
        layoutManager.invalidateRenderingAttributes(for: layoutManager.documentRange)
        for (range, color) in highlights {
            guard let textRange = textRange(from: range) else { continue }
            layoutManager.setRenderingAttributes([.foregroundColor: color], for: textRange)
        }
    }

    // MARK: EditorViewPort

    var text: String {
        get { textView.text ?? "" }
        set { textView.text = newValue }
    }

    var selectionSet: SelectionSet {
        get { textView.utf16SelectionSet }
        set { textView.utf16SelectionSet = newValue }
    }

    func reveal(offset: Int) {
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }

    func breakUndoCoalescing() {
        textView.breakUndoCoalescing()
    }

    func replaceText(in range: Range<Int>, with text: String) {
        // Seal undo on both sides so the edit is one clean Cmd+Z step,
        // never merged with the user's typing before or after it.
        textView.breakUndoCoalescing()
        textView.insertText(text, replacementRange: NSRange(location: range.lowerBound, length: range.count))
        textView.breakUndoCoalescing()
    }

    // MARK: Split panes (shared text storage)

    func adoptBuffer(of primary: any EditorPane) {
        guard let primaryPort = primary as? STTextViewPort else { return }
        // STTextView's setter attaches our layout manager to the shared
        // content manager and (as a side effect) makes ours primary; give
        // the primary role straight back to the original pane.
        textView.textContentManager = primaryPort.textView.textContentManager
        textView.textContentManager.primaryTextLayoutManager = primaryPort.textView.textLayoutManager
    }

    func releaseBuffer(to primary: any EditorPane) {
        guard let primaryPort = primary as? STTextViewPort else { return }
        let shared = textView.textContentManager
        shared.removeTextLayoutManager(textView.textLayoutManager)
        shared.primaryTextLayoutManager = primaryPort.textView.textLayoutManager
    }

    // MARK: Offset translation (UTF-16 offsets <-> TextKit 2 locations)
    // The real conversions live in the STTextView extension below, shared
    // with EditorTextView's own actions.

    private func textRange(from range: Range<Int>) -> NSTextRange? {
        textView.textRange(fromUTF16: range)
    }

    private func nsRange(from textRange: NSTextRange) -> NSRange {
        textView.nsRangeValue(from: textRange)
    }
}

// @preconcurrency: the delegate protocol predates Swift concurrency and
// carries no isolation annotation; AppKit calls it on the main thread, so
// checking that at runtime instead of compile time is safe.
extension STTextViewPort: @preconcurrency STTextViewDelegate {

    func undoManager(for textView: STTextView) -> UndoManager? {
        undoManagerProvider?()
    }

    func textViewDidChangeText(_ notification: Notification) {
        refreshWhitespaceMarks()
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // draw_white_space ["selection"]: marks follow the selection live.
        if settings.whitespaceMode == .selection { refreshWhitespaceMarks() }
    }

    func textView(_ textView: STTextView, shouldChangeTextIn affectedCharRange: NSTextRange, replacementString: String?) -> Bool {
        // translate_tabs_to_spaces (or the per-file detect_indentation
        // override): swap the incoming tab for spaces and cancel the
        // original insertion.
        if translateTabsOverride ?? settings.translateTabsToSpaces, replacementString == "\t" {
            textView.insertText(String(repeating: " ", count: settings.tabSize), replacementRange: nsRange(from: affectedCharRange))
            return false
        }
        return true
    }
}
