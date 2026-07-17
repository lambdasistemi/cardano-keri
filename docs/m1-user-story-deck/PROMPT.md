# cardano-keri M1 — narrative slide-deck brief

Create a 13-slide, 16:9 (1920×1080) presentation titled **“One identity. New
Cardano authority.”** It explains what cardano-keri M1 enables by following one
composite pilot organization through a complete story. This is not a feature
catalogue and not a roadmap presentation.

The audience is technical peers and prospective pilot counterparties. They
understand keys, signatures, and UTxOs but may not know KERI. The tone is
confident, concrete, and deliberately unhyped.

## The editorial rule

Use one protagonist throughout:

> **Northstar** (clearly labelled “composite pilot”) already operates a standard
> E-prefix Blake3 KERI AID in a Veridian-compatible environment. A 2-of-3 board
> controls its current keys and successor material is held separately.
> Northstar wants one Cardano record controlled by that identity. It refuses to
> re-issue the identity, pin a fixed hot key, or introduce a custodian into the
> operating path.

Every capability must advance Northstar’s journey:

`need → register → use → rotate → recover → trust`

Do not introduce a “cast of six personas” slide. Watchers, auditors, issuers,
and dApp authors appear only when Northstar’s story creates a concrete job for
them.

Every story slide contains:

1. a persona/time kicker;
2. a plain-language outcome title;
3. one user-story sentence in the form “As …, I can …, so that …”;
4. one diagram or one three-column strip;
5. at most three factual proof points;
6. the journey line with the current stage highlighted;
7. speaker notes that state the accuracy boundary.

## Status language

Never blur delivered contract work with the remaining M1 build.

- **MERGED + BYTE-TESTED**: the frozen E-native wire contract and its independent
  Haskell/Aiken vectors and checks.
- **SHIPS WITH M1**: the validator state machine, registration/advance wiring,
  convict/freeze paths, and runnable devnet acceptance demo.
- **NOT IN M1**: credential-chain verification, general authorization envelopes,
  KERI-wallet signing UX, delegated AIDs, and superseding recovery.

Do not use “implemented” as a blanket deck-level adjective.

## Visual system

- Background `#0e1217`; alternate background `#141a22`.
- Panels `#1a212b` or `#212a35`; 1px borders `#2b333e`; 14px radius.
- Text `#e9edf1`; muted `#9aa5b1`; dim `#69737f`.
- Teal `#5cb8b0` / `#86cec7`; amber `#d8a75f`; danger `#d97b6b`.
- IBM Plex Sans for prose; IBM Plex Mono for labels, code, status, and proof
  points.
- Titles 56–60px, weight 600, tight tracking. Body 27–30px. Labels 18–22px.
- Generous whitespace. No stock photos, decorative illustrations, gradients
  pretending to be content, or walls of cards.
- Use teal for valid/current paths, amber for boundaries or lag, and red only
  for an actual rejected attack or permanent conviction.
- The checkpoint asset should be the recurring visual anchor: its identity is
  stable while its key-state datum changes.

## Accuracy rules

The following claims are fixed:

- M1 is E-native. Standard Blake3 E-prefix AIDs register without re-issuance or
  a Cardano-specific identity flavor.
- One AID corresponds to one quantity-one checkpoint token. The asset name is
  deterministically derived from the AID and is stable across rotations.
- The datum carries raw current keys, current threshold, exact KERI `n`/`nt`
  next commitment, witnesses/threshold, Cardano sequence, and native KERI event
  sequence. Raw current keys make normal authorization zero-hash.
- Integer and fractionally weighted multi-clause thresholds are represented;
  zero weights are valid where KERI permits them. Production GLEIF/QVI shapes
  round-trip.
- Rotation enforces the KERI dual-threshold rule and supports partial reserve
  revelation. The live GLEIF Root shape reveals 3 of 7 committed keys and
  carries reserves forward.
- Each revealed successor key costs one Blake3 block, measured at 3.6% CPU and
  4.5% memory of a transaction budget. Plain authorization performs no hash.
- A holder of every current key still cannot rotate without the pre-committed
  successor material. This negative case exists in both implementations.
- For inception events up to 1024 bytes, the hash-proof path verifies
  `blake3(inception_event) == AID` on-chain. This covers observed registering
  production shapes below GLEIF-Root scale.
- **Do not overclaim genesis trust.** The hash proof trustlessly binds the event
  bytes to the AID, and the signed registration package proves key possession;
  semantic projection of CESR fields into the datum remains the explicit
  attested registration boundary with challenge/freeze.
- A dApp resolves the checkpoint by `(policy_id, aid_asset_name)`, includes it
  as a CIP-31 reference input, and revalidates asset, quantity, datum, version,
  lineage, and active/freeze rules against the ledger. An indexer affects
  liveness only.
- Divergence enforcement ships in the M1 validator: a signed conflicting
  rotation can permanently convict/burn the identity and pay the prover; a
  witnessed later KERI event can freeze a lagging checkpoint until it advances.
  Witness signatures alone cannot frame the owner.
- M1 also includes KEL replay/dual-root reconstruction, lifecycle with
  discoverable tombstones, and a per-issuer TEL revocation-status registry.
- The wire contract is frozen and byte-tested across Haskell (195 tests) and
  Aiken (157 checks).
- The M1 acceptance demo is a runnable local-devnet terminal cast: incept a
  2-of-3 identity, write an owned leaf, rotate, and reject a stolen-current-
  quorum rotation attempt.

## Slide sequence

1. **One identity. New Cardano authority.** Establish that this is one pilot
   story. Show the two status chips: wire merged/byte-tested; validator and
   enforcement ship with M1.
2. **They already have an identity.** Introduce Northstar’s existing AID,
   governance, concrete need, and non-negotiables.
3. **Bring the identity you already operate.** Show existing inception event →
   ≤1024-byte hash proof → sovereign quantity-one checkpoint. Include the honest
   semantic-projection boundary in amber.
4. **A stable name for changing authority.** Make the checkpoint asset the
   fixed visual object and show the datum fields that advance.
5. **The board’s real rules survive the move.** Show Northstar’s 2-of-3 rule,
   then the wider weighted/multi-clause/zero-weight compatibility.
6. **Write once. Keep control after every rotation.** Show an owned MPFS leaf
   authorized against the current checkpoint and unchanged after rotation.
7. **Rotate without asking anyone.** Explain the KERI dual-threshold rule,
   partial reserve rotation, and measured per-reveal cost.
8. **Stolen current keys do not control the future.** This is the climax. Show
   “attacker has every current key → rotation rejected” versus “owner reveals
   committed successor keys → checkpoint advances.” State the next-material
   loss boundary.
9. **Contracts follow the identity, not its keys.** Show asset lookup → CIP-31
   reference → ledger revalidation. State that stale indexers delay but cannot
   forge, and frozen state fails closed.
10. **Lying has an on-chain consequence.** Three columns: fork → burn; Cardano
    behind → freeze; Cardano ahead → witness-receipt prevention and later
    convergence/conviction. State “no framing.”
11. **The public evidence creates three useful roles.** Watcher: compare/prove/
    get paid. Auditor: replay/byte-compare/tombstones. Issuer: publish per-issuer
    TEL status. Explicitly scope full credential-chain verification to M2.
12. **One terminal cast is the acceptance test.** Incept → write → rotate →
    stolen-current-quorum attack rejected. Show 195 Haskell tests / 157 Aiken
    checks as contract evidence, not as a substitute for the devnet demo.
13. **What M1 proves—and where it stops.** Two columns: M1 establishes versus
    M2/M3/M5 boundaries. Close with a specific pilot invitation: “one independent
    KERI AID · one Cardano record it should own · one explicit freshness policy.”

## Final quality gate

Reject the output and revise if any of these are true:

- the slides can be reordered without breaking the narrative;
- Northstar disappears for more than two consecutive slides;
- a slide is primarily a list of features rather than a decision, action,
  failure, or consequence;
- “trustless registration” is used without separating byte binding from
  semantic projection;
- M1 validator work is presented as already merged;
- a technical term appears before the user need that makes it relevant;
- any slide contains more than one main visual or more than three proof points;
- the 2-of-3 attack/recovery sequence is not the visual climax;
- the final slide is a generic “thank you” instead of an honest scope and pilot
  invitation.
