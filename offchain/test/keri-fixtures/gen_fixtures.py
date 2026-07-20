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
  registration  — #114 icp-admission family: witnessed / weighted / delegated
                  (dip, drt) / oversize inceptions plus the true S5
                  measurement shapes (unwitnessed 2-key, unwitnessed
                  GLEIF-shaped 7-key — T114-S5a), each with generator-emitted
                  per-field byte offsets into the raw serialization (offset
                  convention documented on _field_spans) and exported signer
                  seeds (temp test keys from the fixed Salter seed below —
                  safe to commit).
  advance       — #115 witnessed rotations: 2-key and GLEIF 7-key cut/add,
                  all-witness downgrade, and no-delta keep, with incoming-set
                  receipts, rotation offsets, and controller/witness seeds.

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


def _event_record(serder, rotation_fields=False):
    ked = {
        "t": serder.ked["t"],
        "s": serder.ked["s"],
        "i": serder.ked["i"],
        "k": serder.ked["k"],
        "n": serder.ked["n"],
        "kt": serder.ked["kt"],
        "nt": serder.ked["nt"],
        "b": serder.ked.get("b", []),
        "bt": serder.ked.get("bt", "0"),
    }
    if rotation_fields:
        ked.update(
            {
                "p": serder.ked["p"],
                "br": serder.ked["br"],
                "ba": serder.ked["ba"],
            }
        )
    return {
        "pre": serder.pre,
        "said": serder.said,
        "raw_hex": serder.raw.hex(),
        "raw_len": len(serder.raw),
        "ked": ked,
    }


def _scan_string(raw: bytes, pos: int):
    """Content span (start, end) of the JSON string starting at raw[pos] == '"'."""
    assert raw[pos : pos + 1] == b'"'
    end = raw.index(b'"', pos + 1)
    assert b"\\" not in raw[pos + 1 : end], "escape inside a KERI field string"
    return pos + 1, end


def _skip_value(raw: bytes, pos: int):
    """Position just past the JSON value starting at pos."""
    c = raw[pos : pos + 1]
    if c == b'"':
        return _scan_string(raw, pos)[1] + 1
    if c in (b"[", b"{"):
        depth = 0
        while True:
            ch = raw[pos : pos + 1]
            if ch == b'"':
                pos = _scan_string(raw, pos)[1] + 1
            elif ch in (b"[", b"{"):
                depth += 1
                pos += 1
            elif ch in (b"]", b"}"):
                depth -= 1
                pos += 1
                if depth == 0:
                    return pos
            else:
                pos += 1
    end = pos
    while raw[end : end + 1] not in (b",", b"}", b"]"):
        end += 1
    return end


def _field_spans(raw: bytes):
    """Byte spans of the top-level JSON values in keripy's compact serialization.

    OFFSET CONVENTION (the ground truth consumed by the E1-E9 slice checks
    and RegistrationFixturesSpec):

      * string values  -> the span covers the VALUE CONTENT between the
                          quotes (a 44-char qb64 primitive, "icp", a hex
                          digit string), quotes excluded;
      * array values   -> the span covers the full array INCLUDING the
                          brackets (the weighted kt/nt fraction-string
                          re-spelling); each string element additionally
                          yields its own between-quotes content span.

    KERI field strings never contain JSON escapes (asserted), so quote
    scanning locates exact byte spans. Returns {key: (kind, start, end,
    elems)} where kind is "string" | "array" | "other" and elems lists
    (start, end) content spans of string elements for arrays (else None).
    """
    assert raw[:1] == b"{", "not a compact JSON object serialization"
    spans = {}
    pos = 1
    while raw[pos : pos + 1] != b"}":
        ks, ke = _scan_string(raw, pos)
        key = raw[ks:ke].decode()
        pos = ke + 1
        assert raw[pos : pos + 1] == b":"
        pos += 1
        c = raw[pos : pos + 1]
        if c == b'"':
            vs, ve = _scan_string(raw, pos)
            spans[key] = ("string", vs, ve, None)
            pos = ve + 1
        elif c == b"[":
            end = _skip_value(raw, pos)
            elems = []
            p = pos + 1
            while raw[p : p + 1] != b"]":
                if raw[p : p + 1] == b'"':
                    es, ee = _scan_string(raw, p)
                    elems.append((es, ee))
                    p = ee + 1
                else:
                    p = _skip_value(raw, p)
                if raw[p : p + 1] == b",":
                    p += 1
            spans[key] = ("array", pos, end, elems)
            pos = end
        else:
            end = _skip_value(raw, pos)
            spans[key] = ("other", pos, end, None)
            pos = end
        if raw[pos : pos + 1] == b",":
            pos += 1
    return spans


def _offsets_record(serder, rotation_fields=False):
    """Per-field value offsets into serder.raw, per the _field_spans convention.

    Scalar fields (t, i, s, kt, nt, bt) map to a single offset — the value
    content for strings, the opening '[' for weighted kt/nt arrays. The
    k/n/b fields map to per-element content offsets ([] when the event has
    no such field, e.g. b in a drt).
    """
    spans = _field_spans(serder.raw)
    offsets = {}
    scalar_fields = ["t", "i", "s", "kt", "nt", "bt"]
    array_fields = ["k", "n", "b"]
    if rotation_fields:
        scalar_fields.append("p")
        array_fields.extend(("br", "ba"))
    for f in scalar_fields:
        if f in spans:
            offsets[f] = spans[f][1]
    for f in array_fields:
        offsets[f] = [start for start, _ in spans[f][3]] if f in spans else []
    return offsets


def _assert_offsets(serder, offsets):
    """Self-check: slicing raw at each exported offset reproduces the ked value."""
    raw = serder.raw
    ked = serder.ked

    def sl(off, blen):
        return raw[off : off + blen]

    for f in ("t", "i", "s", "d", "p", "bt"):
        if f in offsets:
            exp = ked[f].encode()
            assert sl(offsets[f], len(exp)) == exp, f"offset self-check failed: {f}"
    for f in ("kt", "nt"):
        if f in offsets:
            v = ked[f]
            exp = (
                json.dumps(v, separators=(",", ":")) if isinstance(v, list) else v
            ).encode()
            assert sl(offsets[f], len(exp)) == exp, f"offset self-check failed: {f}"
    for f in ("k", "n", "b", "br", "ba"):
        if f not in offsets:
            continue
        elems = ked.get(f) or []
        assert len(offsets[f]) == len(elems), f"offset count mismatch: {f}"
        for off, e in zip(offsets[f], elems):
            assert sl(off, len(e)) == e.encode(), f"offset self-check failed: {f}"


def _seed_records(signers):
    """Signer-seed export: raw Ed25519 seed (hex) + the qb64 verkey it derives."""
    return [
        {"seed_hex": s.raw.hex(), "verkey_qb64": s.verfer.qb64} for s in signers
    ]


def _reg_record(serder, cur, nxt, note, delegator_pre=None):
    """One registration sub-fixture: event, sigs, offsets, signer seeds."""
    offsets = _offsets_record(serder)
    _assert_offsets(serder, offsets)
    rec = {
        "note": note,
        "event": _event_record(serder),
        "event_sigs": [
            _sig_record(cur[i], i, serder.raw, serder.said, "controller")
            for i in range(len(cur))
        ],
        "offsets": offsets,
        "signer_seeds": {
            "current": _seed_records(cur),
            "next": _seed_records(nxt),
        },
    }
    if delegator_pre is not None:
        rec["delegator_pre"] = delegator_pre
    return rec


def _enforcement_event_record(serder, rotation_fields=False):
    """One enforcement event with generator-derived field offsets.

    Enforcement consumes only t/i/s/k/kt/n/nt/bt.  The offsets are scanned
    from keripy's exact serialization and self-checked before they become
    fixture data; they are never maintained as hand-authored constants.
    """
    offsets = _offsets_record(serder, rotation_fields=rotation_fields)
    offsets["d"] = _field_spans(serder.raw)["d"][1]
    _assert_offsets(serder, offsets)
    return {
        **_event_record(serder, rotation_fields=rotation_fields),
        "offsets": offsets,
    }


def _advance_record(
    icp,
    rot,
    icp_cur,
    rot_cur,
    rot_next,
    witness_outgoing,
    witness_added,
    receipts,
    note,
):
    """One #115 fixture with incoming-indexed receipts and seed material."""
    offsets = _offsets_record(rot, rotation_fields=True)
    _assert_offsets(rot, offsets)
    return {
        "note": note,
        "icp": _event_record(icp),
        "icp_sigs": [
            _sig_record(signer, index, icp.raw, icp.said, "controller")
            for index, signer in enumerate(icp_cur)
        ],
        "rot": _event_record(rot, rotation_fields=True),
        "rot_sigs": [
            _sig_record(signer, index, rot.raw, rot.said, "controller")
            for index, signer in enumerate(rot_cur)
        ],
        "rot_witness_receipts": [
            _sig_record(signer, incoming_index, rot.raw, rot.said, "witness")
            for signer, incoming_index in receipts
        ],
        "offsets": offsets,
        "signer_seeds": {
            "inception_current": _seed_records(icp_cur),
            "rotation_current": _seed_records(rot_cur),
            "rotation_next": _seed_records(rot_next),
            "witness_outgoing": _seed_records(witness_outgoing),
            "witness_added": _seed_records(witness_added),
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
        "icp": _enforcement_event_record(ficp),
        "icp_sigs": [_sig_record(c1[0], 0, ficp.raw, ficp.said, "controller")],
        "rot_recorded": _enforcement_event_record(rotA),  # what Cardano wrote
        "rot_recorded_sigs": [_sig_record(fn[0], 0, rotA.raw, rotA.said, "controller")],
        "rot_conflict": _enforcement_event_record(rotB),  # the conviction evidence
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
        "icp": _enforcement_event_record(licp),
        "icp_sigs": [_sig_record(lc[0], 0, licp.raw, licp.said, "controller")],
        "witness_verkey_qb64": lw[0].verfer.qb64,
        "rot": _enforcement_event_record(lrot),
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
        "icp": _enforcement_event_record(fwicp),
        "icp_sigs": [_sig_record(fwc[0], 0, fwicp.raw, fwicp.said, "controller")],
        "witness_verkey_qb64": fww[0].verfer.qb64,
        "rot_recorded": _enforcement_event_record(fwrotA),
        "rot_recorded_sigs": [_sig_record(fwn[0], 0, fwrotA.raw, fwrotA.said, "controller")],
        "rot_recorded_witness_receipts": [_sig_record(fww[0], 0, fwrotA.raw, fwrotA.said, "witness")],
        "rot_conflict": _enforcement_event_record(fwrotB),
        "rot_conflict_sigs": [_sig_record(fwn[0], 0, fwrotB.raw, fwrotB.said, "controller")],
        "rot_conflict_witness_receipts": [_sig_record(fww[0], 0, fwrotB.raw, fwrotB.said, "witness")],
    }

    # --- advance: #115 witnessed rotation ground truth -------------------
    # Receipt indices are positions in the derived incoming set
    # (outgoing witnesses minus br, followed by ba), never the outgoing set.

    # True 2-key witnessed shape: [w0,w1,w2] -> [w1,w2,w3].  Receipts use
    # incoming indices 0 and 2, proving both survivor reindexing and add index.
    awc = salt.signers(count=2, transferable=True, temp=True, path="awc")
    awn = salt.signers(count=2, transferable=True, temp=True, path="awn")
    awn2 = salt.signers(count=2, transferable=True, temp=True, path="awn2")
    aww = salt.signers(count=4, transferable=False, temp=True, path="aww")
    awicp = eventing.incept(
        keys=[s.verfer.qb64 for s in awc],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in awn],
        isith="2", nsith="2",
        wits=[s.verfer.qb64 for s in aww[:3]], toad="2",
        code=coring.MtrDex.Blake3_256,
    )
    awrot = eventing.rotate(
        pre=awicp.pre, dig=awicp.said, sn=1,
        keys=[s.verfer.qb64 for s in awn],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in awn2],
        isith="2", nsith="2", toad="2",
        wits=[s.verfer.qb64 for s in aww[:3]],
        cuts=[aww[0].verfer.qb64], adds=[aww[3].verfer.qb64],
    )

    # GLEIF-root reserve shape: reveal committed positions 0,5,6 and restate
    # a 3-clause current threshold while retaining a 7-key next reserve.
    a7c = salt.signers(count=7, transferable=True, temp=True, path="a7c")
    a7n = salt.signers(count=7, transferable=True, temp=True, path="a7n")
    a7n2 = salt.signers(count=7, transferable=True, temp=True, path="a7n2")
    a7w = salt.signers(count=4, transferable=False, temp=True, path="a7w")
    a7icp = eventing.incept(
        keys=[s.verfer.qb64 for s in a7c],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in a7n],
        isith=["1/3"] * 7, nsith=["1/3"] * 7,
        wits=[s.verfer.qb64 for s in a7w[:3]], toad="2",
        code=coring.MtrDex.Blake3_256,
    )
    a7reveal = [a7n[0], a7n[5], a7n[6]]
    a7rot = eventing.rotate(
        pre=a7icp.pre, dig=a7icp.said, sn=1,
        keys=[s.verfer.qb64 for s in a7reveal],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in a7n2],
        isith=["1/3"] * 3, nsith=["1/3"] * 7, toad="2",
        wits=[s.verfer.qb64 for s in a7w[:3]],
        cuts=[a7w[0].verfer.qb64], adds=[a7w[3].verfer.qb64],
    )

    # Visible downgrade: all witnesses are cut, the incoming set is empty,
    # bt is zero, and no receipts exist.
    adc = salt.signers(count=2, transferable=True, temp=True, path="adc")
    adn = salt.signers(count=2, transferable=True, temp=True, path="adn")
    adn2 = salt.signers(count=2, transferable=True, temp=True, path="adn2")
    adw = salt.signers(count=3, transferable=False, temp=True, path="adw")
    adicp = eventing.incept(
        keys=[s.verfer.qb64 for s in adc],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in adn],
        isith="2", nsith="2",
        wits=[s.verfer.qb64 for s in adw], toad="2",
        code=coring.MtrDex.Blake3_256,
    )
    adrot = eventing.rotate(
        pre=adicp.pre, dig=adicp.said, sn=1,
        keys=[s.verfer.qb64 for s in adn],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in adn2],
        isith="2", nsith="2", toad="0",
        wits=[s.verfer.qb64 for s in adw],
        cuts=[s.verfer.qb64 for s in adw], adds=[],
    )

    # Common steady state: no witness delta, same non-empty set and threshold
    # receipts from two unchanged witnesses.
    akc = salt.signers(count=2, transferable=True, temp=True, path="akc")
    akn = salt.signers(count=2, transferable=True, temp=True, path="akn")
    akn2 = salt.signers(count=2, transferable=True, temp=True, path="akn2")
    akw = salt.signers(count=3, transferable=False, temp=True, path="akw")
    akicp = eventing.incept(
        keys=[s.verfer.qb64 for s in akc],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in akn],
        isith="2", nsith="2",
        wits=[s.verfer.qb64 for s in akw], toad="2",
        code=coring.MtrDex.Blake3_256,
    )
    akrot = eventing.rotate(
        pre=akicp.pre, dig=akicp.said, sn=1,
        keys=[s.verfer.qb64 for s in akn],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in akn2],
        isith="2", nsith="2", toad="2",
        wits=[s.verfer.qb64 for s in akw], cuts=[], adds=[],
    )

    bundles["advance"] = {
        "note": (
            "#115 witnessed rotations with controller and incoming-set "
            "witness signatures over exact keripy event raw bytes"
        ),
        "offset_convention": (
            "Offsets index into rot.raw: string values point to unquoted "
            "content; array offsets identify each unquoted element. All "
            "t/i/s/k/kt/n/nt/p/br/ba/bt slices are self-checked against ked."
        ),
        "adv_wit_2key": _advance_record(
            awicp, awrot, awc, awn, awn2, aww[:3], [aww[3]],
            [(aww[1], 0), (aww[3], 2)],
            "2-key witnessed rotation cutting witness 0 and adding witness 3",
        ),
        "adv_wit_7key": _advance_record(
            a7icp, a7rot, a7c, a7reveal, a7n2, a7w[:3], [a7w[3]],
            [(a7w[1], 0), (a7w[3], 2)],
            "GLEIF-root partial 3-of-7 reveal with witness cut/add",
        ),
        "adv_downgrade": _advance_record(
            adicp, adrot, adc, adn, adn2, adw, [], [],
            "all witnesses cut, bt=0, and zero receipts",
        ),
        "adv_keep": _advance_record(
            akicp, akrot, akc, akn, akn2, akw, [],
            [(akw[0], 0), (akw[2], 2)],
            "no witness delta; threshold receipts from the unchanged set",
        ),
    }

    # --- registration: #114 icp-admission ground truth --------------------
    # Every event and signature is keripy output; per-field offsets are
    # computed from keripy's own serialization (_field_spans) and
    # self-checked against ked before export. Exported seeds are temp test
    # keys derived from the fixed Salter seed — safe to commit; the Haskell
    # layer uses them to produce Cardano-side InceptionMessage signatures
    # at test time (deployment parameters are chosen there, so keripy
    # cannot pre-sign those preimages).
    rwc = salt.signers(count=2, transferable=True, temp=True, path="rwc")
    rwn = salt.signers(count=2, transferable=True, temp=True, path="rwn")
    rww = salt.signers(count=3, transferable=False, temp=True, path="rww")
    ricp_w = eventing.incept(
        keys=[s.verfer.qb64 for s in rwc],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in rwn],
        isith="2", nsith="2",
        wits=[s.verfer.qb64 for s in rww], toad="2",
        code=coring.MtrDex.Blake3_256,
    )

    rgc = salt.signers(count=3, transferable=True, temp=True, path="rgc")
    rgn = salt.signers(count=3, transferable=True, temp=True, path="rgn")
    ricp_g = eventing.incept(
        keys=[s.verfer.qb64 for s in rgc],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in rgn],
        isith=["1/2", "1/4", "1/4"], nsith=["1/2", "1/4", "1/4"],
        code=coring.MtrDex.Blake3_256,
    )

    # A 1-key delegator whose pre anchors the delegated pair below; only its
    # prefix is needed (the delegating seal lives in the delegator's KEL).
    rdel_c = salt.signers(count=1, transferable=True, temp=True, path="rdelc")
    rdel_n = salt.signers(count=1, transferable=True, temp=True, path="rdeln")
    rdel_icp = eventing.incept(
        keys=[rdel_c[0].verfer.qb64],
        ndigs=[coring.Diger(ser=rdel_n[0].verfer.qb64b).qb64],
        isith="1", nsith="1", code=coring.MtrDex.Blake3_256,
    )

    rdc = salt.signers(count=1, transferable=True, temp=True, path="rdc")
    rdn = salt.signers(count=1, transferable=True, temp=True, path="rdn")
    rdn2 = salt.signers(count=1, transferable=True, temp=True, path="rdn2")
    rdip = eventing.delcept(
        keys=[rdc[0].verfer.qb64],
        delpre=rdel_icp.pre,
        ndigs=[coring.Diger(ser=rdn[0].verfer.qb64b).qb64],
        isith="1", nsith="1", code=coring.MtrDex.Blake3_256,
    )
    rdrt = eventing.deltate(
        pre=rdip.pre, dig=rdip.said, sn=1,
        keys=[rdn[0].verfer.qb64],
        ndigs=[coring.Diger(ser=rdn2[0].verfer.qb64b).qb64],
        isith="1", nsith="1",
    )

    # GLEIF-Root-shaped board pushed past the single-chunk boundary: 7
    # fractionally-weighted keys, 7 next digests, 7 witnesses, toad 5.
    roc = salt.signers(count=7, transferable=True, temp=True, path="roc")
    ron = salt.signers(count=7, transferable=True, temp=True, path="ron")
    row = salt.signers(count=7, transferable=False, temp=True, path="row")
    ricp_o = eventing.incept(
        keys=[s.verfer.qb64 for s in roc],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in ron],
        isith=["1/3"] * 7, nsith=["1/3"] * 7,
        wits=[s.verfer.qb64 for s in row], toad="5",
        code=coring.MtrDex.Blake3_256,
    )

    # True S5 measurement shapes (A-003 / T114-S5a): the unwitnessed
    # 2-key and the unwitnessed GLEIF-shaped 7-key icp, with seeds +
    # offsets so the Cardano-side registration package (preimage
    # signatures) can be produced for them like any family member.
    r2c = salt.signers(count=2, transferable=True, temp=True, path="r2c")
    r2n = salt.signers(count=2, transferable=True, temp=True, path="r2n")
    ricp_2 = eventing.incept(
        keys=[s.verfer.qb64 for s in r2c],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in r2n],
        isith="2", nsith="2", code=coring.MtrDex.Blake3_256,
    )

    r7c = salt.signers(count=7, transferable=True, temp=True, path="r7c")
    r7n = salt.signers(count=7, transferable=True, temp=True, path="r7n")
    ricp_7 = eventing.incept(
        keys=[s.verfer.qb64 for s in r7c],
        ndigs=[coring.Diger(ser=s.verfer.qb64b).qb64 for s in r7n],
        isith=["1/3"] * 7, nsith=["1/3"] * 7, code=coring.MtrDex.Blake3_256,
    )

    bundles["registration"] = {
        "note": (
            "#114 registration path ground truth: icp-admission fixtures "
            "with generator-emitted per-field offsets and signer-seed export"
        ),
        "offset_convention": (
            "Offsets index into the raw serialization (raw_hex decoded). "
            "For string-valued fields (t, i, s, bt, unweighted kt/nt, and "
            "each k/n/b element) the offset points at the first byte of the "
            "value content BETWEEN the quotes; for weighted kt/nt it points "
            "at the opening '[' and the value spans the full compact-JSON "
            "fraction-string array. Emitted by _field_spans from keripy's "
            "own serialization and self-checked against ked before export."
        ),
        "reg_witnessed": _reg_record(
            ricp_w, rwc, rwn,
            "3-witness toad-2 icp — the parent-acceptance witnessed 2-of-3 shape",
        ),
        "reg_weighted": _reg_record(
            ricp_g, rgc, rgn,
            "fractionally-weighted kt icp (E5 weighted re-spelling material)",
        ),
        "reg_dip": _reg_record(
            rdip, rdc, rdn,
            "real keripy delegated inception (E1 rejection material)",
            delegator_pre=rdel_icp.pre,
        ),
        "reg_drt": _reg_record(
            rdrt, rdn, rdn2,
            "real keripy delegated rotation (E1 rejection material)",
            delegator_pre=rdel_icp.pre,
        ),
        "reg_oversize": _reg_record(
            ricp_o, roc, ron,
            "GLEIF-Root-shaped 7-key 7-witness icp > 1024 B (H1 rejection material)",
        ),
        "reg_2key": _reg_record(
            ricp_2, r2c, r2n,
            "unwitnessed 2-key kt-2 icp — the true S5 2-key measurement shape",
        ),
        "reg_7key": _reg_record(
            ricp_7, r7c, r7n,
            "unwitnessed GLEIF-shaped 7-key icp — the true S5 7-key measurement shape",
        ),
    }
    assert bundles["registration"]["reg_oversize"]["event"]["raw_len"] > 1024, (
        "reg_oversize does not breach the single-chunk boundary"
    )
    for small in (
        "reg_witnessed", "reg_weighted", "reg_dip", "reg_drt",
        "reg_2key", "reg_7key",
    ):
        assert bundles["registration"][small]["event"]["raw_len"] <= 1024, (
            f"{small} unexpectedly exceeds the single-chunk boundary"
        )

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
    # O1 assertion: no signature should have slipped through as "said".
    # Walks nested sub-fixtures too (the registration family nests one
    # level deeper than the flat #106 families).
    def _sig_targets(node):
        if isinstance(node, dict):
            for key, val in node.items():
                if key.endswith("sigs") or key.endswith("receipts"):
                    for s in val:
                        yield s["signing_target"]
                else:
                    yield from _sig_targets(val)

    targets = set(_sig_targets(bundles))
    assert targets == {"event_raw"}, f"O1 violated: unexpected signing targets {targets}"
    print(f"wrote {len(bundles)} fixture bundles + manifest to {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
