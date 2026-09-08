import Foundation
import Testing
@testable import EditorCore

@Suite struct AgentPolicyTests {

    /// The fence is the README's promise made mechanical: this list is what
    /// "the human has the only save button" means. Changing it is a
    /// contract change, so the test pins every member.
    @Test func commitClassListIsExactlyTheHumanRights() {
        #expect(AgentPolicy.commitClassCommands == [
            "file.save", "file.saveAs", "file.revert", "file.close", "app.quit",
        ])
    }

    @Test func editingCommandsStayRunnable() {
        for id in ["edit.undo", "edit.redo", "view.toggleMarkdownPreview", "selection.addNext", "goto.commandPalette", "file.new", "file.open"] {
            #expect(AgentPolicy.isAgentRunnable(id), "\(id) must stay agent-runnable")
        }
    }

    @Test func commitClassCommandsAreRefusedWithTheRuleNamed() {
        for id in AgentPolicy.commitClassCommands {
            #expect(!AgentPolicy.isAgentRunnable(id))
            #expect(AgentPolicy.refusalMessage(for: id).contains(id))
            #expect(AgentPolicy.refusalMessage(for: id).hasPrefix("refused:"))
        }
    }
}
