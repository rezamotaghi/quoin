import Foundation
import Testing
@testable import EditorCore

@Suite struct AgentProtocolTests {

    @Test func requestRoundTrips() throws {
        let request = AgentRequest(id: 7, method: "open_file", params: ["path": .string("/tmp/a.txt"), "line": .int(12)])
        let data = try #require(AgentWire.encodeLine(request))
        #expect(data.last == 0x0A)
        let decoded = try #require(AgentWire.decode(AgentRequest.self, from: data.dropLast()))
        #expect(decoded.id == 7)
        #expect(decoded.method == "open_file")
        #expect(decoded.params?["path"]?.stringValue == "/tmp/a.txt")
        #expect(decoded.params?["line"]?.intValue == 12)
    }

    @Test func responseRoundTripsNestedValues() throws {
        let response = AgentResponse(id: 1, result: .array([
            .object(["path": .null, "dirty": .bool(true), "name": .string("Untitled")]),
        ]))
        let data = try #require(AgentWire.encodeLine(response))
        let decoded = try #require(AgentWire.decode(AgentResponse.self, from: data.dropLast()))
        guard case .array(let docs) = decoded.result, case .object(let doc) = docs[0] else {
            Issue.record("wrong shape")
            return
        }
        #expect(doc["dirty"] == .bool(true))
        #expect(doc["path"] == .null)
    }

    @Test func intValueAcceptsStringsAndDoubles() {
        #expect(AgentJSON.string("42").intValue == 42)
        #expect(AgentJSON.double(42.0).intValue == 42)
        #expect(AgentJSON.string("x").intValue == nil)
    }

    @Test func malformedLineDecodesToNil() {
        #expect(AgentWire.decode(AgentRequest.self, from: Data("{oops".utf8)) == nil)
    }

    @Test func agentSettingsKeysParse() {
        let s = EditorSettings.merging(jsoncLayers: [#"{ "agent_server": false, "follow_agent_edits": true }"#])
        #expect(!s.agentServer)
        #expect(s.followAgentEdits)
        #expect(EditorSettings().agentServer)       // default on
        #expect(!EditorSettings().followAgentEdits) // default off
    }
}
