# Current state — 2026-10-31

- Desk: Claude Opus 5.5 in pane %240 (Codex seats retired by operator ruling of 2026-10-30).
- #437 retained parking merged as PR 486 (ff78b1c).
- #439 exact consumer identity: PR 487 merged as 9d23a8c; #435 entry 4 updated; issue closed.
- #477 Aiken consumer of the published Singular package: PR 488 merged 2026-10-30 as 2a92c4b; issue closed.
- #343 consumer check in Aiken: PR 491 merged 2026-10-30 as 4554970 (predicate mirrors the Lean clause for clause, 47 predicate tests, 8 validator tests, 7 node-evaluated local-chain cases, 11 caught mutants; labelled test encoding and seeded holding). Issue stays open: next slice binds the #489 bytes and reproduces the vector table; genuine registration journey is #324. Team: ticket owner Opus 5.5, commit owner Sonnet 5.5, auditor Opus 5.5.
- #489 concrete consumer identity bytes in Lean (AID key = qualified CESR text bytes; layout = public Singular preimage module; BLAKE2b-256 in Lean; 8-row checked vector table): PR 490 merged 2026-10-30 as 2c10e45; #435 entry 4 updated; issue closed. Binding the Aiken predicate to these bytes is the next slice of #343.
- Paused 2026-10-30 21:15 UTC and resumed by the operator 2026-10-31 05:55 UTC. #495 (on-chain owner-exit removal, consumer Parked state removed too) merged as PR 496 (9f796bb); #343 item 1 ticked.
- 2026-10-31: #497 (ckeri close and reopen removed from offchain/, plus the Koios classifier that read conviction burns as closes) merged as PR 499 (922e46c). #498 (V2 checkpoint datum and concrete consumer decoder in Lean) merged as PR 500 (68d333d); #435 entry 4, #339 and #343 updated. Operator decisions: the Lean declares V2 first; the AID is carried as qualified CESR text; poisoned, frozen, born-at, refund and termination are datum facts while pool and bond amounts come from the output value (a separate value obligation, #339). Desk ruling: realizesState compares the datum facts only. The #343 Aiken decoder for the V2 datum merged as PR 501 (8391716); #343 keeps only the registration journey (#324). #502 (checkpoint output value in Lean) merged as PR 503 (0eab1e1). Operator decisions 2026-10-31: minimum ADA is separate and equals the registry Mc; the registration carrier is Mc + D + B + pool0 with pool0 chosen per registration; desk rulings under them: registry D = D + B, locked = carrierAda - Mc. Running: lane datum-v2-onchain (Aiken team, ticket owner Opus 5.5 pane %309) makes the checkpoint validator write V2 with the exact held value (#339). Then #324, #325, #354 on a local test chain.
- 2026-10-30 morning goal met: #439, #477, #489 and #343 merged in part (PRs 487, 488, 490, 491, 492). #343 parked open: datum layout in Lean, registration journey #324.
- #493 merged as PR 494 (1a73568): the Lean, simulators, corpora and docs have no owner exit. Open economic item: an honest owner cannot recover deposit, freeze bond or pool except through conviction or premiums. 26 affected issues rescoped 2026-10-30; #229 closed not planned; #227 retargeted to signing for rotation and poison intents; #343 rescoped (remove Aiken parked state, datum decoder binding, registration journey).
- Operator ruling 2026-10-30: no owner exit; a checkpoint is alive until convicted (parking economics unsettled: deposit holder while parked, sponsor tracking; parking returns only with an economic model settling both). #342, #349, #358 closed as not planned; #435 entry 2 records it. #493 (one Opus 5.5 writer, window cardano-keri-ms1-lean-no-owner-exit) removes park, revive and owner close from the Lean first; Aiken and off-chain follow-ups and issue rescoping come from its affected-issues list.
- Order now: #493 Lean; then the Aiken and off-chain follow-ups it names; then #324, #325, #354 on a local test chain.
- Held: #356 preprod deployment, #328 cutover, #357 release, and release PR 485.

The sections below are the 28 October intake record and remain valid where not superseded above.

# Identity core milestone — current delivery snapshot

Updated 28 October 2026. As an identity controller, register once, maintain a witnessed checkpoint, park and revive with the retained token and last key state, and have proven duplicity permanently retire the identity. As a relying application, use the exact checkpoint asset and canonical registry to authorize a real downstream transaction within its validity interval.

Current delivery is limited to a local test chain. Preprod deployment, cutover and release remain held. The code is not for mainnet. This snapshot replaces the September execution order; historical evidence remains in the linked issues and pull requests.

## Current evidence

Main is a4c103726c41c5f3d2ab4788bec92ff28efbb0aa. The concrete duplicity model and qualified theorem identity repair landed in [PR #483](https://github.com/lambdasistemi/cardano-keri/pull/483), closing #438 and #387. This establishes the bounded model and simulator results described there, not Aiken/Haskell or connected ledger correspondence. No open pull request was reported at intake.

## Delivery order

1. Bind the KERI Lean model to the exact public Singular main revision delivering the new contract. Align retained parking (#437) and the consumer's exact token, registry and validity end (#439). Public upstream delivery: [registration](https://github.com/lambdasistemi/singular/issues/742), [termination](https://github.com/lambdasistemi/singular/issues/743).
2. Deliver the reproducible pinned Aiken consumer check (#477). Its technical compatibility evidence does not accept application behavior.
3. Implement the consumer mirror (#343), park (#342) and revive (#349) against the accepted model.
4. Integrate the application (#324), packaged commands (#325) and connected local story replay (#354). Request custody, reclaim and refunds still depend on #468; these obligations are not waived by this order.
5. Hold preprod deployment (#356), cutover (#328) and release (#357). Other independent work is not dispatched by this snapshot.

## Contract evidence

The conviction row in registry.md now names the enforcing model declarations and finite controls from PR #483. Production enforcement remains open. Remaining legacy registry rows retain their original evidence limits; none gains acceptance from this sweep. Retained parking, exact consumer identity, request custody and connected implementation correspondence remain open requirements.

## Recovery and reporting

The current session and authorized writer arrangement are in session.md. The complete prior snapshot is preserved locally under /home/paolino/.orch-runtime/cardano-keri/m1/handoffs/prior-milestone-snapshot, bound to revision 62d696da14e882c3389ab37c6d072828ffb7eb0d; unresolved historical decisions remain subject to their current issues and accepted rulings. No implementation worker is active at this intake. The milestone owner reviews statements before push and grants merge only after exact-head checks and acceptance review.

The [milestone wiki](https://github.com/lambdasistemi/cardano-keri/wiki/Milestone-1) still contains an older story projection. Its last observed remote revision is c027adaa79187af27759f223926626b82ffcde55. Full story reconciliation and publication are pending; this snapshot does not claim the wiki is current.

## Issue inventory

This is a state census, not an acceptance claim. Closed requirements retain the limits stated in their issue and PR records. Every open issue remains an obligation unless explicitly superseded; state alone does not settle dispatch or acceptance.

| Issue | State | Title |
| --- | --- | --- |
| [#15](https://github.com/lambdasistemi/cardano-keri/issues/15) | closed | docs: re-vet the canonical permissionless model |
| [#24](https://github.com/lambdasistemi/cardano-keri/issues/24) | closed | epic: the V1 validator — an identity's on-chain life, from registration to retirement |
| [#26](https://github.com/lambdasistemi/cardano-keri/issues/26) | closed | feat: migrate legacy entries and restrict shutdown so owners cannot lose their data |
| [#43](https://github.com/lambdasistemi/cardano-keri/issues/43) | closed | docs: roadmap page — milestone layout and overall plan |
| [#44](https://github.com/lambdasistemi/cardano-keri/issues/44) | closed | demo(identity): watch it work end to end — one identity, one key rotation, two attacks that fail |
| [#49](https://github.com/lambdasistemi/cardano-keri/issues/49) | closed | docs: fix status claims in vlei.md gap table; super-watcher and runway notes in roadmap |
| [#68](https://github.com/lambdasistemi/cardano-keri/issues/68) | closed | design(identity): freeze weighted CheckpointDatumV1 and CBOR boundary |
| [#69](https://github.com/lambdasistemi/cardano-keri/issues/69) | closed | fix(super-watcher): burning an identity's record must leave a permanent tombstone, not erase it |
| [#70](https://github.com/lambdasistemi/cardano-keri/issues/70) | closed | fix(identity): the emergency freeze exposes the identity's reserve key without rotating to it |
| [#71](https://github.com/lambdasistemi/cardano-keri/issues/71) | closed | spec(identity): fully specify the emergency-freeze transaction and sign the key it reveals |
| [#72](https://github.com/lambdasistemi/cardano-keri/issues/72) | closed | fix(identity): a single freeze signature can be replayed to keep an identity frozen forever |
| [#75](https://github.com/lambdasistemi/cardano-keri/issues/75) | closed | design(super-watcher): the misbehaviour bond is advertised as a guarantee it cannot yet deliver |
| [#76](https://github.com/lambdasistemi/cardano-keri/issues/76) | closed | fix(identity): duplicity detection misses real forks and can destroy an innocent identity |
| [#77](https://github.com/lambdasistemi/cardano-keri/issues/77) | closed | fix(identity): rotation redeemer must bind rot_msg to new_next/trie_key/seq_to |
| [#78](https://github.com/lambdasistemi/cardano-keri/issues/78) | closed | design(deposit): the docs disagree about how the security deposit works — pick one model |
| [#79](https://github.com/lambdasistemi/cardano-keri/issues/79) | closed | spec(identity): identity_root single-value vs sliding-window; inception staleness; typing |
| [#81](https://github.com/lambdasistemi/cardano-keri/issues/81) | closed | spec(identity): remove passive delegator field from CheckpointDatumV1 |
| [#84](https://github.com/lambdasistemi/cardano-keri/issues/84) | closed | docs: bring the hash-requirement document up to date with credentials, the CF trust anchor, and the watcher oracle |
| [#106](https://github.com/lambdasistemi/cardano-keri/issues/106) | closed | feat(identity): freeze and fully receipted irreconcilable-fork conviction |
| [#109](https://github.com/lambdasistemi/cardano-keri/issues/109) | closed | chore(88): measure the real cost of blake3 hashing inside full transactions |
| [#135](https://github.com/lambdasistemi/cardano-keri/issues/135) | open | test(e2e): consolidate checkpoint PV11 scenarios into one devnet boot |
| [#156](https://github.com/lambdasistemi/cardano-keri/issues/156) | closed | epic: producer applications — every role behind a CLI (milestone M1) |
| [#157](https://github.com/lambdasistemi/cardano-keri/issues/157) | closed | M1 story: preprod witness pool with a published OOBI list |
| [#158](https://github.com/lambdasistemi/cardano-keri/issues/158) | closed | M1 story: deploy V1 to preprod with a verifiable release manifest |
| [#159](https://github.com/lambdasistemi/cardano-keri/issues/159) | closed | M1 story: a stranger registers their kli identity (incl. 2-of-5) |
| [#160](https://github.com/lambdasistemi/cardano-keri/issues/160) | closed | M1 story: a kli rotation lands on the preprod checkpoint |
| [#161](https://github.com/lambdasistemi/cardano-keri/issues/161) | closed | M1 story: close and reclaim the escrow |
| [#162](https://github.com/lambdasistemi/cardano-keri/issues/162) | open | M1 story: relayer — rotations land with nobody relaying by hand |
| [#163](https://github.com/lambdasistemi/cardano-keri/issues/163) | closed | M1 story: hunter I — freeze, response, claim, thaw on preprod |
| [#164](https://github.com/lambdasistemi/cardano-keri/issues/164) | closed | M1 story: hunter II — witnessed conviction on preprod |
| [#165](https://github.com/lambdasistemi/cardano-keri/issues/165) | closed | M1 story: the endpoint board — a current, on-chain OOBI registry for witnesses |
| [#166](https://github.com/lambdasistemi/cardano-keri/issues/166) | open | M1 story: the stranger run — full lifecycle by docs alone |
| [#168](https://github.com/lambdasistemi/cardano-keri/issues/168) | closed | chore: declare the preprod witness stack in /code/infrastructure (IaC) |
| [#171](https://github.com/lambdasistemi/cardano-keri/issues/171) | closed | epic: the indexer — chain-follower state for every watcher (milestone M1) |
| [#175](https://github.com/lambdasistemi/cardano-keri/issues/175) | closed | M1 story: the follower library — indexed checkpoint state with exact rollback |
| [#176](https://github.com/lambdasistemi/cardano-keri/issues/176) | closed | M1 story: the query endpoint — the follower hosted, answers without a node |
| [#177](https://github.com/lambdasistemi/cardano-keri/issues/177) | closed | M1 story: one interface, three backends — ckeri reads local, hosted, or third-party |
| [#181](https://github.com/lambdasistemi/cardano-keri/issues/181) | closed | M1 story: no cardano-cli in the transaction path — build, sign and submit in-process |
| [#183](https://github.com/lambdasistemi/cardano-keri/issues/183) | open | chore: replace CheckpointTxBuilder's bespoke assembly — import and instantiate the tx-build abstraction |
| [#184](https://github.com/lambdasistemi/cardano-keri/issues/184) | open | chore: audit the settled M1 tree and derive the release-quality remediation map |
| [#185](https://github.com/lambdasistemi/cardano-keri/issues/185) | open | chore: independently prove M1 release quality from a fresh checkout |
| [#186](https://github.com/lambdasistemi/cardano-keri/issues/186) | closed | epic: M1 release hardening — enforce whole-repository quality before release |
| [#196](https://github.com/lambdasistemi/cardano-keri/issues/196) | closed | chore: release pipeline — publish runnable artifacts from cardano-keri (day 0) |
| [#219](https://github.com/lambdasistemi/cardano-keri/issues/219) | closed | onchain: finish the permissionless migration on the advance path (M1, blocks #162/#163/#164/#166) |
| [#220](https://github.com/lambdasistemi/cardano-keri/issues/220) | open | M1 story: hear a rotation — resolve witnesses from the board, fetch and verify the KEL (ckeri verify) |
| [#226](https://github.com/lambdasistemi/cardano-keri/issues/226) | open | M1: register needs two plain UTxOs and says so nowhere — the first-run wall |
| [#227](https://github.com/lambdasistemi/cardano-keri/issues/227) | open | release: ship signing support for next-key checkpoint parking |
| [#228](https://github.com/lambdasistemi/cardano-keri/issues/228) | closed | M1: status crashes without --board-manifest, whose default path only exists in a checkout |
| [#229](https://github.com/lambdasistemi/cardano-keri/issues/229) | open | close routes the entire fee-UTxO remainder to --change-address |
| [#231](https://github.com/lambdasistemi/cardano-keri/issues/231) | open | errors surface as raw GHC IOException traces; the actionable line is buried |
| [#232](https://github.com/lambdasistemi/cardano-keri/issues/232) | closed | M1: collateral exposure is unbounded — a failed script seizes the entire second-largest UTxO |
| [#235](https://github.com/lambdasistemi/cardano-keri/issues/235) | closed | M1: E2E (withDevnet)'s Plutus blueprint is a stale fixed-output derivation, silently decoupled from onchain/ source since 8edfa8b |
| [#237](https://github.com/lambdasistemi/cardano-keri/issues/237) | open | list aborts entirely when one AID has duplicate live checkpoints |
| [#238](https://github.com/lambdasistemi/cardano-keri/issues/238) | open | payer omits UTxO values, and its as_of_slot answers the wrong question |
| [#239](https://github.com/lambdasistemi/cardano-keri/issues/239) | open | ckeri: report parked and terminal identities consistently across read commands |
| [#240](https://github.com/lambdasistemi/cardano-keri/issues/240) | closed | M1: remove Koios from the write path — local tier only |
| [#241](https://github.com/lambdasistemi/cardano-keri/issues/241) | closed | M1: close and board-close still need Koios — the historical-read half of #240 |
| [#253](https://github.com/lambdasistemi/cardano-keri/issues/253) | closed | onchain: OOBI board registration binds no nonce — bind owner + sequence to the witness signature |
| [#254](https://github.com/lambdasistemi/cardano-keri/issues/254) | closed | onchain: support checkpoint validator version migration — do not repeat MPFS's stuck-at-v0 trap |
| [#257](https://github.com/lambdasistemi/cardano-keri/issues/257) | closed | M1: refactor the chain-query layer — free query algebra, providers as interpreters, atomic snapshots |
| [#259](https://github.com/lambdasistemi/cardano-keri/issues/259) | closed | M1: the gate silently rewrites flake.lock — a declared input is unlocked, and nothing checks it |
| [#262](https://github.com/lambdasistemi/cardano-keri/issues/262) | closed | Route every write-path read through the ChainQuery algebra (INV-240-LOCALTIER, split from #240) |
| [#263](https://github.com/lambdasistemi/cardano-keri/issues/263) | closed | The deployed endpoint-board validator cannot be rebuilt from this repository (frozen policy id has no preimage) |
| [#265](https://github.com/lambdasistemi/cardano-keri/issues/265) | closed | Replace #262 public-surface text heuristics with GHC export information |
| [#266](https://github.com/lambdasistemi/cardano-keri/issues/266) | closed | Derive the public-surface guard from GHC export information instead of hand-rolled source scanning (split from #262) |
| [#271](https://github.com/lambdasistemi/cardano-keri/issues/271) | closed | onchain: enforcement bounty payees are unauthenticated — a mempool observer steals the hunter and convictor rewards |
| [#272](https://github.com/lambdasistemi/cardano-keri/issues/272) | closed | constitution + docs: state the KERI projection law, and fix the doc rows that made an audit invent a requirement |
| [#274](https://github.com/lambdasistemi/cardano-keri/issues/274) | closed | epic: the on-chain block — projection law, validator migration, board binding, bounty authentication |
| [#275](https://github.com/lambdasistemi/cardano-keri/issues/275) | open | chore: scrub internal-process leaks from PR descriptions across the repository |
| [#279](https://github.com/lambdasistemi/cardano-keri/issues/279) | open | onchain: inventory preprod v0 checkpoints before the cutover — an ARMED or FROZEN checkpoint blocks it entirely |
| [#291](https://github.com/lambdasistemi/cardano-keri/issues/291) | open | fix: the checkpoint lets the submitter choose which event type it is reading |
| [#318](https://github.com/lambdasistemi/cardano-keri/issues/318) | open | epic K0: the record — design note 003, the Lean merged, the clarity record folded in |
| [#319](https://github.com/lambdasistemi/cardano-keri/issues/319) | open | epic K1: slim main — delete the enforcement economy and the M1.2 skeleton, measure what is left |
| [#320](https://github.com/lambdasistemi/cardano-keri/issues/320) | open | epic K2: INV-BIND on the slimmed tree, and the advance-versus-keripy parity oracle |
| [#321](https://github.com/lambdasistemi/cardano-keri/issues/321) | open | epic K3: receipts budget spike — measure verification cost before the hunter's edges |
| [#322](https://github.com/lambdasistemi/cardano-keri/issues/322) | open | epic: datum V2, rotation, poison and retained-output parking |
| [#323](https://github.com/lambdasistemi/cardano-keri/issues/323) | open | epic K5: the hunter's edges — paid advance, freeze, top-up, conviction |
| [#324](https://github.com/lambdasistemi/cardano-keri/issues/324) | open | epic: KERI application integration with the Singular registry backend |
| [#325](https://github.com/lambdasistemi/cardano-keri/issues/325) | open | epic K7: off-chain — every role behind a ckeri command, and the hunter daemon |
| [#326](https://github.com/lambdasistemi/cardano-keri/issues/326) | open | epic K8: the fifteen stories as the acceptance suite |
| [#327](https://github.com/lambdasistemi/cardano-keri/issues/327) | open | epic K9: docs from the stories, the simulations in every page |
| [#328](https://github.com/lambdasistemi/cardano-keri/issues/328) | open | epic: K10 — preprod cutover and identity-core release |
| [#329](https://github.com/lambdasistemi/cardano-keri/issues/329) | closed | epic U1 (upstream tracking): MPFS permissionless batching |
| [#330](https://github.com/lambdasistemi/cardano-keri/issues/330) | closed | epic U2 (upstream tracking): MPFS gating plugin for the keri registry |
| [#331](https://github.com/lambdasistemi/cardano-keri/issues/331) | closed | Lean checkpoint machine (two slices, 62 theorems) and the checkpoint simulator |
| [#332](https://github.com/lambdasistemi/cardano-keri/issues/332) | open | docs: DESIGN NOTE 003 — the checkpoint, its poison, its bonds and the registry, from the design page |
| [#333](https://github.com/lambdasistemi/cardano-keri/issues/333) | open | lean: fold the simulator's clarity record into the Lean doc comments |
| [#334](https://github.com/lambdasistemi/cardano-keri/issues/334) | open | onchain+offchain: delete the enforcement economy, lifting convict_predicate first |
| [#335](https://github.com/lambdasistemi/cardano-keri/issues/335) | open | onchain: delete the M1.2 skeleton, keep the MPF dependency and the proof-check recipe |
| [#336](https://github.com/lambdasistemi/cardano-keri/issues/336) | open | onchain: the size table of the surviving scripts after the deletion |
| [#337](https://github.com/lambdasistemi/cardano-keri/issues/337) | open | onchain: the advance-versus-keripy parity oracle, with a mutant that flips the witness set |
| [#338](https://github.com/lambdasistemi/cardano-keri/issues/338) | open | onchain: measure advance verification cost by witness count and signer count |
| [#339](https://github.com/lambdasistemi/cardano-keri/issues/339) | open | onchain: datum V2 and registration with the three value components |
| [#340](https://github.com/lambdasistemi/cardano-keri/issues/340) | open | onchain: rotate with bond options and the signed intent |
| [#341](https://github.com/lambdasistemi/cardano-keri/issues/341) | open | onchain: poison — the current quorum declares the epoch untrustworthy |
| [#342](https://github.com/lambdasistemi/cardano-keri/issues/342) | open | onchain: park the checkpoint with its token and last key state |
| [#343](https://github.com/lambdasistemi/cardano-keri/issues/343) | open | onchain: the consumer predicate in Aiken, checked against the Lean's decidable mirror |
| [#344](https://github.com/lambdasistemi/cardano-keri/issues/344) | open | onchain: advance paid from the pool, unpaid when the pool is short |
| [#345](https://github.com/lambdasistemi/cardano-keri/issues/345) | open | onchain: freeze — take the freeze bond when the pool is short |
| [#346](https://github.com/lambdasistemi/cardano-keri/issues/346) | open | onchain: top-up — anyone adds to the pool |
| [#347](https://github.com/lambdasistemi/cardano-keri/issues/347) | open | onchain: convict on a duplicity proof — seize the bond, end the identity |
| [#348](https://github.com/lambdasistemi/cardano-keri/issues/348) | open | onchain: KERI registration approval and Singular-backed checkpoint creation |
| [#349](https://github.com/lambdasistemi/cardano-keri/issues/349) | open | onchain: revive a parked KERI output while the Singular leaf stays active |
| [#350](https://github.com/lambdasistemi/cardano-keri/issues/350) | open | onchain: permanent Singular retirement on KERI conviction |
| [#351](https://github.com/lambdasistemi/cardano-keri/issues/351) | open | ckeri: the owner's commands — register-request, advance with a bond option, poison, close, reopen, top-up |
| [#352](https://github.com/lambdasistemi/cardano-keri/issues/352) | open | ckeri: the hunter daemon — watch the KEL, advance or freeze, convict on proof |
| [#353](https://github.com/lambdasistemi/cardano-keri/issues/353) | open | follower, indexer and query endpoint on datum V2 and the registry leaf |
| [#354](https://github.com/lambdasistemi/cardano-keri/issues/354) | open | e2e: replay the simulator's story trees as transaction sequences on a devnet |
| [#355](https://github.com/lambdasistemi/cardano-keri/issues/355) | closed | docs: the user guide rewritten from the stories, with the simulation on every page |
| [#356](https://github.com/lambdasistemi/cardano-keri/issues/356) | open | preprod: deploy the family and the registry store, reissue the manifests, migrate the operator's identities |
| [#357](https://github.com/lambdasistemi/cardano-keri/issues/357) | open | release: publish the accepted identity-core artifact after version reconciliation |
| [#358](https://github.com/lambdasistemi/cardano-keri/issues/358) | open | lean: bind retained-output parking to next-key and payee authorization |
| [#359](https://github.com/lambdasistemi/cardano-keri/issues/359) | closed | lean: checkpoint machine slice 3 — active / parked(hash) / convicted; leaving is the reap, no withdraw, no unbonded checkpoint (D-040) |
| [#361](https://github.com/lambdasistemi/cardano-keri/issues/361) | open | registry simulator: story trunks end on the state the reader wanted; mechanical refusals become forks |
| [#362](https://github.com/lambdasistemi/cardano-keri/issues/362) | open | gates: assert the denominator — an empty run must be RED, not GREEN |
| [#363](https://github.com/lambdasistemi/cardano-keri/issues/363) | closed | Checkpoint inversions: one public inversion per Step ctor, 100% gate |
| [#364](https://github.com/lambdasistemi/cardano-keri/issues/364) | closed | Registry inversions (+ Step-relation decision) |
| [#365](https://github.com/lambdasistemi/cardano-keri/issues/365) | closed | Historical semantic-atom coverage and non-vacuity witnesses |
| [#366](https://github.com/lambdasistemi/cardano-keri/issues/366) | closed | Lifecycle disposition + hash-bound audit report |
| [#367](https://github.com/lambdasistemi/cardano-keri/issues/367) | closed | Lean FULL close-out: inversions, semantic atoms, and missing mutant surfaces |
| [#368](https://github.com/lambdasistemi/cardano-keri/issues/368) | closed | Hash-bound Lean audit report (serial tail) |
| [#374](https://github.com/lambdasistemi/cardano-keri/issues/374) | closed | Factor simulator session-tree into headless backend modules with CLI |
| [#375](https://github.com/lambdasistemi/cardano-keri/issues/375) | closed | Author simulator scenarios in a terse DSL compiling to the current JSON |
| [#376](https://github.com/lambdasistemi/cardano-keri/issues/376) | open | Devnet runner reads the scenario DSL |
| [#377](https://github.com/lambdasistemi/cardano-keri/issues/377) | open | Promote free-played stories N1–N11 to the acceptance suite |
| [#381](https://github.com/lambdasistemi/cardano-keri/issues/381) | open | epic: Singular backend readiness for Cardano KERI M1 |
| [#382](https://github.com/lambdasistemi/cardano-keri/issues/382) | open | test(e2e): the withDevnet smoke races the validity interval and blocks unrelated branches |
| [#383](https://github.com/lambdasistemi/cardano-keri/issues/383) | closed | Semantic-atom campaign re-cut: gate executability + fresh audit (F-365-001) |
| [#387](https://github.com/lambdasistemi/cardano-keri/issues/387) | closed | two tools truncate qualified Lean names, and both check by count instead of identity |
| [#400](https://github.com/lambdasistemi/cardano-keri/issues/400) | open | the interface we offer, with ckeri as its first consumer |
| [#404](https://github.com/lambdasistemi/cardano-keri/issues/404) | open | Design shared GLEIF KEL/TEL sponsorship without issuer participation in Cardano |
| [#405](https://github.com/lambdasistemi/cardano-keri/issues/405) | open | Pre-fund checkpoint unfreezing with a sponsor-funded locked reserve |
| [#406](https://github.com/lambdasistemi/cardano-keri/issues/406) | open | Protect sponsor funds from issuer-driven rewards and closure |
| [#408](https://github.com/lambdasistemi/cardano-keri/issues/408) | closed | registry: remove pause, the on-chain parked state and grace window after ruling 12 |
| [#409](https://github.com/lambdasistemi/cardano-keri/issues/409) | open | Bring the identity watcher and funding invariants into executable Lean |
| [#410](https://github.com/lambdasistemi/cardano-keri/issues/410) | open | Record Lean invariant coverage and baseline attack traces |
| [#411](https://github.com/lambdasistemi/cardano-keri/issues/411) | open | Ordinary KEL evidence and watcher |
| [#412](https://github.com/lambdasistemi/cardano-keri/issues/412) | open | Challenge alternatives |
| [#413](https://github.com/lambdasistemi/cardano-keri/issues/413) | open | Sponsor ownership and loss |
| [#414](https://github.com/lambdasistemi/cardano-keri/issues/414) | open | Prepaid recovery and shared operation |
| [#415](https://github.com/lambdasistemi/cardano-keri/issues/415) | open | Identity-core composition and review |
| [#416](https://github.com/lambdasistemi/cardano-keri/issues/416) | open | Keep authenticated ordinary KEL key-state history in the checkpoint |
| [#418](https://github.com/lambdasistemi/cardano-keri/issues/418) | open | docs: explain retained tokens, parking revival and freeze in checkpoint stories |
| [#422](https://github.com/lambdasistemi/cardano-keri/issues/422) | open | release: the release pipeline has been red since 7 September — a stale release PR blocks every new one |
| [#424](https://github.com/lambdasistemi/cardano-keri/issues/424) | open | gates: the three simulator gates are wired into nothing — CI never runs them |
| [#426](https://github.com/lambdasistemi/cardano-keri/issues/426) | closed | docs: the registry's upstream is singular, not cardano-mpfs-onchain |
| [#429](https://github.com/lambdasistemi/cardano-keri/issues/429) | closed | docs: link the KERI specification from every story page, at the pinned version |
| [#431](https://github.com/lambdasistemi/cardano-keri/issues/431) | closed | docs: three corrections the onboarding readers surfaced (first-seen, terminal conviction, six programs) |
| [#433](https://github.com/lambdasistemi/cardano-keri/issues/433) | closed | docs: the project's words, define or rename; retire "the M1 return" as a name |
| [#434](https://github.com/lambdasistemi/cardano-keri/issues/434) | closed | constitution: Lean is the behavioral authority, model-first rulings, retroactive |
| [#435](https://github.com/lambdasistemi/cardano-keri/issues/435) | open | Lean correspondence register: where the repository already diverges from its model, as user stories awaiting rulings |
| [#437](https://github.com/lambdasistemi/cardano-keri/issues/437) | open | lean: dormancy in the KERI application — a parked identity keeps its output, the registry leaf stays active |
| [#438](https://github.com/lambdasistemi/cardano-keri/issues/438) | closed | lean: make the duplicity predicate concrete, conformant to KERI 1.1 |
| [#439](https://github.com/lambdasistemi/cardano-keri/issues/439) | open | lean: the consumer predicate gains the exact token, the canonical registry and the validity end |
| [#446](https://github.com/lambdasistemi/cardano-keri/issues/446) | closed | lean: bind to Singular's Lean as a pinned dependency (final re-cut) |
| [#449](https://github.com/lambdasistemi/cardano-keri/issues/449) | open | preprod demos: verify manifests and board state through the indexer |
| [#450](https://github.com/lambdasistemi/cardano-keri/issues/450) | open | plan: reconcile v1/v2 demo milestones with the 0.5.0 release tickets |
| [#451](https://github.com/lambdasistemi/cardano-keri/issues/451) | open | 2026-10-23 — Cardano KERI Singular-backend mapping review (target) |
| [#452](https://github.com/lambdasistemi/cardano-keri/issues/452) | open | 2026-12-07 — Registry-backed identity registration (target) — [Cardano KERI v1.0.0 planned] |
| [#453](https://github.com/lambdasistemi/cardano-keri/issues/453) | open | 2026-12-22 — Identity register and advance (target) — [Cardano KERI v1.0.0 planned] |
| [#454](https://github.com/lambdasistemi/cardano-keri/issues/454) | open | 2027-01-06 — Hunter advance and short-pool branch (target) — [Cardano KERI v1.0.0 planned] |
| [#455](https://github.com/lambdasistemi/cardano-keri/issues/455) | open | 2027-01-21 — Application park/revive and permanent conviction (target) |
| [#456](https://github.com/lambdasistemi/cardano-keri/issues/456) | open | 2027-02-05 — Identity role commands (target) — [Cardano KERI v1.0.0 planned] |
| [#457](https://github.com/lambdasistemi/cardano-keri/issues/457) | open | 2027-02-20 — Identity story suite on preprod (target) — [Cardano KERI v1.0.0 planned] |
| [#458](https://github.com/lambdasistemi/cardano-keri/issues/458) | open | 2027-03-07 — Preprod cutover rehearsal (target) — [Cardano KERI v1.0.0 planned] |
| [#459](https://github.com/lambdasistemi/cardano-keri/issues/459) | open | 2027-03-22 — Identity preprod release journey (target) — [Cardano KERI v1.0.0 planned] |
| [#468](https://github.com/lambdasistemi/cardano-keri/issues/468) | open | lean: KERI owns request processing, reclaim and refunds on the redesigned Singular registry |
| [#477](https://github.com/lambdasistemi/cardano-keri/issues/477) | open | build: pin a reproducible Aiken consumer to the redesigned Singular package |
| [#478](https://github.com/lambdasistemi/cardano-keri/issues/478) | closed | lean: pin a compatible Singular main revision after the Lean 4.27 repair |
| [#480](https://github.com/lambdasistemi/cardano-keri/issues/480) | closed | Reconcile conviction payouts with Singular's ruled termination economics |
| [#482](https://github.com/lambdasistemi/cardano-keri/issues/482) | closed | Lean dependency check: the pinned Singular checkout's hash changes between fetches (fetchgit leaveDotGit) |
