# Milestone ledger — cardano-keri M1.2 (GitHub milestone 11)

**Snapshot. Current 2026-08-28.** Resurrection reads this file. The narrative
record of everything up to 2026-08-27 is preserved verbatim in
`ledger-history-to-2026-08-27.md` and is not repeated here — burying the snapshot
under archaeology is what this split exists to prevent. Rulings cited below
(A-018, A-019, Q-MS12-00x) live in that history file.

## Outcome and its observable test

**Outcome:** the decomposed record+cursor family — the M1-terminal redesign as
deployable validators, delivered as usable packaged executables on the provisional
`ckeri` line.

**Observable test:** every family member compiles within the per-script ceilings
with stated headroom, each sits behind an immutable can-fail gate on the INV-BIND
pattern, and **a stranger can obtain and run the packaged `ckeri` artifact**.
Counting closed children is the vacuous pass and is not accepted.

**Status:** architectural experiment until its gates pass. The experiment claims
policy is in force for every external word.

## The burn-down is misleading, deliberately recorded as such

GitHub shows **one open issue** (#300) on this milestone. Closing it would satisfy
the counter and none of the test. What actually stands between #300 and a closed
milestone is in the unit table below: three of four requirement slices have no lane,
the fourth is parked, S3 is withheld, and the artifact has shipped nothing from this
milestone.

## Units

| unit | state | detail |
|---|---|---|
| S0 — size fail-fast | ✅ merged | `main` `84e3b7159115e9169b57a85cbf9053b94aa889ba` |
| S1 — harness quality | ✅ released, executed | |
| DESIGN NOTE 001 | ✅ merged | PR #301, blob `918e4289eb71a5f12199d2eda02305c6746e0448`, 4 `[OPEN]` / 7 `[settled]` intact |
| #300 requirements contract | ✅ accepted, ⏳ unmerged | commit `0cfc9c282247f2910f3c45295b8b81ba6d334275`; submission 1, zero repairs; fresh independent audit PASS 8/8; **PR #306 draft**, #300 **open** |
| R1 — event-derived key | ⛔ parked | PR #305 draft; builds 5/5 with a granted unspent sixth; frozen gate v4 unsatisfiable by any candidate; v8 draft unfrozen, composition question open |
| R2 / R3 / R4 | ⏳ no lane | mandates staged, pinned by `refs/tags/ms11/mandates/a-019`; each names its predecessor, so they serialize behind R1 |
| S3 — preprod lineage drill | ⛔ withheld | needs a second written release naming every write |
| DESIGN NOTE 002 | 🟡 received, unlanded | captured 2026-08-28, sha256 `d52923f6ab3f343c7413c12768dd127d60fa2dc1bfe5d2357fc4a36c793d676a`; addressed to this desk to accept, amend or discard |
| `ckeri` artifact | ❓ | v0.4.0 shipped 2026-08-04, **before** this milestone was founded 2026-08-18. Nothing since |

## Priority order, with reasons

1. **DN-002 disposition** — it is unlanded evidence naming a regression (F-2); the
   longer it sits in `/tmp`-adjacent space the more likely it dies with a host, which
   is exactly what #300 existed to prevent for DN-001.
2. **R1's gate ruling** (`Q-MS12-004` lineage) — it blocks R2/R3/R4 by construction,
   so it is the only thing whose delay costs three slices rather than one.
3. **PR #306 merge decision** — cheap, but deliberately held: merging it makes the
   burn-down read complete.
4. **Witnessing documentation** — an external reviewer already hit this gap.
5. **`ckeri` release carrying milestone content** — the outcome test's second half.

## Parked decisions, and what unblocks each

| item | unblocked by |
|---|---|
| the 4 `[OPEN]` items in DN-001 | operator ruling only; still open by explicit order 2026-08-28 |
| DN-002's `[OPEN]` items (rung-4 pricing, the designated-payee lever, out-graded kill switch) | operator; none of them blocks stating requirements |
| new issues for R2/R3/R4 or DN-002 | `RELEASE-015` holds issue mutations; the grant that produced #300 covered exactly one issue |
| merge of PR #306, closing #300 | operator; withheld by this desk on the burn-down argument above |
| S3 | a second written machine release |
| R1's frozen gate | the gate-version ruling, then a gate proven able to fail in both directions |

## Pause and release history relevant to resurrection

- `OMNIA PAUSA 2026-08-24T14:20Z` — first; **never fully released**. Still governs R1,
  PR #305, and the withheld set.
- `RELEASE-M12-300-PUSH-2026-08-27` — narrow operator release, #300 push/PR only.
- `OMNIA PAUSA 2026-08-27T17:42Z` — second.
- `RELEASE-2026-08-28T1104Z-keri-m12` — this session only; the omnia pausa stays in
  force for reactivegas, treasury-ms1, 0-projects and session 0.

A future RELEASE should say **which** order it lifts. Silence between the two has
already cost this milestone once.

## Registry

See `registry.md`. Live `enforced: NONE` entries at this snapshot, worst first:

1. **#271 entitlement absent from the m12 escrow** — a regression, not a gap.
2. **what witnesses are for** — DN-002 §6 and the pen construction, unreconciled.
3. **the published witnessing story** — every repo design doc predates 2026-08-18.
4. **cursor-verdict vs witness-receipting policy** — the first-seen layering.

Resolved this snapshot: **mandate-pin**, `NONE` → `TAG`
(`refs/tags/ms11/mandates/a-019`).
