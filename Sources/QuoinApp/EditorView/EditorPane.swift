import AppKit
import EditorCore

/// What the shell needs from an editor pane, beyond the pure EditorViewPort
/// data protocol: a view to install, settings application, and wiring hooks.
/// The shell talks only to this protocol and obtains instances through
/// makeEditorPane(), so no code outside EditorView/ ever names the rented
/// text view's types (invariant 2). Swapping the rental = one new
/// conformance + changing makeEditorPane().
@MainActor
protocol EditorPane: EditorViewPort {
    /// The view to install as window content (the scroll view).
    var rootView: NSView { get }

    /// The view that should become first responder (the text view itself).
    var focusView: NSView { get }

    /// Called after each committed text edit.
    var onTextChange: (() -> Void)? { get set }

    /// Escape pressed with nothing pane-internal to cancel: return true if
    /// the shell consumed it (e.g. closed the Markdown preview), false to
    /// let AppKit have it.
    var onCancel: (() -> Bool)? { get set }

    /// The pane registers its undo actions with this manager; handing it the
    /// document's UndoManager is what makes the dirty dot and the Undo menu
    /// track edits automatically.
    var undoManagerProvider: (() -> UndoManager?)? { get set }

    /// Apply font, tab size, wrap, line numbers, theme colors.
    func apply(_ settings: EditorSettings)

    /// Per-document override of translate_tabs_to_spaces, set from
    /// detect_indentation when a file opens (true = spaces, false = tabs,
    /// nil = follow the global setting).
    var translateTabsOverride: Bool? { get set }

    /// Seal the current undo group so edits after a save never merge with
    /// edits before it (keeps the dirty dot honest across save + undo).
    func breakUndoCoalescing()

    /// Replace a UTF-16 range with text as a NORMAL, undoable edit: exactly
    /// the path typing takes, so undo, the dirty dot, and delegate hooks all
    /// behave. Agent writes come through here; one Cmd+Z reverts them.
    func replaceText(in range: Range<Int>, with text: String)

    /// Replace all syntax coloring with these (range, color) pairs.
    /// Implemented as TextKit 2 rendering attributes: purely visual, never
    /// touches the text storage, so undo and dirty state stay untouched.
    func applyHighlights(_ highlights: [(range: Range<Int>, color: NSColor)])

    /// Apply the active color scheme's chrome (background, text, caret...).
    /// Split from apply(_ settings:) because these change with the OS
    /// appearance too, not only with the settings file.
    func applyColors(_ colors: PaneColors)

    /// Split panes (Phase 5): make this pane render and edit the SAME text
    /// storage as `primary` (TextKit 2 allows N layout managers, i.e. N
    /// views, on one content manager). Edits in either pane appear in both;
    /// there is exactly one buffer, one undo stack, one dirty state.
    func adoptBuffer(of primary: any EditorPane)

    /// Tear down what adoptBuffer set up, before this pane is discarded:
    /// detach from the shared storage and hand coordination back to the
    /// primary pane. Skipping this leaves a zombie layout manager attached
    /// to the buffer, paying layout cost on every future edit.
    func releaseBuffer(to primary: any EditorPane)
}

/// The scheme "globals" resolved to platform colors. nil = keep the system
/// default for that role.
struct PaneColors {
    var background: NSColor?
    var foreground: NSColor?
    var caret: NSColor?
    var lineHighlight: NSColor?
    var gutterForeground: NSColor?
}
