import Foundation

/// THE architectural boundary of this app.
///
/// The concrete text view (NSTextView, STTextView, whatever is currently
/// rented) lives behind this protocol. Every feature - find, palette
/// commands, multi-cursor, split panes - talks to an EditorViewPort and must
/// compile without knowing which view implements it. Swapping the text view
/// means writing one new conformance in Sources/QuoinApp/EditorView/,
/// and nothing else.
///
/// Grows deliberately and slowly: each phase may add methods, but a method
/// that only one concrete view could ever implement is a design smell.
@MainActor
public protocol EditorViewPort: AnyObject {
    /// The full text. Phase 1 keeps this a plain String; if large-file
    /// performance ever demands a rope or piece table, that change happens
    /// behind this property without moving callers.
    var text: String { get set }

    var selectionSet: SelectionSet { get set }

    /// Reveal the given UTF-16 offset (scroll it into view).
    func reveal(offset: Int)
}
