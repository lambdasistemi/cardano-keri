# #116 freeze-bond full-validator measurements

## Verdict

**All six final T116-R4 ACCEPT contexts retain at least 25.00% headroom on
both execution-unit axes.** The binding row is the GLEIF-shaped 7-key Arm at
**51.38% memory headroom** and **70.10% CPU headroom**. No evidence, signer,
receipt, event-size, handler, or limit arithmetic was weakened.

Mainnet per-transaction maxima and the mechanical R4 limits are:

| resource | ledger maximum | 25% headroom limit |
| --- | ---: | ---: |
| memory | 14,000,000 | 10,500,000 |
| cpu | 10,000,000,000 | 7,500,000,000 |

## Reproduction and fixture shape

Measured on 2026-07-21 from the R4 worktree based on clean pushed HEAD
`d6fc1e8073df0381f7f876740e2ea238ccd08139`, using the pinned Aiken compiler
and:

```console
just measure-checkpoint
```

Every row calls the real six-parameter `checkpoint.checkpoint.spend` handler
on an ACCEPT context. Arm uses the committed generated 2-key and GLEIF-shaped
7-key KERI wires with their real controller signatures, witness receipts, and
event bytes. Claim spends the real ARMED lifecycle shape. Each Convict row
uses the committed witnessed-fork wire on the ACTIVE, ARMED, or FROZEN path.
Convict inputs also carry 42,000,000 lovelace of unrelated conservative
surplus, returned as ordinary change after the exact protected payout(s) and
terminal tombstone output.

| ACCEPT context | memory | memory used | memory headroom | cpu | cpu used | cpu headroom |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Arm 2-key | 3,610,929 | 25.79% | 74.21% | 1,695,175,872 | 16.95% | 83.05% |
| Arm 7-key GLEIF-shaped | 6,806,289 | 48.62% | 51.38% | 2,990,090,781 | 29.90% | 70.10% |
| Claim | 654,656 | 4.68% | 95.32% | 213,846,973 | 2.14% | 97.86% |
| Convict ACTIVE | 1,644,269 | 11.74% | 88.26% | 707,052,786 | 7.07% | 92.93% |
| Convict ARMED | 1,751,278 | 12.51% | 87.49% | 746,925,761 | 7.47% | 92.53% |
| Convict FROZEN | 1,693,140 | 12.09% | 87.91% | 727,347,040 | 7.27% | 92.73% |

Minimum measured headroom is therefore **51.38% memory** and **70.10% CPU**,
both on Arm 7-key. The hard-stop condition did not fire.

Register, every Advance path, and Close remain absent from this table because
they are staging-closed at this non-deployable HEAD. Exact measurement-title
checking in `just measure-checkpoint` rejects any attempt to substitute those
paths for the six required final contexts.
