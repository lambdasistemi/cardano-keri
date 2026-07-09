# BLAKE3 Multi-Tx Measurement Report

## Question

Can the issue #97 checkpointed 1024-byte BLAKE3 path fit under the current
mainnet per-transaction execution budget when split into an 8-block Step
transaction and an 8-block Finish transaction?

Budget used for this spike:

- memory: 14,000,000
- CPU: 10,000,000,000

## Method

Measurements were taken with:

```sh
cd spikes/97-blake3-multitx && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

The measurement module uses:

- one literal 1024-byte input matching the existing BLAKE3 test vector input;
- a literal `blake2b_256(input)` commitment;
- a literal BLAKE3 chaining value at offset 512 after absorbing 8 blocks;
- a literal expected 32-byte BLAKE3 digest.

`measure_step_1024_offset0_absorb8` calls `checkpoint.step` with the initial
chaining value, offset 0, and `blocks = 8`.

`measure_finish_1024_offset512_after_8_blocks` calls `checkpoint.finish` with
the precomputed offset-512 chaining value, so the Finish measurement does not
include the Step absorb work.

## Results

| Measurement | Memory | CPU | Memory budget | CPU budget |
| --- | ---: | ---: | ---: | ---: |
| Step: 1024-byte input, offset 0, absorb 8 blocks | 9,690,042 | 7,329,428,765 | 69.21% | 73.29% |
| Finish: 1024-byte input, offset 512, finish 8 blocks | 9,571,994 | 7,261,349,572 | 68.37% | 72.61% |

Headroom:

- Step: 4,309,958 memory and 2,670,571,235 CPU.
- Finish: 4,428,006 memory and 2,738,650,428 CPU.

## Verdict

The measured 8+8 checkpoint path fits the per-transaction budget for both Step
and Finish. Each side uses less than 74% of the CPU budget and less than 70% of
the memory budget.

## Caveats And Follow-Ups

- The Step measurement calls the real `checkpoint.step` helper, including the
  `blake2b_256(input)` commitment check and BLAKE3 absorb work, but it does not
  measure the spend validator's `has_continuing_output` transaction-output
  traversal.
- The Finish measurement calls the real `checkpoint.finish` helper, including
  the commitment check and digest-prefix check.
- The verdict is conservative for the BLAKE3/checkpoint core but should be
  followed by a full script-context spend measurement before production sizing.
