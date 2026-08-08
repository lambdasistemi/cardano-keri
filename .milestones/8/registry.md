# Milestone 8 contract registry

Updated: 2026-08-02T07:24Z

## Exact production artifact identity

contract: Aiken source and pinned toolchain produce the blueprint UPLC imported by Lean/Blaster.
parties: Cardano-KERI onchain source/build; #189 bridge; #190 theorem portfolio.
invariant: every manifest title resolves through the exact Nix build to a non-empty program hash, and theorem evidence names that hash and source/toolchain identity.
enforced: #189 generated manifest + fail-loud extraction + fresh-checkout CI + audit-manifest hash verification; source mutation and clean-restoration controls prove the seam can fail.

## Frozen bridge consumed by the portfolio

contract: #190 properties consume only #189's accepted artifact and purpose conventions.
parties: epic #189 producer; epic #190 consumer.
invariant: P0 ratification postdates the tractability record and every accepted theorem binds to the frozen bridge manifest.
enforced: milestone dependency order, manifest identity in every theorem record, changed-program invalidation, and independent audit.

## Abstract lifecycle versus compiled lifecycle

contract: the 21 abstract Lean goals and compiled validator baseline may describe different protocol generations.
parties: abstract `lean/` model; production validators; #190 mapping.
invariant: every goal and production path is classified against a named baseline, including MODEL-AHEAD/CODE-AHEAD and existing PENDING parity markers; a baseline change invalidates affected evidence.
enforced: #190 threat/mapping matrix and baseline-triggered rerun rule.

## Deployed instance binding

contract: unapplied blueprint code hashes are not deployed applied-script hashes for parameterized validators.
parties: #189 audit manifest; deployed/integration evidence consumers.
invariant: each deployed instance claimed as covered names parameter values and resulting applied-script hash, otherwise deployment binding is visibly OUT-OF-SCOPE.
enforced: #189 manifest schema and final audit of any claimed applied-script chain.

## Proof vocabulary and trust boundary

contract: readers must not confuse an SMT Valid admitted through `blasterProven` with a Lean kernel proof or whole-system verification.
parties: #189 taxonomy/docs; #190 theorem report; milestone description/audit.
invariant: every claim is labeled KERNEL-PROVED, SMT-VALID (no proof term), TESTED, UNPROVED, OUT-OF-SCOPE, or OUT-OF-SCOPE-BY-FORM; kernel label is abstract-model-only and solver/import/compiler/ledger trust remains explicit.
enforced: published taxonomy, warning visibility, theorem matrix, and independent READY/NOT READY audit.

## Blueprint inventory

contract: prose baseline counts must not outrank the generated production manifest.
parties: Cardano-KERI blueprint; #189 manifest; #190 matrix; final audit.
invariant: every current title/program is classified; 23 titles/8 programs are observations only at baseline `7e19e550b6f107bbc10b4c65e77765e3e439f043`.
enforced: CI fails on unreviewed add/remove/rename and #190/final audit derive scope from the manifest.

## Legacy root gate lifecycle

contract: the shared repository root gate follows the canonical untracked and ignored per-ticket lifecycle without breaking active M1 users.
parties: M8 milestone governance; all Cardano-KERI issue lanes consuming the gate lifecycle; a future standalone M8 migration owner.
invariant: root `gate.sh` becomes untracked, `/gate.sh` is ignored, positive and negative lifecycle controls prove the convention, and normal CI remains green without smuggling the migration into an unrelated feature ticket.
enforced: NONE — operator ruling `2026-08-02` assigns this work to M8 but makes it parallel and non-blocking for #192. Verified `origin/main` `1473885a1a16d5d993b6d0c475566e086bf50dfb` still tracks `gate.sh` blob `2540cdb658ebe0a597ca971f5b81d00500e9ab17`; `.gitignore` blob `545e072cae49dd7605297364552aeb69337b7ce2` has zero exact `/gate.sh` entries. Commission a separately fenced standalone M8 ticket with both-way lifecycle controls and CI. Until then #192 keeps both root files forbidden and uses its frozen runtime gate.
