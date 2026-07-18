import Foundation
import Markdown

/// Markdown -> themed HTML page for the preview pane. swift-markdown does
/// the parsing (CommonMark + GitHub extensions: tables, strikethrough, task
/// lists); this visitor only serializes the tree, so rendering fidelity is
/// the parser's problem, not regex guesswork.
struct MarkdownHTML {

    /// Full standalone page (CSS inlined, themed to the app).
    static func page(markdown: String, dark: Bool) -> String {
        var visitor = HTMLVisitor()
        let body = visitor.visit(Document(parsing: markdown))
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>\(css(dark: dark))</style></head>
        <body><article>\(body)</article></body></html>
        """
    }

    private static func css(dark: Bool) -> String {
        let bg = dark ? "#303841" : "#FCFCFA"
        let fg = dark ? "#D8DEE9" : "#333B41"
        let accent = dark ? "#6699CC" : "#1D5FA9"
        let teal = dark ? "#5FB4B4" : "#0B7C7C"
        let muted = dark ? "#65737E" : "#8A939C"
        let codeBg = dark ? "#262E36" : "#F0F0EE"
        return """
        * { box-sizing: border-box; }
        body { margin: 0; background: \(bg); color: \(fg);
               font: 16px/1.6 -apple-system, sans-serif; }
        article { max-width: 44em; margin: 0 auto; padding: 2em 2.5em 4em; }
        h1, h2, h3, h4 { color: \(accent); line-height: 1.25; margin: 1.4em 0 .5em; }
        h1 { font-size: 1.9em; } h2 { font-size: 1.5em; } h3 { font-size: 1.2em; }
        a { color: \(teal); }
        code { font-family: Menlo, monospace; font-size: .9em;
               background: \(codeBg); padding: .12em .35em; border-radius: 4px; }
        pre { background: \(codeBg); padding: .9em 1.1em; border-radius: 8px;
              overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 1em 0; padding: .1em 1.2em; color: \(muted);
                     border-left: 3px solid \(muted); }
        hr { border: none; border-top: 1px solid \(muted); margin: 2em 0; }
        table { border-collapse: collapse; margin: 1em 0; }
        th, td { border: 1px solid \(muted); padding: .4em .8em; text-align: left; }
        th { background: \(codeBg); }
        img { max-width: 100%; }
        li.task { list-style: none; margin-left: -1.3em; }
        """
    }
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: any Markup) -> String { children(markup) }

    mutating func children(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    mutating func visitHeading(_ h: Heading) -> String { "<h\(h.level)>\(children(h))</h\(h.level)>" }
    mutating func visitParagraph(_ p: Paragraph) -> String { "<p>\(children(p))</p>" }
    func visitText(_ t: Markdown.Text) -> String { escape(t.string) }
    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(children(e))</em>" }
    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(children(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(children(s))</del>" }
    func visitInlineCode(_ c: InlineCode) -> String { "<code>\(escape(c.code))</code>" }
    func visitCodeBlock(_ c: CodeBlock) -> String { "<pre><code>\(escape(c.code))</code></pre>" }
    func visitSoftBreak(_ b: SoftBreak) -> String { "\n" }
    func visitLineBreak(_ b: LineBreak) -> String { "<br>" }
    func visitThematicBreak(_ b: ThematicBreak) -> String { "<hr>" }
    func visitHTMLBlock(_ h: HTMLBlock) -> String { h.rawHTML }        // the user's own document
    func visitInlineHTML(_ h: InlineHTML) -> String { h.rawHTML }

    mutating func visitLink(_ l: Markdown.Link) -> String {
        "<a href=\"\(escape(l.destination ?? "#"))\">\(children(l))</a>"
    }

    mutating func visitImage(_ i: Markdown.Image) -> String {
        "<img src=\"\(escape(i.source ?? ""))\" alt=\"\(escape(i.plainText))\">"
    }

    mutating func visitUnorderedList(_ l: UnorderedList) -> String { "<ul>\(children(l))</ul>" }
    mutating func visitOrderedList(_ l: OrderedList) -> String { "<ol>\(children(l))</ol>" }

    mutating func visitListItem(_ item: ListItem) -> String {
        if let checkbox = item.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li class=\"task\"><input type=\"checkbox\" disabled\(checked)> \(children(item))</li>"
        }
        return "<li>\(children(item))</li>"
    }

    mutating func visitBlockQuote(_ q: BlockQuote) -> String { "<blockquote>\(children(q))</blockquote>" }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        var html = "<table><thead><tr>"
        for cell in table.head.cells { html += "<th>\(children(cell))</th>" }
        html += "</tr></thead><tbody>"
        for row in table.body.rows {
            html += "<tr>"
            for cell in row.cells { html += "<td>\(children(cell))</td>" }
            html += "</tr>"
        }
        return html + "</tbody></table>"
    }
}
