// Swift Testing (not XCTest): XCTest ships with Xcode.app, which this
// machine doesn't have; Swift Testing ships in the toolchain itself.
import Testing
@testable import FuzzyKit

@Suite struct FuzzyMatcherTests {

    @Test func nonSubsequenceFails() {
        #expect(FuzzyMatcher.match(pattern: "xyz", candidate: "main.swift") == nil)
    }

    @Test func caseInsensitiveSubsequenceMatches() {
        #expect(FuzzyMatcher.match(pattern: "fm", candidate: "FuzzyMatcher.swift") != nil)
    }

    @Test func wordBoundaryBeatsMidWord() {
        // "sel" at the start of "Selection.swift" should outscore
        // a scattered match inside "consoleLogger.swift".
        let ranked = FuzzyMatcher.rank(
            pattern: "sel",
            candidates: ["consoleLogger.swift", "Selection.swift"]
        )
        #expect(ranked.first?.index == 1)
    }

    @Test func consecutiveRunBeatsScattered() {
        let ranked = FuzzyMatcher.rank(
            pattern: "editor",
            candidates: ["e_d_i_t_o_r_x.txt", "EditorCore.swift"]
        )
        #expect(ranked.first?.index == 1)
    }

    @Test func emptyPatternMatchesEverything() {
        #expect(FuzzyMatcher.match(pattern: "", candidate: "anything") != nil)
    }
}
