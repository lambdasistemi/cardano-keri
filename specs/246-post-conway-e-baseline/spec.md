# #246 — post-Conway E baseline and stranger evidence-bundle skeleton

Parent epic: #190. Milestone 8. Anchor: `main`
`fe535810d7bb7a343b0cb30c950c43ea356105e7`.

## Outcome

One frozen P0 execution identity — `COMMIT + TOOLCHAIN + VARIANT`, target
`PlutusV3 / post-Conway / defaultFunSemanticsVariantE` — plus the skeleton of
an evidence bundle a stranger can re-derive from a fresh checkout.

Every later #190 theorem ticket binds its records to this identity. Nothing
here proves a P0 security claim; this ticket establishes what a proof would
have to be *about*, and proves that establishment can fail.

## Vocabulary

Unchanged from the epic: `KERNEL-PROVED`, `SMT-VALID (no proof term)`,
`TESTED`, `UNPROVED`, `OUT-OF-SCOPE`, `OUT-OF-SCOPE-BY-FORM`. Independent of
disposition, every assertion attempt emits exactly one `evaluation_outcome`:
`ESTABLISHED`, `REFUTED`, or `COULD-NOT-EVALUATE`. The third is RED, names the
layer that failed, and is never "no counterexample found".

## Requirements

| ID | Requirement |
|---|---|
| R-01 | The baseline identity is anchored at commit `fe535810…`, at the Aiken toolchain the repository itself validates with, and at variant E. All three values are announced together wherever the baseline is named. |
| R-02 | Before any evidence is regenerated, a read-only compatibility audit resolves every reference the tracked bridge source makes into its pinned upstream Lean packages. It reports a resolution count, carries a positive control proving the resolver finds references that exist, and carries a seeded retired-reference negative control proving it reports references that do not. |
| R-03 | If compatibility requires bridge source changes, those changes are frozen as a new bridge source and manifest identity before any evidence is generated from them. A byte-verified pin is not compatibility evidence and never substitutes for R-02. |
| R-04 | The baseline manifest covers all 23 blueprint titles and 8 distinct compiled programs, and records for each: exact title, declared parameter count, and `program_sha256`; and for the whole manifest: blueprint SHA-256, source commit, Aiken version, upstream pin identities, `PlutusV3`, protocol era, and `BuiltinSemanticsVariant`. Every value is computed from the artifact; none may be satisfied by a literal. |
| R-05 | The evidence bundle is produced and verified from a fresh checkout by someone with no access to this worktree, this machine's Nix store, or desk knowledge. A claim that cannot be re-derived that way is an assertion, not evidence. |
| R-05a | The bundle's contents are enumerated from an explicit declared inventory. Tracked-file enumeration may contribute to that inventory but may not define it: **untracked means uncovered** is the default, and the burden of demonstrating coverage is on the mechanism, never on a reader noticing an absence. |
| R-05b | A declared artifact missing from the assembled bundle is RED — not a warning, not a log line. Declared file modes, including the executable bit, are preserved and asserted. |
| R-05c | The completeness check carries its own falsifier: deliberately omitting one declared artifact is shown RED **before** the clean assembly is shown GREEN. |
| R-05d | The reproduction claim is tested, not asserted: the assembled bundle is executed from a location with no access to this working tree. |
| R-06 | The record schema that downstream tickets must fill exists and is enforced here: one required per-claim falsifiability field pair (`REFUTED` before `ESTABLISHED`, same slice, same frozen identity) and, for the Advance family, two distinctly labelled E records whose distinct purposes are stated in the records themselves. |
| R-07 | Every emitted record carries its `evaluation_outcome`. A missing variant, missing toolchain, unresolved reference, unbuilt artifact, or unread output is `COULD-NOT-EVALUATE` and RED. |
| R-08 | No credential, secret, or network-authenticated resource is in scope. |

## Rejection behaviour

The following are failures, not warnings:

- a manifest row whose value was written down rather than computed;
- a compatibility audit that reports zero unresolved references without having
  demonstrated, in the same run, that it can report a non-zero count;
- any record naming variant C, or naming no variant, offered as baseline
  evidence;
- a control that exists but is not reached by the command the gate runs;
- a bundle step that succeeds only because an artifact is already present in
  the local Nix store;
- a bundle assembled by enumerating the tree rather than a declared inventory,
  or one whose completeness check has never been shown to fail;
- `COULD-NOT-EVALUATE` reported as a pass, a skip, or "no counterexample".

## Observable success

1. The compatibility audit runs from the flake-owned runner, prints its
   resolved/unresolved counts, and both of its controls are exercised by that
   same run.
2. The baseline manifest lists 23 titles over 8 distinct programs with computed
   hashes, and names commit, Aiken version, era, and variant E.
3. Mutating any single manifest input — a title, a program byte, the variant,
   the toolchain — makes the verification exit non-zero and say which.
4. The bundle's own instructions, followed literally against a fresh clone,
   reproduce the manifest and the same triple.

## Historical material

All existing variant C / pre-Conway measurements, and the pre-#219 blueprint
`896d2c46…` with its eight program hashes, remain valid historical evidence of
a different configuration. They are relabelled, never deleted and never
reinterpreted as E. No C record can satisfy a P0 claim.

## Out of scope

Applied/deployed script hashes (W-04), the P0-01..P0-13 security theorems
themselves (#247, #248), the P0-14 production-reaching mutation sweep (#249),
and release publication (#250). This ticket makes those possible and is not
allowed to pre-empt them.
