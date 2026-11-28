#!/usr/bin/env python3
"""Join the comparison outputs of one run into the matrix, and fail the run when anything is missing.

    python matrix.py <evidence directory> <output directory>

Inputs (all written by run.sh): keripy-results.json, comparison.json, advance-comparison.json,
registration-comparison.json, thresholds-comparison.json, aiken-*.txt.
Outputs: MATRIX.md, matrix.json, completeness.txt. Nothing is written when a completeness check fails.

Relations: "same verdict" (keripy and the layer admit, or both do not), "DISAGREEMENT" (different verdicts on
matching inputs), "no like surface" (the layer has no admission predicate for that kind of event).
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import keripy_admission as K  # noqa: E402  (the corpus definitions: the expected cases)
import thresholds as T  # noqa: E402
import registration as R  # noqa: E402
import advance as A  # noqa: E402
from receipts import threshold_results, verdicts  # noqa: E402

ev, outdir = sys.argv[1], sys.argv[2]
load = lambda n: json.load(open(os.path.join(ev, n)))
keripy = load("keripy-results.json")["cases"]
model = load("comparison.json")
advance_list = load("advance-comparison.json")
registration_list = load("registration-comparison.json")
advance = {r["case"]: r for r in advance_list}
registration = {r["case"]: r for r in registration_list}
thresholds = load("thresholds-comparison.json")
TRACK = {"I01": "#590", "R17": "#591"}
problems = []


def exact(what, found, expected):
    """The found identifiers are exactly the expected ones, each once."""
    dups = sorted({x for x in found if list(found).count(x) > 1})
    missing = sorted(set(expected) - set(found))
    extra = sorted(set(found) - set(expected))
    if dups:
        problems.append("%s: repeated %s" % (what, dups))
    if missing:
        problems.append("%s: missing %s" % (what, missing))
    if extra:
        problems.append("%s: unexpected %s" % (what, extra))


# the fixtures every layer must answer for, taken from the corpus definitions themselves
EXPECTED_EVENTS = [c["id"] for c in K.CASES]
EXPECTED_THRESHOLDS = [c[0] for c in T.CASES]
EXPECTED_MODEL = [(c["id"], "subject") for c in K.CASES]
EXPECTED_REGISTRATION = [c["id"] for c, st, sad in R.cases()]
EXPECTED_ADVANCE = [c["id"] for c, st, icp in A.rows()]


def relation(direction):
    if direction.startswith("agree"):
        return "same verdict"
    if direction.startswith("not comparable"):
        return "no like surface"
    if direction.startswith("WE-"):
        return "DISAGREEMENT"
    problems.append("unrecognized direction: " + direction)
    return "unrecognized"


rows = []
# 1. the keripy receipts hold exactly the corpus; every step it persisted has an exact log readback (context steps included)
exact("keripy results", [c["id"] for c in keripy], EXPECTED_EVENTS)
for c in keripy:
    for st in c["steps"]:
        if st["outcome"] == "accepted":
            rb = st.get("readback") or {}
            if not (rb.get("logged") and rb.get("saidAtSn") == st["said"] and rb.get("storedBytesEqual")):
                problems.append("%s: step %s is accepted without a consistent log readback" % (c["id"], st["label"]))
        elif st["role"] == "context":
            problems.append("%s: context step %s was not persisted: the case is not a valid positive control" % (c["id"], st["label"]))
        elif st["outcome"] == "escrowed" and "escrowIndex" not in st:
            problems.append("%s: escrowed without an escrow index entry" % c["id"])
    if c["steps"][-1]["role"] != "subject":
        problems.append("%s: no subject step" % c["id"])


def kdesc(r):
    return r["keripy"] + (": " + r["keripyClass"] if r["keripyClass"] else "")


# 2. the model layer: one row per subject step
by_case = {c["id"]: c for c in keripy}
exact("model rows", [(m["case"], m["role"]) for m in model], EXPECTED_MODEL)
for m in model:
    rows.append({"case": m["case"], "layer": "model (Lean, decoded inputs)", "input": "%s sn %s %s" % (m["ilk"], m["sn"], (m["said"] or "")[:12]),
                 "what": m["title"], "keripy": kdesc(m), "layer_result": m["model"], "relation": relation(m["direction"]), "tracker": TRACK.get(m["case"], "")})

# 3. the chain layers: every inception and every first rotation has a typed verdict
exact("registration rows", [r["case"] for r in registration_list], EXPECTED_REGISTRATION)
exact("advance rows", [r["case"] for r in advance_list], EXPECTED_ADVANCE)
exact("threshold rows", [t["id"] for t in thresholds], EXPECTED_THRESHOLDS)
# the transcripts again, read here and compared with the verdicts the comparison carried
for fname, prefix, src, allowed in (("aiken-registration.txt", "reg_", registration, ["Valid", "R4InceptionInvalid"] + R.ERRORS),
                                    ("aiken-advance.txt", "adv_", advance, ["Valid", "AdvReceiptQuorumUnsatisfied", "Eq8CreatedIllFormed"] + A.MSG + A.EVT)):
    try:
        seen = verdicts(os.path.join(ev, fname), prefix, list(src), allowed)
    except SystemExit as exc:
        problems.append(str(exc))
        continue
    for cid, r in src.items():
        if seen.get(cid) != r["chain"]:
            problems.append("%s: the comparison carries %s, the transcript %s" % (cid, r["chain"], seen.get(cid)))
try:
    threshold_results(os.path.join(ev, "aiken-thresholds.txt"), load("thresholds.json")["cases"])
except SystemExit as exc:
    problems.append(str(exc))
for tag, src, layer in (("reg", registration, "Aiken registration_predicate"), ("adv", advance, "Aiken advance_predicate")):
    for cid, r in src.items():
        if r["chain"] in ("", "no evidence built"):
            problems.append("%s: %s has no typed verdict" % (cid, layer))
        rows.append({"case": cid, "layer": layer, "input": "", "what": r["title"], "keripy": kdesc(r), "layer_result": r["chain"],
                     "relation": relation(r["direction"]), "tracker": TRACK.get(cid, "")})
for cid, c in by_case.items():
    fam = c["family"]
    if fam == "inception" and cid not in registration:
        problems.append("%s: inception without a registration verdict" % cid)
    if fam == "rotation" and cid not in advance and not any(s["role"] == "context" and s["ilk"] == "rot" for s in c["steps"]):
        problems.append("%s: rotation without an advance verdict" % cid)

# 4. thresholds: keripy, model, codec
for t in thresholds:
    if not t["lean"] or t["lean"] == "no row":
        problems.append("%s: no model result" % t["id"])
    if not t["aiken"] or "not representable" in t["aiken"]:
        problems.append("%s: not held by the codec" % t["id"])
    rows.append({"case": t["id"], "layer": "threshold (model and codec)", "input": json.dumps(t["sith"]) + " over %d keys" % t["n"], "what": "",
                 "keripy": t["keripy"], "layer_result": "model: " + t["lean"] + "; codec: " + t["aiken"],
                 "relation": "same verdict" if t["direction"] == "agree" else "DISAGREEMENT", "tracker": ""})

if problems:
    sys.stderr.write("matrix: completeness checks failed\n" + "\n".join(" - " + p for p in problems) + "\n")
    sys.exit(1)

os.makedirs(outdir, exist_ok=True)
tally = {}
for r in rows:
    tally[r["relation"]] = tally.get(r["relation"], 0) + 1
md = ["# Ordinary admission matrix (generated by matrix.py from one run; do not edit)\n",
      "Event cases: %d. Threshold cases: %d. Rows: %d. Tally by relation: %s\n" % (len(keripy), len(thresholds), len(rows), json.dumps(tally, sort_keys=True)),
      "| case | layer | input | what it tests | keripy 1.3.5 | layer result | relation | ticket |", "|---|---|---|---|---|---|---|---|"]
for r in rows:
    md.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (r["case"], r["layer"], r["input"], r["what"], r["keripy"], r["layer_result"], r["relation"], r["tracker"]))
open(os.path.join(outdir, "MATRIX.md"), "w").write("\n".join(md) + "\n")
json.dump({"tally": tally, "rows": rows}, open(os.path.join(outdir, "matrix.json"), "w"), indent=1)
open(os.path.join(outdir, "completeness.txt"), "w").write("completeness checks passed\nevent cases %d, threshold cases %d, rows %d\n" % (len(keripy), len(thresholds), len(rows)))
print(json.dumps(tally, sort_keys=True))
