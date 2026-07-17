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

## Slice 2 — Haskell predicates

- [ ] T106-S2 `qb64Aid` in CESR.hs; `EventEvidence`, `convictPredicate`, `freezePredicate` in Enforcement.hs
- [ ] T106-S2 RED-first fixture self-consistency: load the manifest, decode qb64 keys/sigs, verify each Ed25519 signature over `event_raw` with cardano-crypto-class (independent confirmation of O1 + retroactive check that qb64+blake3 reproduces keripy's `n` entries)
- [ ] T106-S2 RED: honest-does-not-convict (F3), fork-convicts, lag-freezes, O1-pinned signature bytes
- [ ] T106-S2 negatives F1, F2, F4, F5, F6, F7, F10 via fixture mutation in EnforcementSpec
- [ ] T106-S2 gate green; committed with trailer `Tasks: T106-S2`

## Slice 3 — Aiken mirror + vectors + verdict parity

- [ ] T106-S3 `enforcement.ak` + `qb64_aid`; verdict types per #68 convention
- [ ] T106-S3 vector generator extended; fixture-derived constants committed; drift-stable
- [ ] T106-S3 aiken tests: byte parity + verdict parity incl. fork/lag scenarios
- [ ] T106-S3 committed with trailer `Tasks: T106-S3`

## Slice 4 — lifecycle vectors + output-shape predicates

- [ ] T106-S4 `TombstoneV1` + output-shape predicates (Convict 5 / Freeze 4) in both languages
- [ ] T106-S4 negatives F8, F9, F11, F12, F13 in both languages
- [ ] T106-S4 committed with trailer `Tasks: T106-S4`

## Slice 5 — measurement + finalization prep

- [ ] T106-S5 #109 matrix extended with Convict/Freeze full-context cells (2-key + 7-key fixtures)
- [ ] T106-S5 ≥ 25% headroom asserted or the spec's budget target revised with rationale
- [ ] T106-S5 O3/O4 recorded as #24 parameters in spec.md open questions
- [ ] T106-S5 gate extended with measurement invocation; committed with trailer `Tasks: T106-S5`
