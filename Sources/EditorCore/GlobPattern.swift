import Foundation

/// Sublime-style exclude patterns ("*.pyc", ".venv*", "node_modules"):
/// shell-glob syntax matched against a single path COMPONENT (a file or
/// folder name), not a whole path. * matches any run, ? one character;
/// everything else is literal. Case-insensitive, macOS filesystem style.
public struct GlobPattern: Sendable {
    private let regex: NSRegularExpression?

    public init(_ pattern: String) {
        var escaped = ""
        for ch in pattern {
            switch ch {
            case "*": escaped += ".*"
            case "?": escaped += "."
            default: escaped += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
    }

    public func matches(_ name: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(location: 0, length: (name as NSString).length)
        return regex.firstMatch(in: name, range: range) != nil
    }

    public static func anyMatch(_ name: String, patterns: [String]) -> Bool {
        patterns.contains { GlobPattern($0).matches(name) }
    }
}
