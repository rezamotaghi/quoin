import Foundation
import Testing
@testable import EditorCore

@Suite struct JSONCTests {

    @Test func stripsLineComments() {
        let json = JSONC.stripToJSON("{\n// hello\n\"a\": 1 // trailing\n}")
        let dict = JSONC.parseObject(json)
        #expect(dict?["a"] as? Int == 1)
    }

    @Test func stripsBlockComments() {
        let dict = JSONC.parseObject("{ /* x */ \"a\": /* y */ 2 }")
        #expect(dict?["a"] as? Int == 2)
    }

    @Test func preservesSlashesInsideStrings() {
        let dict = JSONC.parseObject(#"{ "url": "https://example.com", "note": "a /* not a comment */" }"#)
        #expect(dict?["url"] as? String == "https://example.com")
        #expect(dict?["note"] as? String == "a /* not a comment */")
    }

    @Test func preservesEscapedQuotesInsideStrings() {
        let dict = JSONC.parseObject(#"{ "a": "say \"hi\" // ok" }"#)
        #expect(dict?["a"] as? String == #"say "hi" // ok"#)
    }

    @Test func removesTrailingCommasInObjectsAndArrays() {
        let dict = JSONC.parseObject("{ \"a\": [1, 2, 3, ], \"b\": 1, // c\n }")
        #expect((dict?["a"] as? [Int]) == [1, 2, 3])
        #expect(dict?["b"] as? Int == 1)
    }

    @Test func commaInsideStringIsNotTrailing() {
        let dict = JSONC.parseObject(#"{ "a": "x, }" }"#)
        #expect(dict?["a"] as? String == "x, }")
    }

    @Test func malformedInputReturnsNil() {
        #expect(JSONC.parseObject("{ not json") == nil)
    }

    @Test func parsesTheShippedDefaultsFile() throws {
        // The real file this app ships; if its syntax drifts out of what the
        // parser handles, this catches it.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EditorCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Settings/default-settings.jsonc")
        let text = try String(contentsOf: url, encoding: .utf8)
        let dict = try #require(JSONC.parseObject(text))
        #expect(dict["tab_size"] as? Int == 4)
        #expect(dict["line_numbers"] as? Bool == true)
    }
}

@Suite struct EditorSettingsTests {

    @Test func defaultsMatchTheShippedFileValues() {
        let s = EditorSettings()
        #expect(s.fontSize == 18)
        #expect(s.tabSize == 4)
        #expect(s.lineNumbers)
        #expect(!s.translateTabsToSpaces)
    }

    @Test func userLayerOverridesKeyByKey() {
        let s = EditorSettings.merging(jsoncLayers: [
            #"{ "font_size": 13, "tab_size": 4 }"#,
            "{ \"font_size\": 15 // my override\n}",
        ])
        #expect(s.fontSize == 15)
        #expect(s.tabSize == 4) // untouched by the user layer
    }

    @Test func unknownKeysAreIgnored() {
        let s = EditorSettings.merging(jsoncLayers: [#"{ "some_future_key": true, "font_size": 12 }"#])
        #expect(s.fontSize == 12)
    }

    @Test func wrongTypedValuesAreSkippedNotFatal() {
        let s = EditorSettings.merging(jsoncLayers: [#"{ "font_size": "big", "tab_size": 8 }"#])
        #expect(s.fontSize == 18) // kept default
        #expect(s.tabSize == 8)
    }

    @Test func malformedLayerIsSkipped() {
        let s = EditorSettings.merging(jsoncLayers: ["{ broken", #"{ "tab_size": 2 }"#])
        #expect(s.tabSize == 2)
    }

    @Test func wordWrapAcceptsAutoAndBool() {
        #expect(EditorSettings.merging(jsoncLayers: [#"{ "word_wrap": "auto" }"#]).wordWrap)
        #expect(!EditorSettings.merging(jsoncLayers: [#"{ "word_wrap": false }"#]).wordWrap)
        #expect(EditorSettings.merging(jsoncLayers: [#"{ "word_wrap": true }"#]).wordWrap)
    }

    @Test func tabSizeIsClampedToAtLeastOne() {
        let s = EditorSettings.merging(jsoncLayers: [#"{ "tab_size": 0 }"#])
        #expect(s.tabSize == 1)
    }
}
