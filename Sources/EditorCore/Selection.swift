import Foundation

/// One caret or selection. `anchor` is where the selection started, `head` is
/// where the cursor currently is (so head < anchor for a backwards drag).
/// A plain caret is `anchor == head`.
///
/// Offsets are UTF-16 code units, because that is what AppKit's text system
/// (NSRange) speaks. Converting at the view boundary, not here, would invite
/// off-by-one bugs with emoji and non-Latin text.
public struct Selection: Hashable, Codable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    public init(caretAt offset: Int) {
        self.init(anchor: offset, head: offset)
    }

    public var isCaret: Bool { anchor == head }

    public var lowerBound: Int { min(anchor, head) }
    public var upperBound: Int { max(anchor, head) }
    public var range: Range<Int> { lowerBound..<upperBound }

    public func overlaps(_ other: Selection) -> Bool {
        lowerBound <= other.upperBound && other.lowerBound <= upperBound
    }
}

/// The full selection state of one editor view. Always at least one selection.
/// Multi-cursor (Phase 6) is simply "this array has more than one element";
/// no view code may hold its own idea of where the carets are.
public struct SelectionSet: Hashable, Codable, Sendable {
    public private(set) var selections: [Selection]
    /// Index of the primary selection (the one find/scroll operations follow).
    public private(set) var primaryIndex: Int

    public init(_ selections: [Selection] = [Selection(caretAt: 0)], primaryIndex: Int = 0) {
        precondition(!selections.isEmpty, "SelectionSet must never be empty")
        self.selections = selections
        self.primaryIndex = min(max(0, primaryIndex), selections.count - 1)
    }

    public var primary: Selection { selections[primaryIndex] }

    /// Sorted by position, overlapping/touching selections merged.
    /// The invariant every mutation must restore before the view renders.
    public func normalized() -> SelectionSet {
        let sorted = selections.sorted { ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound) }
        var merged: [Selection] = []
        for sel in sorted {
            if let last = merged.last, last.overlaps(sel) || last.upperBound == sel.lowerBound {
                merged[merged.count - 1] = Selection(
                    anchor: min(last.lowerBound, sel.lowerBound),
                    head: max(last.upperBound, sel.upperBound)
                )
            } else {
                merged.append(sel)
            }
        }
        return SelectionSet(merged, primaryIndex: merged.count - 1)
    }
}
