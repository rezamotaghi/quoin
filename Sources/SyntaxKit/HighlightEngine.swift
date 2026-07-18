import Foundation

/// A styled span produced by highlighting. `styleName` is a semantic token
/// name ("keyword", "string", "comment", ...) resolved to a color by the
/// active color scheme, never a color itself: schemes and grammars stay
/// independent.
public struct HighlightSpan: Equatable, Sendable {
    public let range: Range<Int>   // UTF-16 offsets, same convention as EditorCore
    public let styleName: String

    public init(range: Range<Int>, styleName: String) {
        self.range = range
        self.styleName = styleName
    }
}

/// Boundary for syntax highlighting. Phase 3 implements this with
/// tree-sitter (incremental parsing: re-parse only the edited region on each
/// keystroke). The protocol is deliberately edit-aware so an incremental
/// engine fits without breaking callers.
/// MainActor: engines run on the UI thread today (SwiftTreeSitter's
/// predicate resolution is itself MainActor); background parsing would be a
/// deliberate change here, not a per-engine accident.
@MainActor
public protocol HighlightEngine: AnyObject {
    /// Full (re)load of a document.
    func setText(_ text: String)

    /// Report an edit so an incremental parser can update cheaply.
    /// `newText` is the replacement for `oldRange`.
    func textDidChange(oldRange: Range<Int>, newText: String)

    /// Spans for the requested (visible) range. May return spans that extend
    /// slightly beyond it.
    func highlights(in range: Range<Int>) -> [HighlightSpan]
}

/// Placeholder: no highlighting.
@MainActor
public final class PlainTextEngine: HighlightEngine {
    public init() {}
    public func setText(_ text: String) {}
    public func textDidChange(oldRange: Range<Int>, newText: String) {}
    public func highlights(in range: Range<Int>) -> [HighlightSpan] { [] }
}
