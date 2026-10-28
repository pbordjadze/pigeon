#!/usr/bin/env python3
"""Exploratory QA through Maestro's MCP server (`maestro mcp`): the steps of
.github/workflows/qa-explore.yml on the macOS runner, and `send`, with which an agent elsewhere
drives that runner's simulator.

On the runner:
  qa.py probe <out> --udid <udid>
      Starts `maestro mcp`, lists its tools and calls list_devices, take_screenshot and
      inspect_screen on the simulator, writing what came back to <out> (the screenshot as an
      agent gets it). Fails unless the device is listed, a real screenshot came back and the
      screen's elements did, in one of two attempts: the check that runs before any model is used.
  qa.py relay <out> --udid <udid> --run <id> --branch <b> --publish <dir> --minutes <m> --log <file>
      Runs the calls an agent elsewhere commits under cmd/<id>/ on branch <b> (`send`), in order,
      writes each result to <out> and publishes <dir> after each to refs/qa-runs/<id>. Ends
      after <m> minutes, after 10 minutes without a call, or at an `_end` call.
  qa.py transcript <stream.jsonl> <out>
      Claude Code's stream-json output as transcript.md, every image a tool gave the agent saved
      beside it (shots/), and summary.json (turns, cost, tool calls, images received).
  qa.py publish <dir> <ref> [<message>]
      Commits <dir>, screen recordings and the raw transcript left out, and force-pushes it to
      <ref> of the checkout's origin, authenticated with $QA_PUSH_TOKEN when it is set.
  qa.py scrub <dir> <VAR>...
      Replaces the value of each named environment variable in every text file under <dir>.

In a clone anywhere (a Claude Code cloud session has no Mac):
  qa.py send <run-id> <calls.json | -> [--branch claude/qa-relay] [--out <dir>] [--wait <s>]
      Commits the calls, a JSON list of {"tool": ..., "arguments": {...}} (or one such object),
      to the relay branch with [skip ci], so no workflow runs on it; waits for the runner's
      result in refs/qa-runs/<run-id>, extracts it to --out (default qa-relay-<run-id>) and prints
      the text results and the images' paths. The first result (relay/hello.json, with a
      screenshot) is waiting before any call: `send <run-id>` fetches it; `--result <n>` fetches
      call n's result again (after a --wait ran out) without sending anything.

A call is one of Maestro's local tools (list_devices, take_screenshot, inspect_screen, run,
cheat_sheet; device_id is filled in), `_log` (the app log's last `lines`, default 60) or `_end`.
Maestro Cloud's tools and the viewer are refused.
"""
import argparse
import base64
import json
import os
import queue
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

LOCAL_TOOLS = {"list_devices", "take_screenshot", "inspect_screen", "run", "cheat_sheet"}
# Never handed to `maestro mcp`, whose flows can read the environment.
SECRETS = ("QA_PUSH_TOKEN", "GITHUB_TOKEN", "GH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN")
POLL = 3
IDLE_MINUTES = 10


class Maestro:
    """`maestro mcp` over stdio, newline-delimited JSON-RPC."""

    def __init__(self, log_path, udid):
        self.udid = udid
        self.log = open(log_path, "a", buffering=1)
        env = {k: v for k, v in os.environ.items() if k not in SECRETS}
        cmd = [os.environ.get("MAESTRO", "maestro"), "mcp", "--no-viewer"]
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log,
                                     text=True, bufsize=1, env=env)
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.next_id = 0
        self.server = self.request("initialize", {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "qa-explore", "version": "1"}}, 180)
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.tools = self.request("tools/list", {}, 60).get("tools", [])
        self.schemas = {t["name"]: t.get("inputSchema", {}) for t in self.tools}

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def _send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def request(self, method, params, timeout):
        self.next_id += 1
        wanted = self.next_id
        self._send({"jsonrpc": "2.0", "id": wanted, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while True:
            try:
                line = self.lines.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty:
                raise TimeoutError(f"{method}: no answer in {timeout} s") from None
            if line is None:
                raise RuntimeError(f"maestro mcp exited ({self.proc.poll()}) during {method}")
            try:
                message = json.loads(line)
            except ValueError:
                self.log.write("stdout: " + line)
                continue
            if "method" in message and "id" in message:
                # A request from the server: only ping is expected (no capabilities were offered).
                reply = {"result": {}} if message["method"] == "ping" else \
                    {"error": {"code": -32601, "message": "not supported"}}
                self._send({"jsonrpc": "2.0", "id": message["id"], **reply})
                continue
            if message.get("id") != wanted:
                self.log.write("message: " + line)
                continue
            if "error" in message:
                raise RuntimeError(f"{method}: {message['error']}")
            return message.get("result", {})

    def call(self, tool, arguments, timeout=600):
        arguments = dict(arguments or {})
        if "device_id" in self.schemas.get(tool, {}).get("properties", {}):
            arguments.setdefault("device_id", self.udid)
        return self.request("tools/call", {"name": tool, "arguments": arguments}, timeout)

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=20)
        except Exception:
            self.proc.kill()


def image_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker == 0x01 or 0xD0 <= marker <= 0xD8 or marker == 0xFF:
                i += 1 if marker == 0xFF else 2
                continue
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack(">HH", data[i + 5:i + 9])
                return width, height
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    return None, None


def record(result, out, stem, tool, arguments, seconds):
    """One tool result as JSON beside its images, named <stem>.json and <stem>-<n>.<ext>."""
    texts, images = [], []
    for n, block in enumerate(result.get("content", []), 1):
        if block.get("type") == "image":
            data = base64.b64decode(block.get("data", ""))
            ext = {"image/jpeg": "jpg", "image/png": "png"}.get(block.get("mimeType"), "bin")
            name = f"{stem}-{n}.{ext}"
            (out / name).write_bytes(data)
            width, height = image_size(data)
            images.append({"file": name, "mimeType": block.get("mimeType"), "bytes": len(data),
                           "width": width, "height": height})
        elif block.get("type") == "text":
            texts.append(block.get("text", ""))
        else:
            texts.append(json.dumps(block))
    entry = {"tool": tool, "arguments": arguments, "seconds": round(seconds, 1),
             "isError": bool(result.get("isError")), "text": texts, "images": images}
    (out / f"{stem}.json").write_text(json.dumps(entry, indent=1))
    return entry


def timed_call(maestro, out, stem, tool, arguments, app_log=None):
    started = time.monotonic()
    try:
        if tool == "_log":
            lines = Path(app_log).read_text(errors="replace").splitlines() if app_log else []
            count = max(1, int((arguments or {}).get("lines", 60)))
            result = {"content": [{"type": "text", "text": "\n".join(lines[-count:])}]}
        elif tool not in LOCAL_TOOLS:
            result = {"isError": True, "content": [{"type": "text", "text": f"refused: {tool} is not a local tool"}]}
        else:
            result = maestro.call(tool, arguments)
    except Exception as error:  # a timeout or a dead server is a result too: the agent sees it
        result = {"isError": True, "content": [{"type": "text", "text": f"{type(error).__name__}: {error}"}]}
    return record(result, out, stem, tool, arguments, time.monotonic() - started)


def summary_line(entry):
    first = (entry["text"][0] if entry["text"] else "").replace("\n", " ")
    images = ", ".join(f"{i['file']} {i['width']}x{i['height']} {i['bytes'] // 1024} KiB" for i in entry["images"])
    state = "ERROR" if entry["isError"] else "ok"
    return f"{entry['tool']}: {state} in {entry['seconds']} s; {images or 'no image'}; {first[:160]}"


def probe(args):
    """Up to two attempts: Maestro's driver sometimes starts broken on a busy runner."""
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    lines, passed = [], False
    for attempt in (1, 2):
        try:
            maestro = Maestro(out / "maestro.log", args.udid)
        except Exception as error:
            lines.append(f"attempt {attempt}: maestro mcp didn't start: {error}")
            continue
        (out / "server.json").write_text(json.dumps(maestro.server, indent=1))
        (out / "tools.json").write_text(json.dumps(maestro.tools, indent=1))
        info = maestro.server.get("serverInfo", {})
        lines += [f"attempt {attempt}: server {info.get('name')} {info.get('version')}, protocol "
                  f"{maestro.server.get('protocolVersion')}; tools: " + ", ".join(t["name"] for t in maestro.tools)]
        entries = {}
        for n, tool in enumerate(("list_devices", "take_screenshot", "inspect_screen"), 1):
            entries[tool] = timed_call(maestro, out, f"{attempt}-{n}-{tool}", tool, {})
            lines.append(summary_line(entries[tool]))
        maestro.close()
        shot = entries["take_screenshot"]
        checks = {
            "the simulator is listed": args.udid.lower() in " ".join(entries["list_devices"]["text"]).lower(),
            # A 1x1 image is what a driver that never reached the screen returns.
            "a screenshot came back as an image": not shot["isError"] and any(
                (i["width"] or 0) >= 100 and (i["height"] or 0) >= 100 for i in shot["images"]),
            "the screen's elements came back": not entries["inspect_screen"]["isError"]
                and any(t.strip() for t in entries["inspect_screen"]["text"]),
        }
        lines += [f"{'PASS' if ok else 'FAIL'}: {name}" for name, ok in checks.items()]
        if all(checks.values()):
            passed = True
            break
    lines.append(f"{'passed' if passed else 'failed'} in {round(time.monotonic() - started)} s")
    (out / "summary.md").write_text("# Probe\n\n" + "\n".join(f"- {line}" for line in lines) + "\n")
    print("\n".join(lines))
    return 0 if passed else 1


def git(*args, check=True, auth=False, cwd=None, data=None):
    prefix = ["git"]
    token = os.environ.get("QA_PUSH_TOKEN")
    if auth and token:
        basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        prefix += ["-c", f"http.https://github.com/.extraheader=AUTHORIZATION: basic {basic}"]
    result = subprocess.run(prefix + list(args), cwd=cwd, input=data, capture_output=True,
                            text=data is None or isinstance(data, str))
    if check and result.returncode != 0:
        raise RuntimeError(f"git {args[0]} failed: {result.stderr.strip()[-400:]}")
    return result.stdout


def publish_dir(src, ref, message):
    """Pushes to the checkout's origin, as the token's owner when $QA_PUSH_TOKEN is set."""
    url = git("remote", "get-url", "origin").strip()
    gitdir = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / "qa-publish.git"
    if not gitdir.exists():
        git(f"--git-dir={gitdir}", "init", "-q")
        (gitdir / "info").mkdir(exist_ok=True)
        (gitdir / "info" / "exclude").write_text("*.mp4\n*.mov\ntranscript.jsonl\n")
    g = [f"--git-dir={gitdir}", f"--work-tree={src}"]
    git(*g, "add", "-A")
    git(*g, "-c", "user.name=qa", "-c", "user.email=qa@users.noreply.github.com",
        "commit", "-q", "--allow-empty", "-m", message)
    git(*g, "push", "-q", "-f", url, f"HEAD:{ref}", auth=True)


def publish(args):
    publish_dir(Path(args.dir), args.ref, args.message)
    return 0


def relay(args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    deadline = started + args.minutes * 60
    maestro = Maestro(out / "maestro.log", args.udid)
    hello = timed_call(maestro, out, "hello", "take_screenshot", {})
    hello.update(tools=maestro.tools, udid=args.udid, run=args.run, branch=args.branch)
    (out / "hello.json").write_text(json.dumps(hello, indent=1))
    publish_dir(args.publish, f"refs/qa-runs/{args.run}", "relay ready")
    print(f"relay ready: {summary_line(hello)}", flush=True)
    done, seen, ended = 0, None, False
    idle_until = time.monotonic() + IDLE_MINUTES * 60
    branch_ref = f"refs/heads/{args.branch}"
    while not ended and time.monotonic() < min(deadline, idle_until):
        try:
            tip = git("ls-remote", "origin", branch_ref, auth=True).split()
            if not tip or tip[0] == seen:
                time.sleep(POLL)
                continue
            git("fetch", "-q", "origin", f"+{branch_ref}:refs/qa-relay/cmd", auth=True)
            seen = tip[0]
        except RuntimeError as error:  # GitHub having a bad moment: poll again
            print(f"relay: {error}", flush=True)
            time.sleep(POLL)
            continue
        names = git("ls-tree", "--name-only", f"refs/qa-relay/cmd:cmd/{args.run}", check=False).split()
        for name in sorted(n for n in names if n.split(".")[0].isdigit()):
            n = int(name.split(".")[0])
            if n <= done:
                continue
            try:
                calls = json.loads(git("show", f"refs/qa-relay/cmd:cmd/{args.run}/{name}"))
                calls = [calls] if isinstance(calls, dict) else calls
            except ValueError as error:
                calls = [{"tool": "_invalid", "arguments": {"error": str(error)}}]
            results = []
            for k, call in enumerate(calls if isinstance(calls, list) else [calls], 1):
                if not isinstance(call, dict):
                    call = {"tool": "_invalid", "arguments": {"call": call}}
                if call.get("tool") == "_end" or time.monotonic() >= deadline:
                    ended = call.get("tool") == "_end"
                    break
                entry = timed_call(maestro, out, f"{n:04}-{k}", call.get("tool"), call.get("arguments"), args.log)
                results.append(entry)
                print(f"{n}.{k} {summary_line(entry)}", flush=True)
            (out / f"{n:04}.json").write_text(json.dumps({"n": n, "results": results, "ended": ended}, indent=1))
            done = n
            if ended or time.monotonic() >= deadline:
                break
        try:
            publish_dir(args.publish, f"refs/qa-runs/{args.run}", f"relay call {done}")
        except RuntimeError as error:  # the next call's publish carries this one too
            print(f"relay: {error}", flush=True)
        idle_until = time.monotonic() + IDLE_MINUTES * 60
    maestro.close()
    reason = "ended by the agent" if ended else "out of time" if time.monotonic() >= deadline else "idle"
    print(f"relay stopped after {done} call(s), {round((time.monotonic() - started) / 60, 1)} min: {reason}")
    return 0


def send(args):
    text = sys.stdin.read() if args.calls == "-" else args.calls
    calls = [] if args.result else json.loads(text if text.lstrip()[:1] in "[{" else Path(text).read_text())
    calls = [calls] if isinstance(calls, dict) else calls
    out = Path(args.out or f"qa-relay-{args.run}")
    out.mkdir(parents=True, exist_ok=True)
    ref = f"refs/qa-runs/{args.run}"
    if args.result:
        wanted = f"relay/{args.result:04}.json"
    elif calls:
        branch_ref = f"refs/heads/{args.branch}"
        tip = git("ls-remote", "origin", branch_ref).split()
        entries = []
        if tip:
            git("fetch", "-q", "origin", f"+{branch_ref}:refs/qa-relay/cmd")
            listing = git("ls-tree", f"refs/qa-relay/cmd:cmd/{args.run}", check=False)
            entries = [line for line in listing.splitlines() if line.strip()]
        n = 1 + max([int(line.split("\t")[1].split(".")[0]) for line in entries] or [0])
        blob = git("hash-object", "-w", "--stdin", data=json.dumps(calls, indent=1)).strip()
        entries.append(f"100644 blob {blob}\t{n:04}.json")
        run_tree = git("mktree", data="\n".join(entries) + "\n").strip()
        others = [line for line in git("ls-tree", "refs/qa-relay/cmd:cmd", check=False).splitlines()
                  if tip and line.strip() and not line.endswith(f"\t{args.run}")]
        cmd_tree = git("mktree", data="\n".join(others + [f"040000 tree {run_tree}\t{args.run}"]) + "\n").strip()
        root = git("mktree", data=f"040000 tree {cmd_tree}\tcmd\n").strip()
        parent = ["-p", tip[0]] if tip else []
        commit = git("-c", "user.name=qa", "-c", "user.email=qa@users.noreply.github.com", "commit-tree", root,
                     *parent, "-m", f"QA relay {args.run}: call {n} [skip ci]").strip()
        git("push", "-q", "origin", f"{commit}:{branch_ref}")
        wanted = f"relay/{n:04}.json"
    else:
        wanted = "relay/hello.json"
    deadline = time.monotonic() + args.wait
    while True:
        git("fetch", "-q", "origin", f"+{ref}:{ref}", check=False)
        if subprocess.run(["git", "cat-file", "-e", f"{ref}:{wanted}"], capture_output=True).returncode == 0:
            break
        status = subprocess.run(["git", "show", f"{ref}:STATUS.md"], capture_output=True, text=True)
        if status.returncode == 0:
            print(f"the run has ended without {wanted}:\n{status.stdout}", file=sys.stderr)
            return 2
        if time.monotonic() > deadline:
            print(f"no {wanted} in {ref} after {args.wait} s", file=sys.stderr)
            return 1
        time.sleep(POLL)
    stem = wanted[:-len(".json")]
    files = [f for f in git("ls-tree", "-r", "--name-only", ref, "relay/").split() if f.startswith(stem)]
    for f in files:
        target = out / Path(f).name
        target.write_bytes(subprocess.run(["git", "show", f"{ref}:{f}"], capture_output=True, check=True).stdout)
    result = json.loads((out / Path(wanted).name).read_text())
    for entry in result.get("results", [result]):
        print(f"== {entry['tool']} {json.dumps(entry.get('arguments'))[:300]}")
        print(f"   {'ERROR' if entry['isError'] else 'ok'} in {entry['seconds']} s")
        for text in entry["text"]:
            print("   " + text[:args.chars].replace("\n", "\n   ") + (" …" if len(text) > args.chars else ""))
        for image in entry["images"]:
            print(f"   image: {out / image['file']} ({image['width']}x{image['height']}, {image['bytes'] // 1024} KiB)")
    return 0


def transcript(args):
    out = Path(args.out)
    (out / "shots").mkdir(parents=True, exist_ok=True)
    lines, calls, images, summary = [], {}, 0, {}
    names = {}
    for raw in Path(args.stream).read_text(errors="replace").splitlines():
        try:
            event = json.loads(raw)
        except ValueError:
            continue
        kind = event.get("type")
        if kind == "system" and event.get("subtype") == "init":
            summary["model"] = event.get("model")
            summary["mcp_servers"] = event.get("mcp_servers")
            summary["tools"] = event.get("tools")
            lines.append(f"**Start**: model {event.get('model')}, MCP {json.dumps(event.get('mcp_servers'))}\n")
        elif kind == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "text" and block.get("text", "").strip():
                    lines.append("> " + block["text"].strip().replace("\n", "\n> ") + "\n")
                elif block.get("type") == "tool_use":
                    names[block.get("id")] = block.get("name")
                    calls[block.get("name")] = calls.get(block.get("name"), 0) + 1
                    lines.append(f"→ `{block.get('name')}` `{json.dumps(block.get('input'))[:600]}`\n")
        elif kind == "user":
            content = event.get("message", {}).get("content", [])
            for block in content if isinstance(content, list) else []:
                if block.get("type") != "tool_result":
                    continue
                parts = block.get("content")
                parts = [{"type": "text", "text": parts}] if isinstance(parts, str) else parts or []
                flag = " (error)" if block.get("is_error") else ""
                for part in parts:
                    if part.get("type") == "image":
                        images += 1
                        source = part.get("source", {})
                        ext = "png" if "png" in source.get("media_type", "") else "jpg"
                        name = f"shots/{images:03}.{ext}"
                        data = base64.b64decode(source.get("data", ""))
                        (out / name).write_bytes(data)
                        width, height = image_size(data)
                        lines.append(f"← {names.get(block.get('tool_use_id'))}{flag}: image ![{images}]({name}) {width}x{height}\n")
                    elif part.get("type") == "text":
                        text = part.get("text", "").strip()
                        lines.append(f"← {names.get(block.get('tool_use_id'))}{flag}: {text[:400]}{' …' if len(text) > 400 else ''}\n")
        elif kind == "result":
            for key in ("subtype", "is_error", "num_turns", "duration_ms", "total_cost_usd", "result", "usage"):
                summary[key] = event.get(key)
    summary.update(tool_calls=calls, images_received=images)
    head = ["# Agent transcript\n", f"- end: {summary.get('subtype')}, {summary.get('num_turns')} turns, "
            f"{round((summary.get('duration_ms') or 0) / 60000, 1)} min, estimated ${summary.get('total_cost_usd')}",
            f"- tool calls: {json.dumps(calls)}", f"- images the agent received: {images}\n"]
    (out / "transcript.md").write_text("\n".join(head + lines))
    (out / "summary.json").write_text(json.dumps(summary, indent=1))
    print("\n".join(head))
    return 0


def scrub(args):
    for name in args.names:
        value = os.environ.get(name, "")
        if len(value) < 8:
            continue
        count = 0
        for path in Path(args.dir).rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            try:
                text = path.read_text()
            except (UnicodeDecodeError, OSError):
                continue
            if value in text:
                path.write_text(text.replace(value, f"[{name} redacted]"))
                count += 1
        print(f"{name}: {'redacted in ' + str(count) + ' file(s)' if count else 'not found'}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("probe")
    p.add_argument("out")
    p.add_argument("--udid", required=True)
    p.set_defaults(func=probe)
    p = sub.add_parser("relay")
    p.add_argument("out")
    p.add_argument("--udid", required=True)
    p.add_argument("--run", required=True)
    p.add_argument("--branch", required=True)
    p.add_argument("--publish", required=True)
    p.add_argument("--minutes", type=float, default=15)
    p.add_argument("--log")
    p.set_defaults(func=relay)
    p = sub.add_parser("send")
    p.add_argument("run")
    p.add_argument("calls", nargs="?", default="[]")
    p.add_argument("--result", type=int, help="fetch the result of call N again instead of sending")
    p.add_argument("--branch", default="claude/qa-relay")
    p.add_argument("--out")
    p.add_argument("--wait", type=float, default=300)
    p.add_argument("--chars", type=int, default=1500)
    p.set_defaults(func=send)
    p = sub.add_parser("transcript")
    p.add_argument("stream")
    p.add_argument("out")
    p.set_defaults(func=transcript)
    p = sub.add_parser("publish")
    p.add_argument("dir")
    p.add_argument("ref")
    p.add_argument("message", nargs="?", default="QA report")
    p.set_defaults(func=publish)
    p = sub.add_parser("scrub")
    p.add_argument("dir")
    p.add_argument("names", nargs="+")
    p.set_defaults(func=scrub)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
