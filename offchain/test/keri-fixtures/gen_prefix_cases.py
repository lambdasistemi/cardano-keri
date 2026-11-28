#!/usr/bin/env python3
"""The fifteen indexed inception bookings of the #590 prefix model, built by keripy 1.3.5.

The model (draft #600, lean/check-inception-prefix.py) compares each booking with the
keripy construction of the same inception. This script builds the same fifteen
inceptions with fixed seeds, serializes and signs each admitted one, and records the
exact bytes, the controller signature, the identifier and keripy's own SAID, so the
off-chain decoder and builder checks run on keripy's artifacts.

Admitted means keripy constructed and parsed the event and the controller signature
verified over its bytes; refused means keripy raised while constructing it.

Run through the flake of this directory:  nix develop . --command python gen_prefix_cases.py
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

assert keri.__version__ == "1.3.5"

OUT = os.environ.get("FIXTURES_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures"))


def signer(byte, transferable):
    return signing.Signer(raw=bytes([byte]) * 32, code=coring.MtrDex.Ed25519_Seed, transferable=transferable)


transferable = signer(0x11, True)
nontransferable = signer(0x22, False)
witness = signer(0x33, False)
next_digest = coring.Diger(ser=transferable.verfer.qb64b).qb64

CASES = []


def check(label, who, expect, **fields):
    row = {"label": label, "expected": expect, "key": who.verfer.qb64}
    try:
        event = eventing.incept(keys=[who.verfer.qb64], **fields)
        parsed = serdering.SerderKERI(raw=event.raw)
        signature = who.sign(ser=parsed.raw, index=0)
        assert who.verfer.verify(signature.raw, parsed.raw)
    except (kering.ValidationError, ValueError) as error:
        row.update(admitted=False, error=str(error)[:200])
    else:
        row.update(admitted=True, raw_hex=parsed.raw.hex(), signature_hex=signature.raw.hex(),
                   pre=parsed.pre, said=parsed.said)
    assert row["admitted"] == expect, (label, row)
    CASES.append(row)


check("B empty", nontransferable, True)
check("D empty", transferable, True)
check("B next", nontransferable, False, ndigs=[next_digest])
check("D next", transferable, True, ndigs=[next_digest])
check("B witness", nontransferable, False, wits=[witness.verfer.qb64], toad=1)
check("D witness", transferable, True, wits=[witness.verfer.qb64], toad=1)
check("B seal", nontransferable, False, data=[{"d": next_digest}])
check("D seal", transferable, True, data=[{"d": next_digest}])
check("D weighted one", transferable, False, isith=["1"])
check("E digest", transferable, True, code=coring.MtrDex.Blake3_256)
check("D missing next", transferable, False, nsith=1)
check("D oversized next", transferable, False, ndigs=[next_digest], nsith=2)
check("B missing next", nontransferable, False, nsith=1)
check("E zero signing", transferable, False, code=coring.MtrDex.Blake3_256, isith=0)
check("D zero next with digest", transferable, True, ndigs=[next_digest], nsith=0)

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "inception_prefix_cases.json"), "w", encoding="utf-8") as sink:
    json.dump({"keripy": keri.__version__, "model": "draft #600 16e6502e848dcad30073963f28573146b71213dd lean/check-inception-prefix.py",
               "cases": CASES}, sink, indent=2, sort_keys=True)
    sink.write("\n")
print(len(CASES), "cases;", sum(c["admitted"] for c in CASES), "admitted")
