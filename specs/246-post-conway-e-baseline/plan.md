# #246 plan

Anchor: `main` `9d4eb9577464b81d2edc3dd64d71f61d62d791a4` (rebased 2026-08-05
onto #234's Stage D closeout; the original anchor was `fe535810…`, which the
findings below were measured at). Branch `feat/246-post-conway-e-baseline`.

**Mandate version 2.** Version 1's Slice A campaign was closed after two
findings verdicts, both of the same class. See "Why this mandate was rewritten"
below before reading the invariants.

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

That receipt is retained as a `REFUTED`/RED measurement with full provenance
(`evidence/RED-baseline-receipt.md` under the ticket runtime root). It is never
repaired in place, rewritten, or deleted, and it is read-only to every slice.
It has a second job: it is the **falsification case** for the identity
consistency check (R-09/R-10, T246-B7/B8). A checker validated only against an
invented broken input would not have been shown to catch the case that actually
happened here.

## Why this mandate was rewritten

Version 1's Slice A ran a full commit-owner campaign — RED bundle, candidate,
audit, one authorized repair, second audit — and was closed on a second findings
verdict. Both blocking findings were **one class**:

> **Root cause: the mandate permitted a resolver that approximates Lean's name
> resolution textually, and both campaigns built one.** Submission 1 matched a
> reference's final `.`-separated token across a whole package, so a symbol that
> had *moved namespace* resolved. Submission 2's indexer *reset* the namespace
> stack where Lean 4 *appends*, fabricating 108 entries under names that do not
> exist while the real names went missing.

Version 1's own strategy prose already required a resolver "that cannot
disagree with the compiler that will later build them". The `INV-A1` row did
not carry that; it said only "resolved against those exact pins". Two competent
campaigns satisfied the row while violating the strategy — which is what an
under-specified observable buys. The defect was mine, not either implementer's.

**This is a fresh owner campaign on a revised mandate, not a third submission.**
The two-submission cap applied to the campaign that closed; a revised
architecture or contract is explicitly a new campaign with a fresh owner
context. Recording it here so nobody reads the next dispatch as cap evasion:
the mandate changed first, and the change is the reason.

What survives from version 1, as read-only starting substance rather than
discards: the RED bundle `25a3d9e8`, the namespace-aware repair `db1899a1`, the
two in-process self-test legs, and three reviewer-contributed seed controls
(two already permanent gate legs, one queued for A-v4).

## Campaign contract

Binding on every Slice A/B/C campaign under this mandate.

**Ledger.** `/tmp/ms-keri-8/e190/t246/campaign-ledger.md`, one row per declared
invariant, carried forward across submissions by successive auditors. A fresh
auditor inherits the ledger; it does not restart a campaign that is already
partly terminal.

**Row states.** `OPEN`, or terminal `KILLED` / `RESIDUAL` / `BLOCKED`.
`KILLED` requires a **named mutant demonstrated to kill the row** — a proof
merely observed to pass leaves the row `OPEN`. `RESIDUAL` requires severity
`ADVISORY`, a named owner, a follow-up ID, and one line of honest limit.

**Severity** is fixed at spec time in the invariant table above and is never
argued at audit time. **A `BLOCKING` row may terminate only as `KILLED` or
`BLOCKED` — never `RESIDUAL`.** No budget and no fatigue converts a blocking
row into an accepted survivor.

**Termination** at the first of: **set-point** (every row terminal);
**tail-stop** (a round with no finding on a row not already in the ledger and
none at `BLOCKING` — recorded `stopped=TAIL`, never "clean"), which **cannot**
close over an `OPEN` `BLOCKING` row; or **budget**, which with any `OPEN`
`BLOCKING` row does not close the campaign but raises
`MUTATION-CAMPAIGN-OVERRUN` to this ticket owner for an epic-altitude decision.

Nobody writes "no survivors", "fully mutated", or "exhaustive". Equivalent
mutants make those claims unavailable to everyone.

**Build budget.** `builds_spent=0`, `builds_budget=3` for this ticket. Every
auditor packet carries both fields. Reading, typechecking, language-server
queries and interpreted instrument runs are **unmetered**; only a compiling
audit spends. Before a build that would exceed the budget, stop and ask.

*Bill, stated in advance so it is not discovered at exhaustion:* nine
`BLOCKING` rows each need one killing mutant, inside three building audits.
Mutants run against a warm tree, so this is expected to fit — but if it does
not, the correct outcome is `MUTATION-CAMPAIGN-OVERRUN` and an escalation, not
a quiet `RESIDUAL`.

**Reliance declaration.** Before its RED bundle, the commit owner declares what
its change *relies on* in code it did not write, in registry shape:
`INV-246-<NAME>`, the observable truth, severity, and `enforced:` the exact
executable check, `PARTIAL` with its honest limit, or **`NONE`**. `enforced:
NONE` is a complete, legal, cheap outcome — naming an unguarded assumption is
the deliverable, not a failure to do more. This ticket owner ratifies each row
into the invariant set, discards it, or promotes a `NONE` row into its own
work; unratified rows bind nobody and enter no audit campaign. A reliance that
proves *false* is a defect, not a declaration: the owner stops with
`CONTRACT-CHALLENGE` rather than building on it.

**Findings become properties.** An auditor establishes that a proof cannot
fail; the commit owner ships the permanent property that makes it fail from
then on, closing the **class** the finding names rather than the reported
instance. The auditor's frozen instrument travels with the finding as
read-only, sha256-bound seed evidence.

**Every measured quantity carries its instrument and its measurement window.**
A number without the thing that produced it and the interval it covers is not a
measurement, and must not be recorded as one. A percentage without its reset
window is the standing example: "16% used" is unreadable, "16% used, resets
21:31 on 15 Aug, read twice identically at 12:35Z" is a measurement. This binds
every record this ticket emits — resolution counts, durations, build spend,
free space, coverage figures — and every receipt an auditor or owner hands up.
Where the instrument cannot state its window, the quantity is
`COULD-NOT-EVALUATE`, not a smaller number.

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

### Slice A2 — collector closure over the source language

Authorized re-cut inside #246 (ruling A-001, basis A-e190-017), not a new
ticket and not a third campaign on the closed Slice-A boundary. Its boundary is
stated here **before** its campaign starts, which is the whole point of cutting
it: Slice A's boundary was drawn before anyone understood the problem, and six
failure shapes arrived one at a time inside it.

**Target: `INV-A1.v1`** — the universal claim, preserved rather than narrowed.
Slice A closing does **not** kill or residualise it; it moves here intact.

Boundary:

- collector closure over the tracked source language, explicitly **including
  syntax whose source spelling omits an upstream namespace** — Lean's
  leading-dot constructor notation is the known instance, and it is an instance,
  not the definition;
- every explicit cross-package reference is either **collected** or the run
  reports `COULD-NOT-EVALUATE`/RED. There is no third outcome and no silent
  omission;
- closure is decided **by the pins**, not by the collector's own token pattern.
  A collector that defines its own coverage cannot be short of it;
- the named killing mutant seeds an unrecognised or previously-omitted construct
  **of a class the collector does not already name** into tracked scope, and
  makes the real run RED — not merely produce a smaller count.

Also carried by this slice, because Slice A cannot close without them:

- the honest bounded publication required by `INV-A1.v2` — `collected`, `total`,
  coverage classes, collecting instrument, measurement window, remeasured
  against the candidate and never transcribed. The provisional ≈68 of ≈99
  observation is an *input to the question*, not a value to hard-code;
- the relabelling of the tautological agreement assertion (see below).

`INV-246-RESOLUTION-CLOSURE-BINDING` and `INV-246-PINNED-MODULE-GRAPH` are
`BLOCKING` and `OPEN` here. Neither may disappear, and each ends only `KILLED`
by its named demonstrated mutant or `BLOCKED` naming the exact blocking fact.

### The agreement assertion is not a measurement

Gate A-v6 asserts `disagreements=0` over a comparison whose two sides are the
same predicate, so it cannot fail. That is **not** a weakness in the oracle —
satisfying an invariant by construction is stronger than measuring it, and the
by-construction identity is exactly what this mandate demanded. It is a
labelling defect, and mine: I wrote an assertion that cannot fail and labelled
it a measurement.

Before Slice A closes, the record either states the identity —
`agreement=by-construction` with the predicate named — or uses a genuinely
discriminating second predicate. The `declaration-membership` mode already is
one. A non-falsifiable assertion may not ship labelled as a measurement.

### Slice B — frozen post-#219 / post-Conway baseline identity

Re-anchors the baseline artifact so it is reproducible rather than
substituted, measures all 23 titles and 8 programs, and freezes the triple with
variant E named. Depends on Slice A's variant answer and on any bridge repair
Slice A finds necessary, which would itself become a new frozen source and
manifest identity before this slice measures anything.

## Slice B invariants

Severity fixed **here, at spec time**, and never argued at audit time. Slice B
is where the chain-state test stops being one step removed: these rows are the
identity of the compiled validators that govern registration bonds, freeze
bonds, conviction forfeiture and endpoint deposits.

| ID | Severity | Must hold | Observable failure |
|---|---|---|---|
| INV-246-B1 | BLOCKING | The baseline blueprint is **rebuilt from source** at the accepted anchor with the Aiken version the repository validates its onchain sources with, not substituted by a declared output hash. | The artifact is content-addressed such that a cold store cannot reproduce it, or it is built with a toolchain other than the repository's validating one. |
| INV-246-B2 | **ADVISORY** | What a cold store does with the retired pre-#219 fixed-output baseline is established mechanically, by a check that runs inside the gate. | The claim is asserted from the divergence of declared hash and builder inputs rather than observed. |
| INV-246-B3 | BLOCKING | The manifest covers all 23 titles over 8 distinct programs, every field computed from the artifact; the cardinality is asserted, not assumed. A title is not a program — `mint`/`spend`/`else` of one validator share one `compiledCode`. | A field is a literal that happens to equal the computed value; or the cardinality is taken from the mandate rather than measured. |
| INV-246-B4 | BLOCKING | Variant E is bound as the evaluation identity, and any version-derived selection is named as a separate value that cannot silently stand in for it. | The record names no variant, names C as E, or infers the variant from a program's UPLC version. |
| INV-246-B5 | BLOCKING | Mutating any single manifest input — a title, a program byte, the toolchain, the variant — makes verification exit non-zero **and name which input moved**. | A mutated input still verifies, or the failure does not identify what changed. |
| INV-246-B6 | BLOCKING | Historical C / pre-#219 material is relabelled in place, neither deleted nor reinterpreted, and can never satisfy a P0 claim. | A C record is presented as E, or historical material is removed rather than relabelled. |
| INV-246-B7 | BLOCKING | The identity-consistency check goes RED when any element of `COMMIT + TOOLCHAIN + VARIANT` is unnamed, or when the elements describe different configurations — applied to **every** record the bundle carries, receipts included. | An internally inconsistent record passes, or an unnamed element is treated as anything other than `COULD-NOT-EVALUATE`. |
| INV-246-B8 | BLOCKING | That check is demonstrated RED **against the retained pre-slice receipt** before any clean baseline is accepted; the retained receipt is never repaired, regenerated or deleted. | The checker is validated only against an invented broken input, or the retained receipt is modified. |

**Carried into Slice B, not re-derived:**

| ID | Severity | State |
|---|---|---|
| `INV-246-ORACLE-CLOSURE-IDENTITY` | BLOCKING | `OPEN` — the `.ilean` root the oracle consumes is independently bound to the intended complete pinned upstream closure, not merely supplied by the same Nix interpolation the checker compares against. Terminates **only** `KILLED` by a named mutant or `BLOCKED` naming the exact infeasibility fact. Never `RESIDUAL`. |
| `INV-246-TRACKED-IMPORT-ORDER` | ADVISORY | `OPEN` — the source re-elaboration compiles tracked modules in dependency order, not alphabetical order. |

Ten rows, seven `BLOCKING`. Audit budget for Slice B is a **fresh**
`builds_spent=0 / builds_budget=3`, separate from the spent Slice A2 ladder and
its one finalisation run. Bill stated in advance: seven blocking rows each
needing a named killing mutant or a named blocking fact, inside three building
audits. If that does not fit, the outcome is escalation, never a quiet
`RESIDUAL`.

### Slice C — stranger-runnable bundle skeleton and downstream record schema

Turns the frozen identity into something a stranger re-derives from a fresh
clone, and installs the record schema #247/#248/#249 must fill: the per-claim
falsifier-before-GREEN pair, the three-outcome field, and the two distinctly
labelled Advance records.

## Slice A invariants

Severity is fixed **here, at spec time**, and is never argued at audit time.
`BLOCKING` when the value the invariant constrains reaches chain state, money,
or a signature; `ADVISORY` otherwise; undeclared is `BLOCKING`.

Slice A builds an *instrument*, so the test is one step removed and must be
applied honestly rather than deflated: this audit's verdict is the compatibility
premise that #247–#250 will cite for claims about validators governing
registration bonds, freeze bonds, conviction forfeiture and endpoint deposits.
A false `ESTABLISHED` here does not itself move a coin; it licenses a theorem
record that speaks about the code which does. That is why nine of these ten
rows are `BLOCKING`.

| ID | Severity | Must hold | Observable failure |
|---|---|---|---|
| INV-A1.v1 | BLOCKING | **Slice A2 target — universal.** Every explicit cross-package reference the tracked bridge source makes is *collected or fails closed*, and every collected reference is decided by the pinned Lean elaborator-compatible oracle. | A reference the source makes is neither collected nor reported `COULD-NOT-EVALUATE`; or a collected reference is decided by anything other than that oracle. |
| INV-A1.v2 | BLOCKING | **Slice A closing claim — bounded, and it must say what it is bounded to.** Every reference in the *collected* population resolves under the namespace it actually names, decided by an oracle that cannot disagree with the pinned Lean elaborator, in both directions; the complete unresolved set is reported. The record publishes `collected`, `total`, the coverage classes, the collecting instrument and the measurement window. A bare `unresolved=0` is forbidden, and the counts are remeasured against the candidate, never transcribed. | A resolution verdict disagrees with the elaborator either way; or the record publishes a verdict without its coverage, instrument and window. |
| INV-A2 | BLOCKING | The resolver is shown, in the same run, to find references that are present: a reported resolved count greater than zero that corresponds to references actually made by the tracked source. | The run reports zero resolved, or reports a count no source reference accounts for. |
| INV-A3 | BLOCKING | A deliberately seeded reference to a name absent at the pins is reported unresolved and makes the audit exit non-zero. | The seeded reference is reported resolved, is silently skipped, or the audit still exits 0. |
| INV-A4 | BLOCKING | Pin identity is taken from the locked inputs rather than transcribed, so a pin that moves without the audit noticing is impossible. | A changed pin leaves the audit's reported identity unchanged. |
| INV-A5 | BLOCKING | The audit reports whether variant E and an era-based variant selection are expressible at the pins, as an explicit outcome. | The question is unanswered, answered by inference, or silently defaulted to the version-derived variant. |
| INV-A6 | BLOCKING | Every checked item carries `ESTABLISHED`, `REFUTED`, or `COULD-NOT-EVALUATE`; the third is RED and names the layer that failed. | Any item reports a bare pass/fail, an empty result, or a skipped item counted as clean. |
| INV-A7 | BLOCKING | Both controls are reached by the single flake-owned command the gate runs. | A control is reachable only by a hand-typed command, or the gate passes with a control removed. |
| INV-A8 | ADVISORY | Evaluating the offchain flake from a clean checkout leaves the tracked lock unmodified. | Evaluation dirties the working tree. |
| INV-A9 | BLOCKING | The audit changes no bridge semantics: no assertion, theorem, or existing check is weakened, and the audit does not write tracked sources. | Any tracked Lean assertion changes, or the audit mutates tracked files. |
| INV-A10 | BLOCKING | The audit's own records name the commit they describe, so a source-compatibility result cannot be read against the wrong tree. | The report is silent about which tree it audited. |

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
