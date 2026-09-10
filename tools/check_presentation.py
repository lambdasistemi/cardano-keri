#!/usr/bin/env python3
"""Presentation gate for reader-facing Markdown: stories, diagrams, no index labels.

Usage: check_presentation.py [--register PATH ...] [--front FILE] ROOT [ROOT ...]

ROOT is a Markdown file or a directory searched recursively for *.md.
--register marks a file (or directory) as a machine-facing register whose
index labels are permitted; everything else is reader-facing.
--front names the front page (default: README.md if present under the first
directory root, else index.md) that must carry a story heading and a diagram.
--no-speech skips the speech binding. By default every page must have a sibling
PAGE.speech.json whose `_source.sha256` equals the page's current hash (see
stamp_speech.py) and whose keys are exactly the page's h2/h3 anchor ids: a page
edited without its speech being redone and re-stamped fails.

Exit 1 with a JSON report of every violation; exit 0 with a JSON summary.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

LABEL = re.compile(r"(?<![\w/#.-])(?:R|S|D|N|M|INV)-?\d{1,3}[a-z]?(?![\w.-])")
FENCE = re.compile(r"^```")
MERMAID = re.compile(r"^```mermaid\b")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
STORY = re.compile(r"\b(stor(y|ies)|who (this|it) is for|what you can do)\b", re.I)
STRUCTURAL = re.compile(r"(architecture|design|lifecycle|flow|protocol|overview|spec)", re.I)


def parse_args(argv):
    registers, front, roots, speech = [], None, [], True
    it = iter(argv)
    for a in it:
        if a == "--register":
            registers.append(Path(next(it)).resolve())
        elif a == "--front":
            front = Path(next(it)).resolve()
        elif a == "--no-speech":
            speech = False
        else:
            roots.append(Path(a))
    if not roots:
        sys.exit(__doc__)
    return registers, front, roots, speech


def slugify(text):
    """python-markdown's toc slugify, so ids match what MkDocs renders."""
    text = re.sub(r"[^\w\s-]", "", text.strip().lower())
    return re.sub(r"[\s]+", "-", text).strip("-")


def check_speech(md, headings):
    """Return violations binding md's speech companion to md's current text."""
    speech = md.with_suffix(".speech.json")
    if not speech.exists():
        return [{"file": str(md), "rule": "speech-missing"}]
    try:
        data = json.loads(speech.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [{"file": str(speech), "rule": "speech-invalid-json", "detail": str(e)}]
    out = []
    stamp = (data.get("_source") or {}).get("sha256")
    actual = hashlib.sha256(md.read_bytes()).hexdigest()
    if stamp != actual:
        out.append({"file": str(speech), "rule": "speech-stale", "stamped": (stamp or "")[:12], "page": actual[:12]})
    keys = {k for k in data if not k.startswith("_")}
    # Speech covers the sections a reader can play: h2 and h3, as the reader and the generator do.
    ids = {slugify(text) for level, text in headings if level in (2, 3)}
    if keys != ids:
        out.append({"file": str(speech), "rule": "speech-headings-mismatch", "missing": sorted(ids - keys), "extra": sorted(keys - ids)})
    for k in keys:
        segs = data[k]
        if not (isinstance(segs, list) and segs and all(isinstance(s, dict) and isinstance(s.get("text"), str) and s["text"].strip() for s in segs)):
            out.append({"file": str(speech), "rule": "speech-empty-section", "section": k})
    return out


def is_register(path, registers):
    return any(path == r or r in path.parents for r in registers)


def scan(path):
    """Return (labels, mermaid_count, headings) for one Markdown file, skipping code fences."""
    labels, mermaid, headings, in_fence = [], 0, [], False
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if FENCE.match(line):
            if not in_fence and MERMAID.match(line):
                mermaid += 1
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        h = HEADING.match(line)
        if h:
            headings.append((len(h.group(1)), h.group(2).strip()))
        for m in LABEL.finditer(line):
            labels.append((n, m.group(0)))
    return labels, mermaid, headings


def main(argv):
    registers, front, roots, speech = parse_args(argv)
    files = []
    for r in roots:
        files.extend(sorted(r.rglob("*.md")) if r.is_dir() else [r])
    files = [f.resolve() for f in files]
    if front is None:
        for r in roots:
            base = r if r.is_dir() else r.parent
            for cand in ("README.md", "index.md"):
                if (base / cand).exists():
                    front = (base / cand).resolve()
                    break
            if front:
                break
    violations, summary = [], {"files": len(files), "diagrams": 0, "registers": len(registers)}
    summary["speechBound"] = 0
    for f in files:
        labels, mermaid, headings = scan(f)
        summary["diagrams"] += mermaid
        rel = str(f)
        if speech:
            sv = check_speech(f, headings)
            violations.extend(sv)
            summary["speechBound"] += not sv
        if labels and not is_register(f, registers):
            sample = ", ".join(f"{n}:{lab}" for n, lab in labels[:6])
            violations.append({"file": rel, "rule": "index-labels", "count": len(labels), "sample": sample})
        if STRUCTURAL.search(f.stem) or STRUCTURAL.search(str(f.parent.name)):
            if mermaid == 0 and not is_register(f, registers):
                violations.append({"file": rel, "rule": "structural-page-without-diagram"})
        if front and f == front:
            if not any(STORY.search(text) for _, text in headings):
                violations.append({"file": rel, "rule": "front-page-without-story-heading"})
            if mermaid == 0:
                violations.append({"file": rel, "rule": "front-page-without-diagram"})
    if front is None:
        violations.append({"file": str(roots[0]), "rule": "no-front-page"})
    report = {"summary": summary, "violations": violations}
    print(json.dumps(report, indent=2))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
