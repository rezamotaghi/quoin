import Testing
@testable import EditorCore

@Suite struct IndentationDetectorTests {

    @Test func detectsTabs() {
        let text = "func a() {\n\tfoo()\n\tbar()\n}\n"
        #expect(IndentationDetector.usesSpaces(in: text) == false)
    }

    @Test func detectsSpaces() {
        let text = "def a():\n    foo()\n    bar()\n"
        #expect(IndentationDetector.usesSpaces(in: text) == true)
    }

    @Test func undecidedWhenNoIndentation() {
        let text = "plain\nlines\nonly\n"
        #expect(IndentationDetector.usesSpaces(in: text) == nil)
    }

    @Test func undecidedOnTie() {
        let text = "\ttab line\n  space line\n"
        #expect(IndentationDetector.usesSpaces(in: text) == nil)
    }

    @Test func singleLeadingSpaceIsNotIndentation() {
        // Doc-comment continuation lines (" *") must not vote for spaces.
        let text = "/**\n * a\n * b\n */\nfn() {\n\tx\n}\n"
        #expect(IndentationDetector.usesSpaces(in: text) == false)
    }
}

@Suite struct SaveTransformsTests {

    @Test func trimsTrailingSpacesAndTabs() {
        let out = SaveTransforms.apply(to: "a  \nb\t\nc\n", trimTrailingWhitespace: true, ensureFinalNewline: false)
        #expect(out == "a\nb\nc\n")
    }

    @Test func trimPreservesEmptyLinesAndFinalNewline() {
        let out = SaveTransforms.apply(to: "a\n\n  \nb", trimTrailingWhitespace: true, ensureFinalNewline: false)
        #expect(out == "a\n\n\nb")
    }

    @Test func ensuresFinalNewline() {
        let out = SaveTransforms.apply(to: "a\nb", trimTrailingWhitespace: false, ensureFinalNewline: true)
        #expect(out == "a\nb\n")
    }

    @Test func doesNotDoubleFinalNewline() {
        let out = SaveTransforms.apply(to: "a\n", trimTrailingWhitespace: false, ensureFinalNewline: true)
        #expect(out == "a\n")
    }

    @Test func emptyTextStaysEmpty() {
        let out = SaveTransforms.apply(to: "", trimTrailingWhitespace: true, ensureFinalNewline: true)
        #expect(out == "")
    }

    @Test func noopWhenBothOff() {
        let out = SaveTransforms.apply(to: "a  \nb", trimTrailingWhitespace: false, ensureFinalNewline: false)
        #expect(out == "a  \nb")
    }
}

@Suite struct Phase2SettingsKeysTests {

    @Test func parsesPhase2Keys() {
        let s = EditorSettings.merging(jsoncLayers: [
            #"{ "detect_indentation": false, "copy_with_empty_selection": false, "trim_trailing_white_space_on_save": "all", "ensure_newline_at_eof_on_save": true, "highlight_line": true, "highlight_line_number": false, "hot_exit": false, "open_tabs_after_current": false, "reload_file_on_change": false }"#,
        ])
        #expect(!s.detectIndentation)
        #expect(!s.copyWithEmptySelection)
        #expect(s.trimsTrailingWhitespaceOnSave)
        #expect(s.ensureNewlineAtEOFOnSave)
        #expect(s.highlightLine)
        #expect(!s.highlightLineNumber)
        #expect(!s.hotExit)
        #expect(!s.openTabsAfterCurrent)
        #expect(!s.reloadFileOnChange)
    }

    @Test func trimDefaultsToNone() {
        let s = EditorSettings()
        #expect(!s.trimsTrailingWhitespaceOnSave)
    }
}
