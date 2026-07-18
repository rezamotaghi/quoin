import Testing
@testable import EditorCore

@Suite struct GlobPatternTests {

    @Test func starMatchesRuns() {
        #expect(GlobPattern("*.pyc").matches("module.pyc"))
        #expect(!GlobPattern("*.pyc").matches("module.py"))
        #expect(GlobPattern(".venv*").matches(".venv-py311"))
        #expect(GlobPattern(".Trash-*").matches(".Trash-501"))
    }

    @Test func questionMarkMatchesOneCharacter() {
        #expect(GlobPattern("a?.txt").matches("ab.txt"))
        #expect(!GlobPattern("a?.txt").matches("abc.txt"))
    }

    @Test func literalNamesMatchExactlyAndCaseInsensitive() {
        #expect(GlobPattern("node_modules").matches("node_modules"))
        #expect(GlobPattern(".DS_Store").matches(".ds_store"))
        #expect(!GlobPattern("node_modules").matches("node_modules_backup"))
    }

    @Test func regexSpecialsAreLiteral() {
        #expect(GlobPattern("a+b.txt").matches("a+b.txt"))
        #expect(!GlobPattern("a+b.txt").matches("aab.txt"))
        #expect(GlobPattern("(draft)*").matches("(draft) v2"))
    }

    @Test func anyMatchScansTheList() {
        let patterns = [".git", "*.o", "DerivedData"]
        #expect(GlobPattern.anyMatch("main.o", patterns: patterns))
        #expect(GlobPattern.anyMatch(".git", patterns: patterns))
        #expect(!GlobPattern.anyMatch("main.swift", patterns: patterns))
    }

    @Test func settingsCarryTheStockExcludeLists() {
        let s = EditorSettings()
        #expect(s.folderExcludePatterns.contains(".git"))
        #expect(s.fileExcludePatterns.contains("*.pyc"))
        let overridden = EditorSettings.merging(jsoncLayers: [#"{ "folder_exclude_patterns": ["only_this"] }"#])
        #expect(overridden.folderExcludePatterns == ["only_this"])
    }
}
