import Foundation

/// The Sublime multi-cursor selection algebra (Phase 6), as pure functions
/// over text + SelectionSet so it is unit-testable. The view layer only
/// reads/writes SelectionSet; it never invents selection logic.
/// Offsets are UTF-16 code units throughout, as everywhere in EditorCore.
public enum MultiCursor {

    /// Cmd+D. If the primary selection is a caret: select the word around
    /// it. Otherwise: add the next occurrence of the selected text (after
    /// the last selection, wrapping around), which becomes primary.
    public static func selectingNextOccurrence(in text: String, current: SelectionSet) -> SelectionSet {
        let normalized = current.normalized()
        let primary = normalized.primary

        if primary.isCaret {
            guard let word = wordRange(in: text, at: primary.head) else { return normalized }
            let selections = normalized.selections.map {
                $0 == primary ? Selection(anchor: word.lowerBound, head: word.upperBound) : $0
            }
            return SelectionSet(selections).normalized()
        }

        let ns = text as NSString
        let needle = ns.substring(with: NSRange(location: primary.lowerBound, length: primary.range.count))
        guard !needle.isEmpty else { return normalized }

        let searchFrom = normalized.selections.map(\.upperBound).max() ?? 0
        let candidates = [
            NSRange(location: searchFrom, length: ns.length - searchFrom),
            NSRange(location: 0, length: searchFrom), // wrap
        ]
        for window in candidates where window.length > 0 {
            let found = ns.range(of: needle, options: [], range: window)
            guard found.location != NSNotFound else { continue }
            let selection = Selection(anchor: found.location, head: found.location + found.length)
            if normalized.selections.contains(where: { $0.overlaps(selection) }) { continue }
            return SelectionSet(normalized.selections + [selection]).normalized()
        }
        return normalized
    }

    /// Select every occurrence of the primary selection's text (word around
    /// the caret if nothing is selected).
    public static func selectingAllOccurrences(in text: String, current: SelectionSet) -> SelectionSet {
        var base = current.normalized()
        if base.primary.isCaret {
            base = selectingNextOccurrence(in: text, current: base) // caret -> word
            if base.primary.isCaret { return base }                 // no word here
        }
        let ns = text as NSString
        let primary = base.primary
        let needle = ns.substring(with: NSRange(location: primary.lowerBound, length: primary.range.count))
        guard !needle.isEmpty else { return base }

        var selections: [Selection] = []
        var cursor = 0
        while cursor < ns.length {
            let found = ns.range(of: needle, options: [], range: NSRange(location: cursor, length: ns.length - cursor))
            guard found.location != NSNotFound else { break }
            selections.append(Selection(anchor: found.location, head: found.location + found.length))
            cursor = found.location + max(found.length, 1)
        }
        return selections.isEmpty ? base : SelectionSet(selections).normalized()
    }

    /// Collapse to a single selection (Escape): keep only the primary.
    public static func collapsed(_ current: SelectionSet) -> SelectionSet {
        SelectionSet([current.primary])
    }

    // MARK: Multi-caret editing arithmetic
    // The rented view inserts at every caret but then collapses to ONE
    // caret (verified in its source + live 2026-07-12), so the view layer
    // replays edits per caret and re-asserts caret positions computed here.

    /// Caret positions after replacing every selection with the same
    /// `insertLength`-unit string: each caret sits after its insertion,
    /// shifted by the net size change of all edits before it.
    public static func caretsAfterReplacing(_ selections: SelectionSet, insertLength: Int) -> SelectionSet {
        var delta = 0
        var carets: [Selection] = []
        for selection in selections.normalized().selections {
            carets.append(Selection(caretAt: selection.lowerBound + delta + insertLength))
            delta += insertLength - selection.range.count
        }
        return SelectionSet(carets)
    }

    /// What backspace should delete for each selection: the selection itself,
    /// or the one unit before a caret (nothing for a caret at 0).
    public static func backwardDeletionRanges(for selections: SelectionSet) -> [Range<Int>] {
        selections.normalized().selections.compactMap { selection in
            if !selection.isCaret { return selection.range }
            return selection.head > 0 ? (selection.head - 1)..<selection.head : nil
        }
    }

    /// Caret positions after deleting those ranges.
    public static func caretsAfterDeleting(ranges: [Range<Int>], fallback: SelectionSet) -> SelectionSet {
        var delta = 0
        var carets: [Selection] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            carets.append(Selection(caretAt: range.lowerBound + delta))
            delta -= range.count
        }
        return carets.isEmpty ? fallback : SelectionSet(carets)
    }

    /// The identifier-style word around a UTF-16 offset; nil when the offset
    /// touches no word character.
    public static func wordRange(in text: String, at offset: Int) -> Range<Int>? {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return nil }
        let clamped = min(max(offset, 0), units.count)

        func isWord(_ index: Int) -> Bool {
            guard index >= 0, index < units.count else { return false }
            let unit = units[index]
            if unit == 0x5F { return true } // _
            guard let scalar = Unicode.Scalar(unit) else { return true } // surrogate half: inside a non-BMP char
            return CharacterSet.alphanumerics.contains(scalar)
        }

        var start = clamped
        var end = clamped
        if !isWord(start), isWord(start - 1) { start -= 1; end -= 1 } // caret at word end
        guard isWord(start) else { return nil }
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return start..<end
    }
}
