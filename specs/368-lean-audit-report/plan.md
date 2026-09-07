# Plan — #368 frozen-tree report finish

## Authority and topology

NOTE-008 releases `a67e3ed16d4f406fa99dd8b746a65e0c2c0b8359`, after #372
and #373 merged. It supersedes the planning-only hold and explicitly permits a
pure-report finish without seating an auditor. This lane uses that path:
report author only, no OWNER submission or auditor launch, no new semantic
mutation campaign. The former Muse/Codex two-submission plan is superseded,
not represented as executed or independently accepted.

## Frozen scope

Rebase onto the released commit. Re-derive every tracked Lean input's mode,
blob and path. Exclude only the report and its digest-named evidence directory
from final recomputation. Keep production files unchanged. Decision documents,
mandates, runner and toolchain bytes also receive SHA-256 identities.

## Evidence and verdict

1. Build the released library from an absent `.lake` and retain raw output.
2. Derive the theorem and transition inventory from the compiled environment;
   query every discovered theorem's axioms and reconcile exact name sets.
3. Execute the repository retirement/trust driver and module-specific missing
   import controls. Keep source theorem counts distinct from generated ones.
4. Reconcile inherited receipt hashes against current frozen bytes. Preserve
   historical command identity and audit scope; do not promote them to fresh
   execution. No structural or semantic mutation rerun is claimed.
5. Complete all seven report sections, using AUDIT-FINDINGS when blocking
   provenance or unassessed whole-tree coverage remains. Preserve F-365-001,
   #382, superseded undispatched #383, and OD-366-001. Prescribe no repair.
6. Freeze a mechanical report gate. Its eight negative controls cover only
   artifact/verdict/input/axiom-receipt integrity, not model semantics.

## Delivery

Verify the report, evidence manifest, input identity and allowed delta locally.
The changed Lean surface receives fresh local build/trust checks; this pure
report finish does not rerun the whole on-chain/off-chain just ci locally.
Push the verified report commit, update PR #371 to describe the actual findings,
require fresh remote checks on that SHA, mark ready, journal COMPLETE
ready-for-review, and leave merge to the project desk. Runtime final receipts
record Git/PR/CI identities without a self-referential evidence commit cycle.
