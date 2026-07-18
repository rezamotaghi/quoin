import EditorCore
import Foundation

/// Walks a project folder into the flat file list Cmd+P searches, honoring
/// the Sublime exclude patterns from settings. Folder patterns prune whole
/// subtrees; file + binary patterns drop individual files.
enum ProjectIndexer {

    static let fileCap = 20_000 // sanity ceiling for giant folders

    /// Relative paths under root, exclusions applied, sorted shallow-first
    /// (so "src/main.swift" outranks deep vendored copies at equal fuzzy
    /// score, because rank is stable).
    static func files(under root: URL, settings: EditorSettings) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else { return [] }

        let rootPath = root.standardizedFileURL.path
        var results: [String] = []

        for case let url as URL in enumerator {
            guard results.count < fileCap else { break }
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if values?.isDirectory == true {
                if GlobPattern.anyMatch(name, patterns: settings.folderExcludePatterns) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            if GlobPattern.anyMatch(name, patterns: settings.fileExcludePatterns) { continue }
            if GlobPattern.anyMatch(name, patterns: settings.binaryFilePatterns) { continue }

            var relative = url.standardizedFileURL.path
            if relative.hasPrefix(rootPath + "/") {
                relative = String(relative.dropFirst(rootPath.count + 1))
            }
            results.append(relative)
        }

        return results.sorted {
            let a = $0.filter { $0 == "/" }.count
            let b = $1.filter { $0 == "/" }.count
            return a == b ? $0.localizedStandardCompare($1) == .orderedAscending : a < b
        }
    }
}
