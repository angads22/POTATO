#!/usr/bin/env python3
"""Diff the Godot and web song/chart dumps (see dump_godot.gd / dump_web.js).

A seed must compose the same song and chart on both editions — the Daily
Song is shared across them. Floats are compared with a small tolerance
(Godot's JSON writer rounds), everything else exactly.
"""
import json, sys

def same(a, b, where):
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        if abs(float(a) - float(b)) > 1e-4:
            raise SystemExit(f"MISMATCH at {where}: {a!r} != {b!r}")
        return
    if isinstance(a, dict) and isinstance(b, dict):
        for k in a:
            if k not in b:
                raise SystemExit(f"MISMATCH at {where}: key {k!r} missing on web side")
            same(a[k], b[k], f"{where}.{k}")
        return
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            raise SystemExit(f"MISMATCH at {where}: length {len(a)} != {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)):
            same(x, y, f"{where}[{i}]")
        return
    if a != b:
        raise SystemExit(f"MISMATCH at {where}: {a!r} != {b!r}")

g = json.load(open(sys.argv[1]))
w = json.load(open(sys.argv[2]))
same(g, w, "dump")
notes = sum(len(c) for e in g for c in e["charts"].values())
print(f"WEB PARITY OK — {len(g)} songs, {notes} chart notes identical")
