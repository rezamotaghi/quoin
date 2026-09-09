# AGENTS.md

Instructions for AI coding agents working in this repo. Quoin is itself an
agent-native editor, so this repo treats its agent contributors as
first-class too: read this file and ARCHITECTURE.md before writing code.

## How to work here

- **The architecture is decided.** ARCHITECTURE.md's stack table and
  invariants are frozen; implement within them. Changing one is a deliberate,
  stated decision ("what stands / what changes"), never a silent drive-by or
  a from-scratch reframe.
- **Verify with this repo's gates before claiming done:**
  ```bash
  swift build && swift test        # must be green
  Scripts/bundle-app.sh            # must produce build/Quoin.app; also
                                   # refreshes /Applications/Quoin.app when
                                   # one is installed (never leave the
                                   # installed copy behind the repo)
  open build/Quoin.app             # for changes to visible behavior
  Scripts/mcp-smoke.py --subscribe # the agent surface, walked live over
                                   # stdio against the running fresh bundle;
                                   # stops on the first wrong answer
  ```
- **"It compiles and tests pass" is not "done" for document plumbing.** Save,
  open, revert, and quit-restore must be exercised in the running .app before
  claiming completion.
- **The MCP contract is public API.** The eleven `quoin_*` tools, the
  `quoin://` resources, the prompts, and the commit fence
  (`AgentPolicy.commitClassCommands`) follow semver; see CONTRIBUTING.md
  before touching them.
- **Every menu item is a Command and therefore an agent verb** (invariants
  3 and 6): adding a menu item widens `quoin_run_command`. AppKit adds its
  own items at runtime (Open Recent, Close All, Enter Full Screen, the tab
  bar items, Dictation, Emoji, Writing Tools); do not declare those in
  `MainMenu`, and dump the live menus with System Events when in doubt.
- **No em dashes in any user-facing string or doc** (menu items, palette
  titles, dialogs, error text). Use a colon, comma, or period.

## Cutting a release

A version bump is a short checklist, all in the same commit:

1. `CITATION.cff` `version:` and `date-released:` (the day the release can first
   exist);
2. `Resources/Info.plist` `CFBundleShortVersionString` and `CFBundleVersion`,
   both the same string (when they differ, the About panel shows the build
   number in parentheses; Reza wants one number);
3. `Sources/QuoinMCP/main.swift`, the `Server(... version:)` string;
4. `CHANGELOG.md`: a dated section plus its tag link at the bottom.

`mcpb/manifest.json` needs no bump: `Scripts/make-mcpb.sh` stamps the
CITATION.cff version into the staged copy. `skills/quoin-editing/SKILL.md`
carries the version in its metadata; keep it in step.

Then tag, publish the GitHub release with `dist/quoin-<version>.mcpb`
attached (`Scripts/make-mcpb.sh` builds it), and in the same sitting update
the downstream surfaces per the Vault page's release ritual. A release is not
done until they read it.

## Environment constraints (why the build is SwiftPM-only)

The build assumes the Swift toolchain from Command Line Tools alone, with
**no Xcode.app** (`xcodebuild` may not exist). Therefore: pure SwiftPM, and
`Scripts/bundle-app.sh` wraps the release binary into `Quoin.app` with
`Resources/Info.plist`. Do not introduce an .xcodeproj or any tool that
requires Xcode. Tests use **Swift Testing** (`import Testing`, `@Test`,
`#expect`), NOT XCTest: XCTest ships with Xcode.app and cannot be assumed.

## Learned the hard way (do not reintroduce)

- **Never `MainActor.assumeIsolated` in NSDocument class-level getters.**
  AppKit calls `autosavesInPlace` (and may call other class properties) from
  BACKGROUND queues during save preservation; `assumeIsolated` off-main is a
  deliberate crash (SIGTRAP), verified by crash logs. Settings values needed
  off-main go through a lock-guarded mirror: see
  `SettingsStore.hotExitMirror`. Instance methods like `read(from:)` are
  main-thread only while `canConcurrentlyReadDocuments` stays false.
- **Agent writes bypass the rented view's undo registration on purpose.**
  `TextDocument.replaceTextUndoable` captures the exact old text, swaps with
  the view's own undo registration disabled, and registers its own inverse on
  the document undo manager. The rented view's undo corrupted full-buffer
  replaces and did not propagate dirty state for programmatic edits; do not
  "simplify" back to it.
- **Hot exit restores stale dirty buffers during scripted tests.** Rewriting
  an open file on disk mid-test contaminates offsets; quit clean or set
  `hot_exit: false` when scripting edit tests.
- **Never let the document's undo manager group by event.** AppKit closes
  its automatic undo group only when an event finishes; with the app idle
  in the background (an agent editing from a terminal) no event ever does,
  and every agent edit landed in one still-open group: three edits, one
  Cmd+Z, empty buffer (verified over the socket 2026-09-08). `TextDocument`
  sets `groupsByEvent = false` and every registration opens and closes its
  own group; the rented view already did. The smoke test pins it.
- **AppKit hides a Save All item under autosave-in-place** (as it does in
  TextEdit); a `saveAllDocuments:` item registers a command nobody can see.
  None is declared.
- **The smoke test leaves an empty Untitled tab behind on purpose.** Closing
  is a commit-class command the fence refuses, so the scratch buffer is an
  Untitled one that two undos leave empty and clean.

## Invariants (short form; full list and rationale in ARCHITECTURE.md)

1. `Sources/EditorCore/` never imports AppKit or SwiftUI.
2. Only `Sources/QuoinApp/EditorView/` may name the rented text view's
   concrete types; everyone else talks to `EditorViewPort`.
3. Every user-facing action is a registered `Command` (CommandKit).
4. Settings = JSONC, Sublime key names, unknown keys ignored.
5. SyntaxKit emits semantic style names, never colors.
6. The agent surface reads and acts only through the same public seams as
   the UI. No privileged backdoor: a capability an agent needs is a
   capability the UI gets too, or neither. The one asymmetry runs the other
   way and is deliberate: commit rights (save, save as, revert, close, quit)
   are the human's alone; `AgentPolicy` refuses them (Amendment 2).
