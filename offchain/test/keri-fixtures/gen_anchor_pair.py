#!/usr/bin/env python3
"""A matched pair of inceptions, and a sweep of their anchor size, whose future declaration already books.

Both members of the pair declare one next commitment, a signing threshold of one and a next threshold of
one, and differ only in the anchors: the empty list, and a list of seals. The sweep keeps everything else
and grows the list of seals. One distinct current key (a distinct identifier) per row, so each row can be
booked in one registry. Built by keripy 1.3.5, signed by the row's current key at index 0.

Run through the flake of this directory:  nix develop . --command python gen_anchor_pair.py
"""
import ctypes.util
import json
import os

_find = ctypes.util.find_library


def _find_library(name):
    if name in ("sodium", "libsodium") and "SODIUM_LIB" in os.environ:
        return os.environ["SODIUM_LIB"]
    return _find(name)


ctypes.util.find_library = _find_library
import keri  # noqa: E402
from keri.core import coring, eventing, serdering, signing  # noqa: E402
from keri.db import basing  # noqa: E402

assert keri.__version__ == "1.3.5"
OUT = os.environ.get("FIXTURES_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures"))


def signer(byte):
    return signing.Signer(raw=bytes([byte]) * 32, code=coring.MtrDex.Ed25519_Seed, transferable=True)


def digest(byte):
    return coring.Diger(ser=signer(byte).verfer.qb64b).qb64


ROWS = []
for index, seals in enumerate([0, 1, 2, 4, 8, 16, 32, 64]):
    who = signer(0x60 + index)
    data = [{"d": digest(0x80 + index * 4 + k % 4 + (k // 4) * 0)} for k in range(seals)]
    # distinct seal digests: derive each from its own seed
    data = [{"d": coring.Diger(ser=bytes([index, k % 256, k // 256]) * 8).qb64} for k in range(seals)]
    event = eventing.incept(keys=[who.verfer.qb64], ndigs=[digest(0x40)], nsith=1, data=data)
    wire = serdering.SerderKERI(raw=event.raw)
    signature = who.sign(ser=wire.raw, index=0)
    assert who.verfer.verify(signature.raw, wire.raw)
    with basing.openDB() as db:
        eventing.Kever(serder=wire, sigers=[signature], db=db)
    ROWS.append({"name": f"anchors-{seals:02d}", "seals": seals, "pre": wire.pre, "said": wire.said,
                 "raw_hex": wire.raw.hex(), "signature_hex": signature.raw.hex(), "bytes": len(wire.raw)})

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "inception_anchor_pair.json"), "w", encoding="utf-8") as sink:
    json.dump({"keripy": keri.__version__, "rows": ROWS}, sink, indent=2, sort_keys=True)
    sink.write("\n")
for r in ROWS:
    print(r["name"], r["bytes"], r["pre"])
