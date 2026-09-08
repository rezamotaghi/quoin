#!/usr/bin/env python3
"""Walk the live MCP surface the way a host does and fail on the first wrong answer.

Spawns the QuoinMCP shim over stdio, initializes, and checks tools, resources,
prompts, and the commit fence against the running app. With --edit it also
opens a fresh Untitled buffer, edits it line-addressed, and undoes the edits
through the surface, leaving it empty and clean (closing is the human's).

    Scripts/mcp-smoke.py                 # read-only checks against the running app
    Scripts/mcp-smoke.py --edit          # plus the write and undo round trip
    Scripts/mcp-smoke.py --shim PATH     # a shim other than build/Quoin.app's

Exit status is non-zero on the first failure; the gate reads it.
"""
import argparse
import json
import os
import subprocess
import sys
import time

EXPECTED_TOOLS = {
    "quoin_list_open_documents", "quoin_read_buffer", "quoin_read_lines", "quoin_get_selection",
    "quoin_open_file", "quoin_replace_selection", "quoin_apply_edit", "quoin_replace_lines",
    "quoin_set_text", "quoin_run_command", "quoin_list_commands",
}
READ_ONLY_TOOLS = {"quoin_list_open_documents", "quoin_read_buffer", "quoin_read_lines", "quoin_get_selection", "quoin_list_commands"}
EXPECTED_PROMPTS = {"proofread-selection", "review-buffer", "undo-tour"}
COMMIT_CLASS = {"file.save", "file.saveAs", "file.revert", "file.close", "app.quit"}


class Shim:
    def __init__(self, path):
        self.proc = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.next_id = 1
        self.notifications = []

    def send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def request(self, method, params=None, timeout=10.0):
        rid = self.next_id
        self.next_id += 1
        msg = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            msg["params"] = params
        self.send(msg)
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                raise SystemExit(f"shim closed stdout while waiting for {method}")
            line = line.strip()
            if not line.startswith("{"):
                continue
            obj = json.loads(line)
            if obj.get("id") == rid:
                if "error" in obj:
                    return {"__error__": obj["error"]}
                return obj["result"]
            if "id" not in obj:
                self.notifications.append(obj)
        raise SystemExit(f"timeout waiting for {method}")

    def notify(self, method, params=None):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self.send(msg)

    def wait_notification(self, method, timeout=5.0):
        for n in self.notifications:
            if n.get("method") == method:
                return n
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line.startswith("{"):
                continue
            obj = json.loads(line)
            if "id" not in obj:
                self.notifications.append(obj)
                if obj.get("method") == method:
                    return obj
        return None

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


checks = 0


def check(condition, label):
    global checks
    checks += 1
    if condition:
        print(f"  ok  {label}")
    else:
        print(f"FAIL  {label}")
        raise SystemExit(1)


def call_tool(shim, name, arguments=None):
    return shim.request("tools/call", {"name": name, "arguments": arguments or {}})


def tool_text(result):
    return "".join(c.get("text", "") for c in result.get("content", []))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shim", default=os.path.join(os.path.dirname(__file__), "..", "build", "Quoin.app", "Contents", "MacOS", "QuoinMCP"))
    parser.add_argument("--edit", action="store_true", help="also run the write and undo round trip in a fresh Untitled buffer")
    parser.add_argument("--subscribe", action="store_true", help="also check buffer-change notifications (implies --edit)")
    parser.add_argument("--version", default=None, help="expected server version (e.g. from CITATION.cff)")
    args = parser.parse_args()
    if args.subscribe:
        args.edit = True

    shim = Shim(os.path.abspath(args.shim))
    try:
        init = shim.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                           "clientInfo": {"name": "mcp-smoke", "version": "1"}})
        check("serverInfo" in init, "initialize answers")
        if args.version:
            check(init["serverInfo"].get("version") == args.version, f"server version is {args.version}")
        caps = init.get("capabilities", {})
        check("resources" in caps and "prompts" in caps and "tools" in caps, "capabilities declare tools, resources, prompts")
        if args.subscribe:
            check(caps["resources"].get("subscribe") is True, "resources.subscribe is declared")
        shim.notify("notifications/initialized")

        tools = shim.request("tools/list")["tools"]
        names = {t["name"] for t in tools}
        check(names == EXPECTED_TOOLS, f"tools/list has exactly the {len(EXPECTED_TOOLS)} verbs")
        for t in tools:
            ann = t.get("annotations") or {}
            check("readOnlyHint" in ann and ann.get("openWorldHint") is False, f"{t['name']} carries annotations")
            check(ann["readOnlyHint"] == (t["name"] in READ_ONLY_TOOLS), f"{t['name']} read-only hint is right")
            if t["name"] not in READ_ONLY_TOOLS:
                check(ann.get("destructiveHint") is False, f"{t['name']} is declared non-destructive")
            check(t.get("outputSchema", {}).get("type") == "object", f"{t['name']} declares an output schema")

        resources = shim.request("resources/list")["resources"]
        uris = {r["uri"] for r in resources}
        check({"quoin://documents", "quoin://buffer", "quoin://selection"} <= uris, "resources/list has the three fixed resources")
        templates = shim.request("resources/templates/list")["resourceTemplates"]
        check({t["uriTemplate"] for t in templates} == {"quoin://buffer{+path}", "quoin://selection{+path}"}, "resource templates address buffers and selections by path")

        prompts = shim.request("prompts/list")["prompts"]
        check({p["name"] for p in prompts} == EXPECTED_PROMPTS, "prompts/list has the three choreographies")
        for name in sorted(EXPECTED_PROMPTS):
            got = shim.request("prompts/get", {"name": name, "arguments": {"focus": "grammar"} if name == "review-buffer" else {}})
            text = got["messages"][0]["content"]["text"]
            check(len(text) > 100 and "quoin_" in text, f"prompts/get {name} yields a choreography")
        bad = shim.request("prompts/get", {"name": "nope"})
        check("__error__" in bad, "unknown prompt is an error")

        docs = call_tool(shim, "quoin_list_open_documents")
        check(not docs.get("isError"), "quoin_list_open_documents answers (app is running)")
        check(isinstance(docs.get("structuredContent", {}).get("documents"), list), "structuredContent wraps the document list")
        read_docs = shim.request("resources/read", {"uri": "quoin://documents"})
        check(read_docs["contents"][0].get("mimeType") == "application/json", "resources/read quoin://documents is JSON")

        commands = call_tool(shim, "quoin_list_commands")
        listed = commands["structuredContent"]["commands"]
        ids = {c["id"] for c in listed}
        check(COMMIT_CLASS <= ids, "the commit-class commands exist in the catalog")
        for c in listed:
            check(c["agent_runnable"] == (c["id"] not in COMMIT_CLASS), f"{c['id']} agent_runnable flag is right")
        for cid in sorted(COMMIT_CLASS):
            refused = call_tool(shim, "quoin_run_command", {"id": cid})
            check(refused.get("isError") and "refused" in tool_text(refused), f"run_command {cid} is refused")
        unknown = call_tool(shim, "quoin_run_command", {"id": "no.such.command"})
        check(unknown.get("isError") and "unknown command" in tool_text(unknown), "unknown command id is an error")

        if args.edit:
            # A fresh Untitled buffer (file.new is agent-runnable) hosts the
            # round trip: nothing on disk, and two undos leave it empty and
            # clean, exactly what launching the app creates by itself.
            created = call_tool(shim, "quoin_run_command", {"id": "file.new"})
            check(not created.get("isError"), "file.new opens an Untitled buffer")
            time.sleep(0.5)
            front = [d for d in call_tool(shim, "quoin_list_open_documents")["structuredContent"]["documents"] if d["front"]]
            check(len(front) == 1 and front[0]["path"] is None and front[0]["dirty"] is False, "the new Untitled buffer is front, empty, and clean")
            original = "line one\nline two\nline three\nline four\nline five"
            seeded = call_tool(shim, "quoin_set_text", {"text": original})
            check(not seeded.get("isError"), "quoin_set_text seeds the buffer")
            window = call_tool(shim, "quoin_read_lines", {"from": 2, "to": 3})
            sc = window.get("structuredContent", {})
            check(sc.get("text") == "line two\nline three" and sc.get("total_lines") == 5, "quoin_read_lines reads a window with the line count")
            oob = call_tool(shim, "quoin_read_lines", {"from": 9, "to": 9})
            check(oob.get("isError") and "out of bounds" in tool_text(oob), "quoin_read_lines rejects a missing line")

            if args.subscribe:
                sub = shim.request("resources/subscribe", {"uri": "quoin://buffer"})
                check("__error__" not in sub, "resources/subscribe accepted")
                shim.notifications.clear()

            edited = call_tool(shim, "quoin_replace_lines", {"from": 2, "to": 3, "text": "TWO\nTHREE"})
            check(not edited.get("isError"), "quoin_replace_lines applies")
            buffer = call_tool(shim, "quoin_read_buffer")["structuredContent"]
            check(buffer["text"] == "line one\nTWO\nTHREE\nline four\nline five", "buffer shows the rewritten lines with neighbors intact")
            check(buffer["dirty"] is True and buffer["can_undo"] is True and buffer["path"] is None, "the edit is unsaved, undoable, and nothing is on disk")
            selection = call_tool(shim, "quoin_get_selection")["structuredContent"]
            check(selection["primary_text"] == "TWO\nTHREE", "the agent edit is left selected")
            if args.subscribe:
                note = shim.wait_notification("notifications/resources/updated", timeout=5.0)
                check(note is not None and note["params"]["uri"] == "quoin://buffer", "buffer change was pushed as resources/updated")
                shim.request("resources/unsubscribe", {"uri": "quoin://buffer"})

            undone = call_tool(shim, "quoin_run_command", {"id": "edit.undo"})
            check(not undone.get("isError"), "edit.undo runs over the surface")
            time.sleep(0.3)
            after = call_tool(shim, "quoin_read_buffer")["structuredContent"]
            check(after["text"] == original and after["dirty"] is True, "one undo peels off exactly the last agent edit")
            mirror = shim.request("resources/read", {"uri": "quoin://buffer"})
            check(mirror["contents"][0]["text"] == original and mirror["contents"][0]["mimeType"] == "text/plain", "resources/read mirrors the front buffer")
            missing = shim.request("resources/read", {"uri": "quoin://buffer/no/such/file.txt"})
            check("__error__" in missing, "resources/read of a document that is not open is an error")
            call_tool(shim, "quoin_run_command", {"id": "edit.undo"})
            time.sleep(0.3)
            clean = call_tool(shim, "quoin_read_buffer")["structuredContent"]
            check(clean["text"] == "" and clean["dirty"] is False, "the second undo leaves the Untitled buffer empty and clean")

            # The menu's line commands are agent-runnable too (invariants 3
            # and 6): each is one undo step, same as an agent edit.
            def run(command):
                result = call_tool(shim, "quoin_run_command", {"id": command})
                check(not result.get("isError"), f"run_command {command}")
                time.sleep(0.2)

            def buffer_text():
                return call_tool(shim, "quoin_read_buffer")["structuredContent"]["text"]

            seeded = call_tool(shim, "quoin_set_text", {"text": "b\na\nc"})
            check(not seeded.get("isError"), "quoin_set_text seeds lines for the command checks")
            run("edit.sortLines")
            check(buffer_text() == "a\nb\nc", "Edit > Sort Lines sorts the selected lines")
            run("edit.duplicateLine")
            check(buffer_text() == "a\nb\nc\na\nb\nc", "Edit > Line > Duplicate Line copies the block below itself")
            run("view.syntaxSwift")
            run("edit.toggleComment")
            check(buffer_text() == "a\nb\nc\n// a\n// b\n// c", "View > Syntax > Swift, then Toggle Comment comments the block")
            run("edit.toggleComment")
            check(buffer_text() == "a\nb\nc\na\nb\nc", "Toggle Comment again uncomments it")
            run("edit.reverseLines")
            check(buffer_text() == "a\nb\nc\nc\nb\na", "Edit > Permute Lines > Reverse reverses the block")
            for _ in range(6):
                run("edit.undo")
            final = call_tool(shim, "quoin_read_buffer")["structuredContent"]
            check(final["text"] == "" and final["dirty"] is False, "six undos peel six command edits back to an empty, clean buffer")
            print("  note  the empty Untitled tab stays open; closing is the human's.")
    finally:
        shim.close()
    print(f"PASS  {checks} checks")


if __name__ == "__main__":
    main()
