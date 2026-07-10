# Implementation Plan: Restore cage token and AID-ownership invariants

## Technical shape

The deliverable hardens the **existing** `mpfCage` validator in the main onchain
tree — not a throwaway spike. Files in play:

- `onchain/validators/cage.ak` — mint+spend handlers and helpers.
- `onchain/validators/types.ak` — datum/redeemer wire types.
- `onchain/validators/lib.ak` — token helpers.
- `onchain/validators/cage.tests.ak` — existing helper-level tests.
- New full-context test/measurement modules under `onchain/validators/`.
- `offchain/lib/Cardano/KERI/AID/Cage/Types.hs` + `.../TypesSpec.hs` — Haskell
  parity for mirrored types (`AIDOwnerAuth`, `AIDRequestAction`,
  `AIDOnChainTokenState`).
- `offchain/app/GenVectors.hs` — regenerates `verifyOwnerAuth` vectors if the
  auth message shape changes.
- `docs/index.md` — implementation-status / prototype label.

## Transaction boundary (mandatory — brief)

Every exploit must be demonstrated against the **real handler on a full
`Transaction`**, not a pure helper. The unit of proof is:

- **Mint side:** `mpfCage.mint(redeemer, policyId, tx)` where `tx` carries a
  real `mint` field, `inputs` (incl. the consumed output reference), and
  `outputs` (incl. the designated state output at the cage script).
- **Spend side:** `mpfCage.spend(Some(datum), redeemer, own_ref, tx)` where `tx`
  carries the spent state input at `own_ref`, request inputs, the continuing
  state output, refund outputs, `validity_range`, and `extra_signatories`.

**The existing `cage.tests.ak` harness cannot express this** (it only calls the
pure `verifyOwnerAuth`; the only `OutputReference` literal is a single auth
fixture). Therefore **Slice 1 builds the smallest reusable full-context harness
before any behavior is fixed** — a helper module of `Transaction`/`Input`/
`Output`/`OutputReference`/`Value`/datum constructors (built on
`transaction.placeholder`) plus a set of full-tx happy-path fixtures that the
current code already accepts. Every later attack test and every measurement
reuses these constructors.

## Measurement boundary (mandatory — brief)

Execution units are measured on the **full spend/mint validator context** — the
per-transaction figure — following the #97 R2 precedent
(`spikes/97-blake3-multitx/validators/measurements.ak`,
`REPORT.md`): top-level `const` fixtures (folded at compile time, so fixture
construction is not charged to validator cost) invoke the real `mpfCage`
handlers on their accept path, measured via:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

Measurements live in the main onchain tree (this is the production validator).
The report records memory + CPU for each hardened happy path (Mint, Migrate,
Modify at the supported batch size, End) against the mainnet per-tx budget
(memory 14,000,000; CPU 10,000,000,000) and states the **supported batch/output
bound** (max Modify request inputs / refund outputs proven to fit).

## Attack surfaces (confirmed on current code — hypotheses to demonstrate RED)

| # | Surface | Evidence | Fix |
|---|---|---|---|
| H1 | `Burning -> True` accepts unconditional positive mint | `cage.ak:29` | FR2 |
| H2 | `Migrating` trusts caller-supplied unpinned `oldPolicy` | `cage.ak:386-409`, `types.ak:11-14` | FR3 |
| H3 | Mint/Modify/Migration accept state output without the exact thread token | `cage.ak:377-383`, `:325-357`, `:403-408` | FR1/FR4/FR3 |
| H4 | `Modify` authenticates against the **output** `identity_root` | `cage.ak:331`, `:350`, `:251` | FR5 |
| H5 | authenticated `owner_aid` not bound to mutated `requestKey` | `cage.ak:179-205`, `:253-265` | FR6 |
| H6 | End/Burning not proven as one exact lifecycle transition | `cage.ak:96-101` + H1 | FR2 |

If, during implementation, code evidence shows a hypothesis is misstated, the
pair reports it and the orchestrator updates these artifacts with evidence
before the fix — the acceptance target is never silently weakened.

## RED→GREEN convention for security fixes

Attack tests assert the **desired** (post-fix) rejection using Aiken's
`test name() fail { <handler on malicious tx> }` form:

- On current vulnerable code the malicious tx is **accepted** ⇒ the handler
  returns without failing ⇒ the `fail`-annotated test **fails** (RED).
- After the fix the malicious tx is **rejected** ⇒ the handler fails ⇒ the
  `fail`-annotated test **passes** (GREEN).

Happy-path (accept) tests use the plain `test name() { handler(...) }` form and
must stay green across every subsequent slice (regression protection).

## Recommended designs (pre-applied; pair refines within owned files, orchestrator reviews)

- **FR1 (Minting):** after the existing checks, require the cage policy to mint
  **exactly one** asset name at quantity 1 (reject any additional asset name or
  extra quantity under the policy — check the full `tokens(mint, policyId)` map,
  not just the derived token), and require `quantity(policyId, output.value,
  tokenId) == Some(1)` on the designated state output (the token is confined
  where the state lives), tokenId derived from the consumed `asset` out-ref.
- **FR2 (Burn/End):** replace `Burning -> True` with a handler that (a) rejects
  any positive quantity under the cage policy, (b) requires the cage policy's
  mint map to contain **exactly one** entry, the matching thread token at `-1`
  (reject mismatched or extra cage-policy mint entries), and (c) is coupled to an
  owner-authorized `End` spend of the matching state UTxO (a burn without that
  End is rejected). Candidate wire change: `Burning` carries the burned
  `TokenId` (Aiken-only redeemer; no offchain builder today).
- **FR3 (Migration pin):** remove the attacker-supplied `oldPolicy` from the
  redeemer; pin the predecessor policy as a **validator parameter** (changing the
  parameter changes the script hash, so an attacker-created predecessor cannot
  satisfy it by construction) OR, if parameterization is impractical, require the
  migration to spend a genuine predecessor cage state UTxO at the pinned
  version-1 with its thread token burned. Exactly 1 predecessor burn / 1
  successor mint; successor token confined in the state output (FR1 shape).
  Reject any extra or non-exact predecessor/successor policy quantity or asset
  name (check both policies' full mint maps, not just the named token). The
  exact pinning mechanism is the pair's to finalize **within acceptance AC3**; a
  mechanism that cannot reject an attacker-created predecessor is a BLOCK to the
  epic owner (acceptance-target question), not a silent weakening.
- **FR4 (Modify confinement):** in `validModify`, require
  `quantity(scriptPolicy, output.value, tokenId) == Some(1)` on the continuing
  state output.
- **FR5 (input-root auth):** in `validModify`/`mkAction`, authenticate against
  the **input** state's `identity_root` (`state.identity_root` from the spent
  `StateDatum`, `types.ak:59`) instead of the output datum's `identity_root`.
  No wire change.
- **FR6 (aid↔key binding — frozen cryptographic rule):** in `mkAction`, bind
  every mutated `requestKey` to the authenticated AID with **no ambiguity**:
  require `bytearray.length(requestKey) >= 32` and
  `bytearray.take(requestKey, 32) == blake2b_256(owner_aid)`. A key whose first
  32 bytes equal that digest exactly (length 32) is the owner cell; a longer key
  is a namespaced child under the digest. This rejects (a) a raw-`owner_aid`
  prefix — the AID bytes are not their own `blake2b_256` — and (b) an unrelated
  authenticated AID whose digest differs. No new wire field (`owner_aid` already
  lives in `OwnerAuth`, `requestKey` in `Request`).

**Cross-layer parity note.** The mirrored Haskell types are `AIDOwnerAuth`,
`AIDRequestAction`, `AIDOnChainTokenState`. FR5/FR6 as designed do **not** change
their wire shape (they add `expect` relations over existing fields), so the
existing `TypesSpec.hs` golden/roundtrip tests remain the parity check and must
stay green in `just ci`. The mint-side types (`MintRedeemer`, `Migration`,
`Burning`) have **no** Haskell mirror (no offchain builder in this prototype), so
changes to them are single-layer (Aiken-only) and require no new golden artifact.
**If** a slice does change a mirrored type's wire shape, its Haskell mirror +
`TypesSpec.hs` update + (if the auth message changes) `GenVectors.hs` regen ride
in the **same** slice commit so every commit is bisect-safe with parity intact.

## Gate

`./gate.sh` is the PR-life gate: `git diff --check` then `just ci` (onchain
`aiken fmt --check` + `aiken check` incl. all cage + full-context + measurement
tests; offchain build + unit + hlint + format-check + devshell). Slice briefs
also name a focused command for fast RED/GREEN:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check      # onchain slices
just unit "<pattern>"                                             # offchain parity slices
```

Drivers run `./gate.sh` before committing.

## Slices (each = one bisect-safe commit)

### Slice 1 — Full-transaction test harness (foundation)
Build the reusable full-context constructors + full-tx happy-path fixtures
(Mint/Migrate/Modify/End accept on current code). No validator behavior change.
`test(onchain): add full-transaction cage test harness`

### Slice 2 — Harden Minting confinement (FR1 / H3-mint)
Attack RED ×2: (a) mint accepted with the thread token absent from / outside the
state output; (b) mint accepted with an **additional** asset name (or extra
quantity) under the cage policy. GREEN: require exactly one cage-policy asset at
quantity 1 and that exact token in the designated state output.
`fix(onchain): confine minted cage token to the state output`

### Slice 3 — Harden Burn/End lifecycle (FR2 / H1+H6)
Attack RED ×5: (a) positive mint under `Burning`; (b) burn with an absent/
mismatched matching `End` state spend; (c) burn without the owner signature on
the matching `End` spend; (d) mismatched/extra cage-policy mint entry alongside
the `-1`; (e) an owner-signed `Burning(TokenId)` + `Modify([])` token-dropping
burn (burn through a non-`End` state spend). GREEN: reject positive; require
exactly one cage-policy mint entry (the matching token at `-1`) coupled to the
owner-authorized `End`; AND a `validModify` **reverse guard** — `Modify` may not
mint or burn its own thread token — so an exact burn can coexist only with the
owner-authorized `End` branch (H6 exclusivity). This reverse guard is **distinct
from FR4**: it does not require the token in the continuing output; FR4
output-confinement (blocking a no-burn `Modify` from moving the token out) is a
separate Slice-5 target, additive to this guard. (Aiken-only wire change:
`Burning` gains a `TokenId`.)
`fix(onchain): couple cage burn to owner-authorized end`

### Slice 4 — Harden Migrating pin + confinement (FR3 / H2+H3-migration)
Attack RED ×2: (a) attacker-created predecessor policy accepted; (b) extra or
non-exact predecessor/successor policy quantity or asset name accepted. GREEN:
pin predecessor policy/version; exactly 1 predecessor burn / 1 successor mint
(reject extra entries under either policy); successor token confined in the state
output.
`fix(onchain): pin cage migration predecessor and confine successor`

### Slice 5 — Harden Modify confinement + authorization (FR4+FR5+FR6 / H3-modify+H4+H5)
Attack RED ×4: (a) a no-burn `Modify` moving the thread token OUT of the
continuing state output accepted (FR4/H3-modify — distinct from the S3 reverse
guard, which only blocks minting/burning the token); (b) output-`identity_root`
self-authorization accepted (FR5/H4); (c) unrelated authenticated AID authorizes
the key (FR6/H5); (d) a raw-`owner_aid` prefix (not its `blake2b_256`) authorizes
the key (FR6/H5). GREEN: require the exact thread token in the continuing state
output (FR4); authenticate against the input/reference identity root (FR5);
require `requestKey` length ≥ 32 and its first 32 bytes == `blake2b_256(owner_aid)`
(FR6). S5 **preserves the S3 `validModify` no-mint/burn reverse guard intact**
(additive — must not weaken/revert it). Includes Haskell parity + `TypesSpec.hs`
update **only if** a mirrored type's wire shape changes. (May split into 5a
confinement / 5b authorization if the commit grows unwieldy.)
`fix(onchain): authenticate cage modify against input identity state`

### Slice 6 — Execution-unit measurements + supported bound (FR9)
Full-context `const` fixtures invoking the hardened handlers; record memory/CPU
per happy path via `aiken check --plain-numbers`; write
`specs/99-cage-security/REPORT.md` with the per-tx budget verdict and the
supported Modify batch/output bound.
`docs(onchain): measure hardened cage execution units`

### Slice 7 — Prototype implementation-status text (FR10)
Keep `docs/index.md` labelling the system a prototype. Describe #99 as **one
completed security gate** among the work still required — do not present it as
the sole remaining reason for prototype status, and do not claim production
readiness. Closing #99 does not lift the prototype label.
`docs: record cage security gate; keep prototype label`

### Slice 8 — Live-boundary measurement follow-up (FR9/AC9 boundary proof)
The S6 measurement (`bc8d9b2`) uses source-level typed `const` fixtures — direct
handler calls, empty single-leaf MPF proofs, ledger `Data` deserialization
excluded — so **Modify=65 is a measured HANDLER CEILING, not a production
bound**. This slice, on a fresh commit (do NOT alter `bc8d9b2`):
1. **Amend `REPORT.md` wording** to distinguish "measured handler ceiling = 65"
   from a production-supported bound, and remove any guidance that treats 65 as a
   safe on-chain cap.
2. **Attempt an in-PR live-boundary smoke** that evaluates the COMPILED validator
   through the serialized-`Data` boundary at a **declared** representative/maximum
   MPF proof depth: `aiken build`/`aiken export` the Modify spend handler to UPLC
   with `Data`-encoded datum/redeemer/script-context applied, then
   `aiken uplc eval` (reports real mem/cpu INCLUDING `Data` deserialization). If
   it runs deterministically, record the boundary-inclusive number and (if stable)
   extend `gate.sh` with it.
3. **Full node phase-2 boundary is out of local scope:** host has no
   `cardano-cli`/`node`/`uplc`; the repo has **no #99 transaction builder**, so a
   fully-built #99 tx cannot be produced for `yaci-devkit` evaluation without new
   offchain builder work. If the UPLC-eval smoke is also infeasible in-scope, the
   driver reports the exact missing step and the orchestrator writes a **parent
   Q-file** to the epic owner naming the missing tooling (offchain #99 tx builder
   + `yaci-devkit` evaluation), a **named operator artifact required before the PR
   leaves draft**, and a conservative recommendation — NOT deferring silently to
   #44 or claiming AC9 fully satisfied.
The pair reviews any fixture/report/smoke change.
`docs(onchain): distinguish measured cage ceiling from production bound`
(+ optional `test(onchain): add cage uplc data-boundary smoke` /
`chore: extend gate.sh with cage boundary smoke`)

### AC9 live-boundary proof on real cardano-node Phase-2 (FR9/AC9) — Slices 9a + 9b
Per **amended A-002 / NOTE-013 / NOTE-014 / NOTE-015** (Paolo means the in-house
**real cardano-node** devnet, NOT Yaci), close AC9 **in-PR** by measuring the real
node **Phase-2** supported `Modify` batch bound via the **`cardano-node-clients`
`devnet` public sublibrary** (`Cardano.Node.Client.E2E.Setup.withDevnet`) — the
pin + nix wiring are reused from `/code/cardano-tx-tools`. **Do NOT** use/restart
the shared Yaci container, preprod, mainnet, or any unrelated container.

**READ-ONLY precedent** (copy/adapt the minimum into the #99 worktree; never
edit/clean/reset/commit there — both hold unrelated user changes):
- `/code/cardano-mpfs-onchain/cardano-mpfs-onchain/e2e-test/CageTxBuilder.hs`
  (real Boot/Request/`Modify`/End tx build+eval, ledger types),
  `.../CageE2ESpec.hs` (`withDevnet` start/submit/observe);
- `/code/mpfs/off_chain/src/trie/proof.ts` + MPF lib (non-zero-depth proof
  gen / Plutus-Data serialization precedent).

**Dependency rule:** pin `cardano-node-clients` (owns the `devnet` sublibrary) via
an **immutable** `source-repository-package` in `offchain/cabal.project`, reusing
`cardano-tx-tools`'s exact rev + nix32 `--sha256:` comments (`nix flake prefetch`
→ `nix hash convert --to nix32`). Use the **exact proven tx-tools pair**:
`cardano-node` **10.7.0** and `cardano-node-clients`
**`ca86f11d27b34e37d3814e4d3c3d66e256400403`**, pinned in `offchain/flake.lock`;
the Cabal `source-repository-package` pin and the flake source used for
`E2E_GENESIS_DIR` MUST agree on that `cardano-node-clients` rev. Do **NOT** add
`cardano-tx-tools` as a package dependency unless the code genuinely imports a
`Cardano.Tx.*` module. No dependency on any mutable local checkout.

**Flake wiring (model on `/code/cardano-tx-tools/nix/checks.nix`):** one
strict-PATH `writeShellApplication` app exposed twice — `apps.<sys>.e2e`
(`nix run`) and `checks.<sys>.e2e` (a `runCommand` invoking it via `getExe`, so
`nix flake check` executes it). `runtimeInputs` = `cardano-node` + the built E2E
executable (+ every std util the script calls). `E2E_GENESIS_DIR` comes from the
pinned `cardano-node-clients` source. The live E2E check/app may be **Linux-only**
(NixOS CI runner); keep normal build/unit/lint checks on all supported systems.

**Gate/CI must actually invoke it** — a checked-in transcript alone is
insufficient. `gate.sh` (orchestrator-owned) is extended to run the E2E check;
`.github/workflows/ci.yml` gains an E2E job.

**Dev-shell build gate (NOTE-015 + operator evidence):** the repo's current
dev-shell job runs only tool versions + format/lint (no `cabal build`) and its CI
comment claiming `cabal build` cannot run is **stale** — the operator proved
`cd offchain && nix develop --quiet -c cabal build all --enable-tests -O0` exits 0
in ~16s (GHC 9.12.3), building the unit test suite. S9a **upgrades** `just
devshell-offchain` + the CI dev-shell job to exactly that command
(`nix develop --quiet -c cabal build all --enable-tests -O0`) — `--enable-tests`
is required so the gate covers the new `offchain/e2e` test component and the
`devnet` sublibrary (plain `cabal build all` omits tests). Remove the stale
"tool/format checks substitute for a build" comment. If the `devnet` public
sublibrary is missing from the shell DB when the e2e component is added, expose it
via haskell.nix shell `additional` (`components.sublibs.devnet`); use the SAME
proven command in `just` and CI.

**Script provenance + settlement (NOTE-016):**
- `onchain/plutus.json` is generated + gitignored — the E2E check MUST NOT
  silently consume whatever mutable copy is in the worktree. Prefer a
  **flake-owned `plutus-blueprint` derivation** built from tracked `../onchain`
  sources + the versions locked in `aiken.lock`, passing that immutable path to
  the E2E executable. A committed compiled fixture is an acceptable fallback ONLY
  with a **gate-invoked byte-for-byte freshness check** against a fresh
  `aiken build`.
- The builder applies **BOTH** validator params (`version` and the pinned
  `predecessorPolicy`) and derives the mint/spend policy id from those exact
  applied bytes; **record the script hash** in the artifact.
- A green S9a smoke means the signed tx is **submitted and observed settled** on
  `withDevnet` — `evaluateTx = Right exunits` alone is NOT live settlement proof.
  Record the **tx id + per-redeemer execution units**.
- A failing S9b boundary point must **preserve and report the actual Phase-2
  evaluation/rejection diagnostic**; do NOT silently retain placeholder ExUnits
  (the read-only precedent does that on `Left` — do not copy that).

#### Slice 9a — toolchain + `withDevnet` cage builder + one real Phase-2 smoke
Pin `cardano-node-clients`; add the Haskell E2E component under `offchain/e2e/**`
adapting the read-only precedent to the hardened #99 wire (`StateDatum` w/
`identity_root`, `OwnerAuth`, `RequestAction`, `requestKey ==
blake2b_256(owner_aid)`-bound, parameterized `mpfCage(version,
predecessorPolicy)`); build ONE real `Modify` tx and submit it through
`withDevnet` for a single green Phase-2 smoke (capture accept + ex-units); add the
flake app + `runCommand` check; the pair wires it into **CI** (`ci.yml`) — the
`gate.sh` extension is a **separate** orchestrator commit after S9a acceptance
(S9a-GATE), not part of the pair commit; upgrade the dev-shell build gate. S9a is
RED→GREEN (no RED-SKIP): a navigator-reviewed **failing settled-`Modify` E2E
spec** first, then made green. Focused proof: `nix flake check` runs the E2E check
green + `nix develop --quiet -c cabal build all --enable-tests -O0` green.
`test(e2e): add withDevnet #99 cage phase-2 smoke and dev-shell build gate`

#### Slice 9b — non-zero-depth proof, batch sweep, artifact + report
Generate representative **non-zero-depth** MPF inclusion proofs; sweep `Modify`
batch sizes at a **declared** proof depth + state shape through `withDevnet` until
the pass/fail boundary is observed; record node Phase-2 results + ex-units as the
repo-owned reproducible artifact (produced/verified by the flake check); update
`REPORT.md` with the **qualified** bound (no extrapolation as a universal cap) and
PR #100.
`test(e2e): sweep #99 modify phase-2 batch bound at declared proof depth`

`cardano-tx-tools tx-validate` is Phase-1 preflight only — it does NOT replace
real `withDevnet` submission. Keep PR #100 draft + `gate.sh` installed until both
slices are pair-reviewed, green, and independently verified. Q-file the
orchestrator on any ambiguous pin, toolchain, `additional`-wiring, or #99 wire
adaptation.

## Finalization
Update PR #100 body with delivered behavior, execution units, supported bound,
attack paths proven RED→GREEN, and verification evidence; rerun `./gate.sh` +
`just ci` at HEAD; run the finalization audit against
`specs/99-cage-security/tasks.md`; drop `gate.sh`; mark ready only after local
gate + CI are green. Merge stays with the epic owner — never self-merge.
