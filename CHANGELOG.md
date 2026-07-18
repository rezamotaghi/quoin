# Changelog

All notable changes to Quoin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
nine `quoin_*` MCP verbs are part of the public API: a breaking change to
their names, parameters, or semantics is a major version bump.

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

[1.0.0]: https://github.com/rezamotaghi/quoin/releases/tag/v1.0.0
