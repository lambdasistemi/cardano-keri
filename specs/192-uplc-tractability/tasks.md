# Tasks — exact-UPLC tractability

## Planning and lane bootstrap

- [x] T192-001 read #192, parent #189, constitution, active ruleset, epic map,
  invariant ledger, parent status, and upstream #51 as precedent only
- [x] T192-002 discover/reuse the issue lane and record the exact refreshed base
- [x] T192-003 reserve ignored `.search-board/` and `.orch/` state
- [x] T192-004 run untouched baseline `just ci` and preserve exit/wall/log hash
- [x] T192-005 freeze and falsify the ignored ticket/slice gate
- [x] T192-006 commit/push planning record and open labeled, assigned draft PR

## Slice S1 — pin and exact extraction

- [x] T192-101 add immutable Lean/Blaster/PlutusCoreBlaster/
  CardanoLedgerApiBlaster/Z3/Aiken/nixpkgs lock identities with no mutable pin
- [x] T192-102 cover the existing acceptance-critical Lean CI invocation with
  the pinned Lean identity and record the future raw-revision bump owner
- [x] T192-103 select exactly one non-empty production title with `jq -er`
  from `offchain#plutus-blueprint` and record blueprint/title/program/source/
  lock identities
- [x] T192-104 prove missing, duplicate, renamed, empty, and ambient-blueprint
  controls fail without fallback
- [x] T192-105 establish `just blaster`, `offchain#blaster`, and an invoking
  `offchain#checks.x86_64-linux.blaster` path
- [x] T192-106 obtain PAIR RED/GREEN approval, accept the commit, rerun gate,
  stamp tasks, push, and refresh the PR

## Slice S2 — real imports, purposes, and preparation

S2 closed as a **terminal FAIL, limiting class `builtin support`**, authorised
by milestone answer `A-005`. The unchecked tasks below are bounded by that
result, not skipped: the pinned CEK cannot execute them. They are carried into
the upstream-remediation child ahead of #193–#195. Evidence for every claim
here is the accepted `S2.result` row, gate v2r3
(`a6c833cd82cfefc1f855cff8bcd1a0821833e8becdd0b9c4b3e86f9acc5da41f`) and the
decisive log
(`829f62f062b474ed2ba380d9b230c3dfb57049a95d626b7ada4935ea10f28c59`).

- [x] T192-201 import exact production checkpoint/hash-proof/observer bytes
  with `#import_uplc`
- [ ] T192-202 apply actual parameters followed by one correct V3 context for
  mint, spend, reward, and certify conventions
  — **bounded by the terminal FAIL**: reward did not PASS for any observer;
  `observer_advance` reaches `Blake2b_256`, which the pinned evaluator does not
  implement, and lifecycle/enforcement remain bounded at an earlier dispatch
  failure
- [ ] T192-203 add reward/certify smokes for lifecycle, advance, and enforcement
  observers and prove wrong-purpose RED for each
  — **partially demonstrated, not complete**: `certify` HALT and both
  wrong-purpose controls are RED for all three observers with distinct step
  counts and distinct attributed builtins, but no `reward` smoke passed
- [ ] T192-204 prepare checkpoint and hash-proof at recorded fuel or emit the
  named hard failure class
  — **bounded by the terminal FAIL**: no `S2.prepare` row was emitted and
  hash-proof preparation was never executed; it carries the same
  `Blake2b_256` exposure
- [ ] T192-205 decode actual UPLC and prove pinned Batch-5 `expectedArgs`/CEK
  behavior for every reached builtin, including `xor_bytearray`
  — **bounded by the terminal FAIL**: decoding and the mechanical inventory are
  done, but `xor_bytearray` was never reached, so an every-reached-builtin
  proof cannot be rounded up to it; it stays syntactic-only
- [x] T192-206 publish builtin/preparation/solver-treatment facts without
  claiming uninterpreted crypto semantics
  — the `S2.result` terminal FAIL row plus four explicit `S2.unproved`
  non-claims, with `crypto=UNINTERPRETED semantic_claims=LIMITED`
- [x] T192-207 obtain PAIR RED/GREEN approval, accept the commit, rerun gate,
  stamp tasks, push, and refresh the PR

## Slice S3 — terminal solver envelope and result

S3 is **not implemented and not PASS**. Execution terminates at the accepted S2
builtin-support boundary before preparation is reached, so the solver envelope
was never entered. Each task below is unreachable under the pinned evaluator
and was not executed; each carries to `lambdasistemi/cardano-keri#234` before
#193–#195 may resume. Evidence: the accepted `S2.result` row, gate v2r3
(`a6c833cd82cfefc1f855cff8bcd1a0821833e8becdd0b9c4b3e86f9acc5da41f`) and the
decisive log
(`829f62f062b474ed2ba380d9b230c3dfb57049a95d626b7ada4935ea10f28c59`).

- [ ] T192-301 run the checkpoint dispatch-class property to Valid or a
  counterexample, never Undetermined
  — **unreachable under the accepted terminal FAIL**: not executed; the CEK
  stops at `Blake2b_256` before any property leg runs
- [ ] T192-302 run the checkpoint insufficient-controller-evidence
  signature-class property to Valid or a counterexample, never Undetermined
  — **unreachable under the accepted terminal FAIL**: not executed, same
  boundary
- [ ] T192-303 record artifact/purpose/fuel/options/seed/statistics/timeout/wall/
  hardware/verdict/limiting-class and boundary classification for every leg
  — **unreachable under the accepted terminal FAIL**: no leg ran, so there are
  no per-leg statistics to record; the limiting class is recorded once, at
  ticket level, by `S2.result`
- [ ] T192-304 keep `blasterProven` visible and label Valid only
  `SMT-VALID (no proof term)`
  — **unreachable under the accepted terminal FAIL**: not executed; no
  solver verdict of any kind was produced
- [ ] T192-305 prove the real Nix check fails for a seeded negative and returns
  GREEN only after exact restoration
  — **unreachable under the accepted terminal FAIL**: not executed for the
  solver check; the equivalent discipline was exercised at S2 level, where four
  falsification controls are gate-reachable and each fails through a distinct
  assertion
- [x] T192-306 publish the durable `TRACTABILITY-RESULT`, including PASS/FAIL,
  trust limits, upstream link if proven, and follow-on park/re-scope disposition
  — the one S3 result task the terminal outcome satisfies. Tracked basis: the
  `S2.result` emitter and its gate-reachable assertion in the committed source.
  Published basis: `TRACTABILITY-RESULT: FAIL` in the PR 215 body, with the
  limiting class, pin/program/log identities, the four `UNPROVED` non-claims,
  the trust limits, upstream `input-output-hk/PlutusCoreBlaster#28`, downstream
  `lambdasistemi/cardano-keri#234`, and the parked #193–#195 disposition
- [ ] T192-307 obtain PAIR RED/GREEN approval, accept the commit, rerun gate,
  stamp tasks, push, and refresh the PR
  — **unreachable under the accepted terminal FAIL**: there is no S3
  implementation slice to review; S2's PAIR RED/GREEN approval and acceptance
  are recorded against `T192-207`

## Final ticket acceptance

- [x] T192-401 run the five frozen verification commands from a clean issue
  worktree with complete output, exit, wall time, and hashes
  — run from a fresh clean **tracked** worktree at the exact accepted head,
  with the real flake runner and captured exit status; transcripts, exits, wall
  times and hashes are recorded in the ticket runtime record
- [ ] T192-402 run final `just ci`, commit gate, task/history audit, and verify
  no tracked `gate.sh` or ambient blueprint dependency
  — **partially executed and parent-reconciled**: final `just ci`, the commit
  gate and the ambient-blueprint controls all passed. The tracked-`gate.sh`
  condition is **resolved**: main completed the separate M8-owned legacy gate
  lifecycle, so at this head root `gate.sh` is untracked, is ignored via
  `/gate.sh`, and `.gitignore` carries the accepted blob
  `6c60a6e843f4c983939f8d64a5e36acc92c7fe0d` — verified, and asserted by gate
  v2r4. The unchanged `finalization-audit` therefore now exits `1` **solely**
  because authorised terminal-bounded and final operational tasks remain open.
  That exit is preserved as an honest instrumentation result and is **never**
  recorded as PASS; the parent reconciliation in `A-004` is the closing evidence
- [x] T192-403 verify PR linkage, labels, assignee, living body, pushed HEAD,
  and required CI; mark ready only when all are green
  — read back at `2026-08-03T13:21:31Z` against exact head
  `29ea6987f782e314abd32dc90e60491f9a3a459d` and base
  `ed99d31f86913a7b9d2d63f8ec174c001a06385a`: local = remote = PR head;
  `Closes #192`; labels `feat,experiment`; assignee `paolino`; living body
  carrying `TRACTABILITY-RESULT: FAIL`, `PlutusCoreBlaster#28` and
  `cardano-keri#234`; required CI terminal at `13:20:54Z` with 18 success,
  2 skipped, 0 pending and 0 non-success across 20 checks; `mergeable=MERGEABLE`
  / `CLEAN`. Marked ready only after that readback, then re-read as
  `draft=false state=OPEN`
- [x] T192-404 hand the exact commit and `TRACTABILITY-RESULT` to Epic #189
  for independent acceptance; do not merge
  — accepted by Epic #189 in `A-007` (binding hash) on `A-006` (terms):
  handback `HANDBACK-192-TERMINAL-FAIL.md` at
  `d530662a55dcc2ca433e881a76e1cbf376a3d79d6921091de67a407c40d5f638`, exact
  accepted commit `91e910d997c26516c49bdc275e20615a5e531a99`, literal result
  `TRACTABILITY-RESULT: FAIL`, limiting class `builtin-support` at
  `Blake2b_256` under pin `17cee18a2058790bca36282d82c19146587fb2d1`.
  Not merged; #234 undispatched; #193–#195 parked
