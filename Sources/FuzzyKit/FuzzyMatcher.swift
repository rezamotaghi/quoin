import Foundation

/// Sublime-style fuzzy matching: the pattern must appear as a subsequence of
/// the candidate; scoring prefers consecutive runs, matches at word
/// boundaries (after / _ - . or a camelCase bump), and earlier matches.
/// Pure function, no state: used by both Cmd+P (file names) and the command
/// palette (command titles).
public enum FuzzyMatcher {

    public struct Match: Equatable, Sendable {
        public let score: Int
        /// UTF-16 indices of the matched characters, for highlight rendering.
        public let positions: [Int]
    }

    public static func match(pattern: String, candidate: String) -> Match? {
        if pattern.isEmpty { return Match(score: 0, positions: []) }
        let p = Array(pattern.lowercased().utf16)
        let cOrig = Array(candidate.utf16)
        let c = Array(candidate.lowercased().utf16)
        guard p.count <= c.count else { return nil }

        var score = 0
        var positions: [Int] = []
        var pi = 0
        var lastMatch = -2

        for ci in 0..<c.count {
            guard pi < p.count, c[ci] == p[pi] else { continue }
            var gain = 1
            if ci == lastMatch + 1 { gain += 8 }            // consecutive run
            if ci == 0 || isSeparator(c[ci - 1]) { gain += 6 }  // word start
            else if isCamelBump(prev: cOrig[ci - 1], cur: cOrig[ci]) { gain += 4 }
            score += gain
            positions.append(ci)
            lastMatch = ci
            pi += 1
        }
        guard pi == p.count else { return nil }             // not a subsequence

        score -= (positions[0]) / 4                          // late start penalty
        score -= (c.count - positions.count) / 8             // long-candidate penalty
        return Match(score: score, positions: positions)
    }

    /// Candidates ranked best-first; non-matches dropped.
    public static func rank(pattern: String, candidates: [String]) -> [(index: Int, match: Match)] {
        candidates.enumerated()
            .compactMap { (i, s) in match(pattern: pattern, candidate: s).map { (i, $0) } }
            .sorted { $0.1.score > $1.1.score }
    }

    private static func isSeparator(_ u: UInt16) -> Bool {
        switch u {
        case 0x2F, 0x5F, 0x2D, 0x2E, 0x20: return true  // / _ - . space
        default: return false
        }
    }

    private static func isCamelBump(prev: UInt16, cur: UInt16) -> Bool {
        func isLower(_ u: UInt16) -> Bool { u >= 0x61 && u <= 0x7A }
        func isUpper(_ u: UInt16) -> Bool { u >= 0x41 && u <= 0x5A }
        return isLower(prev) && isUpper(cur)
    }
}
