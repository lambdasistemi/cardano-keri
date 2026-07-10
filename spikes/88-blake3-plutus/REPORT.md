# BLAKE3 in Plutus V3 Spike Report

## Verdict

**FITS for the full single-chunk domain (inputs up to 1024 bytes).**

After a lane-packed rewrite of the compression rounds, single-chunk BLAKE3
verification is within the mainnet per-transaction budget at every input
size the implementation accepts. At 300 bytes it uses **3,141,028 mem** and
**1,709,986,879 cpu**: 22.4% of memory and 17.1% of CPU, leaving more than
three quarters of the budget for the rest of a registration validator
(digest and prefix handling, inclusion proof checks, receipt and key
verification). The full 1024-byte chunk — over CPU budget in every previous
round of this spike — now costs 71.7% of memory and 54.3% of CPU. Memory is
the binding constraint at the top of the range.

Mainnet budget used here:

| resource | budget |
| --- | ---: |
| memory | 14,000,000 |
| cpu | 10,000,000,000 |

## Optimized Measurements

Measured with `nix develop --quiet -c aiken check --plain-numbers`. The
spike-local flake pins the official Aiken v1.1.23 release binary and verifies
its published SHA-256.
The measurement tests call `blake3.verify(input, expected_digest)` with literal
bytearrays, so the numbers cover the hash plus digest equality check and do not
include test-vector generation.

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 3,141,028 | 22.4% | 1,709,986,879 | 17.1% |
| 500 | 5,021,260 | 35.9% | 2,724,416,736 | 27.2% |
| 700 | 6,901,492 | 49.3% | 3,738,848,993 | 37.4% |
| 1024 | 10,035,212 | 71.7% | 5,429,574,328 | 54.3% |

Relative to the CPS rounds this is a further 2.32–2.33x cpu and 1.25x mem
improvement, uniform across input sizes: roughly 342M cpu per compressed
block, down from 794M.

The compiler bump alone, with the lane-packed Aiken source unchanged, saves
4.7% memory, 1.42% cpu, and 6.1% of the serialized verifier. Cross-evaluating
both compiler outputs in the v1.1.23 machine gives the same delta, so the gain
comes from generated UPLC rather than a changed cost model.

Exported `blake3.verify` size:

| artifact | size |
| --- | ---: |
| exported JSON | 15,931 bytes |
| `compiledCode` payload | 15,054 hex chars |
| flat UPLC bytes | 7,527 bytes |

Measured with:

```sh
nix develop --quiet -c aiken export --module blake3 --name verify --trace-level silent
```

The lane-packed program is also smaller than the CPS one (7,527 vs 9,782
flat bytes): one packed step replaces four scalar copies of the same code.

## Result History

Six measured configurations across four optimization PRs plus the compiler
bump. Budget percentages are against the mainnet limits above; the step
column is the cpu/mem improvement over the previous row, measured at 300
bytes. Raw numbers for every generation are in the detailed tables further
down.

| implementation | landed | flat UPLC | 300 B cpu | 300 B mem | 1024 B cpu | 1024 B mem | step (cpu / mem) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| naive: `List<Int>` state, indexed | #89 (measured, replaced in-flight) | — | 358.1% | 771.1% | 1144.8% | 2465.4% | — |
| fixed records, int xor, div/mod rotates | #89 | 4,697 | 114.9% | 147.3% | 367.2% | 471.1% | 3.12x / 5.23x |
| bytes-oriented rounds, fused xor+rotate | #96 | 2,669 | 45.2% | 42.5% | 144.4% | 135.8% | 2.54x / 3.47x |
| CPS rounds, no state records | #101 | 9,782 | 39.7% | 28.1% | 126.7% | 89.9% | 1.14x / 1.51x |
| lane-packed rounds, batched conversions | #102 | 8,017 | 17.3% | 23.5% | 55.1% | 75.2% | 2.29x / 1.20x |
| lane-packed rounds, Aiken v1.1.23 | compiler bump | 7,527 | 17.1% | 22.4% | 54.3% | 71.7% | 1.01x / 1.05x |

Cumulative: 20.9x cpu and 34.4x mem at 300 bytes. The full 1024-byte chunk
went from 11.4x the CPU budget to fitting with 45.7% CPU headroom; each
verdict edge moved with it — #89 concluded DOES NOT FIT, #96 flipped it to
fits-at-representative-sizes, #102 extends it to the whole single-chunk
domain.

## What the Lane Packing Changed

The CPS rounds spent about two thirds of their budget on int <-> bytes
conversions: 224 `integer_to_bytearray` and 248 `bytearray_to_integer`
calls per block, each dominated by a ~1.1–1.6M cpu intercept (see the
builtin cost table below). BLAKE3's round structure makes four G functions
data-parallel, so the rewrite amortizes every conversion intercept over
four lanes:

1. **Rows live as lane-packed integers.** The a- and c-rows (and the b-row
   integer shadow) hold four u32 lanes at a 5-byte stride: lane j occupies
   bits [40*(3-j), 40*(3-j)+40). Additions stay un-reduced as before
   (bounded by ~57 * 2^32 < 2^40), so lanes never carry into each other and
   one packed `+` performs four word additions.
2. **One conversion per ARX step, not four.** Each quarter-round step does
   one width-20 `integer_to_bytearray` of the packed row, one width-20
   `xor_bytearray` against a gap-aligned operand vector, four lane slices,
   four rotates, and one `bytearray_to_integer` to re-pack — instead of
   four scalar truncate/xor/rotate/convert chains.
3. **Packing is concatenation, not arithmetic.** `appendByteString` costs
   ~831 cpu — three orders of magnitude below a conversion — so rotated
   lane words re-pack via a 19-byte gapped concat plus a single
   `bytearray_to_integer`. Diagonal mixing never moves c-lanes: addend pack
   order and extraction offsets are permuted statically instead.
4. **Message quads pack straight from input slices.** The four message
   words a step adds are concatenated as raw little-endian slices and read
   with one little-endian `bytearray_to_integer` (the LE read reverses lane
   order, which the pack order compensates). Message words never exist as
   individual integers, removing all 16 per-block word conversions. This
   requires exact 4-byte slices, so hashing appends one spare zero block to
   the input (~1k cpu) — reinstating the padding the CPS round had removed,
   now load-bearing for lane geometry.

## Measured Builtin Costs

Marginal cpu per call, measured with the differential loops in
`lib/probes.ak` (each probe repeats an op-chain 400 times inside the
control loop; marginal cost is the budget delta divided by 400):

| builtin | marginal cpu |
| --- | ---: |
| `bytearray_to_integer` (4 bytes) | ~1,114,000 |
| `bytearray_to_integer` (20 bytes) | ~1,200,000 |
| `integer_to_bytearray` (width 4) | ~1,403,000 |
| `integer_to_bytearray` (width 20) | ~1,632,000 |
| `slice_bytearray` | ~258,000 |
| `rotate_bytearray` (4 bytes) | ~232,000 |
| `xor_bytearray` (4 bytes) | ~182,000 |
| `append_bytearray` | ~831 |

The conversions are intercept-dominated: 4x the payload costs only ~8–16%
more. That single fact drives the whole design — batching four lanes into
one conversion cuts the per-lane conversion path from ~2.78M cpu
(`integer_to_bytearray` width 5 + slice + `bytearray_to_integer`) to ~0.97M
(a quarter share of one width-20 roundtrip plus a slice).

## Earlier CPS Optimization

Relative to the previous repository implementation, the CPS rewrite reduced
memory by 33.8% and CPU by 12.2% across the measured input sizes, trading
execution units for a larger compiled program (9,782 flat UPLC bytes versus
2,669 previously):

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
   block. (Reverted by the lane-packed round, which needs exact slice
   geometry.)

CPS measurements, superseded above:

| input bytes | mem | mem budget | cpu | cpu budget |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 3,940,904 | 28.1% | 3,969,377,996 | 39.7% |
| 500 | 6,299,246 | 45.0% | 6,342,816,649 | 63.4% |
| 700 | 8,657,588 | 61.8% | 8,716,257,702 | 87.2% |
| 1024 | 12,588,158 | 89.9% | 12,671,997,697 | 126.7% |

## Earlier Bytes-Oriented Optimization

Relative to the first fixed-record implementation (below), the bytes-oriented
rewrite was a 2.5x cpu / 3.5x mem improvement at 300 bytes, from three sources:

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

Bytes-oriented rounds with one `State` record per round:

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

Overall, naive -> lane-packed is roughly 33x mem and 21x cpu at 300 bytes.

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
  but Aiken `v1.1.23` exposes them directly through `aiken/builtin`.
- `builtin.xor_bytearray` works and is used for 32-bit XOR — in the
  lane-packed round as one width-20 xor over four gap-aligned words.
- `builtin.rotate_bytearray(bytes, -n)` on a 4-byte big-endian word is an
  exact 32-bit rotate-right. Rotation is the one step lane packing cannot
  batch: a whole-vector rotate would carry bits across lane boundaries, so
  the four lanes rotate individually.
- `builtin.xor_bytearray(False, a, b)` truncates to the shorter operand from
  index 0. The lane-packed round no longer needs per-word truncation slices:
  the width-20 image is xored whole, and the spare byte per lane absorbs the
  un-reduced high bits until the lane slice drops them.
- Integer/bytes conversions are intercept-dominated (see the measured cost
  table), so their count — not their width — is what a Plutus BLAKE3 must
  minimize. `appendByteString` at ~831 cpu is the escape hatch: byte-level
  lane surgery is effectively free next to any conversion.

## Notes

Genesis is once per identity, in its own registration tx, so the relevant
question is whether BLAKE3 plus the rest of the registration validator fits
at realistic inception-event sizes. At ~300 bytes the answer is now clearly
plausible: 77.6% of memory and 82.9% of CPU remain for the rest of the
validator logic, which this spike does not measure. Even the full 1024-byte
chunk fits with 28.3% memory and 45.7% CPU to spare, so the single-chunk
domain no longer needs the multi-transaction checkpointing explored in spike
#97 — that machinery remains relevant only for inputs beyond 1024 bytes,
where BLAKE3's tree mode starts and a native `blake3` builtin remains the
long-term answer.
