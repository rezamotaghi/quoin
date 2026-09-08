import Foundation
import Testing
@testable import EditorCore

@Suite struct LineOperationsTests {

    let text = "one\ntwo\nthree\nfour"   // offsets: one 0..<3, two 4..<7, three 8..<13, four 14..<18

    @Test func lineSpanFollowsSublimeRules() {
        #expect(LineOperations.lineSpan(of: Selection(caretAt: 5), in: text) == 2...2)
        #expect(LineOperations.lineSpan(of: Selection(anchor: 1, head: 9), in: text) == 1...3)
        // A selection ending at column 0 of "three" does not include it.
        #expect(LineOperations.lineSpan(of: Selection(anchor: 0, head: 8), in: text) == 1...2)
        #expect(LineOperations.lineSpan(of: Selection(caretAt: 8), in: text) == 3...3)
        #expect(LineOperations.lineSpan(of: Selection(caretAt: 18), in: text) == 4...4)
    }

    @Test func duplicateCopiesTheLineBelowItself() {
        let edit = LineOperations.duplicate(Selection(caretAt: 5), in: text)
        #expect(edit.applied(to: text) == "one\ntwo\ntwo\nthree\nfour")
        #expect(edit.selection == Selection(caretAt: 9))
        let last = LineOperations.duplicate(Selection(caretAt: 16), in: text)
        #expect(last.applied(to: text) == "one\ntwo\nthree\nfour\nfour")
        #expect(last.selection == Selection(caretAt: 21))
    }

    @Test func deleteRemovesWholeLines() {
        #expect(LineOperations.delete(Selection(caretAt: 5), in: text).applied(to: text) == "one\nthree\nfour")
        #expect(LineOperations.delete(Selection(caretAt: 16), in: text).applied(to: text) == "one\ntwo\nthree")
        #expect(LineOperations.delete(Selection(anchor: 4, head: 9), in: text).applied(to: text) == "one\nfour")
        #expect(LineOperations.delete(Selection(caretAt: 2), in: "only").applied(to: "only") == "")
    }

    @Test func swapUpAndDownTradeNeighbors() {
        let up = try! #require(LineOperations.swapUp(Selection(caretAt: 5), in: text))
        #expect(up.applied(to: text) == "two\none\nthree\nfour")
        #expect(up.selection == Selection(caretAt: 1))
        #expect(LineOperations.swapUp(Selection(caretAt: 1), in: text) == nil)

        let down = try! #require(LineOperations.swapDown(Selection(caretAt: 5), in: text))
        #expect(down.applied(to: text) == "one\nthree\ntwo\nfour")
        #expect(down.selection == Selection(caretAt: 11))
        #expect(LineOperations.swapDown(Selection(caretAt: 16), in: text) == nil)

        let lastUp = try! #require(LineOperations.swapUp(Selection(caretAt: 16), in: text))
        #expect(lastUp.applied(to: text) == "one\ntwo\nfour\nthree")
    }

    @Test func joinMergesLinesWithSingleSpaces() {
        let single = try! #require(LineOperations.join(Selection(caretAt: 1), in: "one  \n   two\nthree"))
        #expect(single.applied(to: "one  \n   two\nthree") == "one two\nthree")
        #expect(single.selection == Selection(caretAt: 3))
        let multi = try! #require(LineOperations.join(Selection(anchor: 0, head: 9), in: text))
        #expect(multi.applied(to: text) == "one two three\nfour")
        #expect(LineOperations.join(Selection(caretAt: 16), in: text) == nil)
    }

    @Test func indentAndUnindentKeepTheCaretOnItsText() {
        let indented = LineOperations.indent(Selection(caretAt: 5), in: text, unit: "    ")
        #expect(indented.applied(to: text) == "one\n    two\nthree\nfour")
        #expect(indented.selection == Selection(caretAt: 9))
        let atStart = LineOperations.indent(Selection(caretAt: 4), in: text, unit: "\t")
        #expect(atStart.selection == Selection(caretAt: 4))

        let block = LineOperations.indent(Selection(anchor: 0, head: 4), in: "a\n\nb\nc", unit: "  ") // ends at col 0 of "c": excluded
        #expect(block.applied(to: "a\n\nb\nc") == "  a\n\n  b\nc")
        #expect(block.selection == Selection(anchor: 0, head: 8))

        let source = "\tone\n    two\n  three"
        let out = LineOperations.unindent(Selection(anchor: 0, head: 18), in: source, tabSize: 4)
        #expect(out.applied(to: source) == "one\ntwo\nthree")
        let caret = LineOperations.unindent(Selection(caretAt: 7), in: source, tabSize: 4) // inside "    two", column 2
        #expect(caret.applied(to: source) == "\tone\ntwo\n  three")
        #expect(caret.selection == Selection(caretAt: 5))
    }

    @Test func toggleCommentAddsAtShallowestIndentAndRemovesCleanly() {
        let source = "    a\n  b\n\n      c"
        let commented = LineOperations.toggleComment(Selection(anchor: 0, head: 18), in: source, token: "//")
        #expect(commented.applied(to: source) == "  //   a\n  // b\n\n  //     c")
        let back = LineOperations.toggleComment(Selection(anchor: 0, head: 26), in: commented.applied(to: source), token: "//")
        #expect(back.applied(to: commented.applied(to: source)) == source)

        let caret = LineOperations.toggleComment(Selection(caretAt: 2), in: "x = 1", token: "#")
        #expect(caret.applied(to: "x = 1") == "# x = 1")
        #expect(caret.selection == Selection(caretAt: 4))
        let uncomment = LineOperations.toggleComment(Selection(caretAt: 4), in: "# x = 1", token: "#")
        #expect(uncomment.applied(to: "# x = 1") == "x = 1")
        #expect(uncomment.selection == Selection(caretAt: 2))
    }

    @Test func permutationsReorderLines() {
        let source = "pear\nApple\nfig\napple"
        let all = Selection(caretAt: 0) // caret: the whole buffer
        #expect(LineOperations.permute(all, in: source, .sort(caseSensitive: false)).applied(to: source) == "Apple\napple\nfig\npear")
        #expect(LineOperations.permute(all, in: source, .sort(caseSensitive: true)).applied(to: source) == "Apple\napple\nfig\npear")
        #expect(LineOperations.permute(all, in: source, .reverse).applied(to: source) == "apple\nfig\nApple\npear")
        #expect(LineOperations.permute(all, in: "a\nb\na\nc\nb", .unique).applied(to: "a\nb\na\nc\nb") == "a\nb\nc")
        let shuffled = LineOperations.permute(all, in: source, .shuffle, shuffler: { $0.reverse() })
        #expect(shuffled.applied(to: source) == "apple\nfig\nApple\npear")
        // A selection permutes only its lines.
        let partial = LineOperations.permute(Selection(anchor: 5, head: 14), in: source, .reverse)
        #expect(partial.applied(to: source) == "pear\nfig\nApple\napple")
        #expect(partial.selection == Selection(anchor: 5, head: 14))
    }

    @Test func swapCaseFlipsLetters() {
        let edit = try! #require(LineOperations.swapCase(Selection(anchor: 0, head: 7), in: "Hello 1"))
        #expect(edit.replacement == "hELLO 1")
        #expect(LineOperations.swapCase(Selection(caretAt: 3), in: "Hello") == nil)
    }
}

@Suite struct SelectionOperationsTests {

    let text = "one\ntwo\nthree\nfour"

    @Test func splitIntoLinesMakesOneSelectionPerLine() {
        let split = SelectionOperations.splitIntoLines(SelectionSet([Selection(anchor: 1, head: 10)]), in: text)
        #expect(split.selections == [Selection(anchor: 1, head: 3), Selection(anchor: 4, head: 7), Selection(anchor: 8, head: 10)])
        #expect(split.primary == Selection(anchor: 8, head: 10))
        let caret = SelectionOperations.splitIntoLines(SelectionSet([Selection(caretAt: 5)]), in: text)
        #expect(caret.selections == [Selection(caretAt: 5)])
    }

    @Test func addLineKeepsTheColumnAndClamps() {
        let down = SelectionOperations.addLine(SelectionSet([Selection(caretAt: 2)]), in: text, forward: true)
        #expect(down.selections == [Selection(caretAt: 2), Selection(caretAt: 6)])
        #expect(down.primary == Selection(caretAt: 6))
        let clamped = SelectionOperations.addLine(SelectionSet([Selection(caretAt: 12)]), in: text, forward: true) // "three" col 4 -> "four" col 4
        #expect(clamped.selections.last == Selection(caretAt: 18))
        let up = SelectionOperations.addLine(SelectionSet([Selection(anchor: 4, head: 6)]), in: text, forward: false)
        #expect(up.selections.last == Selection(anchor: 0, head: 2))
        let atTop = SelectionOperations.addLine(SelectionSet([Selection(caretAt: 1)]), in: text, forward: false)
        #expect(atTop.selections == [Selection(caretAt: 1)])
    }

    @Test func invertSelectsTheComplement() {
        let inverted = SelectionOperations.invert(SelectionSet([Selection(anchor: 4, head: 7)]), in: text)
        #expect(inverted.selections == [Selection(anchor: 0, head: 4), Selection(anchor: 7, head: 18)])
        let whole = SelectionOperations.invert(SelectionSet([Selection(caretAt: 5)]), in: text)
        #expect(whole.selections == [Selection(anchor: 0, head: 18)])
        let nothing = SelectionOperations.invert(SelectionSet([Selection(anchor: 0, head: 18)]), in: text)
        #expect(nothing.selections == [Selection(caretAt: 18)])
    }
}
