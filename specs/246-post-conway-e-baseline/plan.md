# #246 plan

Base: `fe535810d7bb7a343b0cb30c950c43ea356105e7`. Branch
`feat/246-post-conway-e-baseline`.

## Findings that constrain this plan

Established read-only at the base commit, with the method named so each can be
re-checked:

- **F-01 — the baseline artifact moved.** The blueprint the repository compiles
  at this commit, with the Aiken version the repository validates with, is not
  the blueprint the M8 phase-1 inventory froze. Cardinality is unchanged (23
  titles, 8 distinct `compiledCode`), but sampled per-title program hashes all
  differ from the frozen inventory's. Both #219's onchain changes and an Aiken
  version difference contribute, which is precisely why the acceptance identity
  is a triple and not a commit alone. *Method: hash and per-title extraction
  over the flake's own live blueprint output, using the flake's own extraction
  script.*
- **F-02 — the M8 baseline blueprint is a fixed-output derivation whose
  declared hash and whose builder inputs have diverged.** Its declared output
  hash is the pre-#219 value; its builder consumes the current tracked onchain
  source and a *different* Aiken version from the one the repository validates
  with, and reaches the network for dependency resolution. Content-addressed
  outputs are substituted, not rebuilt, so a machine that already holds the
  store path cannot observe the divergence. **Whether a cold store fails is not
  yet established and must not be assumed** — establishing it, in a way that
  runs inside the gate, is slice work, not a premise.
- **F-03 — the committed lock is out of sync with its flake.** Evaluating the
  offchain flake at this commit rewrites `offchain/flake.lock`, because an
  input present in `flake.nix` has no node in the committed lock: a clean
  checkout becomes dirty on its first evaluation. *Checked and bounded: the
  identity the audit binds is unaffected. The reported `lock_sha256` equals the
  **committed** lock, because evaluation reads the store copy taken before the
  working tree is rewritten. So this is a working-tree hygiene defect and a
  declared-input inconsistency, not a broken identity binding — it matters
  because a gate that requires a clean tree, and a stranger following the
  bundle's own instructions, both meet it immediately.*
- **F-04 — variant selection is currently derived from the program's own UPLC
  version.** That derivation is what produced the historical variant C
  identity. Targeting E is therefore a change of *selection*, not a relabelling
  of existing output, and whether E is expressible at the current pins is an
  open question the compatibility audit must answer rather than assume.

- **F-05 — today's baseline evidence names no variant at all.** A full run of
  the flake-owned blaster runner at this commit prints its artifact and
  toolchain identity and never names a `BuiltinSemanticsVariant`. Under the
  ratified evidence schema a record with no variant named is
  `COULD-NOT-EVALUATE`, which is RED. The variant leg of the triple is
  therefore not merely set to the wrong value — it is absent.
- **F-06 — the announced identity's legs currently disagree with each other.**
  The same run reports source identity `fe535810…` (post-#219 `main`) beside a
  blueprint and program hash that are the pre-#219 values, and reports its
  Aiken as `1.1.21` while the repository validates its onchain sources with
  `1.1.23`. Each leg is individually true of *something*; together they
  describe no single configuration. *Method: one full run of the flake-owned
  runner, exit 0, evidence retained under the ticket runtime root.*

F-01, F-04, F-05 and F-06 together mean every one of the 23 inventory rows is
invalidated by the epic's own `INV` rule and must be re-measured here — and
that the baseline this ticket replaces is not merely stale but internally
inconsistent.

**The baseline runner is green today.** That is the point: a passing run is
what is announcing the inconsistent triple. Slice B's job is not to fix a red
signal but to make this green mean what it claims.

## Strategy

Three bisect-safe slices, in dependency order. Each ends at a commit that
leaves the repository green and says something true on its own.

The load-bearing choice is that **each slice's controls live inside the command
the gate runs**. #234 produced five green gate versions that could not have
failed because the thing they claimed to check was never executed by them. A
control reachable only by hand is treated here as absent.

The second choice is that **the ticket owner holds an independent expectation
of the manifest values and does not publish them into the mandate**. The
manifest must be derived by the implementation and is cross-checked against the
held values at acceptance. A contract that carries the answer cannot detect a
transcription.

### Slice A — compatibility audit and its two controls

Establishes that the tracked bridge source still resolves against its pinned
upstream packages, and that the instrument saying so can fail. Answers, as a
first-class reported outcome, whether variant E is expressible at the pins.

This is first because every later measurement is worthless if the bridge does
not compile against what it claims to be pinned to, and because a zero-finding
scan from an untested scanner is the exact shape this milestone has already
been burned by.

Also lands the lock-sync fix (F-03): the audit binds pin identity from the
locked inputs, so a lock that mutates on evaluation undermines the audit's own
premise.

### Slice B — frozen post-#219 / post-Conway baseline identity

Re-anchors the baseline artifact so it is reproducible rather than
substituted, measures all 23 titles and 8 programs, and freezes the triple with
variant E named. Depends on Slice A's variant answer and on any bridge repair
Slice A finds necessary, which would itself become a new frozen source and
manifest identity before this slice measures anything.

### Slice C — stranger-runnable bundle skeleton and downstream record schema

Turns the frozen identity into something a stranger re-derives from a fresh
clone, and installs the record schema #247/#248/#249 must fill: the per-claim
falsifier-before-GREEN pair, the three-outcome field, and the two distinctly
labelled Advance records.

## Slice A invariants

| ID | Must hold | Observable failure |
|---|---|---|
| INV-A1 | Every reference the tracked bridge source makes into the three pinned upstream packages is resolved against those exact pins, and the complete unresolved set is reported. | An unresolved reference exists and the run still exits 0, or the report omits one. |
| INV-A2 | The resolver is shown, in the same run, to find references that are present: a reported resolved count greater than zero that corresponds to references actually made by the tracked source. | The run reports zero resolved, or reports a count no source reference accounts for. |
| INV-A3 | A deliberately seeded reference to a name absent at the pins is reported unresolved and makes the audit exit non-zero. | The seeded reference is reported resolved, is silently skipped, or the audit still exits 0. |
| INV-A4 | Pin identity is taken from the locked inputs rather than transcribed, so a pin that moves without the audit noticing is impossible. | A changed pin leaves the audit's reported identity unchanged. |
| INV-A5 | The audit reports whether variant E and an era-based variant selection are expressible at the pins, as an explicit outcome. | The question is unanswered, answered by inference, or silently defaulted to the version-derived variant. |
| INV-A6 | Every checked item carries `ESTABLISHED`, `REFUTED`, or `COULD-NOT-EVALUATE`; the third is RED and names the layer that failed. | Any item reports a bare pass/fail, an empty result, or a skipped item counted as clean. |
| INV-A7 | Both controls are reached by the single flake-owned command the gate runs. | A control is reachable only by a hand-typed command, or the gate passes with a control removed. |
| INV-A8 | Evaluating the offchain flake from a clean checkout leaves the tracked lock unmodified. | Evaluation dirties the working tree. |
| INV-A9 | The audit changes no bridge semantics: no assertion, theorem, or existing check is weakened, and the audit does not write tracked sources. | Any tracked Lean assertion changes, or the audit mutates tracked files. |

Slices B and C carry their own invariant sets, versioned before their
dispatch, not pre-committed here.

## Live boundary

The real boundary is a stranger's cold Nix store: an artifact that is
substituted rather than rebuilt hides exactly the divergence this ticket
exists to expose. Slice A does not yet cross it. Slice B must establish
rebuildability mechanically, and Slice C must exercise a genuinely fresh clone
rather than this worktree.

## Constraints

- Anchor is `main`, never the merge's second parent `be3d8860…`.
- No credentials, secrets, or authenticated network resources.
- Historical C material is relabelled, never deleted or reinterpreted.
- Nothing in this ticket may accept, weaken, or pre-empt a P0 security claim.
- Existing consumers of the live blueprint (`checks.e2e`, `ckeriRunner`,
  `packages.ckeri`) must keep using the live blueprint; the baseline artifact
  is a separate identity and must not be routed into them.
