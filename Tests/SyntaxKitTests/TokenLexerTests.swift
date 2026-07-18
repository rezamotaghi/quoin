// Swift Testing (not XCTest; see the note in the other test files).
import Foundation
import Testing
@testable import SyntaxKit

@Suite struct JSONLexerTests {

    private func styles(_ json: String) -> [(String, String)] {
        let ns = json as NSString
        return TokenLexer.lexJSON(json).map {
            (ns.substring(with: NSRange(location: $0.range.lowerBound, length: $0.range.count)), $0.styleName)
        }
    }

    @Test func keysAndValuesDiffer() {
        let result = styles(#"{ "name": "reza", "size": 18, "on": true }"#)
        #expect(result.contains(where: { $0.0 == "\"name\"" && $0.1 == "key" }))
        #expect(result.contains(where: { $0.0 == "\"reza\"" && $0.1 == "string" }))
        #expect(result.contains(where: { $0.0 == "18" && $0.1 == "number" }))
        #expect(result.contains(where: { $0.0 == "true" && $0.1 == "constant" }))
    }

    @Test func jsoncCommentsAreComments() {
        let result = styles("{\n// hello\n\"a\": 1\n}")
        #expect(result.contains(where: { $0.0 == "// hello" && $0.1 == "comment" }))
    }

    @Test func escapedQuoteStaysInString() {
        let result = styles(#"{ "a": "say \"hi\"" }"#)
        #expect(result.contains(where: { $0.0 == #""say \"hi\"""# && $0.1 == "string" }))
    }
}

@Suite struct MarkdownLexerTests {

    @Test func headingIsWholeLine() {
        let spans = TokenLexer.lexMarkdown("# Title\nbody")
        #expect(spans.contains(where: { $0.styleName == "heading" && $0.range == 0..<7 }))
    }

    @Test func fencedBlockIsCode() {
        let text = "```\nlet x = 1\n```\nafter"
        let spans = TokenLexer.lexMarkdown(text)
        let codeSpans = spans.filter { $0.styleName == "code" }
        #expect(codeSpans.count == 3) // both fences + the interior line
        #expect(!spans.contains(where: { $0.range.lowerBound >= 18 && $0.styleName == "code" })) // "after" unstyled
    }

    @Test func inlineTokens() {
        let spans = TokenLexer.lexMarkdown("mix `code` and **bold** and [a link](https://x.y)")
        #expect(spans.contains(where: { $0.styleName == "code" }))
        #expect(spans.contains(where: { $0.styleName == "strong" }))
        #expect(spans.contains(where: { $0.styleName == "link" }))
    }
}
