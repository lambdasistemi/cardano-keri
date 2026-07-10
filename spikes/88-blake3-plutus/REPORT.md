# BLAKE3 in Plutus V3 Spike Report

## Verdict

**FITS for representative inception-event sizes; not for the full 1024-byte
chunk.**

After a CPS rewrite of the compression rounds, single-chunk BLAKE3
verification is within the mainnet per-transaction budget up to roughly 700
bytes of input. At 300 bytes it uses **3,940,904 mem** and **3,969,377,996
cpu**: 28.1% of memory and 39.7% of CPU, leaving the majority of the budget
for the rest of a registration validator (digest and prefix handling,
inclusion proof checks, receipt and key verification). At 500 bytes the CPU
margin is tighter (45.0% mem / 63.4% CPU) but still plausible; at 700 bytes
BLAKE3 consumes 61.8% of memory and 87.2% of CPU. At 1024 bytes memory now
fits, but CPU remains over budget.

Mainnet budget used here:

| resource | budget |
| --- | ---: |
| memory | 14,000,000 |
| cpu | 10,000,000,000 |

## Optimized Measurements

Measured with `nix shell nixpkgs#aiken --command aiken check --plain-numbers`.
The measurement tests call `blake3.verify(input, expected_digest)` with literal
bytearrays, so the numbers cover the hash plus digest equality check and do not
include test-vector generation.

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 3,940,904 | 28.1% | 3,969,377,996 | 39.7% |
| 500 | 6,299,246 | 45.0% | 6,342,816,649 | 63.4% |
| 700 | 8,657,588 | 61.8% | 8,716,257,702 | 87.2% |
| 1024 | 12,588,158 | 89.9% | 12,671,997,697 | 126.7% |

Exported `blake3.verify` size:

| artifact | size |
| --- | ---: |
| exported JSON | 20,441 bytes |
| `compiledCode` payload | 19,564 hex chars |
| flat UPLC bytes | 9,782 bytes |

Measured with:

```sh
nix shell nixpkgs#aiken --command aiken export --module blake3 --name verify --trace-level silent
```

## What the CPS Optimization Changed

Relative to the previous repository implementation, the CPS rewrite reduces
memory by 33.8% and CPU by 12.2% across the measured input sizes. It trades
execution units for a larger compiled program: 9,782 flat UPLC bytes versus
2,669 bytes previously.

1. **No round-boundary state records.** The 20 live values flow through
   continuations across all seven rounds. This removes six `State`
   constructions and destructurings per compressed block.
2. **Final byte forms are reused.** The last diagonal mixes already compute
   four-byte forms of the final a- and c-rows. The final continuation carries
   those bytes directly into the eight output words instead of converting the
   same integers again.
3. **Hot helpers and rounds are compile-time inlined.** Function-valued
   constants make Aiken inline the fixed compression path. Fixed block-length
   and flag words are passed as byte literals, avoiding repeated conversions.
4. **No explicit input padding.** Short little-endian word slices already
   decode as zero-extended values, so hashing no longer appends a 64-byte zero
   block.

## Earlier Bytes-Oriented Optimization

Relative to the first fixed-record implementation (below), the rewrite is a
2.5x cpu / 3.5x mem improvement at 300 bytes, from three sources:

1. **Fused xor+rotate on word bytes.** Each ARX step previously converted
   both operands int -> bytes, xored, converted back to int, and rotated with
   integer div/mod arithmetic. Now the xor and the rotation happen in one
   pass over 4-byte big-endian words (`xor_bytearray` + `rotate_bytearray`),
   and only the values needed for additions come back to integers.
2. **No modular reduction.** Additions run un-reduced; a word accumulates at
   most ~57 * 2^32 < 2^40 across the 7 rounds, so a width-5 big-endian
   conversion plus dropping the top byte recovers the exact u32 during the
   conversion the xor needs anyway. All explicit `% 2^32` operations are
   gone.
3. **No per-mix record traffic.** The 16-field compression state was
   reconstructed 8 times per round and every field access compiled to a
   16-way case. The state is now destructured once per round and words flow
   as plain bindings; the b- and d-rows (always exact rotation outputs) are
   carried between rounds as bytes so the next xor consumes them directly.
   Message words are read with `slice_bytearray` + `bytearray_to_integer`
   from a zero-padded input instead of per-byte `bytearray.at`.

## Earlier Measurements

Previous repository implementation (bytes-oriented rounds with one `State`
record per round):

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 5,949,561 | 42.5% | 4,520,087,651 | 45.2% |
| 500 | 9,510,579 | 67.9% | 7,224,403,186 | 72.2% |
| 700 | 13,071,597 | 93.4% | 9,928,721,121 | 99.3% |
| 1024 | 19,006,627 | 135.8% | 14,435,922,586 | 144.4% |

First refined implementation (fixed record fields, unrolled state updates,
integer xor32 with div/mod rotates):

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 20,625,683 | 147.3% | 11,488,617,500 | 114.9% |
| 500 | 32,989,821 | 235.6% | 18,371,343,386 | 183.7% |
| 700 | 45,353,959 | 324.0% | 25,254,069,272 | 252.5% |
| 1024 | 65,957,085 | 471.1% | 36,724,558,838 | 367.2% |

Naive baseline (`List<Int>` state and indexing), kept long enough to measure
and then replaced:

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 107,958,719 | 771.1% | 35,810,625,979 | 358.1% |
| 500 | 172,649,793 | 1233.2% | 57,265,528,402 | 572.7% |
| 700 | 237,340,867 | 1695.3% | 78,720,430,825 | 787.2% |
| 1024 | 345,155,553 | 2465.4% | 114,477,881,286 | 1144.8% |

Overall, naive -> optimized is roughly 18x mem and 8x cpu at 300 bytes.

## Correctness

The implementation passes the official BLAKE3 hash-mode vectors for input
lengths:

`0, 1, 63, 64, 65, 127, 128, 1023, 1024`

The expected digests are the first 32 bytes of the extended outputs from
`BLAKE3-team/BLAKE3/test_vectors/test_vectors.json`. Keyed and derive-key
modes are intentionally out of scope.

## Builtin Findings

- `aiken/primitive/bytearray` in stdlib `v2.2.0` exposes CIP-121 integer/byte
  conversions (`from_int_little_endian`, `to_int_little_endian`, etc.).
- The stdlib does not wrap the bytearray bitwise helpers in this pinned stack,
  but Aiken `v1.1.21` exposes them directly through `aiken/builtin`.
- `builtin.xor_bytearray` works and is used for 32-bit XOR.
- `builtin.rotate_bytearray(bytes, -n)` on a 4-byte big-endian word is an
  exact 32-bit rotate-right. An earlier probe concluded the rotation path was
  more expensive than integer div/mod rotates, but that probe paid the
  int -> bytes -> int conversion per rotation; fused with the xor that
  already needs the bytes, it is decisively cheaper.
- `builtin.xor_bytearray(False, a, b)` truncates to the shorter operand from
  index 0, so dropping the high byte of a big-endian word needs an explicit
  `slice_bytearray`; a width-5 conversion + slice measured slightly better on
  cpu (and slightly worse on mem) than `% 2^32` + width-4 conversion.

## Notes

Genesis is once per identity, in its own registration tx, so the relevant
question is whether BLAKE3 plus the rest of the registration validator fits
at realistic inception-event sizes. At ~300 bytes the answer is now
plausibly yes; the remaining 71.9% memory and 60.3% CPU headroom has to cover
the rest of the validator logic, which this spike does not measure.
Inception events that approach the 1024-byte chunk limit remain out of reach
on CPU without a native `blake3` builtin, which would still collapse genesis
binding to one primitive hash check.
