import AppKit

/// Sublime's draw_white_space: a faint ("lucent") dot centered where each
/// space is, a short faint bar for tabs. This is a transparent, click-through
/// overlay ABOVE the rented text view; the port feeds it mark rectangles.
/// Keeping it an overlay (instead of hooking the view's own drawing) means
/// it survives a future text-view swap untouched.
final class WhitespaceOverlay: NSView {

    struct Mark {
        let rect: CGRect
        let isTab: Bool
    }

    var marks: [Mark] = [] { didSet { needsDisplay = true } }
    var ink: NSColor = NSColor.white.withAlphaComponent(0.3) { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }          // match text coordinates
    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // never eat clicks

    override func draw(_ dirtyRect: NSRect) {
        guard !marks.isEmpty else { return }
        ink.setFill()
        for mark in marks where mark.rect.intersects(dirtyRect) {
            if mark.isTab {
                let width = min(max(4, mark.rect.width * 0.45), max(2, mark.rect.width - 2))
                let bar = NSRect(x: mark.rect.midX - width / 2, y: mark.rect.midY - 0.75, width: width, height: 1.5)
                NSBezierPath(roundedRect: bar, xRadius: 0.75, yRadius: 0.75).fill()
            } else {
                let d = max(2, mark.rect.height * 0.11)
                NSBezierPath(ovalIn: NSRect(x: mark.rect.midX - d / 2, y: mark.rect.midY - d / 2, width: d, height: d)).fill()
            }
        }
    }
}
