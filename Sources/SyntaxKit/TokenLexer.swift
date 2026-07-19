import Foundation

/// The interim highlighter: hand-rolled lexers for everyday formats
/// (Markdown, JSON/JSONC). Deliberately behind the same HighlightSpan
/// vocabulary as the future tree-sitter engine (Phase 3), so swapping engines
/// changes zero callers. All offsets are UTF-16 code units, matching
/// EditorCore's convention.
public enum LexLanguage: Sendable {
    case markdown
    case json

    public static func detect(fileExtension ext: String) -> LexLanguage? {
        switch ext.lowercased() {
        case "md", "markdown", "mdown": .markdown
        case "json", "jsonc": .json
        default: nil
        }
    }
}

public enum TokenLexer {

    public static func lex(_ text: String, language: LexLanguage) -> [HighlightSpan] {
        switch language {
        case .json: lexJSON(text)
        case .markdown: lexMarkdown(text)
        }
    }

    // MARK: - JSON / JSONC

    /// Single pass over UTF-16 units. Styles: "key" (a string followed by a
    /// colon), "string", "number", "constant" (true/false/null), "comment".
    static func lexJSON(_ text: String) -> [HighlightSpan] {
        let u = Array(text.utf16)
        var spans: [HighlightSpan] = []
        var i = 0
        let n = u.count

        func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }

        while i < n {
            let c = u[i]
            switch c {
            case 0x22: // "
                let start = i
                i += 1
                while i < n, u[i] != 0x22 {
                    i += u[i] == 0x5C ? 2 : 1 // skip escaped pair
                }
                i = min(i + 1, n) // past the closing quote
                // Lookahead over whitespace: a colon makes this a key.
                var j = i
                while j < n, u[j] == 0x20 || u[j] == 0x09 || u[j] == 0x0A || u[j] == 0x0D { j += 1 }
                let style = (j < n && u[j] == 0x3A) ? "key" : "string"
                spans.append(HighlightSpan(range: start..<i, styleName: style))
            case 0x2F where i + 1 < n && u[i + 1] == 0x2F: // //
                let start = i
                while i < n, u[i] != 0x0A { i += 1 }
                spans.append(HighlightSpan(range: start..<i, styleName: "comment"))
            case 0x2F where i + 1 < n && u[i + 1] == 0x2A: // /*
                let start = i
                i += 2
                while i + 1 < n, !(u[i] == 0x2A && u[i + 1] == 0x2F) { i += 1 }
                i = min(i + 2, n)
                spans.append(HighlightSpan(range: start..<i, styleName: "comment"))
            case 0x2D, 0x30...0x39: // - or digit
                let start = i
                i += 1
                while i < n, isDigit(u[i]) || u[i] == 0x2E || u[i] == 0x65 || u[i] == 0x45 || u[i] == 0x2B || u[i] == 0x2D { i += 1 }
                spans.append(HighlightSpan(range: start..<i, styleName: "number"))
            case 0x74, 0x66, 0x6E: // t f n
                let start = i
                for word in ["true", "false", "null"] {
                    let w = Array(word.utf16)
                    if start + w.count <= n, Array(u[start..<(start + w.count)]) == w {
                        i = start + w.count
                        spans.append(HighlightSpan(range: start..<i, styleName: "constant"))
                        break
                    }
                }
                if i == start { i += 1 } // not a constant; step on
            default:
                i += 1
            }
        }
        return spans
    }

    // MARK: - Markdown

    /// Line-based block pass (headings, fences, quotes, bullets) + regex
    /// inline pass (code, strong, emphasis, links) on ordinary lines.
    static func lexMarkdown(_ text: String) -> [HighlightSpan] {
        let ns = text as NSString
        var spans: [HighlightSpan] = []
        var inFence = false

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineSpan = { (style: String) in
                spans.append(HighlightSpan(range: lineRange.location..<(lineRange.location + lineRange.length), styleName: style))
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                lineSpan("code")
                return
            }
            if inFence { lineSpan("code"); return }
            if trimmed.hasPrefix("#") { lineSpan("heading"); return }
            if trimmed.hasPrefix(">") { lineSpan("quote"); return }
            if trimmed.range(of: #"^([-*_])\s*(\1\s*){2,}$"#, options: .regularExpression) != nil {
                lineSpan("punctuation"); return
            }

            // Leading list marker ("- ", "* ", "+ ", "1. ")
            if let m = Self.bulletRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let r = m.range(at: 1)
                spans.append(HighlightSpan(range: (lineRange.location + r.location)..<(lineRange.location + r.location + r.length), styleName: "bullet"))
            }

            // Inline tokens, earlier patterns claim their ranges first.
            var claimed = IndexSet()
            for (regex, style) in Self.inlinePatterns {
                regex.enumerateMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length)) { match, _, _ in
                    guard let match else { return }
                    let r = match.range
                    let indices = r.location..<(r.location + r.length)
                    guard !claimed.intersects(integersIn: indices) else { return }
                    claimed.insert(integersIn: indices)
                    spans.append(HighlightSpan(range: (lineRange.location + r.location)..<(lineRange.location + r.location + r.length), styleName: style))
                }
            }
        }
        return spans
    }

    private static let bulletRegex = try! NSRegularExpression(pattern: #"^\s*([-*+]|\d+\.)\s"#)

    private static let inlinePatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: "`[^`]+`"), "code"),
        (try! NSRegularExpression(pattern: #"\*\*[^*]+\*\*|__[^_]+__"#), "strong"),
        (try! NSRegularExpression(pattern: #"\*[^*\s][^*]*\*|\b_[^_]+_\b"#), "emphasis"),
        (try! NSRegularExpression(pattern: #"!?\[[^\]]*\]\([^)]+\)"#), "link"),
    ]
}
