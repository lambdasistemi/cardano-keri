#!/usr/bin/env python3
"""Ordinary event corpus for the admission comparison, keripy side.

Every event is built from deterministic test signers (fixed Salter seed), serialised to its wire bytes,
parsed with keripy's `SerderKERI(raw=...)` and processed by keripy's `Kevery.processEvent` against a
temporary database that holds the predecessor events. The outcome of each step is read from keripy's own
key event log: the event is persisted when the log holds the exact SAID at its sequence number and the exact
stored bytes. An event that is not persisted is reported as it is (an escrow index, an exception class, or
unknown); nothing is inferred.

The corpus holds ordinary, well-formed events only: inceptions, rotations and interactions that follow the
rules of KERI, with ordinary signing and witness thresholds. Nothing here touches a network.

Output: keripy-results.json (one row per step) and lean-input.json (the same steps translated for the model
driver; the translation is documented in README.md).
"""
import ctypes.util, json, os, re, sys, copy

_orig = ctypes.util.find_library
_sodium = os.environ.get("SODIUM_LIB")
if _sodium:
    ctypes.util.find_library = lambda n: _sodium if n in ("sodium", "libsodium") else _orig(n)

from keri import kering
from keri.core import coring, eventing, serdering
from keri.core.signing import Salter
from keri.db import basing

SEED = b"0123456789abcdef"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("ADMISSION_OUT") or os.getcwd()
salter = Salter(raw=SEED)
_signers = {}


def signers(name, count, transferable=True):
    key = (name, count, transferable)
    if key not in _signers:
        _signers[key] = salter.signers(count=count, path=name, transferable=transferable, temp=True)
    return _signers[key]


def digest(signer):
    return coring.Diger(ser=signer.verfer.qb64b).qb64


# ------------------------------------------------------------------ events
def finish(sad, self_addressing_prefix=False):
    """Wire bytes of `sad` with a correct size and SAID."""
    sad = copy.deepcopy(sad)
    sad["d"] = "#" * 44
    if self_addressing_prefix:
        sad["i"] = "#" * 44
    sad["v"] = "KERI10JSON000000_"
    size = len(json.dumps(sad, separators=(",", ":")).encode())
    sad["v"] = "KERI10JSON%06x_" % size
    said = coring.Diger(ser=json.dumps(sad, separators=(",", ":")).encode(), code=coring.MtrDex.Blake3_256).qb64
    sad["d"] = said
    if self_addressing_prefix:
        sad["i"] = said
    return json.dumps(sad, separators=(",", ":")).encode()


def sad_of(raw):
    return json.loads(raw)


def icp(keys, kt="1", ndigs=(), nt="1", wits=(), toad=0, basic=False):
    sad = {"v": "", "t": "icp", "d": "", "i": keys[0] if keys else "", "s": "0", "kt": kt, "k": list(keys),
           "nt": nt, "n": list(ndigs), "bt": str(toad), "b": list(wits), "c": [], "a": []}
    return finish(sad, self_addressing_prefix=not basic)


def rot(pre, prior, sn, keys, kt="1", ndigs=(), nt="1", wits_cut=(), wits_add=(), toad=0):
    sad = {"v": "", "t": "rot", "d": "", "i": pre, "s": str(sn), "p": prior, "kt": kt, "k": list(keys),
           "nt": nt, "n": list(ndigs), "bt": str(toad), "br": list(wits_cut), "ba": list(wits_add), "a": []}
    return finish(sad)


def ixn(pre, prior, sn):
    return finish({"v": "", "t": "ixn", "d": "", "i": pre, "s": str(sn), "p": prior, "a": []})


# ------------------------------------------------------------------ the keripy run
def classify(exc):
    name = type(exc).__name__
    msg = re.sub(r" at 0x[0-9a-f]+", "", str(exc).replace("\n", " "))[:160]
    pending = (kering.MissingSignatureError, kering.MissingWitnessSignatureError,
               kering.OutOfOrderError, kering.MissingDelegationError,
               kering.MissingDelegableApprovalError, kering.UnverifiedWitnessReceiptError)
    return ("escrowed" if isinstance(exc, pending) else "refused"), name, msg


def sign_with(t, raw):
    """One indexed signature of the step tuple (signer, index)."""
    return t[0].sign(raw, index=t[1], only=False)


def step_result(db, kvy, raw, sig_by, wit_by):
    """Process one event; return the outcome and the facts that identify it."""
    try:
        serder = serdering.SerderKERI(raw=raw)
    except Exception as exc:
        return {"outcome": "refused-at-parse", "class": type(exc).__name__, "detail": str(exc).replace("\n", " ")[:160],
                "said": sad_of(raw).get("d"), "pre": sad_of(raw).get("i"), "sn": sad_of(raw).get("s"), "ilk": sad_of(raw).get("t")}
    sigers = [sign_with(t, serder.raw) for t in sig_by]
    wigers = [sign_with(t, serder.raw) for t in wit_by] or None
    facts = {"said": serder.said, "pre": serder.pre, "sn": serder.sn, "ilk": serder.ilk}
    try:
        kvy.processEvent(serder=serder, sigers=sigers, wigers=wigers)
    except Exception as exc:
        out, cls, msg = classify(exc)
        return {"outcome": out, "class": cls, "detail": msg, "escrowIndex": escrow_index(db, serder), "readback": readback(db, serder), **facts}
    rb = readback(db, serder)
    if rb["logged"]:
        return {"outcome": "accepted", "class": "", "detail": "", "readback": rb, **facts}
    return {"outcome": "unknown", "class": "", "detail": "no exception raised and the event is not in the key event log",
            "escrowIndex": escrow_index(db, serder), "readback": rb, **facts}


def readback(db, serder):
    """The key event log's own record of this exact event: the SAID at its sequence number and the stored bytes."""
    at_sn = db.getKeLast(eventing.snKey(serder.pre, serder.sn))
    stored = db.getEvt(eventing.dgKey(serder.pre, serder.said))
    said_ok = at_sn is not None and bytes(at_sn).decode() == serder.said
    bytes_ok = stored is not None and bytes(stored) == bytes(serder.raw)
    return {"saidAtSn": bytes(at_sn).decode() if at_sn is not None else None, "storedBytesEqual": bytes_ok, "logged": said_ok and bytes_ok}


def escrow_index(db, serder):
    """Which of keripy's escrow indexes holds this event (by SAID at its sequence number)."""
    key = eventing.snKey(serder.pre, serder.sn)
    out = {}
    for name, getter in (("partial-signatures", db.getPses), ("partial-witness-receipts", db.getPwes), ("out-of-order", db.getOoes)):
        try:
            out[name] = any(bytes(v).decode() == serder.said for v in getter(key))
        except Exception as exc:  # an index that cannot be read is evidence of nothing
            out[name] = "unreadable: " + type(exc).__name__
    return out


def run_steps(steps):
    results = []
    with basing.openDB(name="adm", temp=True) as db:
        kvy = eventing.Kevery(db=db, lax=False, local=False)
        for st in steps:
            r = step_result(db, kvy, st["raw"], st.get("sig_by", []), st.get("wit_by", []))
            r["label"] = st["label"]
            r["raw"] = st["raw"].decode()
            r["role"] = st.get("role", "context")
            results.append(r)
    return results


# ------------------------------------------------------------------ lineages and cases
class Line:
    """One identifier's events as the cases build them; keeps the SAID chain."""

    def __init__(self, name, n=2, kt=None, nt=None, wits=0, toad=0):
        self.name = name
        self.cur = signers(name + "-cur", n)
        self.nxt = signers(name + "-nxt", n)
        self.nn = signers(name + "-nn", n)
        self.w = signers(name + "-wit", max(wits, 1), transferable=False)[:wits] if wits else []
        self.kt = kt if kt is not None else str(n)
        self.nt = nt if nt is not None else str(n)
        self.toad = toad
        self.raw_icp = icp([s.verfer.qb64 for s in self.cur], kt=self.kt, ndigs=[digest(s) for s in self.nxt], nt=self.nt,
                           wits=[w.verfer.qb64 for w in self.w], toad=toad)
        sad = sad_of(self.raw_icp)
        self.pre, self.last = sad["i"], sad["d"]


def idx(signer_list, which):
    return [(signer_list[i], i) for i in which]


def wit_all(line):
    return [(w, i) for i, w in enumerate(line.w)]


CASES = []


def case(cid, stage, family, title, build):
    CASES.append({"id": cid, "stage": stage, "family": family, "title": title, "build": build})


def full_icp(L):
    return {"label": "icp", "role": "context", "raw": L.raw_icp, "sig_by": idx(L.cur, range(len(L.cur))), "wit_by": wit_all(L)}


def first_rot(L, **kw):
    kw.setdefault("keys", [s.verfer.qb64 for s in L.nxt])
    kw.setdefault("kt", L.kt)
    kw.setdefault("ndigs", [digest(s) for s in L.nn])
    kw.setdefault("nt", L.nt)
    return rot(L.pre, L.last, 1, **kw)


def subject(label, raw, sig_by, wit_by=(), role="subject"):
    return {"label": label, "role": role, "raw": raw, "sig_by": sig_by, "wit_by": list(wit_by)}


# ---- inceptions
def inception(cid, title, **kw):
    n = kw.pop("n", 2)
    sig = kw.pop("sig", None)
    basic = kw.pop("basic", False)

    def build():
        cur = signers(cid + "-cur", n)
        nxt = signers(cid + "-nxt", n)
        raw = icp([s.verfer.qb64 for s in cur], kt=kw.get("kt", str(n)), ndigs=[digest(s) for s in nxt], nt=kw.get("nt", str(n)), basic=basic)
        which = list(range(n)) if sig is None else sig
        return [subject("icp", raw, idx(cur, which))]
    case(cid, "inception", "inception", title, build)


inception("I01", "1-of-1 inception, basic prefix", n=1, basic=True)
inception("I02", "2-of-3 integer threshold, all three sign", n=3, kt="2", nt="2")
inception("I03a", "weighted 1/2,1/2,1/2: keys 0 and 1 sign", n=3, kt=["1/2", "1/2", "1/2"], nt=["1/2", "1/2", "1/2"], sig=[0, 1])


# ---- rotations (against the inception as predecessor)
def lineage_case(cid, stage, family, title, mk, **line_kw):
    def build():
        return mk(Line(cid, **line_kw))
    case(cid, stage, family, title, build)


def sign_new(L, which=None):
    return idx(L.nxt, range(len(L.nxt)) if which is None else which)


lineage_case("R01", "rotation", "rotation", "2-of-2 rotation signed by both revealed keys",
             lambda L: [full_icp(L), subject("rot", first_rot(L), sign_new(L))])
lineage_case("R07", "rotation", "rotation", "prior next threshold 1 of 2: one revealed key rotates",
             lambda L: [full_icp(L), subject("rot", first_rot(L, keys=[L.nxt[0].verfer.qb64], kt="1"), idx(L.nxt, [0]))],
             nt="1")
lineage_case("R08a", "rotation", "rotation", "prior next threshold [1/2,1/2]: both revealed keys sign",
             lambda L: [full_icp(L), subject("rot", first_rot(L), sign_new(L))], nt=["1/2", "1/2"])
lineage_case("R10c", "rotation", "rotation", "rotation weighted threshold, both keys sign, weights [1/2,1/2]",
             lambda L: [full_icp(L), subject("rot", first_rot(L, kt=["1/2", "1/2"]), sign_new(L))])
lineage_case("R17", "rotation", "rotation", "rotation to an empty next commitment (abandonment), next threshold 0",
             lambda L: [full_icp(L), subject("rot", first_rot(L, ndigs=[], nt="0"), sign_new(L))])
lineage_case("R18", "rotation", "rotation", "prior next threshold 1 of 2; revealed keys are one committed key and one new key, both sign",
             lambda L: [full_icp(L), subject("rot", first_rot(L, keys=[L.nxt[0].verfer.qb64, L.nn[0].verfer.qb64], kt="2"),
                                             [(L.nxt[0], 0), (L.nn[0], 1)])], nt="1")

# ---- rotations with witnesses
_extra_witnesses = lambda: signers("W-extra", 2, transferable=False)


def wrot(L, cuts, adds, toad, receipts):
    X = _extra_witnesses()
    raw = first_rot(L, wits_cut=[L.w[i].verfer.qb64 for i in cuts], wits_add=[X[i].verfer.qb64 for i in adds], toad=toad)
    return [full_icp(L), subject("rot", raw, sign_new(L), receipts(L, X))]


def rcpt(cuts, adds, which):
    def f(L, X):
        d = [w for i, w in enumerate(L.w) if i not in cuts] + [X[i] for i in adds]
        return [(d[i], i) for i in which]
    return f


lineage_case("W01", "rotation", "rotation", "cut one, add one, toad 2, receipts from both of the derived witnesses",
             lambda L: wrot(L, [0], [0], 2, rcpt([0], [0], [0, 1])), wits=2, toad=2)
lineage_case("W09", "rotation", "rotation", "no witness change, toad kept, receipts from both",
             lambda L: wrot(L, [], [], 2, rcpt([], [], [0, 1])), wits=2, toad=2)


# ---- interactions
lineage_case("X01", "interaction", "interaction", "interaction signed by the current keys",
             lambda L: [full_icp(L), subject("ixn", ixn(L.pre, L.last, 1), idx(L.cur, [0, 1]))])
lineage_case("X07", "interaction", "interaction", "interaction after a rotation, signed by the rotated keys",
             lambda L: (lambda r: [full_icp(L), {"label": "rot", "role": "context", "raw": r, "sig_by": sign_new(L), "wit_by": []},
                                   subject("ixn", ixn(L.pre, sad_of(r)["d"], 2), sign_new(L))])(first_rot(L)))


# ------------------------------------------------------------------ translation for the model driver
_ids = {}


def kid(qb64):
    if qb64 not in _ids:
        _ids[qb64] = len(_ids) + 1
    return _ids[qb64]


def frac(text):
    t = str(text)
    if "/" in t:
        a, b = t.split("/", 1)
        return [int(a), int(b)]
    return [int(t), 1]


def threshold_json(sith):
    """The model's `Threshold` from the wire's kt/nt (a string count or a weight list)."""
    if isinstance(sith, int) or (isinstance(sith, str) and not sith.startswith("[")):
        try:
            return {"count": int(str(sith), 16)}
        except ValueError:
            return {"unparsed": str(sith)}
    clauses = sith if sith and isinstance(sith[0], list) else [sith]
    out = []
    for clause in clauses:
        row = []
        for w in clause:
            if isinstance(w, dict):
                (outer, inner), = w.items()
                row.append({"group": [frac(outer), [frac(x) for x in inner]]})
            else:
                row.append({"key": frac(w)})
        out.append(row)
    return {"weighted": out}


def digest_of(qb64):
    return coring.Diger(ser=qb64.encode()).qb64


def opened(digs, universe):
    """Digest list as identities: a digest is the identity of the key that opens it, else a fresh one."""
    table = {digest_of(k): k for k in universe}
    return [kid(table[d]) if d in table else kid("unopened:" + d) for d in digs]


def content_json(sad, universe):
    seals = [json.dumps(x, sort_keys=True, separators=(",", ":")) for x in sad.get("a", [])] + \
            [json.dumps(x, sort_keys=True, separators=(",", ":")) for x in sad.get("c", [])]
    return {
        "aid": kid(sad["i"]), "sn": int(sad["s"], 16), "kind": {"icp": "inception", "rot": "rotation", "ixn": "interaction"}[sad["t"]],
        "priorDigest": kid("said:" + sad.get("p", "")), "keys": [kid(k) for k in sad.get("k", [])],
        "threshold": threshold_json(sad.get("kt", "1")), "nextKeys": opened(sad.get("n", []), universe),
        "nextThreshold": threshold_json(sad.get("nt", "1")), "cuts": [kid(w) for w in sad.get("br", [])],
        "adds": [kid(w) for w in sad.get("ba", [])], "witnessThreshold": int(sad.get("bt", "0"), 16),
        "extension": [kid("seal:" + s) for s in seals]}


def lean_rows(case, steps, results):
    """One model row per rotation step whose predecessor is the inception that keripy persisted."""
    rows = []
    universe = set()
    for st in steps:
        sad = sad_of(st["raw"])
        universe.update(sad.get("k", []))
        universe.update(sad.get("b", []) + sad.get("ba", []) + sad.get("br", []))
    prior = None  # (inception sad, derived witnesses)
    last_said = None  # SAID of the last event keripy persisted: the link a rotation's `p` names
    for st, res in zip(steps, results):
        sad = sad_of(st["raw"])
        if sad["t"] == "icp" and st["role"] == "context":
            if res["outcome"] == "accepted":
                prior = {"sad": sad, "wits": list(sad.get("b", []))}
                last_said = sad["d"]
            continue
        if st["role"] == "subject":
            if prior is None:
                rows.append({"case": case["id"], "step": st["label"], "role": st["role"], "comparable": False, "reason": "no persisted predecessor"})
                continue
            psad = prior["sad"]
            if sad["t"] != "rot":
                rows.append({"case": case["id"], "step": st["label"], "role": st["role"], "comparable": False,
                             "reason": "the model's admission surface is the rotation (rotationValid); interactions and inceptions have none"})
                continue
            signatures = []
            for t in st["sig_by"]:
                key = sad["k"][t[1]] if t[1] < len(sad["k"]) else "out-of-range:%d" % t[1]
                signatures.append({"signer": kid(key), "verified": key == t[0].verfer.qb64})
            derived = prior["wits"]
            derived_after = [w for w in derived if w not in sad.get("br", [])]
            for w in sad.get("ba", []):
                if w not in derived_after:
                    derived_after.append(w)
            receipts = []
            for t in st["wit_by"]:
                w = derived_after[t[1]] if t[1] < len(derived_after) else "out-of-range"
                receipts.append({"signer": kid(w), "verified": w == t[0].verfer.qb64})
            content = content_json(sad, universe | set(sad.get("k", [])))
            prior_json = {"aid": kid(psad["i"]), "sn": int(psad["s"], 16), "delegated": False,
                          "nextKeys": opened(psad.get("n", []), universe), "nextThreshold": threshold_json(psad.get("nt", "1")),
                          "witnesses": [kid(w) for w in derived]}
            structure = (sad["p"] == last_said and sad["i"] == psad["i"])
            rows.append({"case": case["id"], "step": st["label"], "role": st["role"], "comparable": True, "prior": prior_json,
                         "signed": {"event": content, "structureVerified": structure, "signatures": signatures, "receipts": receipts},
                         "keripy": res["outcome"]})
        if res["outcome"] == "accepted" and st["role"] == "context":
            last_said = sad["d"]
        if res["outcome"] == "accepted" and sad["t"] == "rot" and st["role"] == "context":
            prior = {"sad": sad, "wits": [w for w in prior["wits"] if w not in sad.get("br", [])] + [w for w in sad.get("ba", []) if w not in prior["wits"]]}
    return rows


def main():
    results, lean = [], []
    for c in CASES:
        steps = c["build"]()
        res = run_steps(steps)
        results.append({"id": c["id"], "stage": c["stage"], "family": c["family"], "title": c["title"], "steps": res})
        lean.extend(lean_rows(c, steps, res))
    json.dump({"keripy": "1.3.5", "cases": results}, open(os.path.join(OUT, "keripy-results.json"), "w"), indent=1)
    json.dump({"rows": lean}, open(os.path.join(OUT, "lean-input.json"), "w"), indent=1)
    for c in results:
        last = c["steps"][-1]
        print("%-5s %-11s %-9s %-16s %s" % (c["id"], c["family"], last["role"], last["outcome"], (last["class"] + " " + last["detail"])[:70]))


if __name__ == "__main__":
    main()
