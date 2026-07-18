// The Phase 3 highlighting engine: tree-sitter (the incremental parsing
// library Zed/Neovim/Helix use) behind the HighlightEngine protocol.
//
// How the pieces fit: each language ships a GRAMMAR (a compiled C parser)
// and a QUERY file (highlights.scm, patterns that tag syntax-tree nodes with
// semantic names like "keyword" or "string"). We parse the buffer into a
// tree, run the query, and emit HighlightSpans whose styleName is the
// query's capture name. Colors happen elsewhere (invariant 5).
import Foundation
import SwiftTreeSitter
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterPython
import TreeSitterSwift

/// The languages with a bundled tree-sitter grammar.
public enum SyntaxLanguage: String, CaseIterable, Sendable {
    case swift
    case python
    case json
    case markdown

    /// jsonc is deliberately absent: the JSON grammar treats comments as
    /// errors, so JSONC stays with the hand-rolled TokenLexer.
    public static func detect(fileExtension ext: String) -> SyntaxLanguage? {
        switch ext.lowercased() {
        case "swift": .swift
        case "py", "pyi", "pyw": .python
        case "json": .json
        case "md", "markdown", "mdown": .markdown
        default: nil
        }
    }

    var languagePointer: OpaquePointer {
        switch self {
        case .swift: tree_sitter_swift()
        case .python: tree_sitter_python()
        case .json: tree_sitter_json()
        case .markdown: tree_sitter_markdown()
        }
    }

    /// (SwiftPM package name, target name): names the resource bundle that
    /// carries this grammar's queries, "<package>_<target>.bundle".
    var bundleNames: (package: String, target: String) {
        switch self {
        case .swift: ("TreeSitterSwift", "TreeSitterSwift")
        case .python: ("TreeSitterPython", "TreeSitterPython")
        case .json: ("TreeSitterJSON", "TreeSitterJSON")
        case .markdown: ("TreeSitterMarkdown", "TreeSitterMarkdown")
        }
    }
}

/// Locates grammar query files. SwiftPM puts each grammar's queries in a
/// resource bundle next to the built products; the app bundle script copies
/// those bundles into Contents/Resources. Tests find them next to the
/// .xctest bundle.
enum GrammarQueries {
    private final class BundleFinder {}

    static func highlightsURL(package: String, target: String) -> URL? {
        let bundleName = "\(package)_\(target).bundle"
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL { candidates.append(url) }
        if let url = Bundle.main.executableURL?.deletingLastPathComponent() { candidates.append(url) }
        // In `swift test`, SyntaxKit is statically linked into the test
        // bundle; the grammar bundles sit in the same build-products folder.
        candidates.append(Bundle(for: BundleFinder.self).bundleURL.deletingLastPathComponent())
        for dir in candidates {
            let url = dir.appendingPathComponent(bundleName).appendingPathComponent("queries/highlights.scm")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

/// Tree-sitter implementation of HighlightEngine.
///
/// Phase 3 re-parses the whole buffer on each (debounced) change: tree-sitter
/// parses megabytes per second, so for real files this is well under a frame.
/// The edit-aware protocol hook is honored by falling back to a full parse;
/// true incremental parsing (tree.edit + reuse) is a later optimization.
@MainActor
public final class TreeSitterHighlightEngine: HighlightEngine {

    private let parser = Parser()
    private let query: Query
    private var tree: MutableTree?
    private var text = ""

    // Markdown is two grammars: a block grammar (headings, fences, lists)
    // plus an inline grammar (emphasis, links) parsed only inside the block
    // tree's "inline" nodes, via includedRanges.
    private let inlineParser: Parser?
    private let inlineQuery: Query?
    private var inlineTree: MutableTree?

    public init?(language: SyntaxLanguage) {
        let tsLanguage = Language(language.languagePointer)
        let names = language.bundleNames
        guard let queryURL = GrammarQueries.highlightsURL(package: names.package, target: names.target),
              let query = try? tsLanguage.query(contentsOf: queryURL),
              (try? parser.setLanguage(tsLanguage)) != nil
        else { return nil }
        self.query = query

        if language == .markdown {
            let inlineLanguage = Language(tree_sitter_markdown_inline())
            let inlineParser = Parser()
            guard let inlineURL = GrammarQueries.highlightsURL(package: "TreeSitterMarkdown", target: "TreeSitterMarkdownInline"),
                  let inlineQuery = try? inlineLanguage.query(contentsOf: inlineURL),
                  (try? inlineParser.setLanguage(inlineLanguage)) != nil
            else { return nil }
            self.inlineParser = inlineParser
            self.inlineQuery = inlineQuery
        } else {
            inlineParser = nil
            inlineQuery = nil
        }
    }

    // MARK: HighlightEngine

    public func setText(_ text: String) {
        self.text = text
        tree = parser.parse(text)
        reparseInlineLayer()
    }

    public func textDidChange(oldRange: Range<Int>, newText: String) {
        // Full re-parse (see class note). The protocol stays edit-aware so an
        // incremental implementation can slot in without touching callers.
        setText(newText)
    }

    public func highlights(in range: Range<Int>) -> [HighlightSpan] {
        var spans = spans(query: query, tree: tree, in: range)
        if let inlineQuery {
            spans += self.spans(query: inlineQuery, tree: inlineTree, in: range)
        }
        // Broad ranges first, narrow later: a caller applying spans in order
        // gets correct nesting (inner tokens painted over outer ones).
        return spans.sorted {
            ($0.range.lowerBound, $1.range.count) < ($1.range.lowerBound, $0.range.count)
        }
    }

    // MARK: Internals

    private func spans(query: Query, tree: MutableTree?, in range: Range<Int>) -> [HighlightSpan] {
        guard let tree else { return [] }
        // ResolvingQueryCursor evaluates the query's predicates (#match?,
        // #eq?): without it, patterns guarded by them would over-apply.
        let cursor = ResolvingQueryCursor(cursor: query.execute(in: tree))
        cursor.prepare(with: text.predicateTextProvider)

        var spans: [HighlightSpan] = []
        while let match = cursor.next() {
            for capture in match.captures {
                guard let name = capture.name, !name.isEmpty, name != "none" else { continue }
                let nsRange = capture.node.range // UTF-16 offsets (we parse as UTF-16)
                guard nsRange.length > 0 else { continue }
                let span = nsRange.location..<(nsRange.location + nsRange.length)
                guard span.overlaps(range) else { continue }
                spans.append(HighlightSpan(range: span, styleName: name))
            }
        }
        return spans
    }

    /// Parse the inline markdown grammar restricted to the block tree's
    /// "inline" nodes. Offsets stay absolute, so the two span sets compose.
    private func reparseInlineLayer() {
        guard let inlineParser else { return }
        inlineTree = nil
        guard let tree else { return }

        var inlineRanges: [TSRange] = []
        func walk(_ node: Node) {
            if node.nodeType == "inline" {
                inlineRanges.append(node.tsRange)
                return // inline nodes don't nest
            }
            for i in 0..<node.childCount {
                if let child = node.child(at: i) { walk(child) }
            }
        }
        if let root = tree.rootNode { walk(root) }
        guard !inlineRanges.isEmpty else { return }

        inlineParser.includedRanges = inlineRanges
        inlineTree = inlineParser.parse(text)
    }
}

/// The hand-rolled lexer (Markdown fallback, JSONC) behind the same protocol.
@MainActor
public final class TokenLexerEngine: HighlightEngine {
    private let language: LexLanguage
    private var text = ""

    public init(language: LexLanguage) {
        self.language = language
    }

    public func setText(_ text: String) { self.text = text }
    public func textDidChange(oldRange: Range<Int>, newText: String) { text = newText }

    public func highlights(in range: Range<Int>) -> [HighlightSpan] {
        TokenLexer.lex(text, language: language).filter { $0.range.overlaps(range) }
    }
}

/// The one place callers obtain an engine: tree-sitter when a grammar
/// exists, TokenLexer where it still earns its keep, nil = plain text.
@MainActor
public enum HighlighterFactory {
    public static func engine(forFileExtension ext: String) -> (any HighlightEngine)? {
        if let language = SyntaxLanguage.detect(fileExtension: ext),
           let engine = TreeSitterHighlightEngine(language: language) {
            return engine
        }
        // jsonc always lands here; md/json also do if query bundles are
        // missing (e.g. a stale app bundle), degrading gracefully.
        if let lexLanguage = LexLanguage.detect(fileExtension: ext) {
            return TokenLexerEngine(language: lexLanguage)
        }
        return nil
    }
}
