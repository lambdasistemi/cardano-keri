# Identity on Cardano — narrative slide-deck brief

Create a 13-slide, 16:9 (1920×1080) presentation titled **“Keep the identity you
already trust.”** It explains what cardano-keri's first milestone—the identity
core—enables by following one composite pilot organization through a complete
story. This is not a feature catalogue and not a roadmap presentation.

The project plan calls this **Milestone 1 (M1)** internally. Never use a bare
milestone code such as `M1`, `M2`, or `M3` as audience-facing copy. Name the
capability instead: “identity core,” “credential-chain verification,” or
“wallet signing.” Milestone codes may appear in speaker notes after the
capability has been named.

The audience includes technical peers and prospective pilot counterparties.
They may understand keys and signatures but should not need prior KERI
knowledge. The tone is welcoming, concrete, and deliberately unhyped. Write as
if explaining the project to a capable new collaborator: lead with the human
outcome, then introduce the protocol term that makes it possible.

## The editorial rule

Use one protagonist throughout:

> **Northstar** (clearly labelled “composite pilot”) already operates a standard
> E-prefix Blake3 KERI AID in a Veridian-compatible environment. A 2-of-3 board
> controls its current keys, successor material is held separately, and a
> configured KERI witness threshold receipts accepted events.
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
3. one or two complete, conversational sentences explaining why the outcome
   matters to that person or team;
4. one diagram or one three-column strip;
5. at most three factual proof points;
6. the journey line with the current stage highlighted;
7. speaker notes that state the accuracy boundary.

## Status language

Never blur delivered contract work with the remaining identity-core build.

- **MERGED + BYTE-TESTED**: the frozen E-native wire contract and its independent
  Haskell/Aiken vectors and checks.
- **SHIPS WITH THE IDENTITY-CORE MILESTONE**: the validator state machine,
  registration/advance wiring, mandatory witness-receipt checks and two-seal
  handoff, freeze/narrow-conviction paths, and runnable devnet acceptance demo.
- **BUILT IN LATER MILESTONES**: credential-chain verification, general authorization envelopes,
  KERI-wallet signing UX, delegated AIDs, and superseding recovery.

Do not use “implemented” as a blanket deck-level adjective.

## Language system

- Use complete sentences. Avoid stacks of slogan fragments such as “Compare.
  Prove. Get paid.”
- Prefer everyday verbs: “bring,” “find,” “read,” “update,” “pause,” “recover,”
  and “retire.” Put exact protocol verbs such as `mint`, `freeze`, `tombstone`,
  and `convict` in the supporting explanation.
- Define an acronym the first time it appears. For example: “the public KERI
  event log (KEL).”
- Do not assume the audience knows `AID`, `KEL`, `TEL`, `CIP-31`, `n`, `nt`, or
  `kt`. Explain the job first; show the identifier second.
- Security slides should reassure the audience by showing the protection and
  recovery path. Avoid theatrical language such as “identity death” or “lying
  is fatal.”
- Proof points are short supporting sentences, not isolated technical nouns.

## Visual system

- Warm-white background `#f7f6f1`; alternate background `#eef4f2`.
- Panels `#ffffff` or soft teal `#e7f2ef`; 1px borders `#ccd9d5`; 14px radius;
  subtle low-contrast shadows.
- Text `#21343a`; muted `#53666b`; dim `#718187`.
- Teal `#207f7a` / `#126a66`; amber `#a86b16`; danger `#b44d43`.
- IBM Plex Sans for prose; IBM Plex Mono for labels, code, status, and proof
  points.
- Titles 56–60px, weight 600, tight tracking. Body 27–30px. Labels 18–22px.
- Generous whitespace. No stock photos, decorative illustrations, gradients
  pretending to be content, or walls of cards.
- Use teal for valid/current paths, amber for boundaries or lag, and pale red
  only for an actual rejected action or permanent conviction. The overall deck
  should feel open and calm, not like a security incident dashboard.
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
- For a checkpoint with `toad > 0`, every V1 advance additionally requires the
  configured KERI witness threshold's receipts over the anchoring event. Valid
  controller signatures and elapsed time never replace those receipts. A
  witness-set change uses the two-seal handoff; an already witnessless
  (`toad = 0`) checkpoint is an explicit weaker mode.
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
- The third attack is prevented at advance time: without the configured witness
  receipts, proposed Cardano keys never become active and therefore cannot
  authorize an action that a later tombstone would be unable to roll back.
- A witnessed later KERI event can freeze a lagging checkpoint until it advances;
  freeze is permissionless and is not paid from the identity deposit by default.
- Permanent conviction is restricted to a V1-independent-AID conflict proved
  irreconcilable under supported KERI rules. The conflicting establishment
  rotation must satisfy both the pre-committed controller threshold and the
  applicable witness-receipt threshold. The existing quantity-one token moves
  to a permanent tombstone; it is not burned and recreated. Recoverable or
  ambiguous evidence freezes instead. Only successful conviction pays the
  prover from the deposit.
- M1 also includes KEL replay/dual-root reconstruction, lifecycle with
  discoverable tombstones, and a per-issuer TEL revocation-status registry.
- The wire contract is frozen and byte-tested across Haskell (195 tests) and
  Aiken (157 checks).
- The M1 acceptance demo is a runnable local-devnet terminal cast: incept a
  witnessed 2-of-3 identity, write an owned leaf, collect threshold receipts and
  rotate, then reject both a controller-signed receipt-free Cardano-first advance
  and a stolen-current-quorum rotation attempt.

## Slide sequence

1. **Keep the identity you already trust.** Establish that this is one pilot
   story. Define the first milestone as the identity core. Show the two status
   chips: wire merged/byte-tested; the first milestone adds the validator and
   enforcement.
2. **Meet Northstar: a team with an identity already in use.** Introduce Northstar’s existing AID,
   governance, concrete need, and non-negotiables.
3. **Bring your existing identity—no conversion required.** Show existing inception event →
   ≤1024-byte hash proof → sovereign quantity-one checkpoint. Include the honest
   semantic-projection boundary in amber.
4. **Give apps one stable name for your organization.** Make the checkpoint asset the
   fixed visual object and show the datum fields that advance.
5. **Keep the approval rules your team already uses.** Show Northstar’s 2-of-3 rule,
   then the wider weighted/multi-clause/zero-weight compatibility.
6. **Your records stay under the right control.** Show a real Cardano record
   authorized against the current checkpoint and unchanged after rotation.
   Keep the concrete MPFS value-cage implementation in the speaker notes, not
   in audience-facing copy: it is one consumer of the identity core, not part
   of the identity itself.
7. **Update keys directly—with public KERI confirmation.** Explain the KERI
   dual-threshold rule, mandatory witness receipts, no signature-only timeout
   fallback, partial reserve rotation, and measured per-reveal cost.
8. **Losing today’s keys does not mean losing the identity.** This is the
   climax. Show “intruder has every current key → cannot choose tomorrow’s
   keys” versus “owner reveals committed successor keys → recovers the same
   identity.” State the next-material loss boundary.
9. **Apps always read the keys that are valid now.** Show asset lookup → CIP-31
   reference → ledger revalidation. State that stale indexers delay but cannot
   forge, and frozen state fails closed.
10. **Public checks keep Cardano and KERI in sync.** Three columns: Cardano tries
    to move first without receipts → reject before activation; KERI moved first →
    pause without a conviction bounty; irreconcilable, controller-threshold-signed
    and witness-threshold-receipted V1 rotations → move the same token to a
    permanent tombstone and pay the conviction prover. State that recoverable or
    ambiguous evidence freezes rather than destroys the AID.
11. **The same public evidence supports useful services.** Watcher: keep the two
    histories aligned. Auditor: build reports from replayable facts. Issuer:
    publish per-issuer credential status. Explicitly scope full credential-chain
    verification to the next verification milestone; map it to M2 only in the notes.
12. **The end-to-end demo shows the complete journey.** Register → create a record →
    collect receipts and update keys → reject both Cardano-first and stolen-key
    attempts. Show 195 Haskell tests / 157 Aiken checks as
    contract evidence, not as a substitute for the devnet demo.
13. **What this foundation proves—and what comes next.** Two columns: delivered
    by the identity core versus built on top later. Keep M2/M3/M5 mappings in
    speaker notes. Close with a specific pilot invitation: “Bring an
    existing KERI identity, one Cardano record it should control, and a clear
    freshness policy.” Link to the official long-form engineering article for
    readers who want the design reversals, measurements, and threat model.

## Final quality gate

Reject the output and revise if any of these are true:

- the slides can be reordered without breaking the narrative;
- Northstar disappears for more than two consecutive slides;
- a slide is primarily a list of features rather than a decision, action,
  failure, or consequence;
- “trustless registration” is used without separating byte binding from
  semantic projection;
- a bare milestone code appears in visible audience-facing copy;
- M1 validator work is presented as already merged;
- a witnessed advance is shown succeeding with controller signatures alone or
  through a timeout fallback;
- conviction is shown without both controller-threshold signatures and threshold
  witness receipts, or as rollback of an already-settled Cardano action;
- a technical term appears before the user need that makes it relevant;
- any slide contains more than one main visual or more than three proof points;
- the 2-of-3 attack/recovery sequence is not the visual climax;
- the final slide is a generic “thank you” instead of an honest scope and pilot
  invitation.
- the final slide and the engineering article do not link to one another.
