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

    /// The 1-based line containing a UTF-16 offset (the end of the text
    /// belongs to the last line).
    public static func lineNumber(at offset: Int, in text: String) -> Int {
        let ns = text as NSString
        let clamped = min(max(offset, 0), ns.length)
        var line = 1
        var start = 0
        while start < clamped {
            var end = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            guard end > contentsEnd, end <= clamped else { break } // offset is inside this line
            start = end
            line += 1
        }
        return line
    }

    /// A line's content range and its terminator range (empty for the last
    /// line, or any line without one).
    public static func lineParts(ofLine line: Int, in text: String) -> (content: Range<Int>, terminator: Range<Int>)? {
        guard let start = startOffset(ofLine: line, in: text) else { return nil }
        let ns = text as NSString
        var end = 0
        var contentsEnd = 0
        ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
        return (start..<contentsEnd, contentsEnd..<end)
    }

    /// The UTF-16 range covering the CONTENT of lines `from` through `to`
    /// (1-based, inclusive): from the first character of `from` to the last
    /// character of `to`, excluding `to`'s line terminator. Replacing this
    /// range rewrites those lines while every other line keeps its place; the
    /// replacement needs no trailing newline. nil when the lines do not exist.
    public static func contentRange(ofLines from: Int, through to: Int, in text: String) -> Range<Int>? {
        guard from >= 1, to >= from, let start = startOffset(ofLine: from, in: text) else { return nil }
        guard let last = lineParts(ofLine: to, in: text) else { return nil }
        return start..<last.content.upperBound
    }

    /// The content of lines `from` through `to`, or nil if out of range.
    public static func text(ofLines from: Int, through to: Int, in text: String) -> String? {
        guard let range = contentRange(ofLines: from, through: to, in: text) else { return nil }
        return (text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    /// Every line's content, in order (count == lineCount).
    public static func lines(of text: String) -> [String] {
        let ns = text as NSString
        var result: [String] = []
        var offset = 0
        while true {
            var end = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            result.append(ns.substring(with: NSRange(location: offset, length: contentsEnd - offset)))
            guard end > contentsEnd, end <= ns.length else { break }
            offset = end
            if offset == ns.length { result.append(""); break } // trailing terminator: the empty last line
        }
        return result
    }

    /// The terminator a new line should use: the first one the text uses,
    /// "\n" when it has none yet.
    public static func dominantTerminator(in text: String) -> String {
        let ns = text as NSString
        var end = 0
        var contentsEnd = 0
        var offset = 0
        while offset < ns.length {
            ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            if end > contentsEnd { return ns.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd)) }
            offset = end
        }
        return "\n"
    }
}

/// One buffer replacement plus the selection that should follow it: what a
/// line-level command hands the document to apply as a single undo step.
public struct LineEdit: Equatable, Sendable {
    public let range: Range<Int>
    public let replacement: String
    public let selection: Selection

    public init(range: Range<Int>, replacement: String, selection: Selection) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// The edit applied to a text, for tests and previews.
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: replacement)
    }
}

/// Sublime's Edit > Line, Comment, Convert Case, and Permute Lines commands
/// as pure functions over text and the primary selection. Every function
/// returns the one replacement that performs the command (nil when the
/// command does not apply, e.g. swapping the first line up), so the shell
/// applies it as one undoable edit and never invents line logic.
public enum LineOperations {

    /// The 1-based lines a selection touches. A selection that ends at
    /// column 0 of a line does not include that line (dragging over whole
    /// lines leaves the caret there), a caret always counts its own line.
    public static func lineSpan(of selection: Selection, in text: String) -> ClosedRange<Int> {
        let first = LineIndex.lineNumber(at: selection.lowerBound, in: text)
        var lastOffset = selection.upperBound
        if !selection.isCaret, lastOffset > selection.lowerBound,
           LineIndex.startOffset(ofLine: LineIndex.lineNumber(at: lastOffset, in: text), in: text) == lastOffset {
            lastOffset -= 1
        }
        return first...max(first, LineIndex.lineNumber(at: lastOffset, in: text))
    }

    /// The block of lines: content (first line start to last line content
    /// end) and the last line's terminator.
    static func block(_ lines: ClosedRange<Int>, in text: String) -> (content: Range<Int>, terminator: Range<Int>) {
        let start = LineIndex.startOffset(ofLine: lines.lowerBound, in: text) ?? 0
        let last = LineIndex.lineParts(ofLine: lines.upperBound, in: text) ?? (start..<start, start..<start)
        return (start..<last.content.upperBound, last.terminator)
    }

    private static func substring(_ text: String, _ range: Range<Int>) -> String {
        (text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    private static func utf16Count(_ string: String) -> Int { (string as NSString).length }

    /// Per-line (content, terminator) strings of a block; the last line's
    /// terminator is excluded, as in `block`.
    private static func lineStrings(_ lines: ClosedRange<Int>, in text: String) -> [(content: String, terminator: String)] {
        lines.map { line in
            let parts = LineIndex.lineParts(ofLine: line, in: text) ?? (0..<0, 0..<0)
            let terminator = line == lines.upperBound ? "" : substring(text, parts.terminator)
            return (substring(text, parts.content), terminator)
        }
    }

    // MARK: Line

    /// Cmd+Shift+D: copy the lines below themselves; the selection moves to
    /// the copy.
    public static func duplicate(_ selection: Selection, in text: String) -> LineEdit {
        let span = lineSpan(of: selection, in: text)
        let block = block(span, in: text)
        let blockText = substring(text, block.content)
        let terminator = substring(text, block.terminator)
        if terminator.isEmpty {
            let replacement = LineIndex.dominantTerminator(in: text) + blockText
            let shift = utf16Count(replacement)
            return LineEdit(range: block.content.upperBound..<block.content.upperBound, replacement: replacement,
                            selection: Selection(anchor: selection.anchor + shift, head: selection.head + shift))
        }
        let replacement = blockText + terminator
        let shift = utf16Count(replacement)
        return LineEdit(range: block.terminator.upperBound..<block.terminator.upperBound, replacement: replacement,
                        selection: Selection(anchor: selection.anchor + shift, head: selection.head + shift))
    }

    /// Ctrl+Shift+K: remove the lines entirely, terminator included (or the
    /// terminator before them when they are the last lines).
    public static func delete(_ selection: Selection, in text: String) -> LineEdit {
        let span = lineSpan(of: selection, in: text)
        let block = block(span, in: text)
        let range: Range<Int>
        if !block.terminator.isEmpty {
            range = block.content.lowerBound..<block.terminator.upperBound
        } else if span.lowerBound > 1, let previous = LineIndex.lineParts(ofLine: span.lowerBound - 1, in: text) {
            range = previous.terminator.lowerBound..<block.content.upperBound
        } else {
            range = block.content
        }
        return LineEdit(range: range, replacement: "", selection: Selection(caretAt: range.lowerBound))
    }

    /// Ctrl+Cmd+Up: the lines trade places with the line above.
    public static func swapUp(_ selection: Selection, in text: String) -> LineEdit? {
        let span = lineSpan(of: selection, in: text)
        guard span.lowerBound > 1, let previous = LineIndex.lineParts(ofLine: span.lowerBound - 1, in: text) else { return nil }
        let block = block(span, in: text)
        let previousText = substring(text, previous.content)
        let previousTerminator = substring(text, previous.terminator)
        let blockText = substring(text, block.content)
        let blockTerminator = substring(text, block.terminator)
        let delta = -(utf16Count(previousText) + utf16Count(previousTerminator))
        return LineEdit(range: previous.content.lowerBound..<block.terminator.upperBound,
                        replacement: blockText + previousTerminator + previousText + blockTerminator,
                        selection: Selection(anchor: selection.anchor + delta, head: selection.head + delta))
    }

    /// Ctrl+Cmd+Down: the lines trade places with the line below.
    public static func swapDown(_ selection: Selection, in text: String) -> LineEdit? {
        let span = lineSpan(of: selection, in: text)
        guard let next = LineIndex.lineParts(ofLine: span.upperBound + 1, in: text) else { return nil }
        let block = block(span, in: text)
        let blockText = substring(text, block.content)
        let blockTerminator = substring(text, block.terminator)
        let nextText = substring(text, next.content)
        let nextTerminator = substring(text, next.terminator)
        let delta = utf16Count(nextText) + utf16Count(blockTerminator)
        return LineEdit(range: block.content.lowerBound..<next.terminator.upperBound,
                        replacement: nextText + blockTerminator + blockText + nextTerminator,
                        selection: Selection(anchor: selection.anchor + delta, head: selection.head + delta))
    }

    /// Cmd+Shift+J: the selected lines (or the line and the one below it)
    /// become one line, joined by single spaces.
    public static func join(_ selection: Selection, in text: String) -> LineEdit? {
        var span = lineSpan(of: selection, in: text)
        if span.count == 1 { span = span.lowerBound...(span.lowerBound + 1) }
        guard LineIndex.startOffset(ofLine: span.upperBound, in: text) != nil else { return nil }
        let block = block(span, in: text)
        let pieces = lineStrings(span, in: text).map(\.content)
        var joined = pieces[0]
        for piece in pieces.dropFirst() {
            let trimmed = piece.drop(while: { $0 == " " || $0 == "\t" })
            joined = joined.trimmingTrailingSpaces + (trimmed.isEmpty ? "" : " " + trimmed)
        }
        let caret = block.content.lowerBound + utf16Count(pieces[0].trimmingTrailingSpaces)
        return LineEdit(range: block.content, replacement: joined, selection: Selection(caretAt: caret))
    }

    /// Cmd+]: one indentation unit in front of every non-empty line.
    public static func indent(_ selection: Selection, in text: String, unit: String) -> LineEdit {
        rewriteLines(selection, in: text, caretShiftOnOwnLine: { line, column in
            line.isEmpty || column == 0 ? 0 : utf16Count(unit)
        }) { line in
            line.isEmpty ? line : unit + line
        }
    }

    /// Cmd+[: remove one indentation unit (a tab, or up to tabSize spaces).
    public static func unindent(_ selection: Selection, in text: String, tabSize: Int) -> LineEdit {
        func removed(from line: String) -> Int {
            if line.hasPrefix("\t") { return 1 }
            return min(tabSize, line.prefix(while: { $0 == " " }).count)
        }
        return rewriteLines(selection, in: text, caretShiftOnOwnLine: { line, column in
            -min(removed(from: line), column)
        }) { line in
            String(line.dropFirst(removed(from: line)))
        }
    }

    /// Cmd+/: comment every non-blank line with `token` at the block's
    /// shallowest indentation, or uncomment them all when each already is.
    public static func toggleComment(_ selection: Selection, in text: String, token: String) -> LineEdit {
        let span = lineSpan(of: selection, in: text)
        let lines = lineStrings(span, in: text).map(\.content)
        let nonBlank = lines.filter { !$0.allSatisfy(\.isWhitespace) }
        let allCommented = !nonBlank.isEmpty && nonBlank.allSatisfy { $0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(token) }
        if allCommented {
            return rewriteLines(selection, in: text, caretShiftOnOwnLine: { line, column in
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                guard column > indent else { return 0 }
                let afterToken = line.dropFirst(indent).dropFirst(token.count)
                let removed = token.count + (afterToken.first == " " ? 1 : 0)
                return -min(removed, column - indent)
            }) { line in
                guard !line.allSatisfy(\.isWhitespace) else { return line }
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                var rest = line.dropFirst(indent.count).dropFirst(token.count)
                if rest.first == " " { rest = rest.dropFirst() }
                return String(indent) + rest
            }
        }
        let column = nonBlank.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        let insertion = token + " "
        return rewriteLines(selection, in: text, caretShiftOnOwnLine: { line, caretColumn in
            line.allSatisfy(\.isWhitespace) || caretColumn < column ? 0 : utf16Count(insertion)
        }) { line in
            guard !line.allSatisfy(\.isWhitespace) else { return line }
            let index = line.index(line.startIndex, offsetBy: column)
            return String(line[..<index]) + insertion + String(line[index...])
        }
    }

    /// Shared shape of indent, unindent, and toggleComment: rewrite each line
    /// of the block; a caret stays on its line (shifted as the line's
    /// prefix changed), a range grows to the rewritten block.
    private static func rewriteLines(_ selection: Selection, in text: String,
                                     caretShiftOnOwnLine: (String, Int) -> Int,
                                     _ transform: (String) -> String) -> LineEdit {
        let span = lineSpan(of: selection, in: text)
        let block = block(span, in: text)
        let pieces = lineStrings(span, in: text)
        let replacement = pieces.map { transform($0.content) + $0.terminator }.joined()
        if selection.isCaret, let caretLine = LineIndex.lineParts(ofLine: span.lowerBound, in: text) {
            let column = selection.head - caretLine.content.lowerBound
            let shift = caretShiftOnOwnLine(pieces[0].content, column)
            return LineEdit(range: block.content, replacement: replacement, selection: Selection(caretAt: selection.head + shift))
        }
        return LineEdit(range: block.content, replacement: replacement,
                        selection: Selection(anchor: block.content.lowerBound, head: block.content.lowerBound + utf16Count(replacement)))
    }

    // MARK: Permute Lines

    public enum Permutation: Sendable {
        case sort(caseSensitive: Bool)
        case reverse
        case unique
        case shuffle
    }

    /// F5 and friends: reorder the selected lines (the whole buffer when
    /// nothing is selected). `shuffle` takes its randomness from `shuffler`
    /// so tests can pin it.
    public static func permute(_ selection: Selection, in text: String, _ permutation: Permutation,
                               shuffler: (inout [String]) -> Void = { $0.shuffle() }) -> LineEdit {
        let span = selection.isCaret ? 1...LineIndex.lineCount(in: text) : lineSpan(of: selection, in: text)
        let block = block(span, in: text)
        var lines = lineStrings(span, in: text).map(\.content)
        switch permutation {
        case .sort(let caseSensitive):
            lines = lines.enumerated().sorted { a, b in
                let (x, y) = caseSensitive ? (a.element, b.element) : (a.element.lowercased(), b.element.lowercased())
                return x == y ? a.offset < b.offset : x < y
            }.map(\.element)
        case .reverse:
            lines.reverse()
        case .unique:
            var seen = Set<String>()
            lines = lines.filter { seen.insert($0).inserted }
        case .shuffle:
            shuffler(&lines)
        }
        let replacement = lines.joined(separator: LineIndex.dominantTerminator(in: text))
        return LineEdit(range: block.content, replacement: replacement,
                        selection: Selection(anchor: block.content.lowerBound, head: block.content.lowerBound + utf16Count(replacement)))
    }

    // MARK: Convert Case

    /// Swap Case on the selected text (nil for a bare caret).
    public static func swapCase(_ selection: Selection, in text: String) -> LineEdit? {
        guard !selection.isCaret else { return nil }
        let original = substring(text, selection.range)
        let swapped = String(original.map { character -> String in
            if character.isUppercase { return character.lowercased() }
            if character.isLowercase { return character.uppercased() }
            return String(character)
        }.joined())
        return LineEdit(range: selection.range, replacement: swapped,
                        selection: Selection(anchor: selection.lowerBound, head: selection.lowerBound + utf16Count(swapped)))
    }
}

private extension String {
    var trimmingTrailingSpaces: String {
        var result = self
        while result.last == " " || result.last == "\t" { result.removeLast() }
        return result
    }
}

/// Sublime's Selection menu beyond what the view already offers: pure
/// functions over text and SelectionSet.
public enum SelectionOperations {

    /// Cmd+Shift+L: each selected line becomes its own selection.
    public static func splitIntoLines(_ set: SelectionSet, in text: String) -> SelectionSet {
        var result: [Selection] = []
        for selection in set.normalized().selections {
            guard !selection.isCaret else { result.append(selection); continue }
            for line in LineOperations.lineSpan(of: selection, in: text) {
                guard let parts = LineIndex.lineParts(ofLine: line, in: text) else { continue }
                let lower = max(parts.content.lowerBound, selection.lowerBound)
                let upper = min(parts.content.upperBound, selection.upperBound)
                result.append(Selection(anchor: lower, head: max(lower, upper)))
            }
        }
        return SelectionSet(result.isEmpty ? set.selections : result, primaryIndex: max(0, result.count - 1))
    }

    /// Ctrl+Shift+Down / Up: add a caret (or a same-column selection) on the
    /// line after the last selection, or before the first one.
    public static func addLine(_ set: SelectionSet, in text: String, forward: Bool) -> SelectionSet {
        let ordered = set.normalized().selections
        guard let edge = forward ? ordered.last : ordered.first else { return set }
        let headLine = LineIndex.lineNumber(at: edge.head, in: text)
        let anchorLine = LineIndex.lineNumber(at: edge.anchor, in: text)
        let target = forward ? max(headLine, anchorLine) + 1 : min(headLine, anchorLine) - 1
        guard let targetParts = LineIndex.lineParts(ofLine: target, in: text),
              let headParts = LineIndex.lineParts(ofLine: headLine, in: text),
              let anchorParts = LineIndex.lineParts(ofLine: anchorLine, in: text) else { return set }
        func place(_ offset: Int, from line: (content: Range<Int>, terminator: Range<Int>)) -> Int {
            targetParts.content.lowerBound + min(offset - line.content.lowerBound, targetParts.content.count)
        }
        let added = headLine == anchorLine
            ? Selection(anchor: place(edge.anchor, from: anchorParts), head: place(edge.head, from: headParts))
            : Selection(caretAt: place(edge.head, from: headParts))
        let all = ordered + [added]
        return SelectionSet(all, primaryIndex: all.count - 1)
    }

    /// Everything that is not selected becomes selected (a caret with
    /// nothing selected inverts to the whole buffer).
    public static func invert(_ set: SelectionSet, in text: String) -> SelectionSet {
        let length = (text as NSString).length
        var result: [Selection] = []
        var cursor = 0
        for selection in set.normalized().selections where !selection.isCaret {
            if selection.lowerBound > cursor { result.append(Selection(anchor: cursor, head: selection.lowerBound)) }
            cursor = max(cursor, selection.upperBound)
        }
        if cursor < length { result.append(Selection(anchor: cursor, head: length)) }
        return SelectionSet(result.isEmpty ? [Selection(caretAt: length)] : result, primaryIndex: max(0, result.count - 1))
    }
}
