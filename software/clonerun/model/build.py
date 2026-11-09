#!/usr/bin/env python3
"""Builds the JavaScript model of Lode Runner as one page,
build/loderunner.html, with the stages, engine.js and main.js inlined.

The stages are Broderbund's and stay out of git: read from
$LODERUNNER_LEVELS, by default ../private/levels.txt. The page carries
them, so it goes to build/, which git ignores. Never commit or publish
the page.
"""
import os
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
levels_path = Path(os.environ.get("LODERUNNER_LEVELS",
                                  here.parent / "private" / "levels.txt"))
if not levels_path.is_file():
    sys.exit(f"build.py: no {levels_path}, Lode Runner's stages "
             "(set LODERUNNER_LEVELS)")
levels = levels_path.read_text()
assert "</script" not in levels.lower()
html = (here / "template.html").read_text()
html = html.replace("@@LEVELS@@", levels.rstrip("\n"))
html = html.replace("@@ENGINE@@", (here / "engine.js").read_text())
html = html.replace("@@MAIN@@", (here / "main.js").read_text())
out = here / "build" / "loderunner.html"
out.parent.mkdir(exist_ok=True)
out.write_text(html)
print(f"wrote {out} ({len(html)} bytes)")
