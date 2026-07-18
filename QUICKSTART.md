# Quoin Quickstart

Your own Sublime-class macOS editor. This guide gets you from a fresh
checkout to editing with multi-cursor, tabs, splits, and an AI agent
looking over your shoulder. Open it any time from Help > Quickstart Guide,
and press Cmd+Shift+M right now to read it with the rendered preview.

## 1. Build and install

```bash
cd path/to/quoin
swift test               # 79 unit tests, should be green
Scripts/bundle-app.sh    # produces build/Quoin.app
open build/Quoin.app
```

Want it in the Dock permanently? Run `Scripts/bundle-app.sh --install`:
it builds and refreshes `/Applications/Quoin.app` in one step. Pin that
copy and re-run with `--install` after upgrades.

## 2. First launch

On first run the app creates your personal settings file:

    ~/Library/Application Support/Quoin/settings.jsonc

It starts as an empty JSONC object. Anything you put there overrides the
shipped defaults key by key, and saved changes apply to the running app
instantly. The documented defaults live in the app bundle and in the repo
at `Settings/default-settings.jsonc`; skim that file once, it is the whole
settings vocabulary.

Hot exit is on: quit and relaunch restores every tab, including unsaved
buffers. (Graceful quit only. A force-kill loses unsaved work.)

## 3. Opening things

- **From Finder:** drag files onto the Dock icon, or Open With > Quoin.
- **From a terminal:** install the CLI once, then use `quoin`:

  ```bash
  ln -s "$(pwd)/Scripts/quoin" /usr/local/bin/quoin   # run from the repo root
  quoin notes.md
  quoin Sources/EditorCore/Selection.swift:42    # jumps to line 42
  ```

- **From anywhere on the Mac:** the `quoin://open?file=PATH&line=N`
  URL scheme does the same; agents and other apps can link straight into
  your buffers.
- **Within a project:** File > Open Folder picks a project root, then
  **Cmd+P** fuzzy-finds any file in it by fragment ("edset" finds
  EditorSettings.swift). Excluded folders (`.git`, `node_modules`, `.build`
  and friends) follow your settings.

New files open as tabs of the same window, right of the current tab,
exactly like Sublime.

## 4. Editing

| Key | What happens |
|---|---|
| Cmd+D | Select the word under the caret; press again to add the next occurrence (multi-cursor) |
| Ctrl+Cmd+G | Select every occurrence at once |
| Escape | Collapse many carets back to one |
| Cmd+Alt+2 | Split the window: two views, ONE buffer (edit in either half) |
| Cmd+F / Cmd+Alt+F | Find / find and replace bar |
| Cmd+E | Use selection for find, then Cmd+G steps through matches |
| Cmd+C with nothing selected | Copies the whole line (Sublime habit, on by default) |
| Cmd+Shift+P | Command palette: every menu action, fuzzy-searchable |
| Cmd+Shift+[ / ] | Previous / next tab |

Syntax highlighting is tree-sitter based and covers Swift, Python, JSON,
and Markdown; JSONC uses a dedicated lexer. Indentation style (tabs vs
spaces) is sniffed per file on open.

## 5. Appearance

`"theme": "auto"` follows macOS light/dark and switches between two scheme
files you can edit like any settings file:

- `Settings/schemes/mariana.jsonc` (dark, Sublime's Mariana)
- `Settings/schemes/breakers.jsonc` (light)

Rules map semantic token names to hex colors; dotted names fall back
(`keyword.operator` falls back to `keyword`), so a scheme only needs to be
as detailed as you care to make it. Font and size come from `font_face` /
`font_size` in your settings (default: Menlo 18).

## 6. Markdown

Cmd+Shift+M toggles a rendered preview beside the editor (links open in
your browser; relative image paths resolve next to the file). File >
Export writes Markdown, plain text, or PDF.

## 7. AI agents

The editor is built to work WITH an agent running in a terminal beside it.

**The passive loop needs no setup:** an agent edits files on disk; clean
buffers reload silently. If you have unsaved edits in a file the agent
rewrote, a banner appears under the title bar with the only honest
options: Reload From Disk or Keep My Edits. Nothing is ever merged or
discarded silently. Optional: set `"follow_agent_edits": true` and the
tab an agent just touched comes to the front by itself.

**The active surface needs one command.** Register the bundled MCP shim
with Claude Code:

```bash
claude mcp add quoin -- "$(pwd)/build/Quoin.app/Contents/MacOS/QuoinMCP"
```

After that, an agent can genuinely share your view of the work, and edit it:

- `quoin_list_open_documents`: what is open, what is dirty, what is front
- `quoin_read_buffer`: the LIVE text, including unsaved edits
- `quoin_get_selection`: where your cursor is, what you selected
- `quoin_open_file`: open a file at a line, for you
- `quoin_run_command` / `quoin_list_commands`: the whole command catalog
- `quoin_replace_selection`: rewrite what you have highlighted
- `quoin_apply_edit`: replace an explicit offset range
- `quoin_set_text`: replace the whole document (a full proofread pass)

Every write lands in the buffer as ONE undoable edit, left selected so you
see it, and nothing reaches disk until you save. The agent proposes, your
Cmd+S disposes; one Cmd+Z reverts any agent edit cleanly.

Try it: select a sentence with a typo, ask Claude to "fix the grammar in my
selection in Quoin," watch the fix appear, then Cmd+Z to confirm it
reverts in one step.

Everything is local only: a unix socket at
`~/Library/Application Support/Quoin/agent.sock`, protected by file
permissions, no network listener. Kill switch: `"agent_server": false` in
settings (applies live).

## 8. Troubleshooting

- **Colors gone / plain text?** The app bundle is stale; rerun
  `Scripts/bundle-app.sh` (grammar query bundles ship inside the .app).
- **Agent tools say the editor is not running:** launch the app, or check
  `agent_server` is not set to false in your settings.
- **Settings file broken?** A malformed settings.jsonc can never take the
  editor down; bad values are skipped and defaults win. Fix the JSON and
  save; it hot-applies.
- **Start fresh:** delete
  `~/Library/Application Support/Quoin/settings.jsonc` and relaunch.

## 9. Where things live

| Thing | Path |
|---|---|
| Your settings | `~/Library/Application Support/Quoin/settings.jsonc` |
| Default settings (reference) | `Settings/default-settings.jsonc` in the repo / app bundle |
| Color schemes | `Settings/schemes/*.jsonc` |
| Agent socket | `~/Library/Application Support/Quoin/agent.sock` |
| MCP shim | `Quoin.app/Contents/MacOS/QuoinMCP` |
| CLI opener | `Scripts/quoin` (symlink it onto your PATH) |
| Architecture and decisions | `ARCHITECTURE.md`, `AGENTS.md` in the repo |
