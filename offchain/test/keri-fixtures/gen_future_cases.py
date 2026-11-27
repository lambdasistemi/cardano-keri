#!/usr/bin/env python3
"""The weighted next declarations of an inception, as keripy 1.3.5 constructs and signs them.

Draft #600 (lean/check-inception-prefix.py, repaired model 23650e65, published head ce10e471) compares
nine weighted next declarations with keripy. This script builds the four rows of Q-069 and the neighbours
that decide them, with fixed seeds: each admitted inception is serialized with its original signed bytes
(a literal spelling such as 2/4 is kept, not normalized) and signed by the one current key.

A row is admitted when keripy's writer, or, for a literal spelling the writer normalizes or refuses, a
Serder built over the exact body, parses it and the controller signature verifies over its bytes and
Kever accepts it; refused rows record where keripy stopped.

Run through the flake of this directory:  nix develop . --command python gen_future_cases.py
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
from keri import kering  # noqa: E402
from keri.core import coring, eventing, serdering, signing  # noqa: E402
from keri.db import basing  # noqa: E402

assert keri.__version__ == "1.3.5"

OUT = os.environ.get("FIXTURES_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures"))
current = signing.Signer(raw=bytes([0x11]) * 32, code=coring.MtrDex.Ed25519_Seed, transferable=True)
digests = [
    coring.Diger(ser=signing.Signer(raw=bytes([0x40 + k]) * 32, code=coring.MtrDex.Ed25519_Seed).verfer.qb64b).qb64
    for k in range(3)
]

CASES = []


def literal(commitments, declaration):
    """An inception whose signed JSON contains exactly this declaration, built over the writer's body."""
    base = eventing.incept(keys=[current.verfer.qb64], ndigs=digests[:commitments], nsith=0)
    sad = dict(base.sad, nt=declaration)
    return serdering.SerderKERI(sad=sad, makify=True)


def row(label, commitments, declaration, expect):
    """The writer's own verdict, then the exact body with the declared spelling, signed and read by Kever."""
    entry = {"label": label, "commitments": commitments, "declaration": declaration, "expected": expect,
             "key": current.verfer.qb64, "next": digests[:commitments]}
    try:
        written = eventing.incept(keys=[current.verfer.qb64], ndigs=digests[:commitments], nsith=declaration)
        entry["writer"] = "admitted"
        entry["writer_nt"] = serdering.SerderKERI(raw=written.raw).sad["nt"]
    except (kering.ValidationError, ValueError) as error:
        entry["writer"] = "refused: " + str(error)[:120]
    try:
        wire = serdering.SerderKERI(raw=literal(commitments, declaration).raw)
    except (kering.ValidationError, ValueError) as error:
        entry.update(admitted=False, body="not constructible: " + str(error)[:120])
        CASES.append(entry)
        return
    signature = current.sign(ser=wire.raw, index=0)
    assert current.verfer.verify(signature.raw, wire.raw)
    entry.update(raw_hex=wire.raw.hex(), signature_hex=signature.raw.hex(), pre=wire.pre, said=wire.said,
                 signed_nt=wire.sad["nt"])
    try:
        with basing.openDB() as db:
            eventing.Kever(serder=wire, sigers=[signature], db=db)
        entry["admitted"] = True
    except (kering.ValidationError, ValueError) as error:
        entry.update(admitted=False, kever="refused: " + str(error)[:160])
    CASES.append(entry)


row("D next unreduced", 2, ["2/4", "2/4"], True)
row("D next partial coverage", 3, [["1"], ["1"]], True)
row("D next exact one", 2, ["1/2", "1/2"], True)
row("D next nested exact one", 3, ["1/2", {"1/2": ["1/2", "1/2"]}], True)
row("D next below one", 2, ["1/3", "1/3"], False)
row("D weighted next without commitments", 0, ["1"], False)
row("D next second clause below one", 2, [["1"], ["1/3"]], False)
row("D next inner below one", 3, ["1", {"1/2": ["1/3", "1/3"]}], False)

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "inception_future_cases.json"), "w", encoding="utf-8") as sink:
    json.dump({"keripy": keri.__version__,
               "model": "draft #600 ce10e471fa5e2168d30a006c377698afbe20391d lean/check-inception-prefix.py (future_cases)",
               "cases": CASES}, sink, indent=2, sort_keys=True)
    sink.write("\n")
for c in CASES:
    print(c["label"], "| expected", c["expected"], "| kever admitted", c["admitted"], "| writer", c.get("writer", "")[:30], "| signed nt", c.get("signed_nt", c.get("body", "")))
