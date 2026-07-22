# #114 permissionless-registration full-validator measurements

## Verdict

**All nine checkpoint ACCEPT contexts retain at least 25.00% headroom on both
execution-unit axes.** The binding row remains the inherited GLEIF-shaped
7-key Arm at **51.38% memory headroom** and **70.10% CPU headroom**. Among the
three T114-R4 Register rows, the binding GLEIF-shaped 7-key inception retains
**64.90% memory headroom** and **78.79% CPU headroom**. No handler, fixture,
signature, receipt, transaction shape, or limit was weakened.

The protocol maxima and unchanged mechanical limits are:

| resource | protocol maximum | 25% headroom limit |
| --- | ---: | ---: |
| memory | 14,000,000 | 10,500,000 |
| CPU | 10,000,000,000 | 7,500,000,000 |

## Reproduction and parameters

Measured on 2026-07-22 from starting HEAD
`84a346c9467e1e202b19df1c3be0a96ba60e2da9` plus the T114-R4
measurement-only diff, using Aiken `v1.1.23+unknown` from pinned nixpkgs
revision `753cc8a3a87467296ddd1fa93f0cc3e81120ee46`:

```console
just measure-checkpoint
```

The recipe collects exactly the nine named `measure_checkpoint_*` tests,
requires every test to pass with numeric execution units, and rejects memory
above 10,500,000 or CPU above 7,500,000,000.

Every row invokes the real checkpoint mint or spend handler with the final six
deployment parameters. The measured parameters are version `0`, hash-proof
policy `4a` repeated 28 bytes, network id `0`, `d_reg = 1,000,000,000`,
`freeze_bond = 5,000,000`, and `freeze_window = 500`. The Register floor is
therefore `min_ada + d_reg + freeze_bond = 1,007,000,000` lovelace.

The 2-key unwitnessed Register uses that exact floor. The witnessed 2-of-2
controller / 2-of-3 receipt and GLEIF-shaped 7-key Register contexts each use
the floor plus 42,000,000 lovelace of conservative surplus, for 1,049,000,000
lovelace. All three use committed generated KERI evidence over the exact event
bytes and retain the generated hash-proof input and burn, event-own controller
signatures, required witness receipts, exact quantity-one AID mint/output, and
the final applied parameter arity.

## Exact execution units

The first three rows are the new T114-R4 Register measurements. The remaining
six rows are inherited unchanged from #116.

| provenance and ACCEPT context | memory | memory used | memory headroom | CPU | CPU used | CPU headroom |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| T114-R4 Register 2-key unwitnessed | 1,468,223 | 10.49% | 89.51% | 649,280,426 | 6.49% | 93.51% |
| T114-R4 Register witnessed 2-of-2 / 2-of-3 | 2,104,834 | 15.03% | 84.97% | 1,001,220,049 | 10.01% | 89.99% |
| T114-R4 Register 7-key GLEIF-shaped | 4,914,284 | 35.10% | 64.90% | 2,121,024,410 | 21.21% | 78.79% |
| inherited #116 Arm 2-key | 3,610,929 | 25.79% | 74.21% | 1,695,175,872 | 16.95% | 83.05% |
| inherited #116 Arm 7-key GLEIF-shaped | 6,806,289 | 48.62% | 51.38% | 2,990,090,781 | 29.90% | 70.10% |
| inherited #116 Claim | 654,656 | 4.68% | 95.32% | 213,846,973 | 2.14% | 97.86% |
| inherited #116 Convict ACTIVE | 1,644,269 | 11.74% | 88.26% | 707,052,786 | 7.07% | 92.93% |
| inherited #116 Convict ARMED | 1,751,278 | 12.51% | 87.49% | 746,925,761 | 7.47% | 92.53% |
| inherited #116 Convict FROZEN | 1,693,140 | 12.09% | 87.91% | 727,347,040 | 7.27% | 92.73% |

The hard-stop condition did not fire.

## Exact applied-program size

The exact production blueprint was rebuilt at silent trace level with pinned
Aiken 1.1.23, then the checkpoint validator was applied in order to all six
parameters. The parameter CBOR values were `00`,
`581c4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a`,
`00`, `1a3b9aca00`, `1a004c4b40`, and `1901f4`:

```console
cd onchain
aiken build -t silent
aiken blueprint apply -m checkpoint -v checkpoint 00 -o p1.json
aiken blueprint apply -i p1.json -m checkpoint -v checkpoint 581c4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a -o p2.json
aiken blueprint apply -i p2.json -m checkpoint -v checkpoint 00 -o p3.json
aiken blueprint apply -i p3.json -m checkpoint -v checkpoint 1a3b9aca00 -o p4.json
aiken blueprint apply -i p4.json -m checkpoint -v checkpoint 1a004c4b40 -o p5.json
aiken blueprint apply -i p5.json -m checkpoint -v checkpoint 1901f4 -o p6.json
jq -r '.validators[] | select(.title | startswith("checkpoint.checkpoint")) | [.title, ((.compiledCode | length) / 2)] | @tsv' p6.json
```

The mint, spend, and fallback purposes each report the same fully applied
program:

| six-parameter applied program | bytes | current - 19,565 | 16,133 - current |
| --- | ---: | ---: | ---: |
| `checkpoint.checkpoint` (silent) | 22,719 | +3,154 | -6,586 |

**=== NON-DEPLOYABLE UNDER THE PRODUCTION 16,384-BYTE CAP ===**

The current applied program exceeds the 16,133-byte deployable
creation-transaction budget by 6,586 bytes. #115 mark-ready remains the hard
deployability stop. If the final validator is still over budget, A-015's
binding remediation order is: build-level reduction first; then
withdraw/observer forwarding of evidence verification; mint/spend split only
after a fresh operator ruling.

## Read-only consistency audit

- Fresh Haskell regeneration reproduces the committed registration vectors,
  and the Aiken suite consumes those generated verdicts and evidence without
  drift.
- No production `InceptionMessage` type, domain, preimage encoder, or signing
  helper remains. The only remaining name occurrences identify deliberately
  obsolete adversarial bytes used to prove rejection; the structural
  inception-datum validator is not a Cardano authorization message.
- The checkpoint registration surface contains no registry, absence proof,
  mint-once mechanism, batcher, or sequencer.
- `lean/traceability.csv` remains the unchanged 21-theorem map. Every existing
  `PENDING(#127-pipeline)` sentinel remains unchanged, and the executable
  traceability drift gate passes.
- The production spend dispatch remains unchanged: Advance and Close still
  fall through to rejection, while the existing #116 Arm, Claim, and Convict
  staging remains intact.

## T114-R5 old-cost devnet evidence matrix

The pinned devnet remains deliberately **NON-DEPLOYABLE**. Its sole genesis
drift is `maxTxSize=32768`; the Plutus V3 cost model remains the 251-entry
old-cost model. The current six-parameter applied program is **23,124 bytes**,
**+3,559** bytes from the 19,565-byte baseline, and **-6,991** bytes of margin
to the 16,133-byte deployable creation budget.

| evidence | settled-on-devnet | pending-on-#190 | proven-at-preprod-#115 |
| --- | --- | --- | --- |
| hash-proof mint | A real node executes the production policy and rejects the mint with `CekError` / `overspending the budget` under protocol version 10; the test also reads the pinned 251-entry Plutus V3 model. | The positive mint is `PENDING(blocked-on=#190)` until the missing Plomin prices are available. Durable sources: [guide](https://github.com/lambdasistemi/cardano-node-clients/issues/190#issuecomment-5048840036), [harness diff](https://github.com/lambdasistemi/cardano-node-clients/issues/190#issuecomment-5048840248). | #115 preprod owns the first real positive lifecycle settlement. |
| permissionless Register with `D_reg+B`, Arm, Claim | None is claimed on this old-cost devnet: all real builders and the complete scenario are compiled by the authorized `PENDING(blocked-on=#190)` row, but not executed as a substitute positive. | `PENDING(blocked-on=#190)` for the full hash-proof mint -> Register -> Arm -> Claim chain. | #115 preprod owns the first real positive lifecycle settlement. |
| Advance and Close | Real, tokenless staging inputs reach the applied production validator and reject; this is independent of the unavailable hash-proof mint and does not claim a positive Register lineage. | Not applicable. | #115 routes the first real positive lifecycle settlement to preprod. |
