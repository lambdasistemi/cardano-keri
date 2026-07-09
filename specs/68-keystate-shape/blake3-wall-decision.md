# Decision record — the Blake3 wall and the CF-as-QVI anchor

Status: **verified feasible; awaiting ratification.** Broader than #68 — this
reframes `blake2b256-requirement.md`, the verification core (#31/#32/#38), and the
"trustless" framing. Should graduate into a `docs/design/` doc once ratified.

## The problem

Plutus has a `blake2b_256` builtin but **no `blake3`**. The vLEI ecosystem — AIDs
*and* ACDC credential SAIDs — is Blake3 (`E`-prefix), rooted at GLEIF. On-chain
verification requires recomputing SAIDs; you cannot recompute a Blake3 SAID in
Plutus. So **native GLEIF vLEI credentials cannot be verified on-chain**, and you
cannot re-hash GLEIF's tree. This looked existential.

## The resolution: anchor trust at a QVI we control (Cardano Foundation)

You do not have to climb the credential chain to GLEIF's root on-chain — only to
whatever issuer you **pin** as trusted. If **Cardano Foundation is the QVI**:

- CF issues its downstream credentials (LE, OOR/ECR, AUTH) with **Blake2b-256
  (`F`) SAIDs** — CF controls its own issuance tooling.
- CF's issuer AID is a **Blake2b (`F`) AID**, pinned on-chain as the trust root.
- On-chain verification of a CF-rooted credential = recompute its `F` SAID
  (`blake2b_256`) + verify the issuer Ed25519 signature against the pinned CF key
  + KEL (rotation) and TEL (revocation) state.
- The **GLEIF → CF** hop (the one Blake3 credential) is **off-chain institutional
  trust** — CF genuinely holds a GLEIF QVI accreditation. Not verified in Plutus.

Bonus: rooting at the QVI instead of GLEIF **drops the on-chain hop bound 4 → 3**.

## Verified facts (research, 2026-07-08)

- **Spec:** SAIDs are digest-agile; CESR code `F` = Blake2b-256; same Saider
  dummy-field mechanism as AID prefixes; nested `a`/`e`/`r` SAIDs too. A verifier
  uses the algorithm named by the SAID's own derivation code — so the credential
  must be **minted** with `F`. (SAID/CESR/ACDC specs.)
- **keripy (issuer side):** Blake2b-256 is first-class — `MatterCodex.Blake2b_256='F'`,
  `Diger` implements it, `Saider.saidify(sad, code=MtrDex.Blake2b_256)` works today.
  Only the `credential()` helper hardcodes Blake3 by not threading the `code` — a
  **small patch** (issuance + schema saidification + tests), no new crypto.
- **signify-ts (wallet side):** `saider.ts` implements only Blake3; the
  lambdasistemi patch covers **AID prefixes only**. Not on the critical path
  (issuance is keripy); wallet needs the AID `F` prefix, which is patched.
- **Issuer auth:** Ed25519 over the SAID is on-chain-checkable given the issuer
  key; the pinned CF AID supplies it. Rotation/revocation need on-chain KEL/TEL —
  i.e. the identity registry (#24) and TEL registry (#30) already in scope.

## The honest trust model

On-chain root of trust = **"Cardano Foundation is the authorized issuer"**
(permissioned anchor, backed off-chain by CF's real GLEIF QVI accreditation), **not**
GLEIF's cryptographic root. Credentials are CF-issued, Blake2b, on-chain-verifiable
— a parallel track, not byte-identical to native GLEIF Blake3 vLEI credentials. This
must be stated plainly wherever the docs claim "on-chain verifiable vLEI."

### Novel, not forbidden, interop-unproven (verified 2026-07-08)

- **No QVI issues Blake2b today.** The entire production vLEI ecosystem is Blake3
  (`E`) — GLEIF Root-of-Trust AID `EINmHd5g...`, all 8 QVIs, every sample. CF would
  be the **first** `F` issuer.
- **Not forbidden.** vLEI EGF v4.0 pins only signature algs (Ed25519/ECDSA) + 128-bit
  strength — **silent on the digest algorithm**. IANA's SAID registration lists
  Blake2b-256 as valid (meets 128-bit). So `F` SAIDs are **spec-compliant**.
- **Interop is the real risk.** keripy's reference verifier can verify `F`, but the
  deployed ecosystem assumes `E`; it is **unconfirmed** whether GLEIF's Reporting API
  / third-party watchers / other QVIs accept `F`. Treat CF Blake2b creds as
  **Cardano-verifiable but CF-parallel** until GLEIF confirms `F` in writing.
- **Mitigations if ecosystem interop is required:** (a) CF **dual-issues** an `E`
  (ecosystem-standard) and an `F` (Cardano-verifiable) credential for the same facts;
  or (b) CF, as a QVI/foundation, gets GLEIF to bless `F` acceptance in writing.

## Working assumption (operator forecast, 2026-07-09)

The positioning call ("CF-anchored Blake2b" vs "real Blake3 ecosystem") is **org-level,
not the engineer's to settle**. Operator forecast, adopted as the working assumption
(both options kept open in the design):

> Target users already hold vLEI credentials from **other QVIs**, in **Blake3**.
> Re-issuing them CF Blake2b credentials is a **big ask**. So the realistic path is the
> **watcher workaround (Blake3→Blake2b bridge) until Plutus has native Blake3** — the
> CF-as-QVI Blake2b path is a fallback/sidecar, not the spine.

Design consequence: build for the **watcher-bridge** path first; keep CF-Blake2b viable
but do not assume re-issuance. The watcher-oracle model below is therefore load-bearing.

## Serving the native Blake3 ecosystem: the watcher as a Blake3-digest oracle

The CF-as-QVI path (Blake2b issuance) is self-sufficient. To *also* verify **native
GLEIF Blake3 credentials** on-chain without a Plutus Blake3 builtin and without
re-issuance, the watcher acts as a **minimal, temporary hash oracle** — NOT a verifier.

- **The verification logic stays on-chain in Plutus.** The watcher attests only
  (a) the ACDC's **existence** and (b) the **Blake mapping** — the Blake3 digest
  values Plutus cannot compute — as inputs to the on-chain verifier. Plutus then
  does all the work trustlessly: Ed25519 issuer-signature over the SAID, edge
  integrity (child edge `n` == parent SAID), schema/role/issuer-AID checks, TEL
  non-revocation.
- **Exact trust boundary.** Because the issuer signature is *over* the SAID and the
  edge equalities are checked on-chain, the *only* thing Plutus cannot check is
  `SAID == blake3(content)` — the self-addressing binding of content to SAID. That
  single binding is what the watcher attests. So the watcher **cannot forge**
  (signatures/edges/revocation are Plutus-verified); its only lever is asserting a
  false `content ↔ SAID` mapping, which is **mechanical, publicly recomputable, and
  bondable/slashable** via the super-watcher.
- **The sunset (why this is not throwaway work).** The on-chain verifier is written
  **once**, against Blake2b-shaped inputs. Today the Blake3 digests come from the
  watcher; the day Plutus gains a Blake3 builtin, the watcher input is dropped and
  the **same verifier computes them itself** — the trust assumption evaporates with
  **zero change to the verification logic**. A Plutus "no" keeps the bridge; a "yes"
  deletes it. Either way the effort stands.
- **The real work underneath** is the super-watcher's bond/slashing soundness
  (vetting **F8**) — that is what keeps the hash oracle honest.

## What this unblocks / touches

- **De-risks the verification core** (#31 ACDC verifier, #32 proof builder, #38
  admission cage): the on-chain verifier only ever sees Blake2b.
- **Softens vetting F8** (super-watcher "can't verify without Blake3") and **F15**
  (feasibility) — for CF-rooted credentials.
- **Confirms #24/#30 are the right substrate** — issuer key rotation and revocation
  are exactly what they provide.
- **#68 (key shape) proceeds on solid ground** — the on-chain verification premise
  is achievable, so the KERI-aligned KeyState work isn't built on sand.

## Follow-up work implied (file as issues once ratified)

1. keripy patch: thread digest `code` through `credential()` / Creder issuance to
   mint `F`-SAID ACDCs (+ schema saidification, tests).
2. Update `blake2b256-requirement.md`: extend the F-prefix mandate from AIDs to
   **credential SAIDs**, and add the CF-as-QVI trust-anchor model + honest framing.
3. Pilot setup (#42/#48): CF issuer AID as a pinned on-chain governance parameter.
