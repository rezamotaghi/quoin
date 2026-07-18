import AppKit
import CommandKit

/// The menu bar as a projection of the CommandRegistry (invariant 3).
///
/// Every command maps to a standard AppKit responder-chain selector
/// ("first responder" = whatever has focus; AppKit walks focused view ->
/// window -> document -> app asking who handles the action). One spec table
/// drives both the registration (Command whose action re-sends the selector,
/// so the Phase 4 palette can run it) and the menu item (which uses the
/// selector directly, so AppKit's built-in enabling/dimming keeps working).
@MainActor
enum MainMenu {

    private struct Item {
        let id: String
        let title: String        // palette-facing, e.g. "File: Save"
        let menuTitle: String    // menu-facing, e.g. "Save"
        let key: String?         // "cmd+s" style, Sublime-ish notation
        let selector: String     // Objective-C selector name
        let tag: Int             // some selectors (find bar) dispatch on the sender's tag

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

    private static let fileMenu: [Entry] = [
        .item(Item("file.new", "File: New File", "New", "cmd+n", "newDocument:")),
        .item(Item("file.open", "File: Open", "Open…", "cmd+o", "openDocument:")),
        .item(Item("file.openFolder", "File: Open Folder", "Open Folder…", nil, "openFolder:")),
        .separator,
        .item(Item("file.close", "File: Close Window", "Close", "cmd+w", "performClose:")),
        .item(Item("file.save", "File: Save", "Save", "cmd+s", "saveDocument:")),
        // Custom selector on purpose: with autosave-in-place on, AppKit
        // rewrites any "saveDocumentAs:" item into Duplicate/Rename/Move To
        // and hides Save As behind the Option key. Reza wants it visible.
        // Deliberately NO key binding: claiming cmd+shift+s made AppKit
        // render its own extra Save As alternate visibly (tested 2026-07-09);
        // unbound, the system block keeps Duplicate=cmd+shift+s and this
        // stays the one visible Save As.
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
    ]

    // The find bar is AppKit's NSTextFinder (the same one TextEdit/Xcode use,
    // already wired up inside the rented view). One selector handles every
    // find action; the menu item's TAG says which action.
    private static let findSubmenu: [Entry] = [
        .item(Item("find.find", "Find: Find", "Find…", "cmd+f",
                   "performTextFinderAction:", tag: NSTextFinder.Action.showFindInterface.rawValue)),
        .item(Item("find.findAndReplace", "Find: Find and Replace", "Find and Replace…", "cmd+alt+f",
                   "performTextFinderAction:", tag: NSTextFinder.Action.showReplaceInterface.rawValue)),
        .item(Item("find.next", "Find: Find Next", "Find Next", "cmd+g",
                   "performTextFinderAction:", tag: NSTextFinder.Action.nextMatch.rawValue)),
        .item(Item("find.previous", "Find: Find Previous", "Find Previous", "cmd+shift+g",
                   "performTextFinderAction:", tag: NSTextFinder.Action.previousMatch.rawValue)),
        .item(Item("find.useSelection", "Find: Use Selection for Find", "Use Selection for Find", "cmd+e",
                   "performTextFinderAction:", tag: NSTextFinder.Action.setSearchString.rawValue)),
        .item(Item("find.hide", "Find: Hide Find Bar", "Hide Find Bar", nil,
                   "performTextFinderAction:", tag: NSTextFinder.Action.hideFindInterface.rawValue)),
    ]

    private static let editMenu: [Entry] = [
        .item(Item("edit.undo", "Edit: Undo", "Undo", "cmd+z", "undo:")),
        .item(Item("edit.redo", "Edit: Redo", "Redo", "cmd+shift+z", "redo:")),
        .separator,
        .item(Item("edit.cut", "Edit: Cut", "Cut", "cmd+x", "cut:")),
        .item(Item("edit.copy", "Edit: Copy", "Copy", "cmd+c", "copy:")),
        .item(Item("edit.paste", "Edit: Paste", "Paste", "cmd+v", "paste:")),
        .separator,
        .item(Item("edit.selectAll", "Edit: Select All", "Select All", "cmd+a", "selectAll:")),
        .separator,
        .submenu("Find", findSubmenu),
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

    private static let appMenu: [Entry] = [
        .item(Item("app.about", "Quoin: About", "About Quoin", nil, "orderFrontStandardAboutPanel:")),
        .separator,
        .item(Item("app.hide", "Quoin: Hide", "Hide Quoin", "cmd+h", "hide:")),
        .separator,
        .item(Item("app.quit", "Quoin: Quit", "Quit Quoin", "cmd+q", "terminate:")),
    ]

    // Multi-cursor (Phase 6): handled by the focused editor view.
    private static let selectionMenu: [Entry] = [
        .item(Item("selection.addNext", "Selection: Add Next Occurrence", "Add Next Occurrence", "cmd+d", "selectNextOccurrence:")),
        .item(Item("selection.selectAllOccurrences", "Selection: Select All Occurrences", "Select All Occurrences", "ctrl+cmd+g", "selectAllOccurrences:")),
    ]

    private static let viewMenu: [Entry] = [
        .item(Item("view.toggleMarkdownPreview", "View: Toggle Markdown Preview", "Toggle Markdown Preview", "cmd+shift+m", "toggleMarkdownPreview:")),
        .item(Item("view.toggleSplitEditor", "View: Toggle Split Editor", "Toggle Split Editor", "cmd+alt+2", "toggleSplitEditor:")),
    ]

    // Sublime's Goto menu: the palette twins (Phase 4).
    private static let gotoMenu: [Entry] = [
        .item(Item("goto.anything", "Goto: Goto Anything", "Goto Anything…", "cmd+p", "showFilePalette:")),
        .item(Item("goto.commandPalette", "Goto: Command Palette", "Command Palette…", "cmd+shift+p", "showCommandPalette:")),
    ]

    private static let helpMenu: [Entry] = [
        .item(Item("help.quickstart", "Help: Quickstart Guide", "Quickstart Guide", nil, "openQuickstartGuide:")),
    ]

    private static var allMenus: [(String, [Entry])] {
        [("Quoin", appMenu), ("File", fileMenu), ("Edit", editMenu), ("Selection", selectionMenu), ("View", viewMenu), ("Goto", gotoMenu), ("Window", windowMenu), ("Help", helpMenu)]
    }

    /// Register every menu action as a Command so future surfaces (the
    /// Phase 4 palette, a user keymap) run the same catalog.
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
                holder.submenu = buildMenu(title: subTitle, entries: children)
                menu.addItem(holder)
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

    /// "cmd+shift+s" -> ("s", [.command, .shift])
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
            default: key = String(part)
            }
        }
        return (key, modifiers)
    }
}
