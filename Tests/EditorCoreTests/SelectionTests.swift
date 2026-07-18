// Swift Testing (not XCTest): XCTest ships with Xcode.app, which this
// machine doesn't have; Swift Testing ships in the toolchain itself.
import Testing
@testable import EditorCore

@Suite struct SelectionTests {

    @Test func backwardsSelectionNormalizesRange() {
        let sel = Selection(anchor: 10, head: 4)
        #expect(sel.range == 4..<10)
        #expect(!sel.isCaret)
    }

    @Test func caret() {
        let sel = Selection(caretAt: 7)
        #expect(sel.isCaret)
        #expect(sel.range == 7..<7)
    }

    @Test func normalizedMergesOverlappingSelections() {
        let set = SelectionSet([
            Selection(anchor: 0, head: 5),
            Selection(anchor: 4, head: 9),   // overlaps the first
            Selection(anchor: 20, head: 25), // separate
        ])
        let merged = set.normalized().selections
        #expect(merged.count == 2)
        #expect(merged[0].range == 0..<9)
        #expect(merged[1].range == 20..<25)
    }

    @Test func normalizedMergesTouchingSelections() {
        let set = SelectionSet([
            Selection(anchor: 0, head: 5),
            Selection(anchor: 5, head: 9),   // touches the first
        ])
        #expect(set.normalized().selections.count == 1)
    }

    @Test func normalizedSortsOutOfOrderSelections() {
        let set = SelectionSet([
            Selection(anchor: 20, head: 25),
            Selection(anchor: 0, head: 5),
        ])
        #expect(set.normalized().selections.first?.range == 0..<5)
    }
}
