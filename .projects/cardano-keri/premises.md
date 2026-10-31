# cardano-keri product premises

## 2026-08-31 — added this sweep

- 2026-08-29: PR #309 merged as `524ffd4`. `docs/design/key-compromise.md` added:
  current-key theft, `ixn` is off-chain-only and unprojected in V1, Close and
  value-auth are the on-chain exposure, rotation supersedes `ixn` and is not
  retroactive. **Conviction is a penalty and a permanent record, NOT
  terminality**; there is no mint-once/unicity and a convicted AID may
  re-register, because Cardano mirrors KERI. TOMBSTONE removed as a role/state
  across 11 files. `mkdocs --strict` clean.
- **SIZE is the binding budget, not execution.** `s0_append` is 8471 B = 52.5%
  of the 16,133 B ceiling, leaving ~4436 B before the redesign threshold. The
  co-residency set append+cursor+staging is 25,617 B = 158.78%, i.e. headroom
  of **minus 9484 B**. No m12 script has any measured execution number at all.
  Per-script green does not prove the central transaction fits.
- Per D-007 the 158.78% co-residency sum is **not** an M1-shaped NO-GO by
  resemblance. It is a measured S2 question: prove witness mode first, cite the
  pinned `maxRefScriptSizePerTx` and reference-script fee tiers, test the inline
  branch, and only then decide whether the append/cursor authentication coupling
  changes.
- The pinned Aiken MPF hashes its keys, so `location||SAID` has no trie locality
  and prefix enumeration is impossible with the stock library; MPF commits no
  cardinality, so a root cannot bound "how many". `occupancy_root` and
  `HistoricalProof.location` are written and never read.
- MPF is pinned at **v2.0.0** (`onchain/aiken.toml:23`) and is missing two
  proof-verification correctness fixes — v2.0.1 leaf-fork-with-nonzero-common-prefix
  and v2.1.0 terminal-fork-with-nonempty-prefix, both in `excluding()`, on which
  the path insert and delete depend. A live defect in shipped code.
- **The repo has no current account of witnessing.** trust-model.md,
  super-watcher.md, aid-model.md and lifecycle-and-bonds.md were all last
  touched 2026-07-28 — before the 2026-08-18 M1-terminal NO-GO and before the
  decomposition — so they describe the superseded monolithic design and still
  use "fully witnessed" as the OLD binary conviction predicate. M1.2's
  three-way receipt grading (fully-witnessed / partial / bare; never gating,
  never economic) is explained in no design document.
- The gist "pen" construction and the merged design record are **not** in
  contradiction; they layer. The record binds the cursor (never resolve by slot,
  abstain); the pen binds an off-chain witness daemon's receipting policy, which
  KERI leaves to the witness. The cursor still counts only signed receipts.
  Residual: R300-4's mutant must stay scoped to the CURSOR.
- An external reviewer (Fergal O Connor, via the operator) has read two gists
  describing this design. External-reader exposure exists; the experiment-claims
  policy is unchanged by it.
- `ckeri` is at v0.4.0, cut 2026-08-04, **before** M1.2 was founded. Nothing
  from this milestone has shipped.
- Host floors v2 remain a correctness boundary: stop AT 50.00 GiB and never
  start a sequence of N cold realizations below `50.00 + 3.10 × N` GiB; one cold
  realization at a time for M1.2.
- Unchanged: no mainnet, production rollout, announcement, external commitment,
  or product graduation is authorized.


## 2026-08-18 — premises in force

- The project is an **architectural experiment**, not a production or mainnet
  system. Source: GitHub milestone 11 mandate and the written S0+S1 release.
- M1 is terminal. Its monolithic checkpoint compiles to 25,934 bytes before
  parameter application, 158.3% of the 16,384-byte transaction limit and
  160.8% of the 16,133-byte reference-program ceiling. The project decision is
  DO NOT SHIP that architecture.
- The INV-BIND decoder defect was real and its repair is proven. That component
  evidence is retained and does not make the oversized architecture feasible.
- M1.2 is the operator-commissioned redesign: a decomposed append/record,
  derived cursor, lineage lifecycle, maintenance escrow, staged proof-token
  path, and consumer predicate family.
- The current S0 evidence is not the early provisional 6–31% table. After the
  audit-triggered redesign, all seven members pass the per-script threshold,
  with append/cursor/staging near 52–54%; acceptance is still under fresh
  audit. Per-script green does not prove the central transaction fits.
- Shipped M1 code structurally uses reference inputs when spending against
  deployed validators, making reference-script cost the strong prior for the
  new family's 25,617-byte co-residency set. The new TxB has not yet proven its
  witness construction; S2 must measure both the reference and inline branches.
- Conditional release `c6a88a47…` is in hand but inactive. It changes no
  present experiment claim and authorizes no S2 work before the two-party
  S0/S1 activation record.
- The residual M1 backlog is not being carried forward unchanged. Its accepted
  ruling is 7 ADOPT / 8 REWRITE / 0 CLOSE against record+cursor. The hunter
  bounty/freeze economy is retired; projection law, duplicity detection,
  consumer refusal, infrastructure, artifact UX, release quality, and the
  proven INV-BIND repair survive in their named forms.
- The preprod inventory issue `#279` targets a future record+cursor cutover.
  This is a product destination premise, not permission to read or write
  preprod; S3/G2 remains withheld.
- A prose triage is not a GitHub mutation manifest. Exact complete final
  issue payloads, fresh concurrency bases, mechanical validation, and project
  acceptance are required before conditional release surface C can execute.
- Graduation remains gated outside M1.2 by one named pilot gating real
  authority on the cursor and one independently operated watcher with a
  published time-to-record. No candidate has been converted into an external
  commitment by this founding.
- Delegation and credential state remain M7/M1bis. No M1.2 scope inference may
  absorb them.
- No mainnet, production rollout, announcement, external commitment, or
  product graduation is authorized.
- Host floors v2 are a correctness boundary: stop AT 50.00 GiB and never start
  a sequence of N cold realizations below `50.00 + 3.10 × N` GiB; one cold
  realization at a time for M1.2.

## Sources

- `/tmp/projects/cardano-keri/inbox/REQUEST-M12-commissioning-2026-08-18.md`
  sha256 `e072e4960b77c68cfda4d894837330e2e08636d39a43c5d05e409200408c715c`.
- GitHub milestone 11 description snapshot sha256
  `0c997ebe646a583e8f95c40a15cb2245c19447cdc69b96f6837a05a8da583454`.
- `/tmp/projects/cardano-keri/inbox/RELEASE-M12-S0-S1-2026-08-18.md`
  sha256 `b0453ae755b56857f7f243c8f089be0b121439f5238e64a35d4c8069acd54609`.
- `/tmp/projects/cardano-keri/inbox/DIRECTIVE-OPERATOR-resume-m1-line-work-2026-08-18.md`
  sha256 `681c78cb865011cb938ccd1791edc2dfeb0a5562c28fc316559eb692a382d2e2`.
- `/tmp/projects/cardano-keri/inbox/RELEASE-M12-S2-CONDITIONAL-2026-08-18.md`
  sha256 `c6a88a475b2bbecbe6f5d03e2604a132283d52c6f5073077a75b62f7209e2f10`.
- `/tmp/machine/TERMINAL-M1-BOTH-VERDICTS-STEERING-PACKAGE.md`
  sha256 `793bab01059d18bd8f9bd20fd9ec3e37b7454b06ea7bb20f87ec1b9ea3d56410`.

## 2026-08-31 evening — added

- The pinned MPF exposes `from_root`, `is_empty`, `has`, `insert`, `delete`,
  `update`, `root`. **No enumeration, no count, no prefix query.** `update` is
  what makes a mutable per-location value possible at all.
- BLS12-381 `g1`, `g2` and `scalar` are already in the Aiken stdlib, so an ECMH
  bucket would have needed no new dependency either. It is nonetheless dropped
  under D-011 — the workaround is unnecessary once key hashing is optional.
- Measured S0 family, against the 16,133 B reference ceiling: append 9,498 B
  (58.9%), staging_proof_token 9,006 B (55.8%), cursor 7,212 B (44.7%). Each
  fits alone; **the three co-resident total 25,716 B = 159%, headroom −9,583 B.**
- The key hashing in MPF exists to keep the trie balanced against adversarial
  key choice. MANDATE-R1 removes submitter key choice entirely, which is the
  premise on which a structured path is safe *for this project* — and the
  premise that must be argued or explicitly scoped before anything is proposed
  upstream.
- **The author of `aiken-lang/merkle-patricia-forestry` is the operator's boss.**
  This is a product-relationship premise, not a technical one, and it governs
  who may speak outward about any of this.

## 2026-09-01 — added

- **V1 admits only establishment events.** `event_decoder.ak:354` accepts
  `icp`, `dip`, `rot`, `drt`; `EventVariant` has no interaction inhabitant.
  Verified in source, not relayed. Registration takes `icp` only, advance takes
  `rot` only, and #115 scoped interactions out on the reasoning that an advance
  is a rotation by definition.
- **First-seen is sound for consistency and unsound for adjudication.** It stops
  a witness equivocating and keeps a served KEL linear and cheap; it also awards
  a contest by arrival order, which is the one variable a thief with stolen
  current keys controls. KERI conflates both roles in one mechanism. Our record
  separates them: it takes no consistency role and no adjudication role, and
  only enlarges the evidence set.
- **Hashing converts a choice attack into a grinding attack** — cost 2^0 to
  2^(4i). R1 already performs that conversion, so a second hash cannot reduce a
  grinding adversary further; its only remaining effect is to destroy locality.
  The hash is load-bearing exactly when the caller lets the submitter choose the
  key. Source: D-012 obligation 1, accepted 2026-09-01.
- **Trie cost gradient**, from the library's own table over `log16(10)=0.83048`:
  one extra level = 127.3 B proof, 36.1 K mem, 16.9 M cpu; an append pays two
  proofs, so 254.6 B per level. The 127.3 B independently recovers the 4×32 B
  neighbors array, confirming the table and the structure are read consistently.
- **Censorship-by-depth fails structurally.** An attacker grinding depth into a
  contested location to price the victim out of publishing cannot target the
  victim's path, because patricia depth is per-path and the victim's path is a
  digest unknown in advance. Blanket depth needs ~16^D separate on-chain
  appends, so victim proof depth is bounded by log16(entries at that location):
  the attacker buys 127.3 B of victim proof per 16× increase in their own spend.
  Economic and logarithmic.
- **A downstream consumer cannot re-derive the cursor.** It reads a datum as a
  CIP-31 reference input and has no execution budget to walk the trie. This is
  a hard constraint on the leaf schema, not a performance preference.

## 2026-09-02 — added this sweep

- The deployed V1 (preprod manifest published 2026-07-28 at `50a5820`) is
  five reference scripts: hash-proof 9,233 B, observer-lifecycle 6,523 B,
  observer-advance 16,130 B (3 B under the 16,133 B ceiling),
  observer-enforcement 14,417 B, checkpoint-register 11,512 B. Parameters:
  registration bond 1,000 tADA, freeze bond 5 tADA, freeze window 10,000.
- `CheckpointDatumV1` is pure key state; enforcement state lives outside it.
  Advance already verifies controller signatures over raw `rot` bytes, the
  dual threshold, and witness receipts against the **new** witness set at the
  **new** `toad`. `ixn`/`dip`/`drt` are rejected. Sequence is strictly +1.
- The proven INV-BIND repair (#291) exists only on this disk:
  `feat/291-inv-bind`, 18 commits, base 2026-08-14, no remote ref, no PR.
- The Lean model on `main` proves the freeze/bond machine (goals 5–21);
  `lifecycle_model.ak` has zero importers.
- The `ckeri` CLI has no enforcement command; the machinery is on chain, in
  Haskell mirrors and vectors, and in the e2e harness only.
- Operator, 2026-09-01: "this project is slowly foundering"; "the only simple
  thing is oracling which I am not interested at all". Operator, 2026-09-02:
  "I am killing M1.2 and going back to M1"; then asked for the audit and plan.
- DESIGN NOTE 002 (https://claude.ai/code/artifact/5cd434d8-d580-440b-8841-0c515d43e5d3)
  is the design basis of the return; it is captured discussion, not a ruling,
  and the audit amends it in five places.
- The public draft (gist `7615e40319a55b8200b9da5ee2cb0169`) and milestone
  12's description still describe the record family. External-reader exposure
  exists (one reviewer read gists on 2026-08-27). The experiment-claims policy
  is unchanged.
- `ckeri` is at v0.4.0 (2026-08-04); PR #311 proposes 0.4.1 (release
  pipeline fix only). Nothing from M1.2 shipped; nothing from the return exists.
- Unchanged: no mainnet, production rollout, announcement, external commitment,
  or product graduation is authorized. Host floors v2 stand.
