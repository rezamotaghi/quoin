import Foundation
import Testing
@testable import EditorCore

@Suite struct JSONCUpsertTests {

    let starter = "// Quoin user settings (JSONC). Overrides the defaults key-by-key.\n{\n}\n"

    @Test func insertsIntoAnEmptyObjectAndParses() {
        let out = JSONC.upserting(key: "word_wrap", jsonValue: "false", in: starter)
        #expect(out == "// Quoin user settings (JSONC). Overrides the defaults key-by-key.\n{\n\t\"word_wrap\": false,\n}\n")
        #expect(JSONC.parseObject(out)?["word_wrap"] as? Bool == false)
    }

    @Test func replacesAnExistingValueKeepingTheComment() {
        let doc = "{\n\t\"font_size\": 18,   // big\n\t\"theme\": \"auto\",\n}\n"
        let out = JSONC.upserting(key: "font_size", jsonValue: "20", in: doc)
        #expect(out == "{\n\t\"font_size\": 20,   // big\n\t\"theme\": \"auto\",\n}\n")
        let theme = JSONC.upserting(key: "theme", jsonValue: "\"dark\"", in: doc)
        #expect(theme == "{\n\t\"font_size\": 18,   // big\n\t\"theme\": \"dark\",\n}\n")
    }

    @Test func replacesArraysAndLastValuesWithoutTrailingComma() {
        let doc = "{\n  \"draw_white_space\": [\"selection\"],\n  \"line_numbers\": true\n}"
        let arr = JSONC.upserting(key: "draw_white_space", jsonValue: "[\"all\"]", in: doc)
        #expect(arr == "{\n  \"draw_white_space\": [\"all\"],\n  \"line_numbers\": true\n}")
        let last = JSONC.upserting(key: "line_numbers", jsonValue: "false", in: doc)
        #expect(last == "{\n  \"draw_white_space\": [\"selection\"],\n  \"line_numbers\": false\n}")
    }

    @Test func ignoresKeysInsideStringsCommentsAndNestedObjects() {
        let doc = "{\n\t// \"theme\": \"commented out\"\n\t\"font_face\": \"theme\",\n\t\"nested\": {\"theme\": \"inner\"},\n}\n"
        let out = JSONC.upserting(key: "theme", jsonValue: "\"light\"", in: doc)
        #expect(out.hasPrefix("{\n\t\"theme\": \"light\",\n\t// \"theme\": \"commented out\""))
        #expect(JSONC.parseObject(out)?["theme"] as? String == "light")
        #expect((JSONC.parseObject(out)?["nested"] as? [String: Any])?["theme"] as? String == "inner")
    }

    @Test func newKeyOnAMissingObjectMakesOne() {
        let out = JSONC.upserting(key: "tab_size", jsonValue: "2", in: "")
        #expect(JSONC.parseObject(out)?["tab_size"] as? Int == 2)
    }
}
