#!/usr/bin/env python3
"""Regenerate api-operations.tsv from the Fabric OpenAPI specs.

Run from this directory: python3 refresh-api-operations.py

Clone cached in a temp directory; delete it if you want a fresh fetch. The specs repository
moves, so record the commit you generated from when citing counts.
"""
import csv
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

REPO = "https://github.com/microsoft/fabric-rest-api-specs"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "api-operations.tsv")
METHODS = ("get", "put", "post", "patch", "delete")


def clone() -> str:
    dest = os.path.join(tempfile.gettempdir(), "fabric-specs")
    if not os.path.isdir(dest):
        subprocess.run(["git", "clone", "--depth", "1", "-q", REPO, dest], check=True)
    return dest


def main() -> int:
    root = clone()
    sha = subprocess.run(
        ["git", "-C", root, "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()

    rows = {}
    for path in sorted(glob.glob(os.path.join(root, "*", "*.json"))):
        group = os.path.basename(os.path.dirname(path))
        try:
            spec = json.load(open(path, encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        for route, item in spec.get("paths", {}).items():
            for method, op in item.items():
                if method not in METHODS:
                    continue
                low = route.lower()
                if "/jobs" in low or "instances" in low:
                    kind = "job"
                elif "definition" in low:
                    kind = "definition"
                elif group == "admin":
                    kind = "admin"
                else:
                    kind = "write" if method != "get" else "read"
                beta = any(
                    isinstance(p, dict) and p.get("name") == "beta"
                    for p in op.get("parameters", [])
                )
                key = (group, method.upper(), route.split("?")[0])
                rows.setdefault(key, (
                    group, method.upper(), route,
                    op.get("operationId", ""), "yes" if beta else "", kind,
                    re.sub(r"\s+", " ", op.get("summary") or "").strip(),
                ))

    ordered = sorted(rows.values())
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(["group", "method", "path", "operationId", "beta", "kind", "summary"])
        writer.writerows(ordered)

    kinds = {}
    for row in ordered:
        kinds[row[5]] = kinds.get(row[5], 0) + 1
    print(f"spec commit: {sha}")
    print(f"operations: {len(ordered)} across {len({r[0] for r in ordered})} groups")
    print("kinds:", ", ".join(f"{k}={v}" for k, v in sorted(kinds.items())))
    print(f"written: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
