# Data and invariant register

Preservation is released by desk A-004 and epic A-003; gate admission is pending.

| Invariant | Preserved data/relationship | Failure meaning |
|---|---|---|
| INV-319-BIND | Evidence raw bytes, offsets and fields; ordered binder errors; unchanged signature targets | A mismatched span/field yields accepted decoded evidence |
| INV-319-CONVICT | Tip/evidence AID, sequence, revealed keys, controller quorum, distinct verifying witness receipts, forward commitment conflict | Honest evidence convicts or invalid/quorumless/unwitnessed evidence convicts |
| INV-319-RETIRED | Current operation/compiled/build extent excludes retired economy and skeleton | A current artifact still admits or exposes retired settlement |
| INV-319-MIGRATION | Existing source/target identity, value and signature binding | Preserve existing old-role decoding and role/payload/value continuity; never claim this proves immutable deployed-source exits |
| INV-319-MANIFEST | Historical deployed source/hash/reference identity stays distinct from undeployed candidate | Mismatched identity accepted or invented deployment claimed |
| INV-319-MPF | Proof-root/key/value relation executed under locked v2.1.0 | Malformed proof accepted, valid preserved case lost, or zero selection passes |
| INV-319-EXTENT | Every discovered shipped program and use purpose reconciles to real application inputs | Unknown, duplicate, omitted or empty population passes |
| INV-319-FIT | Applied byte size <16384 and carrying transaction obeys bound ledger byte/ex-unit limits | Oversize/overbudget/missing path reported as fit |
| INV-319-FENCE | Root Lean semantics and sibling-owned surfaces unchanged until explicit handoff | Scope widened through dependency convenience |

Severity BLOCKING throughout. New current-candidate manifest data must not pretend to carry deployed publication time or live reference outputs. Existing V1 constants are measurement inputs; future P/B/W/D_reg remain undecided.
