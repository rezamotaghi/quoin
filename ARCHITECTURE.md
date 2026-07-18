# Architecture

A Sublime-class macOS text editor, built to evolve deliberately.
This document is the frozen foundation: the decisions here change only
deliberately, never as a side effect of implementing a feature.

## The one decision everything hangs on

A text editor has two halves: the **document model** (text, selections, undo
history, as pure data) and the **text view** (the component that draws glyphs
and handles keystrokes). Sublime's magic is a custom text view; that is years
of work and not the plan here.

So the foundational rule: **the document model is ours from day one; the text
view is a rented component hidden behind a protocol.** The protocol is
`EditorViewPort` in `Sources/EditorCore/EditorViewPort.swift`. Every feature
talks to it; nothing outside `Sources/QuoinApp/EditorView/` may name the
concrete view's types. When the rental is outgrown (most likely at
multi-cursor), it is swapped by writing one new conformance.

Rental candidates, to be verified against their current state at Phase 1
(do not assert their capabilities from memory):
- **STTextView** (TextKit 2 based, check multi-insertion-point support)
- **CodeEditSourceEditor** (CodeEdit project; bundles tree-sitter highlighting
  and line numbers, heavier dependency)
- **NSTextView** raw (the fallback that always works; fights multi-cursor)

## Stack (frozen decisions)

| Concern | Decision | Why |
|---|---|---|
| Language / UI | Swift, AppKit shell; SwiftUI only for panels (palette, settings UI) | SwiftUI has no serious text-editing surface; AppKit is where TextKit lives |
| Documents | `NSDocument` | Free: open/save/save-as, dirty-dot, autosave, revert, recents, Finder integration, and it drives native tabs |
| Tabs | Native macOS window tabbing first; custom Sublime-style tab strip is a later cosmetic swap | One line of configuration, correct behavior for free. Sublime itself runs `"native_tabs": "system"` on Mac |
| Highlighting | tree-sitter via SwiftTreeSitter, wrapped in the `HighlightEngine` protocol (SyntaxKit) | Incremental parsing: re-parses only the edited region per keystroke. What Zed/Neovim/Helix use |
| Settings | JSONC files (JSON + comments), Sublime key names, hot-reloaded on change | "Tweak it exactly my way" as a text file, not a GUI. See `Settings/default-settings.jsonc` |
| Build system | Pure SwiftPM + `Scripts/bundle-app.sh` to produce `Quoin.app` | This machine has Command Line Tools only (no Xcode.app). Fully CLI-driven, ideal for agent sessions. If Xcode is installed later, adding an XcodeGen project is a contained step |
| Text offsets | UTF-16 code units everywhere in EditorCore | It is what NSRange/TextKit speak; converting at the boundary invites emoji/off-by-one bugs |

## Module layout

```
Package.swift            one package, five targets
Sources/
  EditorCore/            PURE data: Selection, SelectionSet, EditorViewPort.
                         Never imports AppKit or SwiftUI. Multi-cursor is
                         [Selection] here, not view state.
  SyntaxKit/             HighlightEngine protocol + (Phase 3) tree-sitter impl.
                         Emits semantic style names; color schemes resolve them.
  CommandKit/            Command = {id, title, keybinding, action} + registry.
                         Menus, keybindings, and the palette all read this.
  FuzzyKit/              The fuzzy scorer (pure function, tested).
  QuoinApp/              The AppKit shell. Subfolders as they arrive:
                         Shell/ (NSDocument, windows, tabs, panes),
                         EditorView/ (the RENTED view behind EditorViewPort),
                         Palette/, Settings/.
Tests/                   EditorCoreTests, FuzzyKitTests (grow per phase)
Scripts/bundle-app.sh    swift build -c release -> build/Quoin.app
Settings/                default-settings.jsonc (+ schemes/ from Phase 3)
Resources/Info.plist     bundle template (document types added in Phase 1)
```

## Invariants (enforced in review, violations are bugs)

1. `EditorCore` never imports AppKit or SwiftUI. It is testable data.
2. Nothing outside `Sources/QuoinApp/EditorView/` names the rented text
   view's types. Everything else talks to `EditorViewPort`.
3. Every user-facing action is a registered `Command`, not a hard-wired menu
   target. Menus and keybindings are projections of the registry.
4. Settings keys keep Sublime's names where an equivalent exists. Unknown
   keys are ignored, never an error (forward compatibility for user files).
5. SyntaxKit emits semantic style names, never colors. Schemes map names to
   colors.

## Command palette is the extensibility seed

CommandKit's registry is the single catalog of actions. The palette
(Cmd+Shift+P) fuzzy-matches over `Command.title`; Cmd+P fuzzy-matches over
project file paths using the same FuzzyKit scorer. A future "my own command"
is a registration plus nothing.

## Build phases

Each phase is one clean coding session and ends runnable. Definition of done
travels with the phase; do not start N+1 with N red.

- **Phase 0 - Skeleton (DONE, this scaffold).** Package builds, tests green,
  `bundle-app.sh` produces a launchable window.
- **Phase 1 - Editor.** NSDocument app: rented editor view showing a real
  file, open/save, monospace + dark theme, line numbers, settings file read
  (font, tab_size). *Done when: edit and save a real file from the .app.*
  Includes: pick the rental (verify candidates' current state), add
  CFBundleDocumentTypes.
- **Phase 2 - Tabs + find.** Native tabbing on, find/replace bar, dirty-dot
  correctness, hot-exit autosave restore, reload-on-external-change.
  *Done when: three files in tabs, dirty state and restore correct.*
- **Phase 3 - Highlighting.** SyntaxKit tree-sitter engine, grammars for the
  initial language set (Swift, Python, Markdown, JSON), Mariana
  dark + Breakers light scheme files, `"theme": "auto"` OS-appearance switch.
  *Done when: a Swift and a Markdown file highlight while typing.*
- **Phase 4 - Palette + Cmd+P.** Palette panel over CommandRegistry; open
  folder as project; fuzzy file-open honoring exclude patterns from settings.
  *Done when: Cmd+P jumps between files by fragment.*
- **Phase 5 - Split panes.** NSSplitView tree of editor groups; the same
  document in two panes shares one buffer (falls out of invariant 1).
- **Phase 6 - Multi-cursor, then minimap (stretch).** Selections have modeled
  as a list since Phase 0; this phase teaches the view layer to render and
  edit N carets. If the rental cannot do it, this is where the rental is
  swapped, which is contained pain by design.

## Risks, named up front

- **Multi-cursor** is the whole reason for invariant 2. Expect the rental
  question to be re-opened here.
- **Minimap** has no good rental; it is custom drawing. Cut it guilt-free.
- **IME, emoji, RTL** (international text input) are silently handled by
  TextKit and silently broken in fully custom views. Another reason to rent.
- **Sublime's User preferences**: the settings vocabulary here was derived
  from Sublime's *default* preferences file; per-user
  `Packages/User/Preferences.sublime-settings` values are not folded in.

## Amendment 1 (2026-07-12): Agent surface

Adopted deliberately after a researched assessment (Zed/Cursor/VS Code
integration models, ACP, MCP app-as-server pattern). Everything above
STANDS: stack table, invariants 1-5, module layout, the rental. This
amendment is additive.

**Principle added:** the editor is a first-class surface for AI agents.
Agents already edit files on disk (reload-on-external-change is the shared
loop); this amendment lets them additionally SEE editor state (open buffers
including unsaved edits, selections) and ACT through the same command
catalog as the user. Editor plugins that expose buffer state over MCP exist
elsewhere; here the surface is built in, and the contract is stricter: the
agent sees exactly what the user sees, down to the unsaved keystroke, and
every agent edit is one undo step. The pure-data core makes this nearly
free.

**What changes (all additive):**

| Piece | What it is |
|---|---|
| `EditorCore/AgentProtocol.swift` | Wire types (JSON-per-line request/response), pure + tested |
| `QuoinApp/Agent/AgentServer.swift` | Unix-socket endpoint in the app (`~/Library/Application Support/Quoin/agent.sock`) |
| `QuoinMCP` executable target | stdio MCP shim over the socket, official `modelcontextprotocol/swift-sdk`; ships in the .app; the MCP dependency never links into the app itself |
| `quoin://open?file=&line=` + `Scripts/quoin` | Deep links and CLI opener, the location lingua franca of agent ecosystems |
| Conflict banner | Dirty buffer + external rewrite = titlebar banner (Reload / Keep), never silent |
| `agent_server` (true), `follow_agent_edits` (false) | Settings keys |

**Endpoint methods = MCP tools:** `list_open_documents`, `read_buffer`
(live text incl. unsaved), `get_selection`, `open_file(path, line)`,
`run_command(id)`, `list_commands`; write methods (added same day):
`replace_selection`, `apply_edit(anchor, head, text)`, `set_text`. Writes
land in the BUFFER as single undoable edits, left selected for visibility;
disk changes only when the user saves. The agent proposes, Cmd+S disposes.

**Invariant 6 (new):** the agent surface reads and acts only through the
same public seams as the UI (NSDocumentController, CommandRegistry,
EditorViewPort/SelectionSet). No privileged backdoor; a capability an agent
needs is a capability the UI gets too, or neither.

**Security posture:** local-only by construction. A unix socket is a
file-permission-protected channel on this machine; there is no network
listener, no auth token to leak. `agent_server: false` turns it off live.

**Deliberately NOT built (rationale recorded):** an ACP host (in-editor
agent panel with diff review, permission prompts, checkpoints). That is
Zed/Cursor's hardest product surface, there is no Swift ACP SDK, and the
terminal agent + this editor side-by-side already covers the workflow. If
this ever changes it is a new amendment, not a drift.
