import Foundation
import Testing
@testable import SyntaxKit

/// A grammar bundle has had two shapes: SwiftPM's native build system wrote
/// a flat folder, the Swift Build engine (default from Swift 6.4) writes a
/// real macOS bundle. The lookup must find the query file in either, in the
/// build tree and in the app bundle the script assembles from it.
@Suite struct GrammarQueriesTests {

    private func makeBundle(queriesAt relative: String) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("quoin-grammar-\(UUID().uuidString)")
            .appendingPathComponent("TreeSitterX_TreeSitterX.bundle")
        let queries = bundle.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: queries, withIntermediateDirectories: true)
        try "(comment) @comment\n".write(to: queries.appendingPathComponent("highlights.scm"), atomically: true, encoding: .utf8)
        return bundle
    }

    @Test func findsQueriesInAFlatBundle() throws {
        let bundle = try makeBundle(queriesAt: "queries")
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let url = try #require(GrammarQueries.highlights(inBundleAt: bundle))
        #expect(url.path.hasSuffix(".bundle/queries/highlights.scm"))
    }

    @Test func findsQueriesInAMacOSBundle() throws {
        let bundle = try makeBundle(queriesAt: "Contents/Resources/queries")
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let url = try #require(GrammarQueries.highlights(inBundleAt: bundle))
        #expect(url.path.hasSuffix(".bundle/Contents/Resources/queries/highlights.scm"))
    }

    @Test func missingBundleIsNil() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("quoin-no-such-\(UUID().uuidString).bundle")
        #expect(GrammarQueries.highlights(inBundleAt: nowhere) == nil)
    }

    /// The real thing: every shipped grammar resolves in this build tree.
    @Test func everyShippedGrammarResolves() {
        let bundles = [
            ("TreeSitterSwift", "TreeSitterSwift"), ("TreeSitterPython", "TreeSitterPython"),
            ("TreeSitterJSON", "TreeSitterJSON"), ("TreeSitterMarkdown", "TreeSitterMarkdown"),
            ("TreeSitterMarkdown", "TreeSitterMarkdownInline"),
        ]
        for (package, target) in bundles {
            #expect(GrammarQueries.highlightsURL(package: package, target: target) != nil, "\(package)_\(target)")
        }
    }
}
