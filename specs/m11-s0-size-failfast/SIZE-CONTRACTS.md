## Unmerged dependency (#291)

The `append` and `cursor` rows measure code that `main` does not have.

`onchain/lib/cardano_keri/m12/event_decoder.ak` is a copy of the INV-BIND
bytes-only establishment decoder from sibling **#291**, which is **unmerged
and pending**: it exists only on `feat/291-inv-bind` as
`7f49dd8b64dbbc9a10d08f257c8b1e39dcf0dddb` (`fix(291): restore p/di parity
from event bytes`) and its descendant
`d57e4354ac03cca9f64165e762626bd2a279e944` (`fix(291): remove obsolete
integer array helper`). Neither commit is an ancestor of `main`
(`77e392dd33f62f50a7b5cc5b5fd9214a507244bb` at the time of writing). The copy
is faithful: the whole textual difference from the #291 file is `aiken fmt`
line wrapping and record-field punning, with no semantic edit.

Consequences, stated so a successor does not inherit a wrong fact:

- `append` 9,498 B and `cursor` 7,212 B are measurements of the #291 decoder,
  not of anything released;
- if #291 changes before it lands, both rows — and every co-residency sum
  derived from them — must be remeasured;
- nothing in this repository re-derives the copy from #291 or re-checks its
  merge status, so this disclosure is the only control on that dependency.

- The `append` and `cursor` rows depend on unmerged #291 (`7f49dd8b`,
  `d57e4354`, not on `main`). See "Unmerged dependency (#291)": both rows
  must be remeasured if #291 changes before landing.
- Per-script gate green does not discharge co-residency. Frozen gate
  v2 is expected to remain green on the seven rows and cannot see this
  finding. NOTE-006's `CO-RESIDENCY-FAIL` is superseded as premature.
  No further decomposition without a milestone ruling.
- R1-APPEND-REMEASURE member=append title=s0_append.s0_append.spend bytes=9498 source_blob=ed65217e1d63a4c8430d3529e9f261601a191edc caveat="size-only; transaction-fit unproven"

## Co-residency

Required scripts in one transaction (architecture, not a rebuild):

| transaction | required S0 family scripts |
| --- | --- |
| Tx A premint | staging_proof_token mint |
| Tx B staged event | append + cursor + staging_proof_token burn |
| Tx B + fully-witnessed premium | the above + maintenance_escrow |
| lineage genesis/successor/close | lineage; record/cursor referenced, not executed |
| escrow notice close | maintenance_escrow |
| adopted consumer evaluation | reference_cursor_consumer (or predicate host); cursor data referenced |

S0 has on-chain skeletons, measurement controls, and specs. It has no
off-chain Tx-B builder, manifest entry, or transaction test, so no
artifact chooses INLINE versus REFERENCE witnesses. Repo-wide
reference-script convention is not evidence for a Tx B that does not
exist.

Bare structural sum of already-measured rows (not a fit measurement):

- append + cursor + staging_proof_token = 25,958 B
- 160.90% of 16,133; headroom -9,825 B
- 158.43% of 16,384; headroom -9,574 B
- with maintenance_escrow: 26,789 B, 166.05% / 163.50%

`CO-RESIDENCY-UNRESOLVED witness_mode=UNSPECIFIED sum=25958`

- If inline, 25,958 B is fatal against the 16,384-byte transaction-body
  limit.
- If referenced, the body limit is not the binding comparison; the next
  row would be live pinned `maxRefScriptSizePerTx` plus the tiered
  reference-script fee. That row is not invented here. Budget rows are
  S2.

Today's single pair-token burn that forces append and cursor into one
transaction is an artifact of this skeleton decomposition, not a
released essential invariant. A second role-bound token or a cursor
derived from append could decouple it. No such redesign is authorized.

Read-only M1 observation, not an S0 Tx-B witness choice:
`ESTABLISHED-WITNESS-PATTERN=REFERENCE`. Existing deploy/register
paths fetch manifest script hashes, require proof/checkpoint/lifecycle
reference UTxOs, put them in `referenceInputs`, and leave inline
`scriptTxWitsL` empty when those UTxOs are present
(`offchain/write-composition/Cardano/KERI/Deployment/CLI.hs:2034-2053`,
`offchain/deployment/Cardano/KERI/Deployment/Registration.hs:437-474`,
`offchain/deployment-test/Cardano/KERI/Deployment/RegistrationSpec.hs:768-770`,
`offchain/e2e/CheckpointTxBuilder.hs:2942,2951-2952`). That makes the
likely future branch a `maxRefScriptSizePerTx` + fee-tier cost
question. It does not select S0 Tx-B witnesses and proves no fit.

S2 handoff name: `S2-HANDOFF-CO-RESIDENCY-WITNESS-MODE`. This is a
named S2 contract, not an unfinished S0 acceptance item.

Caveat remains `size-only; transaction-fit unproven`.
S0-CO-RESIDENCY tx=TxA-premint members=staging_proof_token bytes=9248 witness_mode=UNSPECIFIED verdict=UNRESOLVED caveat="size-only; transaction-fit unproven"
S0-CO-RESIDENCY tx=TxB-staged-event members=append+cursor+staging_proof_token bytes=25958 witness_mode=UNSPECIFIED verdict=UNRESOLVED sum=25958 caveat="size-only; transaction-fit unproven"
S0-CO-RESIDENCY tx=TxB-fully-witnessed-premium members=append+cursor+staging_proof_token+maintenance_escrow bytes=26789 witness_mode=UNSPECIFIED verdict=UNRESOLVED caveat="size-only; transaction-fit unproven"
S0-ESTABLISHED-WITNESS-PATTERN=REFERENCE scope=M1-only not=S0-TxB
S2-HANDOFF-CO-RESIDENCY-WITNESS-MODE status=named-not-s0-closer witness_mode=UNSPECIFIED sum=25958
