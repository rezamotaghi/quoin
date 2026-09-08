import Foundation

/// The settings vocabulary, Sublime key names (invariant 4). This struct's
/// default values ARE the app defaults; Settings/default-settings.jsonc ships
/// the same values as a readable, commented file, and the user's
/// settings.jsonc overrides key-by-key on top. Unknown keys are ignored,
/// never an error.
///
/// Lives in EditorCore (pure Foundation, no AppKit) so parsing and merging
/// are unit-testable.
public struct EditorSettings: Equatable, Sendable {
    public var theme: String = "auto"          // "auto" follows the OS appearance | "dark" | "light"
    public var darkColorScheme: String = "mariana"
    public var lightColorScheme: String = "breakers"
    // Menlo mirrors Sublime's Mac platform default face; 18 is a
    // deliberate size-up from its stock size.
    public var fontFace: String = "Menlo"      // "" = system monospace
    public var fontSize: Double = 18
    public var tabSize: Int = 4
    public var translateTabsToSpaces: Bool = false
    public var wordWrap: Bool = true           // JSON false = off; true or "auto" = on (Phase 1)
    public var lineNumbers: Bool = true
    public var defaultEncoding: String = "UTF-8"
    public var fallbackEncoding: String = "windows-1252"
    // Phase 2
    public var detectIndentation: Bool = true
    public var copyWithEmptySelection: Bool = true
    public var trimTrailingWhiteSpaceOnSave: String = "none"  // "none" | "all" (other values treated as "all")
    public var ensureNewlineAtEOFOnSave: Bool = false
    public var highlightLine: Bool = false
    public var highlightLineNumber: Bool = true
    public var hotExit: Bool = true
    public var openTabsAfterCurrent: Bool = true
    public var reloadFileOnChange: Bool = true
    /// Sublime's draw_white_space vocabulary. Only the coarse modes are
    /// honored: any "all*" entry wins, else any "selection*" entry, else off.
    public var drawWhiteSpace: [String] = ["selection"]

    public enum WhitespaceDrawMode: Sendable { case none, selection, all }
    public var whitespaceMode: WhitespaceDrawMode {
        if drawWhiteSpace.contains(where: { $0 == "all" || $0.hasPrefix("all_") }) { return .all }
        if drawWhiteSpace.contains(where: { $0 == "selection" || ($0.hasPrefix("selection_") && $0 != "selection_none") }) { return .selection }
        return .none
    }

    // Amendment 1: agent surface
    public var agentServer: Bool = true       // local unix-socket endpoint for agents/MCP
    public var followAgentEdits: Bool = false // front a tab when an external edit reloads it

    // Phase 4: Cmd+P indexing (defaults mirror default-settings.jsonc)
    public var folderExcludePatterns: [String] = [".svn", ".git", ".hg", "CVS", ".Trash", ".Trash-*", "node_modules", ".build", ".venv*", "DerivedData"]
    public var fileExcludePatterns: [String] = ["*.pyc", "*.pyo", "*.exe", "*.dll", "*.obj", "*.o", "*.a", "*.lib", "*.so", "*.dylib", "*.ncb", "*.sdf", "*.suo", "*.pdb", "*.idb", ".DS_Store", ".directory", "desktop.ini", "*.class", "*.psd", "*.db", "*.sublime-workspace"]
    public var binaryFilePatterns: [String] = ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.ttf", "*.tga", "*.dds", "*.ico", "*.eot", "*.pdf", "*.swf", "*.jar", "*.zip", "*.webp", "*.otf"]

    /// Convenience: should save trim trailing whitespace?
    public var trimsTrailingWhitespaceOnSave: Bool { trimTrailingWhiteSpaceOnSave != "none" }

    public init() {}

    /// Overlay one parsed settings dictionary onto self. Only known keys are
    /// read; wrong-typed values are skipped rather than erroring, so a broken
    /// user file can never take the editor down.
    public mutating func apply(_ dict: [String: Any]) {
        if let v = dict["theme"] as? String { theme = v }
        if let v = dict["dark_color_scheme"] as? String { darkColorScheme = v }
        if let v = dict["light_color_scheme"] as? String { lightColorScheme = v }
        if let v = dict["font_face"] as? String { fontFace = v }
        if let v = dict["font_size"] as? NSNumber { fontSize = v.doubleValue }
        if let v = dict["tab_size"] as? NSNumber { tabSize = max(1, v.intValue) }
        if let v = boolValue(dict["translate_tabs_to_spaces"]) { translateTabsToSpaces = v }
        if let raw = dict["word_wrap"] {
            // Sublime allows true/false/"auto"; Phase 1 treats "auto" as on.
            if let b = boolValue(raw) { wordWrap = b } else if raw as? String == "auto" { wordWrap = true }
        }
        if let v = boolValue(dict["line_numbers"]) { lineNumbers = v }
        if let v = dict["default_encoding"] as? String { defaultEncoding = v }
        if let v = dict["fallback_encoding"] as? String { fallbackEncoding = v }
        if let v = boolValue(dict["detect_indentation"]) { detectIndentation = v }
        if let v = boolValue(dict["copy_with_empty_selection"]) { copyWithEmptySelection = v }
        if let v = dict["trim_trailing_white_space_on_save"] as? String { trimTrailingWhiteSpaceOnSave = v }
        if let v = boolValue(dict["ensure_newline_at_eof_on_save"]) { ensureNewlineAtEOFOnSave = v }
        if let v = boolValue(dict["highlight_line"]) { highlightLine = v }
        if let v = boolValue(dict["highlight_line_number"]) { highlightLineNumber = v }
        if let v = boolValue(dict["hot_exit"]) { hotExit = v }
        if let v = boolValue(dict["open_tabs_after_current"]) { openTabsAfterCurrent = v }
        if let v = boolValue(dict["reload_file_on_change"]) { reloadFileOnChange = v }
        if let v = dict["draw_white_space"] as? [Any] { drawWhiteSpace = v.compactMap { $0 as? String } }
        if let v = boolValue(dict["agent_server"]) { agentServer = v }
        if let v = boolValue(dict["follow_agent_edits"]) { followAgentEdits = v }
        if let v = stringArray(dict["folder_exclude_patterns"]) { folderExcludePatterns = v }
        if let v = stringArray(dict["file_exclude_patterns"]) { fileExcludePatterns = v }
        if let v = stringArray(dict["binary_file_patterns"]) { binaryFilePatterns = v }
    }

    private func stringArray(_ any: Any?) -> [String]? {
        (any as? [Any])?.compactMap { $0 as? String }
    }

    /// Build settings from JSONC layers, lowest priority first (defaults
    /// file, then user file). Layers that fail to parse are skipped.
    public static func merging(jsoncLayers layers: [String]) -> EditorSettings {
        var settings = EditorSettings()
        for layer in layers {
            if let dict = JSONC.parseObject(layer) {
                settings.apply(dict)
            }
        }
        return settings
    }

    /// JSON booleans arrive as NSNumber from JSONSerialization; accept both.
    private func boolValue(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        return nil
    }
}

/// JSONC = JSON + // and /* */ comments + trailing commas (what Sublime and
/// VS Code use for settings files). Foundation's JSONSerialization only
/// speaks strict JSON, so we strip the extras first, string-aware: a "//"
/// inside a quoted value must survive.
public enum JSONC {
    /// Convert JSONC text to strict JSON text.
    public static func stripToJSON(_ input: String) -> String {
        var out: [Character] = []
        var chars = Array(input)
        var i = 0
        var inString = false
        // Index in `out` of a comma that might turn out to be trailing.
        var pendingComma: Int? = nil

        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count {
                    out.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            // Outside a string.
            if c == "\"" {
                inString = true
                pendingComma = nil
                out.append(c)
                i += 1
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue // keep the newline itself
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, chars.count)
                continue
            }
            if c == "," {
                pendingComma = out.count
                out.append(c)
                i += 1
                continue
            }
            if c == "}" || c == "]" {
                if let commaIndex = pendingComma {
                    out.remove(at: commaIndex) // trailing comma: drop it
                }
                pendingComma = nil
                out.append(c)
                i += 1
                continue
            }
            if !c.isWhitespace { pendingComma = nil }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    /// Parse a JSONC document whose top level is an object.
    public static func parseObject(_ jsonc: String) -> [String: Any]? {
        let json = stripToJSON(jsonc)
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Set one top-level key of a JSONC document to `jsonValue` (already
    /// JSON-encoded, e.g. `true`, `14`, `"dark"`, `["all"]`), keeping every
    /// comment and the rest of the formatting: the value of an existing key
    /// is replaced in place, a new key is inserted after the opening brace.
    /// The menu's toggles write the user's settings file through this, so the
    /// file stays theirs (comments and all) and the file watcher does the rest.
    public static func upserting(key: String, jsonValue: String, in document: String) -> String {
        let chars = Array(document)
        var i = 0
        var depth = 0
        var inString = false
        var stringStart = 0
        var openBrace: Int? = nil

        /// Skip a value starting at `from` (depth 1), returning the index just
        /// past its last non-whitespace character.
        func valueEnd(from: Int) -> Int {
            var j = from
            var d = 0
            var s = false
            var lastContent = from
            while j < chars.count {
                let c = chars[j]
                if s {
                    lastContent = j + 1
                    if c == "\\" { j += 2; continue }
                    if c == "\"" { s = false }
                    j += 1
                    continue
                }
                if c == "\"" { s = true; lastContent = j + 1; j += 1; continue }
                if c == "/", j + 1 < chars.count, chars[j + 1] == "/" {
                    if d == 0 { break }
                    while j < chars.count, chars[j] != "\n" { j += 1 }
                    continue
                }
                if c == "/", j + 1 < chars.count, chars[j + 1] == "*" {
                    if d == 0 { break }
                    j += 2
                    while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                    j = min(j + 2, chars.count)
                    continue
                }
                if c == "[" || c == "{" { d += 1 }
                if c == "]" || c == "}" {
                    if d == 0 { break }
                    d -= 1
                }
                if c == "," && d == 0 { break }
                if !c.isWhitespace { lastContent = j + 1 }
                j += 1
            }
            return lastContent
        }

        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\" { i += 2; continue }
                if c == "\"" {
                    inString = false
                    // A top-level key: "name" followed by a colon.
                    if depth == 1 {
                        let name = String(chars[(stringStart + 1)..<i])
                        var k = i + 1
                        while k < chars.count, chars[k].isWhitespace { k += 1 }
                        if k < chars.count, chars[k] == ":", name == key {
                            var v = k + 1
                            while v < chars.count, chars[v].isWhitespace { v += 1 }
                            let end = valueEnd(from: v)
                            return String(chars[..<v]) + jsonValue + String(chars[end...])
                        }
                        // Not our key: skip its value so nested strings are not mistaken for keys.
                        if k < chars.count, chars[k] == ":" {
                            var v = k + 1
                            while v < chars.count, chars[v].isWhitespace { v += 1 }
                            i = valueEnd(from: v)
                            continue
                        }
                    }
                }
                i += 1
                continue
            }
            if c == "\"" { inString = true; stringStart = i; i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, chars.count)
                continue
            }
            if c == "{" {
                depth += 1
                if depth == 1, openBrace == nil { openBrace = i }
            }
            if c == "}" || c == "]" { depth -= 1 }
            if c == "[" { depth += 1 }
            i += 1
        }

        // Key absent: insert right after the top-level opening brace.
        let line = "\n\t\"\(key)\": \(jsonValue),"
        if let brace = openBrace {
            return String(chars[...brace]) + line + String(chars[(brace + 1)...])
        }
        return "{" + line + "\n}\n"
    }
}
