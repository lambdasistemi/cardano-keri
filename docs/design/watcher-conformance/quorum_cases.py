"""Bounded set arithmetic; not a cryptographic or network conformance test."""
import itertools
import json

rows = []
pairs = 0
for n in range(1, 8):
    universe = range(n)
    for m in range(1, n + 1):
        sets = [set(xs) for xs in itertools.combinations(universe, m)]
        assert sets
        overlaps = [len(a & b) for a in sets for b in sets]
        pairs += len(overlaps)
        minimum = min(overlaps)
        assert minimum == max(0, 2 * m - n)
        for f in range(n + 1):
            assert (minimum > f) == (2 * m > n + f)
        rows.append({"N": n, "M": m, "minimum_overlap": minimum})

examples = [
    {"name": "split_honest_pool", "A": [0, 1], "B": [2, 3], "N": 4, "M": 2},
    {"name": "overlapping_quorums", "A": [0, 1], "B": [1, 2], "N": 3, "M": 2},
]
assert len(set(examples[0]["A"]) & set(examples[0]["B"])) == 0
assert len(set(examples[1]["A"]) & set(examples[1]["B"])) == 1

comparisons = []
for name, tip, tip_m, rival, rival_m, receipts in [
    ("tip_accepts_rival_rejects", {0}, 1, {0, 1}, 2, {0}),
    ("rival_accepts_tip_rejects", {0}, 1, {1}, 1, {1}),
]:
    tip_ok = len(tip & receipts) >= tip_m
    rival_ok = len(rival & receipts) >= rival_m
    assert tip_ok != rival_ok
    comparisons.append({"name": name, "tip_set": sorted(tip), "tip_tally": tip_m,
                        "rival_set": sorted(rival), "rival_tally": rival_m,
                        "receipt_signers": sorted(receipts),
                        "tip_passes": tip_ok, "rival_passes": rival_ok})

assert len(rows) == 28 and pairs > 0
print(json.dumps({"kind": "bounded set arithmetic", "configurations": len(rows),
                  "receipt_set_pairs": pairs, "rows": rows, "examples": examples,
                  "non_implication_examples": comparisons}, indent=2))
