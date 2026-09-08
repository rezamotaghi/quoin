import Foundation

/// What Edit > Comment > Toggle Comment inserts, by file extension. Line
/// comments only: languages with block comments alone (Markdown, HTML, CSS
/// style sheets) answer nil and the command declines, rather than guessing.
public enum CommentTokens {

    public static func lineComment(forFileExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "swift", "json", "jsonc", "js", "mjs", "cjs", "jsx", "ts", "tsx",
             "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "kts", "go",
             "rs", "cs", "scala", "dart", "proto", "groovy", "zig":
            "//"
        case "py", "pyi", "pyw", "rb", "sh", "bash", "zsh", "fish", "yaml", "yml",
             "toml", "ini", "cfg", "conf", "r", "pl", "pm", "mk", "dockerfile",
             "gitignore", "env", "ps1", "jl", "nim", "tcl", "cmake":
            "#"
        case "lua", "sql", "hs", "elm", "ada":
            "--"
        case "erl", "tex", "sty", "bib":
            "%"
        case "vim":
            "\""
        case "lisp", "el", "clj", "cljs", "scm", "rkt", "asm", "s":
            ";"
        default:
            nil
        }
    }
}
