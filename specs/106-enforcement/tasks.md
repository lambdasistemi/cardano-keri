# Tasks: #106 — convict/freeze enforcement spend paths

## Slice 1 — keripy oracle harness + O1/O2 resolution  [orchestrator, inline]

- [X] T106-S1 `gen_fixtures.py` + `run.sh` committed and nix-runnable with pinned keripy 1.3.5; fixed salt; regeneration byte-stable (verified: no diff on re-run)
- [X] T106-S1 honest_2key / honest_7key / fork / lag fixture bundles + manifest.json committed
- [X] T106-S1 every signature carries its verified `signing_target`; all 20 = `event_raw` → **O1 RESOLVED** (signatures over the full serialization, not the SAID); spec.md O1 + shared-checks updated. Threshold spellings recorded verbatim per event (O2 evidence)
- [X] T106-S1 gate.sh extended with the opt-in (`CARDANO_KERI_KERI_FIXTURES=1`) fixture drift check
- [X] T106-S1 committed with trailer `Tasks: T106-S1`

Note: the self-consistency RED test moved to Slice 2 — it needs the Haskell
qb64/Ed25519 decode helpers the driver owns, and doubles as a retroactive
oracle check of the #68 `next_key_digest` derivation (our qb64+blake3 must
reproduce keripy's `n` entries byte-for-byte).

## Slice 2 — validate the PAST: #68 against the oracle (hermetic nix check)  [driver]

Validate the merged #68 contract against the committed keripy fixtures, as a
real nix check exercising the SHIPPED library (not a reimplementation). This is
"validate the past before entering the future": if the E-native derivation were
wrong, this check goes RED before any enforcement code is built on it.

- [X] T106-S2 `Keri68OracleSpec.hs` reads the committed fixtures via `Paths_cardano_keri` data-files (wired in cardano-keri.cabal); registered in test/Main.hs
- [X] T106-S2 O1 confirmation: each committed signature verifies over `event_raw` (cardano-crypto-class Ed25519) and NOT over the SAID — matching the fixture's recorded `signing_target`
- [X] T106-S2 #68 derivation: for each rotation's revealed keys, the REAL `qb64Verkey` + `blake3Hash` reproduces a member of the icp's committed `n` (decoded) — validating the byte-for-byte-equals-KEL claim against the oracle
- [X] T106-S2 negative control: a deliberately-wrong derivation (blake2b, or a bit-flipped key) does NOT match — the check provably discriminates
- [X] T106-S2 the spec is part of the `unit-tests` nix check (`nix build .#checks.x86_64-linux.unit-tests` green); gate green; committed with trailer `Tasks: T106-S2`

## Slice 3 — Haskell enforcement predicates

- [X] T106-S3 `qb64Aid` in CESR.hs; `EventEvidence`, `convictPredicate`, `freezePredicate` in Enforcement.hs
- [X] T106-S3 RED: honest-does-not-convict (F3), fork-convicts, lag-freezes, O1-pinned signature bytes, over the committed fixtures
- [X] T106-S3 negatives F1, F2, F4, F5, F6, F7, F10 via fixture mutation in EnforcementSpec
- [X] T106-S3 gate green; committed with trailer `Tasks: T106-S3`

## Slice 4 — Aiken mirror + vectors + verdict parity

- [ ] T106-S4 `enforcement.ak` + `qb64_aid`; verdict types per #68 convention
- [ ] T106-S4 vector generator extended; fixture-derived constants committed; drift-stable
- [ ] T106-S4 aiken tests: byte parity + verdict parity incl. fork/lag scenarios
- [ ] T106-S4 committed with trailer `Tasks: T106-S4`

## Slice 5 — lifecycle vectors + output-shape predicates

- [ ] T106-S5 `TombstoneV1` + output-shape predicates (Convict 5 / Freeze 4) in both languages
- [ ] T106-S5 negatives F8, F9, F11, F12, F13 in both languages
- [ ] T106-S5 committed with trailer `Tasks: T106-S5`

## Slice 6 — measurement + finalization prep

- [ ] T106-S6 #109 matrix extended with Convict/Freeze full-context cells (2-key + 7-key fixtures)
- [ ] T106-S6 ≥ 25% headroom asserted or the spec's budget target revised with rationale
- [ ] T106-S6 O3/O4 recorded as #24 parameters in spec.md open questions
- [ ] T106-S6 gate extended with measurement invocation; committed with trailer `Tasks: T106-S6`
