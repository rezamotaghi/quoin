import Foundation

/// Pure text logic used by the document layer. Lives in EditorCore so it is
/// unit-testable without AppKit.

/// Sniffs whether a file indents with spaces or tabs (detect_indentation).
public enum IndentationDetector {
    /// true = spaces, false = tabs, nil = undecided (no indented lines, or a
    /// tie). Looks at how indented lines START; a single leading space is
    /// ignored because it is usually continuation alignment (e.g. doc
    /// comments), not indentation.
    public static func usesSpaces(in text: String, sampleLimit: Int = 500) -> Bool? {
        var tabLines = 0
        var spaceLines = 0
        var examined = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if examined >= sampleLimit { break }
            if line.first == "\t" {
                tabLines += 1
                examined += 1
            } else if line.hasPrefix("  ") {
                spaceLines += 1
                examined += 1
            }
        }
        if spaceLines > tabLines { return true }
        if tabLines > spaceLines { return false }
        return nil
    }
}

/// Whole-buffer clean-ups applied on explicit save (never on autosave).
public enum SaveTransforms {
    public static func apply(to text: String, trimTrailingWhitespace: Bool, ensureFinalNewline: Bool) -> String {
        var result = text
        if trimTrailingWhitespace {
            // Split keeping empty lines; a trailing newline round-trips
            // because the final empty subsequence is preserved and rejoined.
            result = result
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    var line = line
                    while line.last == " " || line.last == "\t" { line.removeLast() }
                    return line
                }
                .joined(separator: "\n")
        }
        if ensureFinalNewline, !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }
}
