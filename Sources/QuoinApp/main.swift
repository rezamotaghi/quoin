// Entry point. A SwiftPM executable has no storyboard/nib, so instead of
// NSApplicationMain we stand the app up in code: create the shared
// NSApplication, attach our delegate, and start the event loop.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .regular = a normal app with Dock icon and menu bar (needed because the
// binary can also be launched outside a .app bundle, where this isn't implied).
app.setActivationPolicy(.regular)
app.run()
