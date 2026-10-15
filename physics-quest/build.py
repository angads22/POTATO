#!/usr/bin/env python3
"""Bundle Physics Quest 12 into one self-contained HTML file.

    python3 physics-quest/build.py    -> physics-quest/dist/PhysicsQuest12.html

index.html loads questions.js and game.js as separate files (handy for
development and for the Node question checker); the bundle inlines them so
the whole game is a single file you can double-click and play offline.
"""
import pathlib

here = pathlib.Path(__file__).resolve().parent
html = (here / "index.html").read_text(encoding="utf-8")
for name in ("questions.js", "game.js"):
    src = (here / name).read_text(encoding="utf-8")
    assert "</script" not in src.lower(), f"{name} must not contain a closing script tag"
    tag = f'<script src="{name}"></script>'
    assert tag in html, f"index.html must load {name}"
    html = html.replace(tag, f"<script>\n{src}\n</script>")
out = here / "dist" / "PhysicsQuest12.html"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(html, encoding="utf-8")
print(f"wrote {out} ({len(html.encode('utf-8')) // 1024} KB)")
