# Contributing to Quoin

Thanks for considering a contribution. Quoin is a small, deliberate codebase;
this page tells you how to build it, what a good change looks like, and which
parts of the surface are promises to other people's tooling.

## Build, test, bundle

Pure SwiftPM, macOS 14+, Command Line Tools are enough (no Xcode.app needed):

```bash
swift build              # compile everything
swift test               # 79 unit tests, must be green
Scripts/bundle-app.sh    # wrap the release binary into build/Quoin.app
```

`bundle-app.sh --install` additionally copies the fresh bundle to
`/Applications/Quoin.app`. It never does that without the flag.

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
Add tests in the same style next to the ones that already cover the module
you are touching.

## Code conventions

- **Match the surrounding code.** Read the file you are editing and write in
  its style; do not bring your own.
- **AppKit-native.** The shell is AppKit; SwiftUI appears only in panels.
  Prefer the platform's own mechanisms (NSDocument, undo managers, responder
  chain) over reimplementations.
- **No new dependencies without discussion.** Open an issue first. The
  dependency footprint is small on purpose, and the app itself must never
  link the MCP SDK (only the QuoinMCP shim does).
- **Respect the invariants.** ARCHITECTURE.md lists them; violations are
  bugs, not style points. The short form: EditorCore stays pure data, only
  `Sources/QuoinApp/EditorView/` names the rented text view's types, every
  user-facing action is a registered Command, settings keys keep the
  vocabulary of `Settings/default-settings.jsonc` (unknown keys are ignored,
  never an error), SyntaxKit emits style names rather than colors.
- **No em dashes in user-facing strings** (menu items, dialogs, error text).
  Use a colon, comma, or period.

## What makes a good pull request

- **Small.** One concern per PR. A fix and a refactor are two PRs.
- **Tested.** `swift test` green, with new tests for new behavior. For
  document plumbing (open, save, revert, quit-restore), exercise the running
  .app too; compiling is not proof.
- **Documented.** If behavior changed, update QUICKSTART.md or
  ARCHITECTURE.md in the same PR.

## Where design rationale lives

- **ARCHITECTURE.md**: the frozen decisions, the invariants, and the
  amendments that changed them. Read it before writing code.
- **AGENTS.md**: the working contract for coding sessions, environment
  constraints, and lessons learned the hard way. If your change contradicts
  either document, the change needs to argue with the document first.

## The agent surface is a public contract

The nine `quoin_*` MCP verbs (`quoin_list_open_documents`,
`quoin_read_buffer`, `quoin_get_selection`, `quoin_open_file`,
`quoin_list_commands`, `quoin_run_command`, `quoin_replace_selection`,
`quoin_apply_edit`, `quoin_set_text`) are what external agents are built
against. Treat them like a published API: names, parameters, and semantics
stay stable. A breaking change to any of them needs a strong reason, an
issue where it is agreed, and a major version bump. Additive verbs are fine;
silent behavior changes are not.

## Reporting bugs and proposing features

Use the issue forms; they ask for what we actually need to reproduce or
evaluate. Security problems go through private security advisories, not
public issues: see [SECURITY.md](SECURITY.md).
