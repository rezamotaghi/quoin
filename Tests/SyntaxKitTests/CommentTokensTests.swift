import Testing
@testable import SyntaxKit

@Suite struct CommentTokensTests {

    @Test func bundledLanguagesHaveTheirLineComment() {
        #expect(CommentTokens.lineComment(forFileExtension: "swift") == "//")
        #expect(CommentTokens.lineComment(forFileExtension: "PY") == "#")
        #expect(CommentTokens.lineComment(forFileExtension: "jsonc") == "//")
    }

    @Test func blockCommentOnlyLanguagesDecline() {
        #expect(CommentTokens.lineComment(forFileExtension: "md") == nil)
        #expect(CommentTokens.lineComment(forFileExtension: "html") == nil)
        #expect(CommentTokens.lineComment(forFileExtension: "txt") == nil)
        #expect(CommentTokens.lineComment(forFileExtension: "") == nil)
    }
}
