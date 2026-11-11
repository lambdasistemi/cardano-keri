# MANDATE SKELETON — R4: pinned keripy parity + proven abstention (STAGED)

Authority: A-019 sha256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf` §5,
under A-018 FINAL `1c9788a6…` §5. OPEN-free; new semantic choices return
upward before write.

- Predecessor: R3 accepted AND merged; R4 bases on that result.
- Scope: the cursor-vs-keripy oracle with TWO obligations. "Otherwise-equal"
  binds exactly as ruled: equally admissible AFTER every content-derived KERI
  verification and superseding/reconciliation rule has run (not byte-equal,
  not same-type). Decision procedure verbatim from §5: (1) invalid evidence
  is rejected, never abstained; (2) apply all arrival-order-invariant rules
  (prior chaining, thresholds, content/anchor-derived recovery); (3) if the
  pinned keripy result changes solely under first-seen order permutation of
  the same evidence set → `Abstained(FirstSeenUnavailable,…)`; (4) otherwise
  match keripy exactly. Includes symmetric rival interactions,
  non-superseding rival rotations, first-seen-dependent delegated recovery;
  excludes content-resolved rotation-over-interaction and authenticated
  delegation ordering actually present.
- Oracle duties: pin exact keripy commit/container digest; run both arrival
  orders (all relevant permutations for larger minimal sets); invariant
  result ⇒ equality required; order-dependent result without authenticated
  first-seen evidence ⇒ abstention required; the resolve-by-Cardano-slot
  mutant MUST be demonstrated to fail. No broad "observation-dependent"
  bucket may hide parser rejection, unsupported types, missing
  signatures/anchors, or implementation gaps — each gets a distinct total
  outcome.
- Completing R4 (with R1-R3 + witness slice) satisfies the S2 COMPLETE bar
  and closes registry contracts cursor-fidelity + first-seen-non-replication
  from enforced=NONE to enforced.
- Seats/guards: identical to R1 skeleton.
