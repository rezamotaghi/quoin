import Foundation
import Testing
@testable import SyntaxKit

/// These tests exercise the REAL grammars and their bundled highlight
/// queries (SwiftPM puts the query bundles next to the test bundle).
/// Capture names are pinned loosely (prefix matks) so a grammar's query
/// refinements don't break us.
@MainActor
@Suite struct TreeSitterEngineTests {

    private func spans(_ language: SyntaxLanguage, _ source: String) throws -> [(String, String)] {
        let engine = try #require(TreeSitterHighlightEngine(language: language), "engine (grammar/query) failed to load")
        engine.setText(source)
        let ns = source as NSString
        return engine.highlights(in: 0..<ns.length).map {
            (ns.substring(with: NSRange(location: $0.range.lowerBound, length: $0.range.count)), $0.styleName)
        }
    }

    @Test func swiftHighlights() throws {
        let result = try spans(.swift, "// note\nfunc greet() -> String { return \"hi\" }\n")
        #expect(result.contains { $0.0 == "// note" && $0.1.hasPrefix("comment") })
        #expect(result.contains { $0.0 == "func" && $0.1.hasPrefix("keyword") })
        #expect(result.contains { $0.0.contains("hi") && $0.1.hasPrefix("string") })
        #expect(result.contains { $0.0 == "String" && $0.1.hasPrefix("type") })
    }

    @Test func pythonHighlights() throws {
        let result = try spans(.python, "# note\ndef greet(n):\n    return f\"hi {n}\"\n")
        #expect(result.contains { $0.0 == "# note" && $0.1.hasPrefix("comment") })
        #expect(result.contains { $0.0 == "def" && $0.1.hasPrefix("keyword") })
        #expect(result.contains { $0.0 == "greet" && $0.1.hasPrefix("function") })
    }

    @Test func jsonHighlights() throws {
        let result = try spans(.json, "{ \"size\": 18, \"on\": true }")
        #expect(result.contains { $0.0 == "\"size\"" && $0.1 == "string.special.key" })
        #expect(result.contains { $0.0 == "18" && $0.1.hasPrefix("number") })
        #expect(result.contains { $0.0 == "true" && $0.1.hasPrefix("constant") || $0.0 == "true" && $0.1.hasPrefix("boolean") })
    }

    @Test func markdownBlockAndInlineHighlights() throws {
        let result = try spans(.markdown, "# Title\n\nSome **bold** and `code` here.\n")
        // Block grammar: the heading.
        #expect(result.contains { $0.0.contains("Title") && $0.1.hasPrefix("text.title") })
        // Inline grammar (parsed via includedRanges): bold + code span.
        #expect(result.contains { $0.0.contains("bold") && $0.1 == "text.strong" })
        #expect(result.contains { $0.0.contains("code") && $0.1 == "text.literal" })
    }

    @Test func factoryFallsBackToTokenLexerForJSONC() {
        let engine = HighlighterFactory.engine(forFileExtension: "jsonc")
        #expect(engine is TokenLexerEngine)
        let treeSitter = HighlighterFactory.engine(forFileExtension: "swift")
        #expect(treeSitter is TreeSitterHighlightEngine)
        #expect(HighlighterFactory.engine(forFileExtension: "xyz") == nil)
    }

    @Test func highlightsRespectRequestedRange() throws {
        let engine = try #require(TreeSitterHighlightEngine(language: .swift))
        let source = "let a = 1\nlet b = 2\n"
        engine.setText(source)
        let firstLineOnly = engine.highlights(in: 0..<9)
        #expect(!firstLineOnly.isEmpty)
        #expect(firstLineOnly.allSatisfy { $0.range.lowerBound < 9 })
    }
}
