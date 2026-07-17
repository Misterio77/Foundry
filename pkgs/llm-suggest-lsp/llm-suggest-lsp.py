#!/usr/bin/env python3
import json
import os
import pathlib
import queue
import sys
import threading
import time
import traceback
from urllib.parse import unquote, urlparse

STATE_DIR = pathlib.Path(os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state")) / "llm-suggest"
SUGGESTIONS_FILE = pathlib.Path(os.environ.get("LLM_SUGGEST_FILE", STATE_DIR / "suggestions.json"))

open_docs = set()
shutdown = False
last_payload = None
last_mtime = None
out_lock = threading.Lock()
requests = queue.Queue()


def log(message):
    print(f"llm-suggest-lsp: {message}", file=sys.stderr, flush=True)


def uri_to_path(uri):
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        return None
    return os.path.realpath(unquote(parsed.path))


def path_to_uri(path):
    return pathlib.Path(path).resolve().as_uri()


def read_suggestions():
    try:
        with SUGGESTIONS_FILE.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return []
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    return data


def normalize_range(item):
    start = item.get("range", {}).get("start", {})
    end = item.get("range", {}).get("end", {})
    start_line = int(start.get("line", 0))
    start_char = int(start.get("character", 0))
    end_line = int(end.get("line", start_line))
    end_char = int(end.get("character", start_char))

    if item.get("wholeLine") is True:
        return {
            "start": {"line": start_line, "character": 0},
            "end": {"line": max(start_line + 1, end_line), "character": 0},
        }

    # Treat 0:0 -> 0:0 as a whole-line edit. LLMs often use column 0 as
    # shorthand for "the line"; a literal zero-width LSP edit is rarely useful.
    if start_char == 0 and end_char == 0 and end_line <= start_line:
        return {
            "start": {"line": start_line, "character": 0},
            "end": {"line": start_line + 1, "character": 0},
        }

    return {
        "start": {"line": start_line, "character": start_char},
        "end": {"line": end_line, "character": end_char},
    }


def write_suggestions(items):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with SUGGESTIONS_FILE.open("w", encoding="utf-8") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)
        f.write("\n")


def clear_suggestion(suggestion_id):
    before = read_suggestions()
    after = [s for s in before if s.get("id") != suggestion_id]
    if len(after) != len(before):
        write_suggestions(after)
        for uri in list(open_docs):
            publish(uri)


def suggestions_for(path):
    real = os.path.realpath(path)
    return [s for s in read_suggestions() if os.path.realpath(str(s.get("file", ""))) == real]


def diagnostic_for(item):
    return {
        "range": normalize_range(item),
        "severity": int(item.get("severity", 3)),
        "source": "llm-suggest",
        "message": str(item.get("message", "LLM suggested edit")),
        "data": {"id": item.get("id")},
    }


def text_edits_for(item):
    edits = item.get("edits")
    if isinstance(edits, list):
        result = []
        for edit in edits:
            if not isinstance(edit, dict) or not isinstance(
                edit.get("replacement"), str
            ):
                continue
            result.append(
                {
                    "range": normalize_range(edit),
                    "newText": edit["replacement"],
                }
            )
        if result:
            return result

    replacement = item.get("replacement")
    if not isinstance(replacement, str):
        return []
    return [{"range": normalize_range(item), "newText": replacement}]


def publish(uri):
    path = uri_to_path(uri)
    if not path:
        return
    matches = suggestions_for(path)
    log(f"publishing {len(matches)} diagnostic(s) for {path}")
    diagnostics = [diagnostic_for(item) for item in matches]
    notify("textDocument/publishDiagnostics", {"uri": uri, "diagnostics": diagnostics})


def send(payload):
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    with out_lock:
        sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
        sys.stdout.buffer.write(body)
        sys.stdout.buffer.flush()


def respond(req_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": req_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    send(msg)


def notify(method, params):
    send({"jsonrpc": "2.0", "method": method, "params": params})


def position_key(position):
    return (int(position.get("line", 0)), int(position.get("character", 0)))


def request_matches_range(request_range, action_range):
    if not request_range:
        return True

    request_start = position_key(request_range.get("start", {}))
    request_end = position_key(request_range.get("end", {}))
    action_start = position_key(action_range.get("start", {}))
    action_end = position_key(action_range.get("end", {}))

    # Helix usually asks code actions for the cursor as an empty range. In that
    # case, return only actions whose diagnostic covers the cursor.
    if request_start == request_end:
        return action_start <= request_start < action_end

    return request_start < action_end and action_start < request_end


def context_diagnostic_ids(params):
    diagnostics = params.get("context", {}).get("diagnostics")
    if not diagnostics:
        return None
    ids = {diag.get("data", {}).get("id") for diag in diagnostics}
    ids.discard(None)
    return ids or None


def code_actions(params):
    uri = params.get("textDocument", {}).get("uri")
    path = uri_to_path(uri) if uri else None
    if not path:
        return []
    actions = []
    request_range = params.get("range")
    diagnostic_ids = context_diagnostic_ids(params)
    for item in suggestions_for(path):
        text_edits = text_edits_for(item)
        if not text_edits:
            continue
        if diagnostic_ids is not None and item.get("id") not in diagnostic_ids:
            continue
        item_range = normalize_range(item)
        if not request_matches_range(request_range, item_range):
            continue
        title = str(item.get("title") or item.get("message") or "Apply LLM suggested edit")
        action = {
            "title": f"LLM: {title}",
            "kind": "quickfix",
            "isPreferred": False,
            "diagnostics": [diagnostic_for(item)],
            "edit": {"changes": {uri: text_edits}},
        }
        if item.get("id") is not None:
            action["command"] = {
                "title": "Clear LLM suggestion",
                "command": "llm-suggest.clearSuggestion",
                "arguments": [item.get("id")],
            }
        actions.append(action)
    return actions


def handle(msg):
    global shutdown
    method = msg.get("method")
    req_id = msg.get("id")
    params = msg.get("params") or {}

    if method == "initialize":
        log("initialize")
        respond(req_id, {
            "capabilities": {
                "textDocumentSync": 1,
                "codeActionProvider": {"codeActionKinds": ["quickfix"]},
                "executeCommandProvider": {"commands": ["llm-suggest.clearSuggestion"]},
            },
            "serverInfo": {"name": "llm-suggest-lsp", "version": "0.1.0"},
        })
    elif method == "shutdown":
        shutdown = True
        respond(req_id, None)
    elif method == "textDocument/codeAction":
        respond(req_id, code_actions(params))
    elif method == "workspace/executeCommand":
        if params.get("command") == "llm-suggest.clearSuggestion":
            args = params.get("arguments") or []
            if args:
                clear_suggestion(args[0])
        respond(req_id, None)
    elif method == "textDocument/didOpen":
        uri = params.get("textDocument", {}).get("uri")
        if uri:
            log(f"didOpen {uri}")
            open_docs.add(uri)
            publish(uri)
    elif method == "textDocument/didChange":
        uri = params.get("textDocument", {}).get("uri")
        if uri:
            publish(uri)
    elif method == "textDocument/didClose":
        uri = params.get("textDocument", {}).get("uri")
        if uri:
            open_docs.discard(uri)
            notify("textDocument/publishDiagnostics", {"uri": uri, "diagnostics": []})
    elif method == "initialized":
        for uri in list(open_docs):
            publish(uri)
    elif req_id is not None:
        respond(req_id, None)


def reader():
    while True:
        headers = {}
        while True:
            line = sys.stdin.buffer.readline()
            if not line:
                requests.put(None)
                return
            if line in (b"\r\n", b"\n"):
                break
            name, _, value = line.decode("ascii", "replace").partition(":")
            headers[name.lower()] = value.strip()
        length = int(headers.get("content-length", "0"))
        body = sys.stdin.buffer.read(length)
        try:
            requests.put(json.loads(body.decode("utf-8")))
        except Exception:
            pass


def poller():
    global last_mtime, last_payload
    while not shutdown:
        try:
            stat = SUGGESTIONS_FILE.stat()
            payload = stat.st_mtime_ns
        except FileNotFoundError:
            payload = None
        if payload != last_mtime:
            last_mtime = payload
            for uri in list(open_docs):
                publish(uri)
        time.sleep(1)


threading.Thread(target=reader, daemon=True).start()
threading.Thread(target=poller, daemon=True).start()

while True:
    msg = requests.get()
    if msg is None:
        break
    try:
        if msg.get("method") == "exit":
            break
        handle(msg)
    except Exception:
        traceback.print_exc(file=sys.stderr)
