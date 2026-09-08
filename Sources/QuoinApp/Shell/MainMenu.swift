import AppKit
import CommandKit

/// The menu bar as a projection of the CommandRegistry (invariant 3).
///
/// Every command maps to a standard AppKit responder-chain selector
/// ("first responder" = whatever has focus; AppKit walks focused view ->
/// window -> window controller -> document -> app -> app delegate asking who
/// handles the action). One spec table drives both the registration (Command
/// whose action re-sends the selector, so the palette and the agent surface
/// can run it) and the menu item (which uses the selector directly, so
/// AppKit's built-in enabling/dimming and checkmarks keep working).
///
/// The vocabulary is Sublime Text's Main.sublime-menu, trimmed to what a
/// single-buffer editor without plugins can honor. AppKit adds its own items
/// at runtime and they are deliberately NOT declared here: Open Recent,
/// Close All / Close Tab, Enter Full Screen, Show Tab Bar / Show All Tabs,
/// Start Dictation, Emoji & Symbols, Writing Tools, and the Window menu's
/// arrangement commands.
@MainActor
enum MainMenu {

    private struct Item {
        let id: String
        let title: String        // palette-facing, e.g. "File: Save"
        let menuTitle: String    // menu-facing, e.g. "Save"
        let key: String?         // "cmd+shift+s" style, Sublime-ish notation
        let selector: String     // Objective-C selector name
        let tag: Int             // some selectors (find bar, export, syntax) dispatch on the sender's tag

        init(_ id: String, _ title: String, _ menuTitle: String, _ key: String?, _ selector: String, tag: Int = 0) {
            self.id = id
            self.title = title
            self.menuTitle = menuTitle
            self.key = key
            self.selector = selector
            self.tag = tag
        }
    }

    private enum Entry {
        case item(Item)
        case separator
        case submenu(String, [Entry])
    }

    private static let appMenu: [Entry] = [
        .item(Item("app.about", "Quoin: About", "About Quoin", nil, "orderFrontStandardAboutPanel:")),
        .separator,
        .item(Item("app.settings", "Quoin: Settings", "Settings…", "cmd+,", "openSettings:")),
        .separator,
        .submenu("Services", []), // AppKit fills this one (NSApp.servicesMenu)
        .separator,
        .item(Item("app.hide", "Quoin: Hide", "Hide Quoin", "cmd+h", "hide:")),
        .item(Item("app.hideOthers", "Quoin: Hide Others", "Hide Others", "cmd+alt+h", "hideOtherApplications:")),
        .item(Item("app.showAll", "Quoin: Show All", "Show All", nil, "unhideAllApplications:")),
        .separator,
        .item(Item("app.quit", "Quoin: Quit", "Quit Quoin", "cmd+q", "terminate:")),
    ]

    private static let fileMenu: [Entry] = [
        .item(Item("file.new", "File: New File", "New", "cmd+n", "newDocument:")),
        .item(Item("file.open", "File: Open", "Open…", "cmd+o", "openDocument:")),
        .item(Item("file.openFolder", "File: Open Folder", "Open Folder…", nil, "openFolder:")),
        .separator,
        .item(Item("file.close", "File: Close Window", "Close", "cmd+w", "performClose:")),
        .item(Item("file.save", "File: Save", "Save", "cmd+s", "saveDocument:")),
        // Custom selector on purpose: with autosave-in-place on, AppKit
        // rewrites any "saveDocumentAs:" item into Duplicate/Rename/Move To
        // and hides Save As behind the Option key. Quoin keeps it visible.
        // Deliberately NO key binding: claiming cmd+shift+s made AppKit
        // render its own extra Save As alternate visibly (tested 2026-07-09);
        // unbound, the system block keeps Duplicate=cmd+shift+s and this
        // stays the one visible Save As. (A Save All item was tried
        // 2026-09-08: AppKit hides it under autosave-in-place, so none.)
        .item(Item("file.saveAs", "File: Save As", "Save As…", nil, "saveDocumentAsExplicit:")),
        .separator,
        .submenu("Export", [
            .item(Item("file.exportMarkdown", "File: Export as Markdown", "Markdown (.md)…", nil,
                       "exportDocument:", tag: ExportFormat.markdown.rawValue)),
            .item(Item("file.exportPlainText", "File: Export as Plain Text", "Plain Text (.txt)…", nil,
                       "exportDocument:", tag: ExportFormat.plainText.rawValue)),
            .item(Item("file.exportPDF", "File: Export as PDF", "PDF (.pdf)…", nil,
                       "exportDocument:", tag: ExportFormat.pdf.rawValue)),
        ]),
        .item(Item("file.revealInFinder", "File: Reveal in Finder", "Reveal in Finder", nil, "revealInFinder:")),
        .separator,
        .item(Item("file.revert", "File: Revert to Saved", "Revert to Saved", nil, "revertDocumentToSaved:")),
        .separator,
        // No key: Cmd+P is Goto Anything, as in Sublime.
        .item(Item("file.print", "File: Print", "Print…", nil, "printDocument:")),
    ]

    private static let lineSubmenu: [Entry] = [
        .item(Item("edit.indent", "Edit: Indent", "Indent", "cmd+]", "indentLines:")),
        .item(Item("edit.unindent", "Edit: Unindent", "Unindent", "cmd+[", "unindentLines:")),
        .separator,
        .item(Item("edit.swapLineUp", "Edit: Swap Line Up", "Swap Line Up", "ctrl+cmd+up", "swapLineUp:")),
        .item(Item("edit.swapLineDown", "Edit: Swap Line Down", "Swap Line Down", "ctrl+cmd+down", "swapLineDown:")),
        .separator,
        .item(Item("edit.duplicateLine", "Edit: Duplicate Line", "Duplicate Line", "cmd+shift+d", "duplicateLine:")),
        .item(Item("edit.deleteLine", "Edit: Delete Line", "Delete Line", "ctrl+shift+k", "deleteLine:")),
        .item(Item("edit.joinLines", "Edit: Join Lines", "Join Lines", "cmd+shift+j", "joinLines:")),
    ]

    private static let convertCaseSubmenu: [Entry] = [
        .item(Item("edit.titleCase", "Edit: Title Case", "Title Case", nil, "capitalizeWord:")),
        .item(Item("edit.upperCase", "Edit: Upper Case", "Upper Case", nil, "uppercaseWord:")),
        .item(Item("edit.lowerCase", "Edit: Lower Case", "Lower Case", nil, "lowercaseWord:")),
        .item(Item("edit.swapCase", "Edit: Swap Case", "Swap Case", nil, "swapCase:")),
    ]

    private static let spellingSubmenu: [Entry] = [
        .item(Item("edit.showSpelling", "Edit: Show Spelling and Grammar", "Show Spelling and Grammar", "cmd+:", "showGuessPanel:")),
        .item(Item("edit.checkSpelling", "Edit: Check Document Now", "Check Document Now", "cmd+;", "checkSpelling:")),
        .separator,
        .item(Item("edit.checkSpellingWhileTyping", "Edit: Check Spelling While Typing", "Check Spelling While Typing", nil, "toggleContinuousSpellChecking:")),
        .item(Item("edit.checkGrammarWithSpelling", "Edit: Check Grammar With Spelling", "Check Grammar With Spelling", nil, "toggleGrammarChecking:")),
        .item(Item("edit.correctSpellingAutomatically", "Edit: Correct Spelling Automatically", "Correct Spelling Automatically", nil, "toggleAutomaticSpellingCorrection:")),
    ]

    private static let editMenu: [Entry] = [
        .item(Item("edit.undo", "Edit: Undo", "Undo", "cmd+z", "undo:")),
        .item(Item("edit.redo", "Edit: Redo", "Redo", "cmd+shift+z", "redo:")),
        .separator,
        .item(Item("edit.cut", "Edit: Cut", "Cut", "cmd+x", "cut:")),
        .item(Item("edit.copy", "Edit: Copy", "Copy", "cmd+c", "copy:")),
        .item(Item("edit.paste", "Edit: Paste", "Paste", "cmd+v", "paste:")),
        .item(Item("edit.pasteAndMatchStyle", "Edit: Paste and Match Style", "Paste and Match Style", "cmd+alt+shift+v", "pasteAsPlainText:")),
        .item(Item("edit.delete", "Edit: Delete", "Delete", nil, "delete:")),
        .separator,
        .item(Item("edit.selectAll", "Edit: Select All", "Select All", "cmd+a", "selectAll:")),
        .separator,
        .submenu("Line", lineSubmenu),
        .submenu("Comment", [
            .item(Item("edit.toggleComment", "Edit: Toggle Comment", "Toggle Comment", "cmd+/", "toggleComment:")),
        ]),
        .submenu("Convert Case", convertCaseSubmenu),
        .separator,
        .item(Item("edit.sortLines", "Edit: Sort Lines", "Sort Lines", "f5", "sortLines:", tag: 0)),
        .item(Item("edit.sortLinesCaseSensitive", "Edit: Sort Lines (Case Sensitive)", "Sort Lines (Case Sensitive)", "ctrl+f5", "sortLines:", tag: 1)),
        .submenu("Permute Lines", [
            .item(Item("edit.reverseLines", "Edit: Reverse Lines", "Reverse", nil, "permuteLines:", tag: 0)),
            .item(Item("edit.uniqueLines", "Edit: Unique Lines", "Unique", nil, "permuteLines:", tag: 1)),
            .item(Item("edit.shuffleLines", "Edit: Shuffle Lines", "Shuffle", nil, "permuteLines:", tag: 2)),
        ]),
        .separator,
        .submenu("Spelling and Grammar", spellingSubmenu),
        .submenu("Substitutions", [
            .item(Item("edit.showSubstitutions", "Edit: Show Substitutions", "Show Substitutions", nil, "orderFrontSubstitutionsPanel:")),
            .separator,
            .item(Item("edit.smartQuotes", "Edit: Smart Quotes", "Smart Quotes", nil, "toggleAutomaticQuoteSubstitution:")),
        ]),
        .submenu("Speech", [
            .item(Item("edit.startSpeaking", "Edit: Start Speaking", "Start Speaking", nil, "startSpeaking:")),
            .item(Item("edit.stopSpeaking", "Edit: Stop Speaking", "Stop Speaking", nil, "stopSpeaking:")),
        ]),
    ]

    // Multi-cursor (Phase 6) plus Sublime's Selection menu. The occurrence
    // commands keep Quoin's plainer captions over Sublime's ("Expand
    // Selection to Word" / "Quick Add Next").
    private static let selectionMenu: [Entry] = [
        .item(Item("selection.splitIntoLines", "Selection: Split into Lines", "Split into Lines", "cmd+shift+l", "splitSelectionIntoLines:")),
        .item(Item("selection.single", "Selection: Single Selection", "Single Selection", nil, "singleSelection:")),
        .separator,
        .item(Item("selection.expandToLine", "Selection: Expand Selection to Line", "Expand Selection to Line", "cmd+l", "selectLine:")),
        .item(Item("selection.expandToWord", "Selection: Expand Selection to Word", "Expand Selection to Word", nil, "selectWord:")),
        .item(Item("selection.expandToParagraph", "Selection: Expand Selection to Paragraph", "Expand Selection to Paragraph", nil, "selectParagraph:")),
        .separator,
        .item(Item("selection.addPreviousLine", "Selection: Add Previous Line", "Add Previous Line", "ctrl+shift+up", "addPreviousLine:")),
        .item(Item("selection.addNextLine", "Selection: Add Next Line", "Add Next Line", "ctrl+shift+down", "addNextLine:")),
        .separator,
        .item(Item("selection.addNext", "Selection: Add Next Occurrence", "Add Next Occurrence", "cmd+d", "selectNextOccurrence:")),
        .item(Item("selection.selectAllOccurrences", "Selection: Select All Occurrences", "Select All Occurrences", "ctrl+cmd+g", "selectAllOccurrences:")),
        .item(Item("selection.invert", "Selection: Invert Selection", "Invert Selection", nil, "invertSelection:")),
    ]

    // The find bar is AppKit's NSTextFinder (the same one TextEdit/Xcode use,
    // already wired up inside the rented view). One selector handles every
    // find action; the menu item's TAG says which action.
    private static let findMenu: [Entry] = [
        .item(Item("find.find", "Find: Find", "Find…", "cmd+f",
                   "performTextFinderAction:", tag: NSTextFinder.Action.showFindInterface.rawValue)),
        .item(Item("find.next", "Find: Find Next", "Find Next", "cmd+g",
                   "performTextFinderAction:", tag: NSTextFinder.Action.nextMatch.rawValue)),
        .item(Item("find.previous", "Find: Find Previous", "Find Previous", "cmd+shift+g",
                   "performTextFinderAction:", tag: NSTextFinder.Action.previousMatch.rawValue)),
        .separator,
        .item(Item("find.findAndReplace", "Find: Find and Replace", "Find and Replace…", "cmd+alt+f",
                   "performTextFinderAction:", tag: NSTextFinder.Action.showReplaceInterface.rawValue)),
        .separator,
        .item(Item("find.useSelection", "Find: Use Selection for Find", "Use Selection for Find", "cmd+e",
                   "performTextFinderAction:", tag: NSTextFinder.Action.setSearchString.rawValue)),
        .separator,
        .item(Item("find.hide", "Find: Hide Find Bar", "Hide Find Bar", nil,
                   "performTextFinderAction:", tag: NSTextFinder.Action.hideFindInterface.rawValue)),
    ]

    private static let viewMenu: [Entry] = [
        .item(Item("view.toggleWordWrap", "View: Toggle Word Wrap", "Word Wrap", nil, "toggleWordWrap:")),
        .item(Item("view.toggleLineNumbers", "View: Toggle Line Numbers", "Line Numbers", nil, "toggleLineNumbers:")),
        .submenu("Whitespace", [
            .item(Item("view.whitespaceNone", "View: Whitespace None", "None", nil, "setWhitespaceMode:", tag: 0)),
            .item(Item("view.whitespaceSelection", "View: Whitespace in Selection", "In Selection", nil, "setWhitespaceMode:", tag: 1)),
            .item(Item("view.whitespaceAll", "View: Whitespace All", "All", nil, "setWhitespaceMode:", tag: 2)),
        ]),
        .separator,
        .submenu("Syntax", SyntaxChoice.allCases.map { choice in
            .item(Item("view.syntax\(choice.title.replacingOccurrences(of: " ", with: ""))",
                       "View: Syntax \(choice.title)", choice.title, nil, "setSyntax:", tag: choice.rawValue))
        }),
        .submenu("Indentation", [
            .item(Item("view.indentUsingSpaces", "View: Indent Using Spaces", "Indent Using Spaces", nil, "toggleIndentUsingSpaces:")),
            .separator,
            .item(Item("view.tabWidth2", "View: Tab Width 2", "Tab Width: 2", nil, "setTabWidth:", tag: 2)),
            .item(Item("view.tabWidth4", "View: Tab Width 4", "Tab Width: 4", nil, "setTabWidth:", tag: 4)),
            .item(Item("view.tabWidth8", "View: Tab Width 8", "Tab Width: 8", nil, "setTabWidth:", tag: 8)),
        ]),
        .separator,
        .submenu("Font", [
            .item(Item("view.fontLarger", "View: Font Larger", "Larger", "cmd+=", "fontLarger:")),
            .item(Item("view.fontSmaller", "View: Font Smaller", "Smaller", "cmd+-", "fontSmaller:")),
            .separator,
            .item(Item("view.fontReset", "View: Font Reset", "Reset", nil, "fontReset:")),
        ]),
        .submenu("Theme", [
            .item(Item("view.themeAuto", "View: Theme Auto", "Auto (Follow System)", nil, "setTheme:", tag: 0)),
            .item(Item("view.themeLight", "View: Theme Light", "Light", nil, "setTheme:", tag: 1)),
            .item(Item("view.themeDark", "View: Theme Dark", "Dark", nil, "setTheme:", tag: 2)),
        ]),
        .separator,
        .item(Item("view.toggleMarkdownPreview", "View: Toggle Markdown Preview", "Markdown Preview", "cmd+shift+m", "toggleMarkdownPreview:")),
        .item(Item("view.toggleSplitEditor", "View: Toggle Split Editor", "Split Editor", "cmd+alt+2", "toggleSplitEditor:")),
    ]

    // Sublime's Goto menu: the palette twins (Phase 4) plus line and scroll.
    private static let gotoMenu: [Entry] = [
        .item(Item("goto.anything", "Goto: Goto Anything", "Goto Anything…", "cmd+p", "showFilePalette:")),
        .item(Item("goto.commandPalette", "Goto: Command Palette", "Command Palette…", "cmd+shift+p", "showCommandPalette:")),
        .separator,
        .item(Item("goto.line", "Goto: Goto Line", "Goto Line…", "ctrl+g", "gotoLine:")),
        .separator,
        .item(Item("goto.scrollToSelection", "Goto: Scroll to Selection", "Scroll to Selection", "ctrl+l", "centerSelectionInVisibleArea:")),
    ]

    // Amendment 2: the agent surface gets its own menu; every item is also a
    // verb an agent can run, except the ones that would switch it off.
    private static let agentMenu: [Entry] = [
        .item(Item("agent.status", "Agent: Agent Status", "Agent Status…", nil, "showAgentStatus:")),
        .item(Item("agent.copySetupCommand", "Agent: Copy MCP Setup Command", "Copy MCP Setup Command", nil, "copyAgentSetupCommand:")),
        .separator,
        .item(Item("agent.toggleServer", "Agent: Toggle Agent Server", "Agent Server", nil, "toggleAgentServer:")),
        .item(Item("agent.toggleFollowEdits", "Agent: Toggle Follow Agent Edits", "Follow Agent Edits", nil, "toggleFollowAgentEdits:")),
        .separator,
        .item(Item("agent.undoLastEdit", "Agent: Undo Last Agent Edit", "Undo Last Agent Edit", nil, "undoLastAgentEdit:")),
        .separator,
        .item(Item("agent.guide", "Agent: How to Connect an Agent", "How to Connect an Agent", nil, "openQuickstartGuide:")),
    ]

    private static let windowMenu: [Entry] = [
        .item(Item("window.minimize", "Window: Minimize", "Minimize", "cmd+m", "performMiniaturize:")),
        .item(Item("window.zoom", "Window: Zoom", "Zoom", nil, "performZoom:")),
        .separator,
        .item(Item("window.previousTab", "Window: Show Previous Tab", "Show Previous Tab", "cmd+shift+[", "selectPreviousTab:")),
        .item(Item("window.nextTab", "Window: Show Next Tab", "Show Next Tab", "cmd+shift+]", "selectNextTab:")),
        .item(Item("window.moveTabToNewWindow", "Window: Move Tab to New Window", "Move Tab to New Window", nil, "moveTabToNewWindow:")),
        .item(Item("window.mergeAllWindows", "Window: Merge All Windows", "Merge All Windows", nil, "mergeAllWindows:")),
        .separator,
        .item(Item("window.bringAllToFront", "Window: Bring All to Front", "Bring All to Front", nil, "arrangeInFront:")),
    ]

    private static let helpMenu: [Entry] = [
        .item(Item("help.quickstart", "Help: Quickstart Guide", "Quickstart Guide", nil, "openQuickstartGuide:")),
        .separator,
        .item(Item("help.github", "Help: Quoin on GitHub", "Quoin on GitHub", nil, "openGitHub:")),
        .item(Item("help.reportIssue", "Help: Report an Issue", "Report an Issue…", nil, "reportIssue:")),
        .item(Item("help.releaseNotes", "Help: Release Notes", "Release Notes", nil, "openReleaseNotes:")),
    ]

    private static var allMenus: [(String, [Entry])] {
        [("Quoin", appMenu), ("File", fileMenu), ("Edit", editMenu), ("Selection", selectionMenu),
         ("Find", findMenu), ("View", viewMenu), ("Goto", gotoMenu), ("Agent", agentMenu),
         ("Window", windowMenu), ("Help", helpMenu)]
    }

    /// Register every menu action as a Command so the palette, a user keymap,
    /// and the agent surface run the same catalog.
    static func registerCommands(in registry: CommandRegistry) {
        for (_, entries) in allMenus {
            registerCommands(entries: entries, in: registry)
        }
    }

    private static func registerCommands(entries: [Entry], in registry: CommandRegistry) {
        for entry in entries {
            switch entry {
            case .separator:
                continue
            case .submenu(_, let children):
                registerCommands(entries: children, in: registry)
            case .item(let item):
                let selector = NSSelectorFromString(item.selector)
                // Tag-dispatched selectors read the sender's tag, so the
                // command sends from a stand-in item carrying it.
                let sender = NSMenuItem(title: item.menuTitle, action: selector, keyEquivalent: "")
                sender.tag = item.tag
                registry.register(Command(id: item.id, title: item.title, defaultKeybinding: item.key) {
                    // Normal dispatch needs a key window; when the app is in
                    // the BACKGROUND (agent run_command from a terminal) walk
                    // the front window's responder chain instead.
                    if NSApp.sendAction(selector, to: nil, from: sender) { return }
                    for window in NSApp.orderedWindows {
                        if window.firstResponder?.tryToPerform(selector, with: sender) == true { return }
                    }
                })
            }
        }
    }

    static func build(from registry: CommandRegistry) -> NSMenu {
        let mainMenu = NSMenu()
        for (title, entries) in allMenus {
            let menu = buildMenu(title: title, entries: entries)
            let holder = NSMenuItem()
            holder.submenu = menu
            mainMenu.addItem(holder)
            if title == "Window" { NSApp.windowsMenu = menu }
            if title == "Help" { NSApp.helpMenu = menu }
        }
        return mainMenu
    }

    private static func buildMenu(title: String, entries: [Entry]) -> NSMenu {
        let menu = NSMenu(title: title)
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let subTitle, let children):
                let holder = NSMenuItem(title: subTitle, action: nil, keyEquivalent: "")
                let submenu = buildMenu(title: subTitle, entries: children)
                holder.submenu = submenu
                menu.addItem(holder)
                if subTitle == "Services" { NSApp.servicesMenu = submenu }
            case .item(let item):
                let (keyEquivalent, modifiers) = parseKeybinding(item.key)
                let menuItem = NSMenuItem(
                    title: item.menuTitle,
                    action: NSSelectorFromString(item.selector),
                    keyEquivalent: keyEquivalent
                )
                menuItem.keyEquivalentModifierMask = modifiers
                menuItem.tag = item.tag
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    /// Named keys that are not a single printable character.
    private static let namedKeys: [String: String] = [
        "up": String(UnicodeScalar(NSUpArrowFunctionKey)!),
        "down": String(UnicodeScalar(NSDownArrowFunctionKey)!),
        "left": String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        "right": String(UnicodeScalar(NSRightArrowFunctionKey)!),
        "enter": "\r",
        "return": "\r",
        "tab": "\t",
        "space": " ",
        "escape": "\u{1B}",
        "backspace": "\u{8}",
        "delete": String(UnicodeScalar(NSDeleteFunctionKey)!),
        "f1": String(UnicodeScalar(NSF1FunctionKey)!),
        "f2": String(UnicodeScalar(NSF2FunctionKey)!),
        "f3": String(UnicodeScalar(NSF3FunctionKey)!),
        "f4": String(UnicodeScalar(NSF4FunctionKey)!),
        "f5": String(UnicodeScalar(NSF5FunctionKey)!),
        "f6": String(UnicodeScalar(NSF6FunctionKey)!),
        "f7": String(UnicodeScalar(NSF7FunctionKey)!),
        "f8": String(UnicodeScalar(NSF8FunctionKey)!),
    ]

    /// "cmd+shift+s" -> ("s", [.command, .shift]); "ctrl+cmd+up" -> (up arrow, [.control, .command])
    private static func parseKeybinding(_ binding: String?) -> (String, NSEvent.ModifierFlags) {
        guard let binding, !binding.isEmpty else { return ("", []) }
        var modifiers: NSEvent.ModifierFlags = []
        var key = ""
        for part in binding.split(separator: "+") {
            switch part {
            case "cmd", "super": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "alt", "option": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            default: key = namedKeys[String(part)] ?? String(part)
            }
        }
        return (key, modifiers)
    }
}
