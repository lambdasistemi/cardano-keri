#!/usr/bin/env python3
"""Event object and anchor grammar rows (gate v2) as shared case bytes.

The ten structural rows of the readers' gate (OBJ-1..4, ANCH-1..6), with their
variants, and further well-formedness rows for nested strings, escapes, numbers,
literals and UTF-8, all built from one genuine keripy inception (I02 of the #589
comparison, a self-addressing prefix whose anchors are the empty array). Each row
has one defect, with the declared version size fixed up so the intended check is
the one exercised, except OBJ-4. Positive rows record the typed anchor items the
reader must project. The bytes and their sha256 are for both readers.

Run:  nix develop . --command python gen_grammar_cases.py
"""
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("FIXTURES_OUT", os.path.join(HERE, "fixtures"))

with open(os.path.join(OUT, "inv_bind_prefix.json"), encoding="utf-8") as source:
    base = [c for c in json.load(source)["cases"] if c["id"] == "I02"][0]["raw"].encode("latin1")

TAIL = b'"a":[]}'
assert base.endswith(TAIL) and base.startswith(b'{"v":"KERI10JSON')
HEAD = base[: -len(TAIL)]  # everything before the anchors, size field included


def sized(body):
    """Set the six hexadecimal digits of the version size to the length of body."""
    out = body[:16] + b"%06x" % len(body) + body[22:]
    assert out[22:23] == b"_"
    return out


def with_anchor(value):
    return sized(HEAD + b'"a":' + value + b"}")


def row(row_id, expected, note, raw, items=None, declared_size_ok=True):
    r = {"id": row_id, "expected": expected, "note": note, "raw_hex": raw.hex(),
         "sha256": hashlib.sha256(raw).hexdigest(), "length": len(raw)}
    if items is not None:
        r["anchor_items"] = items
    return r


def obj(raw):
    return {"kind": "object", "raw": raw.decode("utf-8")}


ROWS = [
    row("OBJ-1", "accept", "complete compact event, prescribed order, matching size", base, []),
    row("OBJ-2", "refuse", "separator after the last member before the closing brace", sized(base[:-1] + b",}")),
    row("OBJ-3", "refuse", "a second object after the complete event, size counts every byte", sized(base + b"{}")),
    row("OBJ-3b", "refuse", "trailing bytes after the complete event, size counts every byte", sized(base + b"x")),
    row("OBJ-4", "refuse", "declared size differs from the signed length", base[:16] + b"%06x" % (len(base) + 1) + base[22:]),
    row("ANCH-1", "accept", "anchor field is a literal empty array", with_anchor(b"[]"), []),
]
nested = b'{"i":"EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","s":"0","d":"EBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"}'
ROWS += [
    row("ANCH-2", "accept", "valid nonempty array with a nested object; its names stay local", with_anchor(b"[" + nested + b"]"), [obj(nested)]),
    row("ANCH-3", "refuse", "anchor field is a quoted spelling of an empty array", with_anchor(b'"[]"')),
    row("ANCH-4a", "refuse", "anchor field is a number", with_anchor(b"7")),
    row("ANCH-4b", "refuse", "anchor field is an object", with_anchor(b"{}")),
    row("ANCH-4c", "refuse", "anchor field is a string", with_anchor(b'"x"')),
    row("ANCH-5a", "refuse", "trailing comma", with_anchor(b'[{"d":"x"},]')),
    row("ANCH-5b", "refuse", "missing separator between elements", with_anchor(b'[{"d":"x"}{"d":"y"}]')),
    row("ANCH-5c", "refuse", "leading comma", with_anchor(b'[,{"d":"x"}]')),
    row("ANCH-6a", "refuse", "nested object with a trailing comma", with_anchor(b'[{"d":"x",}]')),
    row("ANCH-6b", "refuse", "nested member without a colon", with_anchor(b'[{"d" "x"}]')),
    row("ANCH-6c", "refuse", "nested member without a value", with_anchor(b'[{"d":}]')),
    row("ANCH-6d", "refuse", "nested member name is not a string", with_anchor(b'[{d:"x"}]')),
    row("ANCH-6e", "refuse", "nested object not closed", with_anchor(b'[{"d":"x"]')),
]
esc = b'{"d":"E\\u0041\\n\\"\\\\\\/\\b\\f\\r\\t"}'
utf = '{"d":"é€😀"}'.encode("utf-8")
num = b'{"a":-1.5e3,"b":0,"c":10,"d":-0.25,"e":1E+2}'
lit = b'{"x":true,"y":null,"z":[1,2,[3]],"w":false,"o":{}}'
ROWS += [
    row("GRAM-ESC-OK", "accept", "valid escapes in a nested string", with_anchor(b"[" + esc + b"]"), [obj(esc)]),
    row("GRAM-UTF8-OK", "accept", "well-formed multibyte UTF-8 in a nested string", with_anchor(b"[" + utf + b"]"), [obj(utf)]),
    row("GRAM-NUM-OK", "accept", "valid numbers", with_anchor(b"[" + num + b"]"), [obj(num)]),
    row("GRAM-LIT-OK", "accept", "literals, nested arrays and an empty object", with_anchor(b"[" + lit + b"]"), [obj(lit)]),
    row("GRAM-ESC-BAD", "refuse", "unknown escape", with_anchor(b'[{"d":"\\x"}]')),
    row("GRAM-U-BAD", "refuse", "short unicode escape", with_anchor(b'[{"d":"\\u12"}]')),
    row("GRAM-CTRL", "refuse", "raw control character in a string", with_anchor(b'[{"d":"a\nb"}]')),
    row("GRAM-UTF8-BAD", "refuse", "invalid UTF-8 in a string", with_anchor(b'[{"d":"\xff\xfe"}]')),
    row("GRAM-UTF8-TRUNC", "refuse", "truncated multibyte sequence in a string", with_anchor(b'[{"d":"\xe2\x82"}]')),
    row("GRAM-NUM-ZERO", "refuse", "number with a leading zero", with_anchor(b'[{"n":01}]')),
    row("GRAM-NUM-DOT", "refuse", "number with a trailing point", with_anchor(b'[{"n":1.}]')),
    row("GRAM-NUM-PLUS", "refuse", "number with a leading plus", with_anchor(b'[{"n":+1}]')),
    row("GRAM-NUM-EXP", "refuse", "number with an empty exponent", with_anchor(b'[{"n":1e}]')),
    row("GRAM-LIT-BAD", "refuse", "misspelled literal", with_anchor(b'[{"n":tru}]')),
    row("GRAM-WS", "refuse", "whitespace in the compact profile", with_anchor(b'[ {"d":"x"}]')),
    row("GRAM-STR-OPEN", "refuse", "unterminated string", with_anchor(b'[{"d":"x}]')),
]

with open(os.path.join(OUT, "inv_bind_grammar.json"), "w", encoding="utf-8") as sink:
    json.dump({"note": "Grammar rows of the readers' gate v2 on shared bytes: one genuine keripy 1.3.5 self-addressing inception (I02 of the #589 comparison) with single defects and the declared size fixed up; sha256 of each body for both readers.",
               "base": hashlib.sha256(base).hexdigest(), "rows": ROWS}, sink, indent=2, sort_keys=True)
    sink.write("\n")
print(len(ROWS), "rows;", sum(r["expected"] == "accept" for r in ROWS), "accept")
