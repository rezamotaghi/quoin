import Testing
@testable import EditorCore

@Suite struct MultiCursorTests {

    let text = "let value = compute(value) + value2\n"
    //          0123456789...
    // "value" occurs at 4..<9, 20..<25, and as prefix of "value2" at 29..<34

    @Test func caretExpandsToWord() {
        let result = MultiCursor.selectingNextOccurrence(in: text, current: SelectionSet([Selection(caretAt: 6)]))
        #expect(result.selections == [Selection(anchor: 4, head: 9)])
    }

    @Test func caretAtWordEndStillFindsTheWord() {
        let result = MultiCursor.selectingNextOccurrence(in: text, current: SelectionSet([Selection(caretAt: 9)]))
        #expect(result.selections == [Selection(anchor: 4, head: 9)])
    }

    @Test func selectionAddsNextOccurrence() {
        let one = SelectionSet([Selection(anchor: 4, head: 9)])
        let two = MultiCursor.selectingNextOccurrence(in: text, current: one)
        #expect(two.selections.count == 2)
        #expect(two.selections.contains(Selection(anchor: 20, head: 25)))
        // New occurrence is primary (normalized() keeps last position primary).
        #expect(two.primary.range == 20..<25)
    }

    @Test func nextOccurrenceWrapsAround() {
        let last = SelectionSet([Selection(anchor: 29, head: 34)]) // the "value" inside value2
        let wrapped = MultiCursor.selectingNextOccurrence(in: text, current: last)
        #expect(wrapped.selections.contains(Selection(anchor: 4, head: 9)))
    }

    @Test func noMatchLeavesSelectionsUnchanged() {
        let sel = SelectionSet([Selection(anchor: 0, head: 3)]) // "let", occurs once
        let result = MultiCursor.selectingNextOccurrence(in: text, current: sel)
        #expect(result.selections == [Selection(anchor: 0, head: 3)])
    }

    @Test func selectAllOccurrencesFromCaret() {
        let result = MultiCursor.selectingAllOccurrences(in: text, current: SelectionSet([Selection(caretAt: 5)]))
        #expect(result.selections.count == 3) // 4..<9, 20..<25, 29..<34 (prefix of value2)
    }

    @Test func collapseKeepsOnlyPrimary() {
        let multi = SelectionSet([Selection(anchor: 4, head: 9), Selection(anchor: 20, head: 25)], primaryIndex: 1)
        let collapsed = MultiCursor.collapsed(multi)
        #expect(collapsed.selections == [Selection(anchor: 20, head: 25)])
    }

    @Test func wordRangeOnPunctuationIsNil() {
        #expect(MultiCursor.wordRange(in: "a + b", at: 2) == nil)
    }

    @Test func wordRangeHandlesUnderscoresAndDigits() {
        let t = "foo_bar2 baz"
        #expect(MultiCursor.wordRange(in: t, at: 4) == 0..<8)
    }

    // MARK: Multi-caret editing arithmetic (the 2026-07-12 typing fix)

    @Test func caretsAfterReplacingTwoSelections() {
        // "name"(4..9) and "name"(20..25) replaced by "uiui" (4 units):
        // caret 1 after first insert = 4+4 = 8; delta = 4-5 = -1;
        // caret 2 = 20 + (-1) + 4 = 23.
        let selections = SelectionSet([Selection(anchor: 4, head: 9), Selection(anchor: 20, head: 25)])
        let carets = MultiCursor.caretsAfterReplacing(selections, insertLength: 4)
        #expect(carets.selections == [Selection(caretAt: 8), Selection(caretAt: 23)])
    }

    @Test func caretsAfterTypingOneCharAtTwoCarets() {
        let selections = SelectionSet([Selection(caretAt: 3), Selection(caretAt: 10)])
        let carets = MultiCursor.caretsAfterReplacing(selections, insertLength: 1)
        #expect(carets.selections == [Selection(caretAt: 4), Selection(caretAt: 12)])
    }

    @Test func backwardDeletionRangesMixCaretsAndSelections() {
        let selections = SelectionSet([Selection(caretAt: 0), Selection(caretAt: 5), Selection(anchor: 8, head: 11)])
        // caret at 0 deletes nothing; caret at 5 deletes 4..<5; range deletes itself
        #expect(MultiCursor.backwardDeletionRanges(for: selections) == [4..<5, 8..<11])
    }

    @Test func caretsAfterDeletingShiftLeft() {
        let carets = MultiCursor.caretsAfterDeleting(ranges: [4..<5, 8..<11], fallback: SelectionSet())
        // first caret at 4; delta -1; second at 8 - 1 = 7
        #expect(carets.selections == [Selection(caretAt: 4), Selection(caretAt: 7)])
    }

    @Test func caretsAfterDeletingNothingUsesFallback() {
        let fallback = SelectionSet([Selection(caretAt: 0)])
        #expect(MultiCursor.caretsAfterDeleting(ranges: [], fallback: fallback).selections == fallback.selections)
    }
}
