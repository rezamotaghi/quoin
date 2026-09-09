---
name: quoin-editing
description: Edit the live buffer of the Quoin macOS editor through its MCP server for a human who keeps the only save button. Use when a user asks to proofread, rewrite, review, or inspect what they have open in Quoin, to change lines in it, or to run an editor command there. Every edit is one undo step; nothing reaches disk until the human saves.
license: MIT
compatibility: Any agent host with the quoin MCP server connected and Quoin.app running (QUICKSTART.md section 7).
metadata:
  author: Dr. Reza Motaghi
  version: "1.1.0"
---

# Editing in Quoin

Quoin is a macOS text editor whose buffers you can read and edit over MCP,
unsaved keystrokes included. The contract, in one line: you propose in the
buffer, the human disposes with Cmd+S.

## The contract (read this first)

- Every write you make lands in the buffer as ONE undo step, left selected so
  the human sees it. One Cmd+Z reverts it; two revert two. Never bundle a
  rewrite into many tiny edits when one `quoin_replace_lines` would do, and
  never split one logical change across calls if you can avoid it: the undo
  stack is the human's review tool.
- Nothing you do reaches disk. `file.save`, `file.saveAs`, `file.revert`,
  `file.close`, and `app.quit` are refused by `quoin_run_command`; do not
  ask for them, do not work around them. When you are done, tell the human
  what changed and that Cmd+S saves it, Cmd+Z reverts it.
- What you read is what they see: `quoin_read_buffer` and `quoin_read_lines`
  return the live text, which may differ from the file on disk. Read from
  Quoin, not from the file system, when the user talks about "what I have
  open".

## Before you start

Call `quoin_list_open_documents`: it tells you which document is front,
which are dirty, and their paths (null for an untitled buffer). Every other
verb takes an optional `path`; omit it for the front document. If a verb
answers "Quoin is not running", ask the human to launch Quoin (or to check
`agent_server` in its settings) and stop.

## The verbs

| Verb | Use it to |
|---|---|
| `quoin_list_open_documents` | See what is open, dirty, and front. |
| `quoin_read_buffer` | Read a whole live buffer (with `line_count`, `dirty`, `can_undo`). |
| `quoin_read_lines` | Read lines `from`..`to` (1-based, inclusive) plus `total_lines`. Prefer this on long files. |
| `quoin_get_selection` | Where the caret or selection is (UTF-16 offsets) and the selected text. |
| `quoin_open_file` | Open a file at a line, for the human. |
| `quoin_replace_selection` | Replace what the human selected (proofreading, rewording). |
| `quoin_replace_lines` | Rewrite lines `from`..`to` with `text`; the range covers the lines' content, so no trailing newline is needed and the neighbors keep their lines. |
| `quoin_apply_edit` | Replace an explicit UTF-16 range `anchor`..`head`. |
| `quoin_set_text` | Replace the whole buffer (a full rewrite the human will review). |
| `quoin_run_command` | Run an editor command by id (`edit.undo`, `edit.sortLines`, `view.syntaxSwift`, `view.toggleMarkdownPreview`, ...). |
| `quoin_list_commands` | The command catalog with `agent_runnable` per command. |

Line numbers are the gutter's: 1-based, and a file ending in a newline has
one more, empty, line. Offsets are UTF-16 code units, as `quoin_get_selection`
returns them.

## Resources and prompts

Hosts that attach context instead of calling tools can read
`quoin://documents`, `quoin://buffer` (front document), `quoin://selection`,
and `quoin://buffer/<absolute path>` or `quoin://selection/<absolute path>`
for any open file. A host may subscribe to a buffer
resource and is then told on every change; a subscription never polls.

Three prompts package the choreographies: `proofread-selection` (fix the
selection in place, one undo step), `review-buffer` (findings by line
number, nothing applied unless asked; argument `focus`), and `undo-tour`
(one small edit, then the human presses Cmd+Z and you confirm the buffer is
back).

## Choreographies

- **Proofread a passage.** `quoin_get_selection`; if empty, ask the human to
  select first. Correct only grammar, spelling, punctuation, clarity. One
  `quoin_replace_selection`. Report in two or three lines.
- **Rewrite a section.** `quoin_read_lines` around it to see the neighbors.
  One `quoin_replace_lines` covering exactly the lines that change. Say which
  lines changed.
- **Review.** Read the buffer (in windows if `line_count` is large). List
  findings with line numbers and a one-line fix each. Apply nothing unless
  asked; then one finding per call.
- **Tidy lines.** `quoin_run_command` with `edit.sortLines`,
  `edit.uniqueLines`, `edit.toggleComment`, `edit.joinLines` and friends acts
  on the human's current selection (or, for sorting with a bare caret, the
  whole buffer) as one undo step each. Set the syntax first with
  `view.syntaxSwift` (or Python, JSON, JSONC, Markdown, PlainText) when an
  untitled buffer needs a comment token.

## Do not

- Do not save, save as, revert, close, or quit; the verbs refuse and the human would
  not thank you for trying.
- Do not edit a file on disk that is open in Quoin: the editor will show a
  conflict banner if the buffer has unsaved edits. Edit the buffer instead.
- Do not describe an edit you did not make. After a write, the buffer is the
  truth; read it back if in doubt.
