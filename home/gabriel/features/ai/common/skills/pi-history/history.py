"""Read-only, bounded views of Pi v2/v3 JSONL archives."""

import argparse
import json
import os
import sys
from collections import deque
from pathlib import Path


def records(path):
    with path.open(encoding="utf-8") as src:
        for number, line in enumerate(src, 1):
            try:
                yield json.loads(line)
            except ValueError:
                print(f"{path}:{number}: skipped invalid JSON", file=sys.stderr)


def prose(entry):
    kind = entry["type"]
    if kind in ("compaction", "branch_summary"):
        return entry.get("summary", "")
    if kind == "session_info":
        return entry.get("name", "")
    msg = entry.get("message", {})
    if msg.get("role") not in ("user", "assistant"):
        return ""
    content = msg.get("content", "")
    if isinstance(content, list):
        content = " ".join(b["text"] for b in content if b.get("type") == "text")
    return content or f"[{msg.get('stopReason', 'no prose')}]"


def excerpt(entry, start=0):
    msg = entry.get("message", {})
    text = prose(entry)[start : start + 400]
    return [entry["id"], msg.get("role", entry["type"]), " ".join(text.split())]


def search(root, term, current):
    for path in sorted(root.rglob("*.jsonl"), reverse=True):
        if path.resolve() == current:
            continue
        rows = records(path)
        header = next(rows, {})
        if header.get("type") != "session" or header.get("id") == os.getenv(
            "PI_SESSION_ID"
        ):
            continue
        hits = deque(maxlen=3)
        for entry in rows:
            offset = prose(entry).lower().find(term.lower())
            if offset >= 0 and "id" in entry:
                hits.append(excerpt(entry, max(0, offset - 80)))
        if hits:
            print(
                json.dumps(
                    {
                        "file": str(path),
                        "session": header["id"],
                        "cwd": header.get("cwd"),
                        "hits": list(hits),
                    }
                )
            )


def inspect(path, tip, limit):
    rows = records(path)
    header = next(rows, {})
    if header.get("type") != "session" or header.get("version", 1) < 2:
        sys.exit("Expected a v2/v3 Pi session file")
    print(
        json.dumps(
            {k: header[k] for k in ("id", "cwd", "parentSession") if k in header}
        )
    )
    entries = {e["id"]: e for e in rows if "id" in e}
    parents = {e.get("parentId") for e in entries.values()}
    tips = [tip] if tip else [k for k in entries if k not in parents]
    for leaf in tips:
        k = leaf
        seen = set()
        tail = []
        while k is not None and len(tail) < limit:
            if k not in entries or k in seen:
                sys.exit(f"Unknown or broken ancestry at {k}")
            seen.add(k)
            e = entries[k]
            if prose(e):
                tail.append(excerpt(e))
            k = e.get("parentId")
        key = "entry" if tip else "tip"
        print(json.dumps({key: leaf, "previous_page_starts_at": k, "tail": tail[::-1]}))


parser = argparse.ArgumentParser(description=__doc__)
commands = parser.add_subparsers(dest="command", required=True)
s = commands.add_parser("search")
s.add_argument("directory", type=Path)
s.add_argument("term")
t = commands.add_parser("tips")
t.add_argument("file", type=Path)
b = commands.add_parser("branch")
b.add_argument("file", type=Path)
b.add_argument("entry")
b.add_argument("--limit", type=int, default=16)
args = parser.parse_args()
if args.command == "search":
    if not args.directory.is_dir() or not args.term.strip():
        parser.error(
            "Provide an existing session directory and a nonempty literal term"
        )
    active = os.getenv("PI_SESSION_FILE")
    search(args.directory, args.term, Path(active).resolve() if active else None)
else:
    inspect(args.file, getattr(args, "entry", None), getattr(args, "limit", 2))
