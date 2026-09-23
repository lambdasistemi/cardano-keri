# Dated demo plays

As an integrator, I want each dated identity demo to show a real preprod result from keripy `kli` and `ckeri`, so that I can inspect the KERI event, Cardano transaction and fresh readback together.

Every dated play targets **Cardano preprod**. Keripy owns the identity and exports CESR; `ckeri` consumes that export, submits the corresponding Cardano transaction and reads its settled state. A cast is attached only after that exact preprod journey has run. An executable Lean row or a Node simulator remains design evidence and is not a demo cast for this path.

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
