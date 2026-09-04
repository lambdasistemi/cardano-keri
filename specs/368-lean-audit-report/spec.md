# Specification — #368 hash-bound Lean audit report

## Outcome

**REQ-368-P1:** One report at `lean/AUDIT-REPORT.md` gives the exact terminal
FULL-audit verdict for the complete tracked `lean/` surface released by epic
#367 after #363, #364, #365, and #366 have merged.

The planning artifact ceiling is 180 lines. The report and evidence are not
filled or verified until the epic owner publishes the merged commit in this
ticket's durable `answers/` directory.

## Authority and frozen input

- **REQ-368-AUTH:** The only admissible release is the commit named by the
  epic owner's durable answer. Branch tips, sibling STATUS claims, and local
  merge simulations are not authority.
- **REQ-368-BASE:** The released commit must contain the merged results of
  #363, #364, #365, and #366. The ticket branch is rebased onto that exact
  commit before inputs are frozen.
- **REQ-368-HASH:** The frozen input is a sorted, mode-and-blob-bound manifest
  of every tracked path below `lean/`, excluding only
  `lean/AUDIT-REPORT.md` and `lean/audit-evidence/**`. Its SHA-256 is the audit
  tree digest, names the evidence directory, and is printed in the report.
  The final gate recomputes the same manifest from the final tree and requires
  byte equality. This exclusion prevents the report from hashing itself.
- **REQ-368-DELTA:** Relative to the released commit, the final branch may
  change only the six mandate files, `lean/AUDIT-REPORT.md`, and the one
  digest-named evidence directory. All other `lean/` files are read-only.

## Report contract

- **REQ-368-VERDICT:** The completed report contains exactly one anchored
  terminal-verdict line, whose value is one of the four values licensed by
  issue #368. The planning skeleton contains no terminal verdict.
- **REQ-368-SECTIONS:** The completed report contains exactly once each of:
  Mode and frozen inputs; Decision coverage; Inversion coverage; Theorem
  outcomes; Mutation adequacy; Correspondence; Honest limits.
- **REQ-368-COVERAGE:** Decision coverage maps ruling to constructor, guard or
  effect and theorem. Inversion coverage uses live-derived denominators,
  theorem binding, exact-premise results, and all required checker
  self-falsifications. Theorem outcomes use only the statuses licensed by the
  issue and point to proof or witness evidence.
- **REQ-368-MUTATION:** Theorem-row coverage and semantic-atom coverage are
  separate finite ledgers. Each row names severity, operator, status, evidence,
  and campaign stopping reason. Structural correspondence/enumeration proofs
  are discounted as mutation kills. Equivalent or shadowed mutants do not
  close a row without proof.
- **REQ-368-CORR:** The report separately settles relation/function,
  Bool/Prop, replay, and simulator-facing correspondence where each surface
  exists; an absent boundary is identified rather than silently passed.
- **REQ-368-LIMITS:** Honest limits distinguish properties of the model from
  fidelity to external rulings and state what remains beyond the declared
  mutation fault model.

## Acceptance invariants

- **INV-368-01 RELEASE:** No verdict or Lean verification precedes the durable
  merged-base release; the reported release commit equals that release.
- **INV-368-02 IDENTITY:** Evidence manifest, evidence directory, report input
  digest, and recomputed final audited-input digest are identical.
- **INV-368-03 SINGULARITY:** Exactly one terminal verdict and exactly seven
  required audit sections exist in the completed report.
- **INV-368-04 STRUCTURE:** Every in-scope finite structural row is closed;
  inversion denominators come from the live compiled/imported surface and all
  required checker mutants turn the checker red for the named reason.
- **INV-368-05 ATOMS:** Every blocking semantic atom has a compile-valid,
  reached, single-atom killed mutant with wrong-reason exclusions. Theorem rows
  have reachable antecedent witnesses and sensitivity kills separately.
- **INV-368-06 TRUST:** A clean-`.lake` build succeeds, the tracked source has
  no `sorry` or `admit`, and theorem-qualified axiom output contains no
  `sorryAx` or unlicensed axiom.
- **INV-368-07 REFUTATION:** No unresolved refutation or OPEN proof claim can
  coexist with a passing verdict.
- **INV-368-08 FINDINGS:** Every finding names the violated row, hashed evidence
  pointer, failure class, honest limit, and blocking status; it prescribes no
  repair. Missing guarantees become findings for later tickets, never edits.
- **INV-368-09 SCOPE:** The audit performs no repair and changes no sibling-
  owned Lean, simulator, on-chain, off-chain, release, or feature artifact.

## Verdict rule

A passing result is licensed only if INV-368-01 through INV-368-07 are all
closed and no blocking finding remains. Otherwise the report uses the single
applicable non-pass result and records findings under INV-368-08. The
commissioning ticket owner accepts or rejects the submission; the auditor does
not accept its own report.

## Non-goals

- Fixing a discovered defect or adding a missing guarantee.
- Choosing Lifecycle disposition, which is predecessor #366's decision.
- Changing ratified Lean statements, adding axioms, or changing product code.
- Claiming exhaustive mutation coverage beyond the frozen finite ledgers.
