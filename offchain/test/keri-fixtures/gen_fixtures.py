#!/usr/bin/env python3
"""Deterministic keripy fixture generator for #106 (convict/freeze enforcement).

keripy is the *oracle*: every event, controller signature, and witness receipt
in the committed fixtures is produced by the KERI reference implementation, so
the on-chain predicates are proven against real artifacts rather than against
our reading of the spec.

Fixture families (each a JSON bundle under fixtures/):
  honest_2key   — a 2-of-2 icp -> rot; the rotation is a valid advance.
  honest_7key   — a 7-key reserve-shaped AID (GLEIF Root shape): 3-of-7 reveal.
  fork          — one identity state rotated TWO conflicting ways at the same
                  sn (same revealed keys, different next commitment): the
                  double-sign artifact the Convict predicate convicts on.
  lag           — a witnessed rotation strictly ahead of a recorded checkpoint
                  state: the Freeze evidence.

Every signature carries a `signing_target` field ("event_raw" | "said") that
the generator sets by re-verifying the signature against BOTH candidate byte
strings. This is the durable evidence closing spec O1 (answer: event_raw).

Determinism: a fixed Salter seed; keripy derives all keys from it. Regenerating
produces byte-identical output (the drift check depends on this).

Run via the nix wrapper `run.sh` (which pins python + libsodium and installs
keripy==1.3.5 in a uv venv); it is NOT part of the offline `just ci` gate
because it needs network for the keripy install. See run.sh header.
"""

import ctypes.util
import os

# pysodium's ctypes.util.find_library('sodium') does not honor LD_LIBRARY_PATH
# on NixOS; point it at the explicit store path the wrapper exports.
_orig_find = ctypes.util.find_library
_sodium = os.environ.get("SODIUM_LIB")
if _sodium:
    ctypes.util.find_library = (
        lambda name: _sodium if name in ("sodium", "libsodium") else _orig_find(name)
    )

import base64
import json
import sys

from keri.core import coring, eventing
from keri.core.signing import Salter

SEED = b"0123456789abcdef"  # frozen; changing it rewrites every fixture
# Output dir: FIXTURES_OUT if set (run.sh pins the committed path), else
# <cwd>/fixtures — so `nix run .#gen` from this directory writes in place
# rather than into the read-only store copy of this script.
OUT = os.environ.get("FIXTURES_OUT") or os.path.join(os.getcwd(), "fixtures")


def _b64u_to_hex(qb64: str) -> str:
    """Raw material of a qb64 primitive as hex (derivation code stripped)."""
    matter = coring.Matter(qb64=qb64)
    return matter.raw.hex()


def _classify_signature(verfer, sig_raw: bytes, event_raw: bytes, said: str) -> str:
    """Return which byte string this signature actually verifies over."""
    if verfer.verify(sig=sig_raw, ser=event_raw):
        return "event_raw"
    if verfer.verify(sig=sig_raw, ser=said.encode()):
        return "said"
    raise AssertionError("signature verifies over neither event_raw nor said")


def _sig_record(signer, index, event_raw, said, kind):
    """One signature entry with its empirically-determined signing target."""
    siger = signer.sign(ser=event_raw, index=index)
    target = _classify_signature(signer.verfer, siger.raw, event_raw, said)
    return {
        "kind": kind,  # "controller" | "witness"
        "index": index,
        "signer_verkey_qb64": signer.verfer.qb64,
        "sig_qb64": siger.qb64,
        "sig_hex": siger.raw.hex(),
        "signing_target": target,  # O1 evidence
    }


def _event_record(serder):
    return {
        "pre": serder.pre,
        "said": serder.said,
        "raw_hex": serder.raw.hex(),
        "raw_len": len(serder.raw),
        "ked": {
            "t": serder.ked["t"],
            "s": serder.ked["s"],
            "i": serder.ked["i"],
            "k": serder.ked["k"],
            "n": serder.ked["n"],
            "kt": serder.ked["kt"],
            "nt": serder.ked["nt"],
            "b": serder.ked.get("b", []),
            "bt": serder.ked.get("bt", "0"),
        },
    }


def build():
    salt = Salter(raw=SEED)
    bundles = {}

    # --- honest_2key: 2-of-2 icp -> rot -----------------------------------
    cur = salt.signers(count=2, transferable=True, temp=True, path="c")
    nxt = salt.signers(count=2, transferable=True, temp=True, path="n")
    nx2 = salt.signers(count=2, transferable=True, temp=True, path="n2")
    icp = eventing.incept(
        keys=[s.verfer.qb64 for s in cur],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in nxt],
        isith="2", nsith="2", code=coring.MtrDex.Blake3_256,
    )
    rot = eventing.rotate(
        pre=icp.pre, dig=icp.said, sn=1,
        keys=[s.verfer.qb64 for s in nxt],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in nx2],
        isith="2", nsith="2",
    )
    bundles["honest_2key"] = {
        "note": "2-of-2 icp then a full-reveal rotation (valid advance)",
        "icp": _event_record(icp),
        "icp_sigs": [_sig_record(cur[i], i, icp.raw, icp.said, "controller") for i in range(2)],
        "rot": _event_record(rot),
        "rot_sigs": [_sig_record(nxt[i], i, rot.raw, rot.said, "controller") for i in range(2)],
    }

    # --- honest_7key: GLEIF-Root-shaped 3-of-7 reserve reveal -------------
    c7 = salt.signers(count=7, transferable=True, temp=True, path="c7")
    n7 = salt.signers(count=7, transferable=True, temp=True, path="n7")
    icp7 = eventing.incept(
        keys=[s.verfer.qb64 for s in c7],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in n7],
        isith=["1/3"] * 7, nsith=["1/3"] * 7, code=coring.MtrDex.Blake3_256,
    )
    # reveal 3 of the 7 committed next keys (indices 0,5,6), restated threshold
    reveal = [n7[0], n7[5], n7[6]]
    n7b = salt.signers(count=7, transferable=True, temp=True, path="n7b")
    rot7 = eventing.rotate(
        pre=icp7.pre, dig=icp7.said, sn=1,
        keys=[s.verfer.qb64 for s in reveal],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in n7b],
        isith=["1/3"] * 3, nsith=["1/3"] * 7,
    )
    bundles["honest_7key"] = {
        "note": "7-key reserve AID; rotation reveals 3 of 7 with restated kt (GLEIF Root shape)",
        "icp": _event_record(icp7),
        "icp_sigs": [_sig_record(c7[i], i, icp7.raw, icp7.said, "controller") for i in range(7)],
        "rot": _event_record(rot7),
        "rot_sigs": [_sig_record(reveal[i], i, rot7.raw, rot7.said, "controller") for i in range(3)],
    }

    # --- fork: two conflicting rotations at the same sn ------------------
    c1 = salt.signers(count=1, transferable=True, temp=True, path="fc")
    fn = salt.signers(count=1, transferable=True, temp=True, path="fn")
    fn2a = salt.signers(count=1, transferable=True, temp=True, path="fn2a")
    fn2b = salt.signers(count=1, transferable=True, temp=True, path="fn2b")
    ficp = eventing.incept(
        keys=[c1[0].verfer.qb64],
        ndigs=[coring.Diger(ser=fn[0].verfer.qb64b).qb64],
        isith="1", nsith="1", code=coring.MtrDex.Blake3_256,
    )
    common = dict(pre=ficp.pre, dig=ficp.said, sn=1,
                  keys=[fn[0].verfer.qb64], isith="1", nsith="1")
    rotA = eventing.rotate(ndigs=[coring.Diger(ser=fn2a[0].verfer.qb64b).qb64], **common)
    rotB = eventing.rotate(ndigs=[coring.Diger(ser=fn2b[0].verfer.qb64b).qb64], **common)
    assert rotA.ked["k"] == rotB.ked["k"] and rotA.ked["n"] != rotB.ked["n"]
    bundles["fork"] = {
        "note": "same sn, same revealed keys, DIFFERENT next commitment — the double-sign",
        "icp": _event_record(ficp),
        "icp_sigs": [_sig_record(c1[0], 0, ficp.raw, ficp.said, "controller")],
        "rot_recorded": _event_record(rotA),  # what Cardano wrote
        "rot_recorded_sigs": [_sig_record(fn[0], 0, rotA.raw, rotA.said, "controller")],
        "rot_conflict": _event_record(rotB),  # the conviction evidence
        "rot_conflict_sigs": [_sig_record(fn[0], 0, rotB.raw, rotB.said, "controller")],
    }

    # --- lag: witnessed rotation ahead of the recorded checkpoint --------
    lc = salt.signers(count=1, transferable=True, temp=True, path="lc")
    ln = salt.signers(count=1, transferable=True, temp=True, path="ln")
    ln2 = salt.signers(count=1, transferable=True, temp=True, path="ln2")
    lw = salt.signers(count=1, transferable=False, temp=True, path="lw")  # witness (B-code)
    licp = eventing.incept(
        keys=[lc[0].verfer.qb64],
        ndigs=[coring.Diger(ser=ln[0].verfer.qb64b).qb64],
        isith="1", nsith="1", wits=[lw[0].verfer.qb64], toad="1",
        code=coring.MtrDex.Blake3_256,
    )
    lrot = eventing.rotate(
        pre=licp.pre, dig=licp.said, sn=1,
        keys=[ln[0].verfer.qb64],
        ndigs=[coring.Diger(ser=ln2[0].verfer.qb64b).qb64],
        isith="1", nsith="1", wits=[lw[0].verfer.qb64],
    )
    bundles["lag"] = {
        "note": "witnessed rotation at sn=1 ahead of a checkpoint recorded at sn=0",
        "icp": _event_record(licp),
        "icp_sigs": [_sig_record(lc[0], 0, licp.raw, licp.said, "controller")],
        "witness_verkey_qb64": lw[0].verfer.qb64,
        "rot": _event_record(lrot),
        "rot_sigs": [_sig_record(ln[0], 0, lrot.raw, lrot.said, "controller")],
        "rot_witness_receipts": [_sig_record(lw[0], 0, lrot.raw, lrot.said, "witness")],
    }

    # --- fork_witnessed: two conflicting WITNESSED rotations at the same sn -
    # A witnessed AID (toad=1) whose witness double-receipts sn=1: the published
    # duplicity that CAN convict (#106 Slice 7 anti-fork). Same shape as `fork`
    # (same revealed keys, DIFFERENT next commitment at sn 1) but both the
    # recorded and the conflicting rotation carry a receipt from the AID's
    # witness — only a witnessed fork proves a real published double-sign;
    # unwitnessed controller-signed bytes cannot frame the identity.
    fwc = salt.signers(count=1, transferable=True, temp=True, path="fwc")
    fwn = salt.signers(count=1, transferable=True, temp=True, path="fwn")
    fwn2a = salt.signers(count=1, transferable=True, temp=True, path="fwn2a")
    fwn2b = salt.signers(count=1, transferable=True, temp=True, path="fwn2b")
    fww = salt.signers(count=1, transferable=False, temp=True, path="fww")  # witness (B-code)
    fwicp = eventing.incept(
        keys=[fwc[0].verfer.qb64],
        ndigs=[coring.Diger(ser=fwn[0].verfer.qb64b).qb64],
        isith="1", nsith="1", wits=[fww[0].verfer.qb64], toad="1",
        code=coring.MtrDex.Blake3_256,
    )
    fwcommon = dict(pre=fwicp.pre, dig=fwicp.said, sn=1,
                    keys=[fwn[0].verfer.qb64], isith="1", nsith="1",
                    wits=[fww[0].verfer.qb64])
    fwrotA = eventing.rotate(ndigs=[coring.Diger(ser=fwn2a[0].verfer.qb64b).qb64], **fwcommon)
    fwrotB = eventing.rotate(ndigs=[coring.Diger(ser=fwn2b[0].verfer.qb64b).qb64], **fwcommon)
    assert fwrotA.ked["k"] == fwrotB.ked["k"] and fwrotA.ked["n"] != fwrotB.ked["n"]
    bundles["fork_witnessed"] = {
        "note": "witnessed fork: same sn, same revealed keys, DIFFERENT next commitment; BOTH rotations witness-receipted (the published duplicity that can convict)",
        "icp": _event_record(fwicp),
        "icp_sigs": [_sig_record(fwc[0], 0, fwicp.raw, fwicp.said, "controller")],
        "witness_verkey_qb64": fww[0].verfer.qb64,
        "rot_recorded": _event_record(fwrotA),
        "rot_recorded_sigs": [_sig_record(fwn[0], 0, fwrotA.raw, fwrotA.said, "controller")],
        "rot_recorded_witness_receipts": [_sig_record(fww[0], 0, fwrotA.raw, fwrotA.said, "witness")],
        "rot_conflict": _event_record(fwrotB),
        "rot_conflict_sigs": [_sig_record(fwn[0], 0, fwrotB.raw, fwrotB.said, "controller")],
        "rot_conflict_witness_receipts": [_sig_record(fww[0], 0, fwrotB.raw, fwrotB.said, "witness")],
    }

    return bundles


def main():
    os.makedirs(OUT, exist_ok=True)
    bundles = build()
    manifest = {
        "generator": "gen_fixtures.py",
        "keri_version": __import__("keri").__version__,
        "seed_hex": SEED.hex(),
        "o1_resolution": "all controller and witness signatures verify over event_raw (not said)",
        "families": sorted(bundles),
    }
    for name, data in bundles.items():
        path = os.path.join(OUT, f"{name}.json")
        with open(path, "w") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
    with open(os.path.join(OUT, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    # O1 assertion: no signature should have slipped through as "said"
    targets = {
        s["signing_target"]
        for data in bundles.values()
        for key, val in data.items()
        if key.endswith("sigs") or key.endswith("receipts")
        for s in val
    }
    assert targets == {"event_raw"}, f"O1 violated: unexpected signing targets {targets}"
    print(f"wrote {len(bundles)} fixture bundles + manifest to {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
