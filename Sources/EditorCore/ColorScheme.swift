import Foundation

/// A color scheme file, parsed but not yet turned into platform colors
/// (EditorCore stays AppKit-free; the app maps hex -> NSColor).
///
/// File shape (JSONC, lives in Settings/schemes/<name>.jsonc):
///   {
///     "name": "Mariana",
///     "globals": { "background": "#303841", "foreground": "#D8DEE9", ... },
///     "rules":   { "keyword": "#C695C6", "string": "#99C794", ... }
///   }
/// Rule keys are the semantic style names emitted by SyntaxKit (invariant 5:
/// grammars emit names, schemes own colors).
public struct ColorScheme: Equatable, Sendable {
    public var name: String = ""
    public var globals: [String: String] = [:]
    public var rules: [String: String] = [:]

    public init() {}

    public static func parse(jsonc: String) -> ColorScheme? {
        guard let dict = JSONC.parseObject(jsonc) else { return nil }
        var scheme = ColorScheme()
        scheme.name = dict["name"] as? String ?? ""
        scheme.globals = (dict["globals"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        scheme.rules = (dict["rules"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        return scheme
    }

    /// Dotted-name fallback, the convention tree-sitter queries use:
    /// "keyword.function" tries itself, then "keyword". A scheme therefore
    /// only needs rules as specific as it cares to be.
    public func hex(forStyle styleName: String) -> String? {
        var key = styleName
        while true {
            if let value = rules[key] { return value }
            guard let dot = key.lastIndex(of: ".") else { return nil }
            key = String(key[..<dot])
        }
    }
}
