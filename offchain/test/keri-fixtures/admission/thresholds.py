#!/usr/bin/env python3
"""Ordinary thresholds (kt/nt) on their own, every signer subset of every case.

keripy side: `Tholder(sith=...)` (construction is its well-formedness check), `Tholder.size` against the
key count, and `Tholder.satisfy(indices)`. The other layers read the same rows (thresholds.json):
the Lean driver (`Admission.lean thresholds`) evaluates `Threshold.satisfied`, and `gen_aiken_thresholds.py`
writes the Aiken module that asks `threshold.well_formed` and `threshold.evaluate`.
"""
import itertools, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import keripy_admission as K  # noqa: E402  (also fixes the sodium path before keripy is imported)
from keri.core import coring  # noqa: E402

D32 = "4294967296"
CASES = [
    ("T01", "1", 1), ("T02", "2", 3), ("T03", "3", 3),
    ("T06", ["1/2", "1/2"], 2), ("T07", ["1/2", "1/2", "1/2"], 3), ("T08", ["1/3", "1/3", "1/3"], 3),
    ("T09", ["1/3", "1/3", "1/3", "1/3"], 4), ("T10", ["1/2", "1/4", "1/4"], 3), ("T14", ["1"], 1),
    ("T18", [["1/2", "1/2"], ["1/3", "1/3", "1/3"]], 5), ("T19", [["1/2", "1/2"], ["1"]], 3),
    ("T26", ["1/" + D32, "4294967295/" + D32], 2), ("T28", ["1/2", "1/2", "1/4", "1/4", "1/4", "1/4"], 6),
    ("T30", ["1/1", "1/1"], 2),
]


def tholder(sith):
    try:
        return coring.Tholder(sith=sith), None
    except Exception as exc:
        return None, "%s: %s" % (type(exc).__name__, str(exc).replace("\n", " ")[:120])


def main():
    out = os.environ.get("ADMISSION_OUT") or os.getcwd()
    rows = []
    for cid, sith, n in CASES:
        t, err = tholder(sith)
        row = {"id": cid, "sith": sith, "n": n, "threshold": K.threshold_json(sith)}
        if t is None:
            row["keripy"] = {"constructed": False, "error": err}
        else:
            fits = (t.size == n) if t.weighted else (t.num <= n)
            row["keripy"] = {"constructed": True, "weighted": t.weighted, "size": t.size, "appliesToKeyCount": fits,
                             "satisfied": {"".join(str(i) for i in s): bool(t.satisfy(list(s)))
                                           for r in range(n + 1) for s in itertools.combinations(range(n), r)}}
        rows.append(row)
    json.dump({"keripy": "1.3.5", "cases": rows}, open(os.path.join(out, "thresholds.json"), "w"), indent=1)
    print("%d threshold cases" % len(rows))


if __name__ == "__main__":
    main()
