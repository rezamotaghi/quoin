import Foundation

/// Every user-facing action in the app is a Command registered here: menu
/// items, keybindings, and the command palette all read the same registry.
/// This is the extensibility seed - adding a personal command later is a
/// registration, not a UI change.
public struct Command: Identifiable, Sendable {
    public let id: String              // reverse-dot, e.g. "file.save", "view.toggleWordWrap"
    public let title: String           // what the palette shows, e.g. "File: Save"
    public let defaultKeybinding: String?  // e.g. "cmd+s"; user keymap file overrides later
    public let action: @MainActor () -> Void

    public init(id: String, title: String, defaultKeybinding: String? = nil,
                action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.defaultKeybinding = defaultKeybinding
        self.action = action
    }
}

@MainActor
public final class CommandRegistry {
    public static let shared = CommandRegistry()

    private var commands: [String: Command] = [:]

    public init() {}

    public func register(_ command: Command) {
        precondition(commands[command.id] == nil, "duplicate command id: \(command.id)")
        commands[command.id] = command
    }

    public var all: [Command] { commands.values.sorted { $0.title < $1.title } }

    public func run(_ id: String) {
        commands[id]?.action()
    }
}
