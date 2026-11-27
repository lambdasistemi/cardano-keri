#!/usr/bin/env python3
"""Top-level string validity rows: member names and values of the event object.

Same base as the grammar rows (one genuine keripy self-addressing inception, I02),
single defects, the declared size fixed up. The agreed grammar applies to every
string of the event, the top-level members included: a raw control character,
ill-formed UTF-8 and a malformed escape are refused; a well-formed escape is
valid JSON, kept in the raw spelling, and is then refused by the schema or the
spelling it no longer matches. A lone surrogate escape is valid JSON syntax; the
row records the verdict the reader gives so the desk can rule on it.

Run:  nix develop . --command python gen_toplevel_string_cases.py
"""
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("FIXTURES_OUT", os.path.join(HERE, "fixtures"))

with open(os.path.join(OUT, "inv_bind_prefix.json"), encoding="utf-8") as source:
    base = [c for c in json.load(source)["cases"] if c["id"] == "I02"][0]["raw"].encode("latin1")


def sized(body):
    out = body[:16] + b"%06x" % len(body) + body[22:]
    assert out[22:23] == b"_"
    return out


def swap(old, new):
    assert base.count(old) == 1, old
    return sized(base.replace(old, new))


ROWS = []


def row(row_id, expected, error, note, raw):
    ROWS.append({"id": row_id, "expected": expected, "error": error, "note": note,
                 "raw_hex": raw.hex(), "sha256": hashlib.sha256(raw).hexdigest()})


row("TS-BASE", "accept", None, "the base event", base)
row("TS-CTRL-VALUE", "refuse", "ErrFraming", "raw newline inside the string value of s", swap(b'"s":"0"', b'"s":"0\n"'))
row("TS-UTF8-VALUE", "refuse", "ErrFraming", "invalid UTF-8 inside the string value of s", swap(b'"s":"0"', b'"s":"0\xff"'))
row("TS-UTF8-TRUNC-VALUE", "refuse", "ErrFraming", "truncated multibyte sequence inside the string value of s", swap(b'"s":"0"', b'"s":"0\xe2\x82"'))
row("TS-ESC-BAD-VALUE", "refuse", "ErrFraming", "malformed escape inside the string value of s", swap(b'"s":"0"', b'"s":"\\x"'))
row("TS-ESC-VALUE", "refuse", "ErrUnsupportedType", "a well-formed escape spells icp in t: valid JSON, kept raw, not a supported type", swap(b'"t":"icp"', b'"t":"i\\u0063p"'))
row("TS-ESC-SEQ", "accept", None, "a well-formed escape in the sequence number: valid JSON, the raw spelling is kept (the spelling check of registration, E3, refuses it)", swap(b'"s":"0"', b'"s":"\\u0030"'))
ROWS[-1]["seq_raw"] = "\\u0030"
row("TS-NAME-CTRL", "refuse", "ErrFraming", "raw control character inside a member name", swap(b'"bt":', b'"b\x01t":'))
row("TS-NAME-UTF8", "refuse", "ErrFraming", "invalid UTF-8 inside a member name", swap(b'"bt":', b'"b\xfft":'))
row("TS-NAME-ESC", "refuse", "ErrFieldOrder", "a well-formed escape in a member name: not the schema's name", swap(b'"bt":', b'"b\\u0074":'))
row("TS-ANCH-SURROGATE-LONE", "accept", None, "a lone surrogate escape in a nested string: valid JSON syntax, recorded", swap(b'"a":[]', b'"a":[{"d":"\\ud800"}]'))
row("TS-ANCH-SURROGATE-PAIR", "accept", None, "a surrogate pair escape in a nested string", swap(b'"a":[]', b'"a":[{"d":"\\ud83d\\ude00"}]'))

with open(os.path.join(OUT, "inv_bind_toplevel_strings.json"), "w", encoding="utf-8") as sink:
    json.dump({"note": "Top-level string validity rows on the grammar base (I02 of the #589 comparison): single defects, declared size fixed up; sha256 of each body for both readers.",
               "base": hashlib.sha256(base).hexdigest(), "rows": ROWS}, sink, indent=2, sort_keys=True)
    sink.write("\n")
print(len(ROWS), "rows")
