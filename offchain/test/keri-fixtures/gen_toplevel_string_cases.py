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
ROWS[-1]["seq_raw_hex"] = b"\\u0030".hex()
row("TS-NAME-CTRL", "refuse", "ErrFraming", "raw control character inside a member name", swap(b'"bt":', b'"b\x01t":'))
row("TS-NAME-UTF8", "refuse", "ErrFraming", "invalid UTF-8 inside a member name", swap(b'"bt":', b'"b\xfft":'))
row("TS-NAME-ESC", "refuse", "ErrFieldOrder", "a well-formed escape in a member name: not the schema's name", swap(b'"bt":', b'"b\\u0074":'))
row("TS-ANCH-SURROGATE-LONE", "accept", None, "a lone surrogate escape in a nested string: valid JSON syntax, recorded", swap(b'"a":[]', b'"a":[{"d":"\\ud800"}]'))
row("TS-ANCH-SURROGATE-PAIR", "accept", None, "a surrogate pair escape in a nested string", swap(b'"a":[]', b'"a":[{"d":"\\ud83d\\ude00"}]'))

# --- both lexical paths, same payloads (NOTE-105): the one compact string syntax at
# the top level (member name and value) and in the anchors (member name and value).
PAYLOADS_BAD = [
    ("ctrl-00", b"a\x00b", "raw U+0000"),
    ("ctrl-1f", b"a\x1fb", "raw U+001F"),
    ("ctrl-0a", b"a\nb", "raw newline"),
    ("surrogate-utf8", b"a\xed\xa0\x80b", "raw UTF-8 encoding of a surrogate"),
    ("overlong", b"a\xc0\x80b", "overlong UTF-8"),
    ("trunc", b"a\xe2\x82", "truncated UTF-8"),
    ("esc-unknown", b"a\\xb", "unknown escape"),
    ("esc-upper-u", b"a\\U0041b", "uppercase U escape"),
    ("esc-3hex", b"a\\u004", "three hexadecimal digits then the closing quote"),
    ("esc-nonhex", b"a\\u004Gb", "non-hexadecimal digit in a unicode escape"),
    ("esc-short", b"a\\u12", "unicode escape cut short by the closing quote"),
]
PAYLOADS_OK = [
    ("del", b"a\x7fb", "raw DEL is not a control character of JSON"),
    ("utf8", "a\u00e9\u20ac\U0001f600b".encode("utf-8"), "raw well-formed multibyte UTF-8"),
    ("short-escapes", b'a\\"\\\\\\/\\b\\f\\n\\r\\tb', "every JSON short escape"),
    ("u-lower", b"a\\u0041b", "lowercase u and four hexadecimal digits"),
    ("u-upper-hex", b"a\\u00ABb", "uppercase hexadecimal digits"),
    ("surrogate-lone-high", b"a\\ud800b", "lone high surrogate escape, preserved"),
    ("surrogate-lone-low", b"a\\udc00b", "lone low surrogate escape, preserved"),
    ("surrogate-pair", b"a\\ud83d\\ude00b", "paired surrogate escapes, preserved"),
]


def at_path(path, payload):
    if path == "top-value":
        return swap(b'"s":"0"', b'"s":"' + payload + b'"')
    if path == "top-name":
        return swap(b'"bt":', b'"' + payload + b'":')
    if path == "nested-value":
        return swap(b'"a":[]', b'"a":[{"d":"' + payload + b'"}]')
    return swap(b'"a":[]', b'"a":[{"' + payload + b'":"v"}]')


for path in ("top-value", "top-name", "nested-value", "nested-name"):
    for name, payload, note in PAYLOADS_BAD:
        row(f"PATH-{path}-{name}", "refuse", "ErrFraming", f"{note}, in the {path} string", at_path(path, payload))
    for name, payload, note in PAYLOADS_OK:
        if path == "top-name":
            row(f"PATH-{path}-{name}", "refuse", "ErrFieldOrder", f"{note}, in a top-level member name: valid string, not the schema's name", at_path(path, payload))
        else:
            row(f"PATH-{path}-{name}", "accept", None, f"{note}, in the {path} string; original bytes preserved", at_path(path, payload))
            if path == "top-value":
                ROWS[-1]["seq_raw_hex"] = payload.hex()

with open(os.path.join(OUT, "inv_bind_toplevel_strings.json"), "w", encoding="utf-8") as sink:
    json.dump({"note": "Top-level string validity rows on the grammar base (I02 of the #589 comparison): single defects, declared size fixed up; sha256 of each body for both readers.",
               "base": hashlib.sha256(base).hexdigest(), "rows": ROWS}, sink, indent=2, sort_keys=True)
    sink.write("\n")
print(len(ROWS), "rows")
