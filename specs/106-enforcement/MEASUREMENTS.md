# #106 schema-layer enforcement predicate measurements

## Verdict

**The schema-layer enforcement predicates pass the ≥ 25% headroom target
comfortably.** Every measured cell leaves well over 70% of both the memory and
CPU per-tx budget free. The binding cell — the GLEIF 7-key 3-of-7 freeze — still
holds **70.62% memory headroom** and **80.70% CPU headroom**; conviction is
nearly free (> 99% headroom on both). Memory is the binding resource on the
freeze path (blake3 `next_key_digest` is memory-heavy in Plutus).

These are the SCHEMA-LAYER predicate costs — per-signature
`verify_ed25519_signature`, per-revealed-key `next_key_digest` (blake3, freeze),
threshold `evaluate`, and the list comparisons — over **decoded** evidence. The
full-spend-context cost (SAID recomputation + CESR slice extraction +
transaction-level checks) is #24/#109's, measured separately; see the #24
takeaway below, which argues that dominant projected cost is likely redundant
under O1.

Mainnet per-tx budget:

| resource | budget |
| --- | ---: |
| memory | 14,000,000 |
| cpu | 10,000,000,000 |

## Measurements

Measured with the pinned aiken
(`github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken`) and
`aiken check --plain-numbers` over the committed `enforcement_vectors.ak`
(reproduce with `just measure-enforcement`). Each `test measure_*` in
`onchain/lib/cardano_keri/checkpoint/enforcement_measurements.ak` runs a real
`convict_predicate` / `freeze_predicate` on a committed keripy fixture vector.
The fixtures are the committed, unmodified vectors; the tier column states each
one's exact signer shape (not a nominal size).

| predicate | fixture (signer shape) | mem | mem used | mem headroom | cpu | cpu used | cpu headroom |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| convict | fork (1 controller) | 84,678 | 0.60% | 99.40% | 84,048,874 | 0.84% | 99.16% |
| freeze | honest_2key (2 controllers, witnessless) | 2,651,268 | 18.94% | 81.06% | 1,259,217,932 | 12.59% | 87.41% |
| freeze | lag (1 controller + 1 witness) | 1,370,140 | 9.79% | 90.21% | 698,470,633 | 6.98% | 93.02% |
| freeze | honest_7key (3 revealed of 7 committed, GLEIF 3-of-7) | 4,113,688 | 29.38% | 70.62% | 1,929,971,270 | 19.30% | 80.70% |

Minimum headroom across all cells: **70.62% memory** and **80.70% CPU** (both on
the honest_7key freeze) — comfortably above the ≥ 25% headroom target.

Reading the cells:

- **convict** is nearly free — one controller `verify_ed25519_signature` over
  `event_bytes` plus the same-reveal / forward-commitment list comparisons.
- **freeze** cost scales with the reveal set: each verifying revealed key costs
  one `verify_ed25519_signature` **and** one `next_key_digest` (a blake3 over the
  44-byte qb64). The 2-controller witnessless case is 18.94% mem; the GLEIF
  3-of-7 reserve (3 verifying reveals digested against 7 committed positions) is
  29.38% mem, the binding cell.
- Memory binds before CPU on every freeze cell, so the memory headroom column is
  the one to watch.

## The #24 takeaway — the SAID recomputation is likely redundant under O1

A full on-chain spend was expected to add a SAID recomputation over the
≤1024-byte event bytes (spike-88 measured single-chunk blake3 at ~10.0M mem /
71.7% at 1024 B) on top of these schema cells, which would make the combined
7-key freeze tight. But **O1 resolved that every signature — controller and
witness — verifies over the complete `event_bytes`, not the SAID.** So the
signatures already bind the bytes:

- **Convict:** controller signatures over the complete `event_bytes` satisfy the
  tip's `cur_threshold`. The AID (`i`) and the conflicting `n` are inside those
  signed bytes; an attacker can neither alter `i` nor forge the signature, so the
  double-sign is proven without recomputing the SAID.
- **Freeze:** witness receipts over the complete `event_bytes` (≥ `toad`) plus
  the revealed keys ∈ committed `next_keys` bind it as a real later event for
  this AID — again with no SAID recomputation.

A SAID recomputation would be load-bearing only if signatures signed the SAID
(they do not — O1). **This should be #24's first design question:** if the
recomputation is confirmed unnecessary, the dominant projected on-chain cost
disappears and even the 7-key GLEIF freeze fits one transaction with wide
headroom. The two-layer boundary stands — the full-spend-context measurement is
#24/#109's — but the schema cells above are the real enforcement cost.
