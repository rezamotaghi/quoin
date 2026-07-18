import AppKit
import FuzzyKit

/// One row the palette can show and run.
struct PaletteItem {
    let title: String          // what fuzzy matching runs against
    let subtitle: String?      // dimmed right-hand hint (keybinding, folder)
    let action: @MainActor () -> Void
}

/// The floating fuzzy panel behind both Cmd+Shift+P (commands) and Cmd+P
/// (files): callers only differ in the items they pass. Type to filter,
/// arrows to move, return to run, escape (or clicking away) to dismiss.
@MainActor
final class PaletteController: NSObject {

    static let shared = PaletteController()

    private var panel: NSPanel?
    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    private var allItems: [PaletteItem] = []
    private var filtered: [PaletteItem] = []
    private var emptyHint: String?
    private let maxVisibleRows = 12
    private let maxResults = 200

    func show(items: [PaletteItem], placeholder: String, emptyHint: String? = nil) {
        allItems = items
        self.emptyHint = emptyHint
        searchField.stringValue = ""
        searchField.placeholderString = placeholder
        refilter()

        let panel = ensurePanel()
        // Center horizontally over the key window (or screen), near the top,
        // Sublime-style.
        let host = NSApp.keyWindow?.frame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: host.midX - size.width / 2,
            y: host.maxY - size.height - 120
        ))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    private func dismiss() {
        panel?.orderOut(nil)
    }

    // MARK: Panel construction (once)

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self

        searchField.font = .systemFont(ofSize: 18)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.backgroundColor = .clear
        searchField.delegate = self

        tableView.addTableColumn(NSTableColumn(identifier: .init("main")))
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(runSelected)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let stack = NSStackView(views: [searchField, scrollView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 10, right: 14)
        panel.contentView = stack

        self.panel = panel
        return panel
    }

    // MARK: Filtering + running

    private func refilter() {
        let pattern = searchField.stringValue
        if pattern.isEmpty {
            filtered = Array(allItems.prefix(maxResults))
        } else {
            let ranked = FuzzyMatcher.rank(pattern: pattern, candidates: allItems.map(\.title))
            filtered = ranked.prefix(maxResults).map { allItems[$0.index] }
        }
        // Dead end with an explanation beats an empty box.
        if filtered.isEmpty, let emptyHint {
            filtered = [PaletteItem(title: emptyHint, subtitle: nil, action: {})]
        }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    @objc private func runSelected() {
        let row = max(tableView.selectedRow, 0)
        guard row < filtered.count else { return }
        let item = filtered[row]
        dismiss()
        item.action()
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let row = min(max(tableView.selectedRow + delta, 0), filtered.count - 1)
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }
}

extension PaletteController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}

extension PaletteController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        refilter()
    }

    // The search field keeps focus; arrows/return/escape are steered here.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)): runSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): dismiss(); return true
        default: return false
        }
    }
}

extension PaletteController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let cell = NSTableCellView()

        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingMiddle

        let stack: NSStackView
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            let hint = NSTextField(labelWithString: subtitle)
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .secondaryLabelColor
            hint.lineBreakMode = .byTruncatingHead
            hint.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            stack = NSStackView(views: [title, NSView(), hint])
        } else {
            stack = NSStackView(views: [title])
        }
        stack.orientation = .horizontal
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
