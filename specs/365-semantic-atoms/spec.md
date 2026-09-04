# Issue 365 — semantic atoms and mutation adequacy

Artifact ceiling: 8,000 bytes / 180 lines.

## Outcome

A release custodian can run one finite, frozen mutation campaign and see every
blocking semantic atom in `lean/SEMANTIC-ATOMS.md` killed by a compile-valid
single-atom mutation for the intended reason. Cage and Samaritan theorem rows
also have reachable antecedent witnesses and sensitivity kills. The two
denominators are reported separately.

## Requirements

- **R365-01 Frozen denominator.** `lean/SEMANTIC-ATOMS.md` binds the ruling,
  model site, owning theorem(s), and severity of every in-scope atom on
  `main@9b2e6b8`. Sibling C1/C2 may add inversions and gates only; any model,
  guard, effect, or statement drift is `SCOPE-FAIL`.
- **R365-02 Atom evidence.** Every blocking ledger row has one exact,
  compile-valid single-atom mutant. Its named owning theorem fails for that
  semantic reason. Syntax/import/setup failures, `sorryAx` evaluation crashes,
  and unrelated downstream failures do not count.
- **R365-03 Theorem-row evidence.** Every theorem declared by `Cage.lean` and
  `Samaritan.lean` has a reachable antecedent witness and at least one relevant
  killed mutant. Shared mutants are allowed; missing reachability is not.
- **R365-04 Cage surface.** Mutation reaches `authorized` separately for every
  `AuthMode` conjunct, both branches of `runBody`, both `ValueMode` effects in
  `routeValue`, and the implication direction of the delegated plugin pin.
- **R365-05 Samaritan surface.** Mutation reaches the `hFund` bound and the
  request/premium/fold split, including destinations and fee accounting.
- **R365-06 Honest runner.** `lean/mutants/run.sh` discovers its denominator
  from the frozen ledger, refuses missing/duplicate/unknown rows, proves one
  exact edit applied, builds the mutated model before attributing theorem RED,
  runs an identity survivor, and restores a clean source tree.
- **R365-07 Generated receipts.** `CHECKPOINT-MUTANTS.md` and
  `REGISTRY-MUTANTS.md` are regenerated from the same raw run. They state the
  operator set, budget, stopping reason, wrong-reason exclusions, identity
  result, and structural discounts once globally and on every affected row.
- **R365-08 Honest limits.** Receipts say only that the frozen finite campaign
  has no blocking survivors. They do not claim zero possible survivors.
- **R365-09 Merged rerun.** Planning and a full campaign proceed on the current
  stable tree. Terminal acceptance waits for the epic owner's merged C1+C2
  release, rebases through the git workflow, and mechanically reruns the whole
  campaign so final receipts name the merged commit.

## Invariants

- **INV-365-DENOMINATORS:** theorem rows and semantic atoms have independent
  totals and verdicts; neither closes the other.
- **INV-365-ATOM-EXACT:** each counted atom result applies exactly one frozen
  production edit and identifies that edit.
- **INV-365-RIGHT-REASON:** a kill names at least one non-structural owning
  theorem; excluded failure classes never count.
- **INV-365-REACHABLE:** each Cage/Samaritan theorem-row witness exercises its
  antecedent and the mutated site on an executable path.
- **INV-365-IDENTITY:** the unchanged control survives and demonstrates that
  the instrument can report a survivor.
- **INV-365-CLEAN:** campaign execution leaves tracked model, theorem, and
  runner inputs unchanged; only deterministic receipts may differ.
- **INV-365-PROVENANCE:** raw log, ledger hash, runner hash, source commit,
  mutant identity, and receipt hashes are mutually bound.
- **INV-365-AXIOMS:** a clean-`.lake` build reports no `sorryAx` for in-scope
  theorems.

## Acceptance

All blocking atom rows are killed for the right reason, all 18 Cage/Samaritan
theorem rows have witnesses and kills, the identity control survives, excluded
failures are zero, clean-`.lake` axioms are acceptable, `lake build` is green,
and tracked receipts are byte-identical to output regenerated on the final
merged C1+C2 base. No merge is authorized.
