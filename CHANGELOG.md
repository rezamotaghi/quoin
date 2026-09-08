# Changelog

All notable changes to Quoin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
`quoin_*` MCP verbs, the `quoin://` resources, and the prompts are part of
the public API: a breaking change to their names, parameters, or semantics
is a major version bump.

## [Unreleased]

## [1.1.0] - 2026-09-08

The agent-native release: the surface describes itself, pushes buffer
changes to the host, and refuses the commit-class commands; the menu grows
to Sublime's vocabulary, and every menu item is an agent verb.

### Added

- MCP verbs `quoin_read_lines` and `quoin_replace_lines`: line-addressed
  read and write (1-based, inclusive). The range covers the lines' content,
  so a replacement needs no trailing newline and the neighbors keep their
  lines. `quoin_read_buffer` gains `line_count`; `quoin_list_commands` gains
  `agent_runnable` per command.
- Every verb carries tool annotations (read-only or not; never destructive,
  every write being one undoable buffer edit) and an output schema, and
  answers with `structuredContent` as well as text.
- MCP resources: `quoin://documents`, `quoin://buffer` and
  `quoin://selection` (the front document), plus the templates
  `quoin://buffer{+path}` and `quoin://selection{+path}` for any open file.
  `resources/subscribe` on a buffer resource pushes
  `notifications/resources/updated` on every change (typing, agent edits,
  reloads), after the editor's own 150 ms debounce: the host is told, it
  does not poll.
- MCP prompts `proofread-selection`, `review-buffer` (argument `focus`), and
  `undo-tour`, the editing choreographies as slash commands.
- Distribution: `Scripts/make-mcpb.sh` builds `dist/quoin-<version>.mcpb`,
  a one-click MCP Bundle of the shim for Claude Desktop (Apple silicon), and
  `skills/quoin-editing/SKILL.md` teaches any host the verbs and the
  contract (Agent Skills format).
- Menus, now ten in Sublime's vocabulary: Edit > Line (Indent, Unindent,
  Swap Line Up/Down, Duplicate, Delete, Join), Comment > Toggle Comment
  (per-language token), Convert Case (Title, Upper, Lower, Swap), Sort Lines,
  Permute Lines (Reverse, Unique, Shuffle), Paste and Match Style, Delete,
  Spelling and Grammar, Substitutions, Speech; Selection > Split into Lines,
  Single Selection, Expand to Line/Word/Paragraph, Add Previous/Next Line,
  Invert; Find as its own menu; View > Word Wrap, Line Numbers, Whitespace,
  Syntax (per-document override), Indentation, Font, Theme; Goto > Goto Line,
  Scroll to Selection; File > Print; Quoin > Settings, Services, Hide Others,
  Show All; Help > Quoin on GitHub, Report an Issue, Release Notes. View
  toggles write the user's `settings.jsonc` in place, comments kept, and
  hot-reload as any edit would.
- An Agent menu: Agent Status, Copy MCP Setup Command, Agent Server and
  Follow Agent Edits switches, Undo Last Agent Edit, How to Connect an Agent.
  A title-bar chip counts the agent edits in a window from the first one on.
- `Scripts/mcp-smoke.py` walks the live surface over stdio the way a host
  does (208 checks with `--subscribe`, including the menu commands driven
  through `quoin_run_command`); it is the gate for the agent surface.

### Changed

- The commit fence: `quoin_run_command` refuses `file.save`, `file.saveAs`,
  `file.revert`, `file.close`, and `app.quit`, naming the rule in the error.
  A host that saved on the user's behalf must stop; the human saves.
- `quoin_open_file`'s `line` and `quoin_apply_edit`'s `anchor` and `head`
  accept integers as well as the strings 1.0 declared.
- Find moved from an Edit submenu to its own menu; command ids are unchanged.
- The shim reports version 1.1.0.

### Fixed

- Undo groups now close per agent edit. With the app idle in the background
  (an agent editing from a terminal, the usual case) AppKit never closed its
  automatic undo group, so any number of agent edits collapsed into one
  Cmd+Z. The document's undo manager no longer groups by event, and each
  agent edit opens and closes its own group: one edit, one undo step,
  whatever the app is doing.

## [1.0.0] - 2026-07-18

Initial public release.

### Added

- The editor: native macOS tabs, tree-sitter highlighting (Swift, Python,
  JSON, Markdown; JSONC via a dedicated lexer), Goto Anything (Cmd+P),
  command palette (Cmd+Shift+P), split panes, multi-cursor (Cmd+D,
  Ctrl+Cmd+G), find and replace, Markdown preview, hot exit, and
  reload-on-external-change with a conflict banner for dirty buffers.
- JSONC settings, hot-reloaded on save, keeping the key vocabulary
  documented in `Settings/default-settings.jsonc`, with two shipped color
  schemes (mariana dark, breakers light) and `"theme": "auto"`.
- The MCP agent surface: a local unix socket in the app plus the QuoinMCP
  stdio shim, exposing nine `quoin_*` verbs (list_open_documents,
  read_buffer, get_selection, open_file, list_commands, run_command,
  replace_selection, apply_edit, set_text). Every agent write is one
  undoable step; nothing reaches disk until the user saves. Off switch:
  `"agent_server": false`.
- `quoin://open?file=...&line=...` URL scheme and the `Scripts/quoin` CLI
  opener.
- `Scripts/bundle-app.sh` to produce `build/Quoin.app` from a pure SwiftPM
  build, with an optional `--install` flag; CI (build + 79 tests) on
  GitHub Actions.
- Documentation: README, QUICKSTART, ARCHITECTURE, AGENTS, CONTRIBUTING,
  SECURITY, code of conduct, issue and PR templates. MIT license.

[1.1.0]: https://github.com/rezamotaghi/quoin/releases/tag/v1.1.0
[1.0.0]: https://github.com/rezamotaghi/quoin/releases/tag/v1.0.0
