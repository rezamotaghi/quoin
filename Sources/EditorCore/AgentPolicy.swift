import Foundation

/// Amendment 2: the commit fence. Everything an agent does over the agent
/// surface lands in the buffer as an undoable edit; the actions that commit
/// the buffer to disk, discard it, or end the session are the human's alone.
/// The list is data (not scattered `if` checks) so the endpoint, the MCP
/// shim's tool descriptions, and the tests all read one definition.
public enum AgentPolicy {

    /// Command ids the agent endpoint refuses to run. Every other registered
    /// command is fair game: an agent may open the palette, toggle the
    /// preview, add a caret, or undo, but never save, revert, close, or quit.
    public static let commitClassCommands: Set<String> = [
        "file.save",
        "file.saveAs",
        "file.saveAll",
        "file.revert",
        "file.close",
        "app.quit",
    ]

    public static func isAgentRunnable(_ commandID: String) -> Bool {
        !commitClassCommands.contains(commandID)
    }

    /// The error text an agent sees; names the rule, not just the refusal.
    public static func refusalMessage(for commandID: String) -> String {
        "refused: \(commandID) is a commit-class command; the human saves, reverts, closes, and quits (Cmd+S is theirs)"
    }
}
