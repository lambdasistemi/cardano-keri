# Dated demo plays

As an integrator, I want each dated identity demo to show a real preprod result from keripy `kli` and `ckeri`, so that I can inspect the KERI event, Cardano transaction and fresh readback together.

Every dated play targets **Cardano preprod**. Keripy owns the identity and exports CESR; `ckeri` consumes that export, submits the corresponding Cardano transaction and reads its settled state. A cast is attached only after that exact preprod journey has run. An executable Lean row or a Node simulator remains design evidence and is not a demo cast for this path.

## Indexer contract for the dated plays

The planned operator stack is the Cardano KERI follower and its indexed RocksDB store. The current `ckeri` write commands require `--store PATH` (or `CKERI_STORE`); readbacks must select `--backend local --store PATH` explicitly, or the indexer-backed query endpoint where that route is supported. Record the follower's chain point and freshness beside every transaction ID. A missing or stale store blocks the connected claim. The [status backend guide](../user/status-backends.md) gives the exact query syntax; its implicit default is still Koios, so a bare `ckeri status` is insufficient evidence for this plan.

The [V1 baseline cast](preprod-v1-baseline.md) used the older `ckeri` 0.4.0 Koios path and remains an accurate historical recording. Its Koios-backed manifest verification does not certify an indexer-only future play. The current `ckeri manifest verify` still uses Koios for live references; [#449](https://github.com/lambdasistemi/cardano-keri/issues/449) tracks the indexed verification and board read path. Singular's persistent registry follower is [Singular #107](https://github.com/lambdasistemi/singular/issues/107).

## Planned major release tags

| Milestone | Plays | Planned tag | Tag gate |
| --- | --- | --- | --- |
| Singular registry handoff M1 | D-01 | Singular `v1.0.0` | Connected registry replay and released archive. |
| Singular naming and escrow M2 | D-02 and D-03 in parallel | Singular `v2.0.0` | Connected D-03 acceptance. |
| Cardano KERI identity core M1 | D-02 mapping, D-04–D-11 | Cardano KERI `v1.0.0` | D-11 cutover, story suite and release artifact. |
| Cardano KERI credential gate M2 | D-12–D-19 | Cardano KERI `v2.0.0` | D-19 valid and revoked preprod transactions. |

These are **planned identities**, not existing git tags or releases. Intermediate plays use named candidates and exact artifact hashes; the milestone tag is cut only at its release gate. The current public tags are still below `v1.0.0`, and the Cardano KERI release planner requires a deliberate Cabal major-version change before the first major tag.

The existing [M1 release epic #328](https://github.com/lambdasistemi/cardano-keri/issues/328) and [release child #357](https://github.com/lambdasistemi/cardano-keri/issues/357) still say `0.5.0`. [#450](https://github.com/lambdasistemi/cardano-keri/issues/450) tracks the reviewed version-policy reconciliation before any major tag is cut.

The [deployed M1 V1 checkpoint](../user/m1-preprod-deployment.md) supports a smaller preprod lifecycle. The [recorded keripy and ckeri baseline](preprod-v1-baseline.md) shows a confirmed registration and signed close. It has no Singular registry mapping or ACDC gate. A V1 transaction therefore cannot close a later card whose story requires those features.

| Target | Play | Current boundary |
| --- | --- | --- |
| 23 October 2026 | [Map the Singular registry to Cardano KERI](d02-registry-mapping.md) | Cross-model mapping under review; not yet playable as a connected integration. |

The [Singular naming story](https://github.com/lambdasistemi/singular/issues/174) is a parallel preprod target. Cardano KERI's identity path does not depend on naming or escrow.

## Later targets

- 2026-12-07: [Registry backed registration](d04-registration.md) — connected target not yet playable.
- 2026-12-22: [Register then advance](d05-advance.md) — connected target not yet playable.
- 2027-01-06: [Hunter advance and short pool](d06-hunter.md) — connected target not yet playable.
- 2027-01-21: [Close and conviction](d07-close-convict.md) — connected target not yet playable.
- 2027-02-05: [Commands for identity roles](d08-roles.md) — connected target not yet playable.
- 2027-02-20: [Fifteen identity stories](d09-stories.md) — connected target not yet playable.
- 2027-03-07: [Preprod cutover rehearsal](d10-cutover.md) — connected target not yet playable.
- 2027-03-22: [Preprod release journey](d11-preprod.md) — connected target not yet playable.
- 2027-04-06: [Historical issuer keys](d12-history.md) — connected target not yet playable.
- 2027-04-21: [TEL seal walk](d13-tel.md) — connected target not yet playable.
- 2027-05-06: [Record a revocation](d14-revocation.md) — connected target not yet playable.
- 2027-05-21: [Non-revocation at the gate](d15-nonrevocation.md) — connected target not yet playable.
- 2027-06-05: [ACDC proof package](d16-proof-package.md) — connected target not yet playable.
- 2027-06-20: [Four-link chain and budget](d17-four-link.md) — connected target not yet playable.
- 2027-07-05: [Credential gated rehearsal](d18-gated-rehearsal.md) — connected target not yet playable.
- 2027-07-20: [Credential gated transaction target](d19-gated-target.md) — connected target not yet playable.
