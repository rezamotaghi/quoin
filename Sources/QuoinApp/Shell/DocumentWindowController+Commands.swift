import AppKit
import EditorCore
import SyntaxKit

/// View > Syntax choices, in menu order; the menu item's tag is the raw value.
enum SyntaxChoice: Int, CaseIterable {
    case plainText, swift, python, json, jsonc, markdown

    var title: String {
        switch self {
        case .plainText: "Plain Text"
        case .swift: "Swift"
        case .python: "Python"
        case .json: "JSON"
        case .jsonc: "JSONC"
        case .markdown: "Markdown"
        }
    }

    /// The file extension the highlighter factory understands.
    var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .swift: "swift"
        case .python: "py"
        case .json: "json"
        case .jsonc: "jsonc"
        case .markdown: "md"
        }
    }

    static func matching(extension ext: String) -> SyntaxChoice {
        switch ext.lowercased() {
        case "swift": .swift
        case "py", "pyi", "pyw": .python
        case "json": .json
        case "jsonc": .jsonc
        case "md", "markdown", "mdown": .markdown
        default: .plainText
        }
    }
}

/// The menu commands a document window answers beyond what the rented view
/// answers by itself: Sublime's Line, Comment, Convert Case, Permute Lines,
/// Selection, Goto Line, Syntax, Indentation, and the Agent menu. Each line
/// command is one pure LineOperations call applied as one undo step through
/// the same document path agent edits take (with its own undo name).
extension DocumentWindowController {

    private var primarySelection: Selection { pane.selectionSet.primary }

    private var indentUnit: String {
        let settings = SettingsStore.shared.settings
        let spaces = pane.translateTabsOverride ?? settings.translateTabsToSpaces
        return spaces ? String(repeating: " ", count: settings.tabSize) : "\t"
    }

    private func apply(_ edit: LineEdit?, named name: String) {
        guard let edit, let document = textDocument,
              document.replaceTextUndoable(range: edit.range, with: edit.replacement,
                                           actionName: name, selectionAfter: edit.selection)
        else {
            NSSound.beep()
            return
        }
    }

    // MARK: Edit > Line

    @objc func indentLines(_ sender: Any?) {
        apply(LineOperations.indent(primarySelection, in: pane.text, unit: indentUnit), named: "Indent")
    }

    @objc func unindentLines(_ sender: Any?) {
        apply(LineOperations.unindent(primarySelection, in: pane.text, tabSize: SettingsStore.shared.settings.tabSize), named: "Unindent")
    }

    @objc func swapLineUp(_ sender: Any?) {
        apply(LineOperations.swapUp(primarySelection, in: pane.text), named: "Swap Line Up")
    }

    @objc func swapLineDown(_ sender: Any?) {
        apply(LineOperations.swapDown(primarySelection, in: pane.text), named: "Swap Line Down")
    }

    @objc func duplicateLine(_ sender: Any?) {
        apply(LineOperations.duplicate(primarySelection, in: pane.text), named: "Duplicate Line")
    }

    @objc func deleteLine(_ sender: Any?) {
        apply(LineOperations.delete(primarySelection, in: pane.text), named: "Delete Line")
    }

    @objc func joinLines(_ sender: Any?) {
        apply(LineOperations.join(primarySelection, in: pane.text), named: "Join Lines")
    }

    // MARK: Edit > Comment, Convert Case, Sort, Permute

    @objc func toggleComment(_ sender: Any?) {
        guard let token = CommentTokens.lineComment(forFileExtension: fileExtension) else {
            NSSound.beep() // no line-comment syntax for this file type
            return
        }
        apply(LineOperations.toggleComment(primarySelection, in: pane.text, token: token), named: "Toggle Comment")
    }

    @objc func swapCase(_ sender: Any?) {
        apply(LineOperations.swapCase(primarySelection, in: pane.text), named: "Swap Case")
    }

    /// Tag 1 = case sensitive.
    @objc func sortLines(_ sender: Any?) {
        let caseSensitive = (sender as? NSMenuItem)?.tag == 1
        apply(LineOperations.permute(primarySelection, in: pane.text, .sort(caseSensitive: caseSensitive)), named: "Sort Lines")
    }

    /// Tags in menu order: 0 reverse, 1 unique, 2 shuffle.
    @objc func permuteLines(_ sender: Any?) {
        let (permutation, name): (LineOperations.Permutation, String) = switch (sender as? NSMenuItem)?.tag ?? 0 {
        case 1: (.unique, "Unique Lines")
        case 2: (.shuffle, "Shuffle Lines")
        default: (.reverse, "Reverse Lines")
        }
        apply(LineOperations.permute(primarySelection, in: pane.text, permutation), named: name)
    }

    // MARK: Selection

    @objc func splitSelectionIntoLines(_ sender: Any?) {
        pane.selectionSet = SelectionOperations.splitIntoLines(pane.selectionSet, in: pane.text)
    }

    @objc func singleSelection(_ sender: Any?) {
        pane.selectionSet = MultiCursor.collapsed(pane.selectionSet)
    }

    @objc func addPreviousLine(_ sender: Any?) {
        let set = SelectionOperations.addLine(pane.selectionSet, in: pane.text, forward: false)
        pane.selectionSet = set
        pane.reveal(offset: set.primary.head)
    }

    @objc func addNextLine(_ sender: Any?) {
        let set = SelectionOperations.addLine(pane.selectionSet, in: pane.text, forward: true)
        pane.selectionSet = set
        pane.reveal(offset: set.primary.head)
    }

    @objc func invertSelection(_ sender: Any?) {
        pane.selectionSet = SelectionOperations.invert(pane.selectionSet, in: pane.text)
    }

    // MARK: Goto

    @objc func gotoLine(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "This buffer has \(LineIndex.lineCount(in: pane.text)) lines."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.placeholderString = "Line number"
        field.stringValue = String(LineIndex.lineNumber(at: primarySelection.head, in: pane.text))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self,
                  let line = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            self.reveal(line: max(1, line))
            self.window?.makeFirstResponder(self.pane.focusView)
        }
    }

    // MARK: View > Syntax, Indentation

    @objc func setSyntax(_ sender: Any?) {
        guard let choice = SyntaxChoice(rawValue: (sender as? NSMenuItem)?.tag ?? -1) else { return }
        syntaxOverride = choice.fileExtension
        refreshDerived()
    }

    @objc func toggleIndentUsingSpaces(_ sender: Any?) {
        let current = pane.translateTabsOverride ?? SettingsStore.shared.settings.translateTabsToSpaces
        setIndentUsesSpaces(!current)
    }

    // MARK: Agent

    /// Undo only when the top of the stack is an agent edit; otherwise the
    /// user's own typing stays.
    @objc func undoLastAgentEdit(_ sender: Any?) {
        guard let manager = textDocument?.undoManager, manager.canUndo, manager.undoActionName == "AI Edit" else {
            NSSound.beep()
            return
        }
        manager.undo()
    }

    // MARK: Validation (checkmarks and enabling for the commands above)

    func validateCommandItem(_ item: any NSValidatedUserInterfaceItem) -> Bool? {
        guard let action = item.action else { return nil }
        let menuItem = item as? NSMenuItem
        if action == #selector(setSyntax(_:)) {
            menuItem?.state = SyntaxChoice.matching(extension: fileExtension).rawValue == menuItem?.tag ? .on : .off
            return true
        }
        if action == #selector(toggleIndentUsingSpaces(_:)) {
            menuItem?.state = (pane.translateTabsOverride ?? SettingsStore.shared.settings.translateTabsToSpaces) ? .on : .off
            return true
        }
        if action == #selector(undoLastAgentEdit(_:)) {
            guard let manager = textDocument?.undoManager else { return false }
            return manager.canUndo && manager.undoActionName == "AI Edit"
        }
        if action == #selector(toggleComment(_:)) {
            return CommentTokens.lineComment(forFileExtension: fileExtension) != nil
        }
        return nil
    }
}
