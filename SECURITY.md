# Security Policy

## Threat model, briefly

Quoin's agent surface is local-only by construction. The app listens on a
unix socket at `~/Library/Application Support/Quoin/agent.sock`, protected
by file permissions. There is no network listener, no port, and no auth
token to leak. The bundled QuoinMCP shim is a stdio process that talks to
that socket; it adds no remote reachability. The whole surface has an off
switch: `"agent_server": false` in settings, applied live.

The remaining attack surface is what runs on your machine as your user.
Any local process running as you can already read your files; Quoin does
not claim to defend against that, and neither does any editor.

## What counts as a vulnerability

Report anything that breaks the local-only, your-user-only posture:

- A way for a non-local process, or another user on the same machine, to
  reach the agent socket or influence buffer contents through it.
- The agent surface remaining reachable with `"agent_server": false` set.
- Sandbox or privilege escapes via the `quoin://` URL scheme, for example
  a crafted link that reads or writes something beyond opening a file at
  a line.
- Agent writes reaching disk without the user saving, or bypassing the
  undo stack.

Crashes without a security consequence are ordinary bugs; use the issue
forms for those.

## How to report

Use GitHub's private security advisories on this repository
(Security tab, "Report a vulnerability"). Do not open a public issue for
a security problem. You will get an acknowledgment, and a fix or an honest
assessment; this is a small project and there is no bounty program.
