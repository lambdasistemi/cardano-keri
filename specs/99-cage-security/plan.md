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

## Finalization
Update PR #100 body with delivered behavior, execution units, supported bound,
attack paths proven RED→GREEN, and verification evidence; rerun `./gate.sh` +
`just ci` at HEAD; run the finalization audit against
`specs/99-cage-security/tasks.md`; drop `gate.sh`; mark ready only after local
gate + CI are green. Merge stays with the epic owner — never self-merge.
