import AppKit
import EditorCore

/// Loads color scheme files and answers "what colors right now?" questions.
///
/// theme "auto" follows the OS appearance; "dark"/"light" pin it. The dark
/// and light sides each name a scheme file (dark_color_scheme /
/// light_color_scheme), loaded from the app bundle's Resources/schemes/.
@MainActor
enum Theme {

    /// Is the app currently rendering dark?
    static var isDark: Bool {
        switch SettingsStore.shared.settings.theme {
        case "dark": true
        case "light": false
        default: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    static var activeScheme: ColorScheme {
        let settings = SettingsStore.shared.settings
        return SchemeStore.shared.scheme(named: isDark ? settings.darkColorScheme : settings.lightColorScheme)
    }

    /// Scheme color for a semantic style name (with dotted fallback).
    static func color(forStyle styleName: String) -> NSColor? {
        activeScheme.hex(forStyle: styleName).flatMap(SchemeStore.color(hex:))
    }
}

@MainActor
final class SchemeStore {

    static let shared = SchemeStore()

    private var cache: [String: ColorScheme] = [:]

    func scheme(named name: String) -> ColorScheme {
        if let cached = cache[name] { return cached }
        let loaded = load(name) ?? ColorScheme() // empty scheme = plain foreground text
        cache[name] = loaded
        return loaded
    }

    private func load(_ name: String) -> ColorScheme? {
        var candidates: [URL] = []
        if let url = Bundle.main.resourceURL {
            candidates.append(url.appendingPathComponent("schemes/\(name).jsonc"))
        }
        // swift run / development fallback: the repo's own Settings/schemes.
        candidates.append(URL(fileURLWithPath: "Settings/schemes/\(name).jsonc"))
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let scheme = ColorScheme.parse(jsonc: text) {
                return scheme
            }
        }
        return nil
    }

    /// "#RRGGBB" (or "#RGB") to NSColor; cached because highlight passes ask
    /// for the same few colors thousands of times.
    private static var colorCache: [String: NSColor] = [:]

    static func color(hex: String) -> NSColor? {
        if let cached = colorCache[hex] { return cached }
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let color = NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
        colorCache[hex] = color
        return color
    }
}
