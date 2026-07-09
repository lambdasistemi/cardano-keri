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

The measurement module (`validators/measurements.ak`) uses:

- one literal 1024-byte input matching the existing BLAKE3 test vector input;
- a literal `blake2b_256(input)` commitment;
- a literal BLAKE3 chaining value at offset 512 after absorbing 8 blocks;
- a literal expected 32-byte BLAKE3 digest.

All script-context fixtures (the datums, the spent input, the continuing
output, the address, the value, and the `OutputReference`) are top-level
`const`s, so their construction is folded at compile time and is **not** charged
to the measured validator cost. This keeps setup work from being mistaken for
validator cost.

Two levels of measurement are recorded for each of the Step and Finish paths:

- **Core-helper**: `measure_step_1024_offset0_absorb8` and
  `measure_finish_1024_offset512_after_8_blocks` call the pure
  `checkpoint.step` / `checkpoint.finish` helpers directly. These capture only
  the BLAKE3 absorb/finish and commitment/digest work.
- **Full spend-context**: `measure_step_full_context_1024_8blocks` and
  `measure_finish_full_context_1024` invoke the validator handler
  `checkpoint.spend(Some(datum), redeemer, own_ref, tx)` on its accept path
  (both return `True`). The Step case exercises the full handler, including
  `find_input` and the `has_continuing_output` transaction-output traversal and
  inline-datum decode. The Finish branch ignores the transaction, so its
  full-context cost tracks the core helper.

## Results

| Measurement | Memory | CPU | Memory budget | CPU budget |
| --- | ---: | ---: | ---: | ---: |
| Step core helper (`checkpoint.step`) | 9,669,685 | 7,313,671,570 | 69.07% | 73.14% |
| Step full spend context (`checkpoint.spend`) | 9,815,601 | 7,354,116,811 | 70.11% | 73.54% |
| Finish core helper (`checkpoint.finish`) | 9,569,178 | 7,260,746,158 | 68.35% | 72.61% |
| Finish full spend context (`checkpoint.spend`) | 9,581,091 | 7,263,792,055 | 68.44% | 72.64% |

Full spend-context headroom:

- Step: 4,184,399 memory and 2,645,883,189 CPU.
- Finish: 4,418,909 memory and 2,736,207,945 CPU.

The Step continuing-output traversal and inline-datum decode add roughly
145,900 memory and 40,400,000 CPU over the core helper — about 1% of the memory
budget and under 0.5% of the CPU budget — so the transaction-output handling is
a small increment on top of the dominant BLAKE3 work.

## Verdict

Judged on the **full spend-validator context** numbers — the per-transaction
figures issue #97 asks for — the measured 8+8 checkpoint path fits the
per-transaction budget for both Step and Finish. The worst case is the full
Step transaction at 70.11% of the memory budget and 73.54% of the CPU budget;
the full Finish transaction is lower on both axes. Both paths retain more than
26% CPU and more than 29% memory headroom.

## Caveats And Follow-Ups

- The full-context measurement calls `checkpoint.spend` directly, so it
  **includes** the continuing-output traversal and inline-datum decode but still
  **excludes** the ledger-level deserialization of the redeemer and datum from
  `Data` at the script boundary. That deserialization is dominated by the
  ~1024-byte redeemer input, so the reported full number is a close **lower
  bound** on true on-chain cost rather than the final figure.
- Production checkpoint authenticity still requires the unique state/thread
  token and the pinned lifecycle work owned by issue #99. This spike does not
  implement #99; the measurements here assume that machinery exists but do not
  charge for it.
