#!/usr/bin/env python3
"""Parse a ZMK `build.yaml` file into TSV rows for the local build script.

Only supports the flat `include: [{board, shield, snippet, cmake-args,
artifact-name}, ...]` structure used by ZMK's build matrix files - the same
structure read via `yq` by the upstream build-user-config.yml action. No
third-party YAML library is required (this repo/host may not have one
installed), so this is a small purpose-built parser rather than a general
YAML parser.

Commented-out entries (lines starting with `#`) are ignored, matching how
they're normally used to disable a board/shield combination in build.yaml.

Output: one line per matrix entry, tab-separated:
    board\tshield\tsnippet\tcmake-args\tartifact-name
Missing fields are emitted as empty strings.
"""
import re
import sys

FIELDS = ("board", "shield", "snippet", "cmake-args", "artifact-name")


def parse(path):
    entries = []
    current = None
    with open(path) as f:
        for raw in f:
            stripped = raw.strip()

            if not stripped or stripped == "---" or stripped.startswith("#"):
                continue
            if stripped == "include:":
                continue

            m = re.match(r"^-\s+([\w-]+):\s*(.*)$", stripped)
            if m:
                if current is not None:
                    entries.append(current)
                current = {}
                key, val = m.group(1), m.group(2).strip()
                current[key] = val
                continue

            m = re.match(r"^([\w-]+):\s*(.*)$", stripped)
            if m and current is not None:
                key, val = m.group(1), m.group(2).strip()
                current[key] = val
                continue

        if current is not None:
            entries.append(current)
    return entries


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "build.yaml"
    entries = parse(path)
    if not entries:
        print(f"warning: no build matrix entries found in {path}", file=sys.stderr)
    for entry in entries:
        print("\t".join(entry.get(field, "") for field in FIELDS))


if __name__ == "__main__":
    main()
