# BLAKE3 in Plutus V3 Spike Report

## Verdict

**DOES NOT FIT.**

A correct single-chunk BLAKE3 implementation can be written in Aiken/Plutus V3,
but the refined implementation still exceeds the mainnet per-transaction budget
for representative KERI inception-event sizes. At 300 bytes, BLAKE3 verification
alone uses **20,625,683 mem** and **11,488,617,500 cpu**: 147.3% of memory and
114.9% of CPU. A real registration transaction would still need the rest of the
validator logic, including digest/prefix handling, inclusion proof checks, and
receipt/key verification, so BLAKE3 alone consuming more than the budget is a
hard fail.

Mainnet budget used here:

| resource | budget |
| --- | ---: |
| memory | 14,000,000 |
| cpu | 10,000,000,000 |

## Current Refined Measurements

Measured with `nix shell nixpkgs#aiken --command aiken check --plain-numbers`.
The measurement tests call `blake3.verify(input, expected_digest)` with literal
bytearrays, so the numbers cover the hash plus digest equality check and do not
include test-vector generation.

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 20,625,683 | 147.3% | 11,488,617,500 | 114.9% |
| 500 | 32,989,821 | 235.6% | 18,371,343,386 | 183.7% |
| 700 | 45,353,959 | 324.0% | 25,254,069,272 | 252.5% |
| 1024 | 65,957,085 | 471.1% | 36,724,558,838 | 367.2% |

Exported `blake3.verify` size:

| artifact | size |
| --- | ---: |
| exported JSON | 10,271 bytes |
| `compiledCode` payload | 9,394 hex chars |
| flat UPLC bytes | 4,697 bytes |

Measured with:

```sh
nix shell nixpkgs#aiken --command aiken export --module blake3 --name verify --trace-level silent
```

## Naive Baseline Measurements

The first correct implementation used `List<Int>` for compression state and
message/state indexing. It was kept long enough to measure the obvious baseline,
then replaced with fixed record fields and unrolled state updates.

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 107,958,719 | 771.1% | 35,810,625,979 | 358.1% |
| 500 | 172,649,793 | 1233.2% | 57,265,528,402 | 572.7% |
| 700 | 237,340,867 | 1695.3% | 78,720,430,825 | 787.2% |
| 1024 | 345,155,553 | 2465.4% | 114,477,881,286 | 1144.8% |

The fixed-record rewrite improved CPU by roughly 3.1x and memory by roughly
5.2x, but the refined 300-byte case still fails both budgets.

## Correctness

The implementation passes the official BLAKE3 hash-mode vectors for input
lengths:

`0, 1, 63, 64, 65, 127, 128, 1023, 1024`

The expected digests are the first 32 bytes of the extended outputs from
`BLAKE3-team/BLAKE3/test_vectors/test_vectors.json`. Keyed and derive-key modes
are intentionally out of scope.

## Builtin Findings

- `aiken/primitive/bytearray` in stdlib `v2.2.0` exposes CIP-121 integer/byte
  conversions (`from_int_little_endian`, `to_int_little_endian`, etc.).
- The stdlib does not wrap the bytearray bitwise helpers in this pinned stack,
  but Aiken `v1.1.21` exposes them directly through `aiken/builtin`.
- `builtin.xor_bytearray` works and is used for 32-bit XOR.
- `builtin.rotate_bytearray` and `builtin.shift_bytearray` are exposed. A
  scratch probe showed `rotate_bytearray` can implement 32-bit rotate-right via
  big-endian conversion and negative rotation, but the conversion path measured
  more expensive than the integer div/mod rotates used here.

## Notes

This result argues for keeping the registration-attested genesis path for now.
A native `blake3` builtin would change the tradeoff directly: genesis binding
would become one primitive hash check instead of hundreds of in-script ARX
operations, making native end-to-end genesis verification plausible again.
