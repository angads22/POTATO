#!/usr/bin/env python3
"""Bundle the web edition into one self-contained HTML file.

    python3 web/build.py                 -> web/dist/SliceIt-Web.html
    python3 web/build.py --artifact OUT  -> OUT, without the document skeleton
                                            (for hosts that wrap the page)

index.html loads core.js and audio.js as separate files (handy for GitHub
Pages and for the Node parity check); the bundle inlines them so the whole
game is a single file you can double-click and play offline.
"""
import re, sys, pathlib

here = pathlib.Path(__file__).resolve().parent
html = (here / "index.html").read_text()
for name in ("core.js", "audio.js"):
    src = (here / name).read_text()
    html = html.replace(f'<script src="{name}"></script>', f"<script>\n{src}\n</script>")
assert 'src="core.js"' not in html and 'src="audio.js"' not in html

if len(sys.argv) > 2 and sys.argv[1] == "--artifact":
    # strip the skeleton: the host supplies doctype/html/head/body + charset/viewport
    for pat in (r"<!doctype html>\s*", r"<html[^>]*>\s*", r"</html>\s*", r"<head>\s*", r"</head>\s*",
                r"<body>\s*", r"</body>\s*", r'<meta charset="utf-8">\s*', r'<meta name="viewport"[^>]*>\s*'):
        html = re.sub(pat, "", html, flags=re.I)
    out = pathlib.Path(sys.argv[2])
else:
    out = here / "dist" / "SliceIt-Web.html"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(html)
print(f"wrote {out} ({len(html) // 1024} KB)")
