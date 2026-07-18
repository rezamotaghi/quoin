import Foundation
import Testing
@testable import EditorCore

@Suite struct ColorSchemeTests {

    @Test func parsesSchemeFile() {
        let scheme = ColorScheme.parse(jsonc: """
        // comment allowed
        {
            "name": "Test",
            "globals": { "background": "#111213", },
            "rules": { "keyword": "#C695C6", "string": "#99C794", },
        }
        """)
        #expect(scheme?.name == "Test")
        #expect(scheme?.globals["background"] == "#111213")
        #expect(scheme?.rules["keyword"] == "#C695C6")
    }

    @Test func dottedNamesFallBackToPrefix() {
        var scheme = ColorScheme()
        scheme.rules = ["keyword": "#111111", "keyword.operator": "#222222"]
        #expect(scheme.hex(forStyle: "keyword.operator") == "#222222")   // exact
        #expect(scheme.hex(forStyle: "keyword.function") == "#111111")   // falls to "keyword"
        #expect(scheme.hex(forStyle: "keyword.conditional.ternary") == "#111111") // multi-step
        #expect(scheme.hex(forStyle: "variable.builtin") == nil)         // no rule at all
    }

    @Test func malformedFileReturnsNil() {
        #expect(ColorScheme.parse(jsonc: "{ nope") == nil)
    }

    @Test func shippedSchemesParseAndCoverCoreStyles() throws {
        for name in ["mariana", "breakers"] {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // EditorCoreTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // repo root
                .appendingPathComponent("Settings/schemes/\(name).jsonc")
            let text = try String(contentsOf: url, encoding: .utf8)
            let scheme = try #require(ColorScheme.parse(jsonc: text), "\(name) failed to parse")
            for role in ["background", "foreground", "caret"] {
                #expect(scheme.globals[role] != nil, "\(name) missing global \(role)")
            }
            for style in ["comment", "string", "keyword", "number", "text.title"] {
                #expect(scheme.hex(forStyle: style) != nil, "\(name) missing rule \(style)")
            }
        }
    }
}
