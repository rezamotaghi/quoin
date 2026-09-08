import Foundation
import Testing
@testable import EditorCore

@Suite struct LineIndexTests {

    @Test func lineCountMatchesTheGutter() {
        #expect(LineIndex.lineCount(in: "") == 1)
        #expect(LineIndex.lineCount(in: "a") == 1)
        #expect(LineIndex.lineCount(in: "a\nb") == 2)
        #expect(LineIndex.lineCount(in: "a\nb\n") == 3)   // trailing newline: one empty line after it
        #expect(LineIndex.lineCount(in: "a\r\nb\r\n") == 3)
        #expect(LineIndex.lineCount(in: "\n\n") == 3)
    }

    @Test func startOffsetsWalkTerminators() {
        let text = "ab\ncd\r\nef"
        #expect(LineIndex.startOffset(ofLine: 1, in: text) == 0)
        #expect(LineIndex.startOffset(ofLine: 2, in: text) == 3)
        #expect(LineIndex.startOffset(ofLine: 3, in: text) == 7)
        #expect(LineIndex.startOffset(ofLine: 4, in: text) == nil)
        #expect(LineIndex.startOffset(ofLine: 0, in: text) == nil)
    }

    @Test func contentRangeExcludesTheLastTerminator() {
        let text = "a\nbb\nccc"
        #expect(LineIndex.contentRange(ofLines: 1, through: 1, in: text) == 0..<1)
        #expect(LineIndex.contentRange(ofLines: 2, through: 2, in: text) == 2..<4)
        #expect(LineIndex.contentRange(ofLines: 1, through: 3, in: text) == 0..<8)
        #expect(LineIndex.contentRange(ofLines: 2, through: 3, in: text) == 2..<8)
        #expect(LineIndex.text(ofLines: 2, through: 3, in: text) == "bb\nccc")
    }

    @Test func contentRangeRejectsMissingLinesAndInvertedRanges() {
        let text = "a\nb"
        #expect(LineIndex.contentRange(ofLines: 3, through: 3, in: text) == nil)
        #expect(LineIndex.contentRange(ofLines: 2, through: 1, in: text) == nil)
        #expect(LineIndex.contentRange(ofLines: 1, through: 5, in: text) == nil)
    }

    @Test func trailingNewlineYieldsAnEmptyLastLine() {
        let text = "a\nb\n"
        #expect(LineIndex.contentRange(ofLines: 3, through: 3, in: text) == 4..<4)
        #expect(LineIndex.text(ofLines: 3, through: 3, in: text) == "")
    }

    @Test func crlfLinesKeepTheirPairs() {
        let text = "one\r\ntwo\r\nthree"
        #expect(LineIndex.text(ofLines: 2, through: 2, in: text) == "two")
        #expect(LineIndex.contentRange(ofLines: 1, through: 2, in: text) == 0..<8)
    }

    /// Replacing the content range of lines keeps the neighbors on their own
    /// lines with no trailing newline in the replacement: the agent contract.
    @Test func replacingContentRangeKeepsNeighborsIntact() {
        let text = "keep\nold one\nold two\nkeep too"
        let range = LineIndex.contentRange(ofLines: 2, through: 3, in: text)!
        let ns = text as NSString
        let result = ns.replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: "new")
        #expect(result == "keep\nnew\nkeep too")
    }
}
