import Foundation

/// Line arithmetic over UTF-16 offsets, the convention EditorCore speaks.
/// Lines are 1-based, the way the gutter, `quoin file:line`, and agents
/// count them. A file that ends with a newline has one more (empty) line
/// after it, exactly as the gutter shows. Terminators follow Foundation's
/// line rules (LF, CRLF, CR, and the Unicode separators).
public enum LineIndex {

    /// How many lines the gutter would number.
    public static func lineCount(in text: String) -> Int {
        let ns = text as NSString
        var count = 1
        var offset = 0
        while offset < ns.length {
            var end = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            if end > contentsEnd { count += 1 } // this line has a terminator, so another line follows
            if end <= offset { break }        // no progress: defensive, cannot happen below length
            offset = end
        }
        return count
    }

    /// UTF-16 offset where a 1-based line starts, or nil if the text has
    /// fewer lines.
    public static func startOffset(ofLine line: Int, in text: String) -> Int? {
        guard line >= 1 else { return nil }
        let ns = text as NSString
        var offset = 0
        var current = 1
        while current < line {
            guard offset < ns.length else { return nil }
            var end = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            guard end > contentsEnd else { return nil } // last line has no terminator: nothing follows
            offset = end
            current += 1
        }
        return offset
    }

    /// The UTF-16 range covering the CONTENT of lines `from` through `to`
    /// (1-based, inclusive): from the first character of `from` to the last
    /// character of `to`, excluding `to`'s line terminator. Replacing this
    /// range rewrites those lines while every other line keeps its place; the
    /// replacement needs no trailing newline. nil when the lines do not exist.
    public static func contentRange(ofLines from: Int, through to: Int, in text: String) -> Range<Int>? {
        guard from >= 1, to >= from, let start = startOffset(ofLine: from, in: text) else { return nil }
        guard let lastStart = to == from ? start : startOffset(ofLine: to, in: text) else { return nil }
        let ns = text as NSString
        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: lastStart, length: 0))
        return start..<contentsEnd
    }

    /// The content of lines `from` through `to`, or nil if out of range.
    public static func text(ofLines from: Int, through to: Int, in text: String) -> String? {
        guard let range = contentRange(ofLines: from, through: to, in: text) else { return nil }
        return (text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }
}
