# Tasks: registration path — icp admission and checkpoint genesis (#114)

One slice = one bisect-safe commit carrying `Tasks: T114-S<n>`; boxes are
checked in the same amended commit that lands the slice.

## Slice 1 — keripy registration fixture family

- [X] T114-S1 Extend `gen_fixtures.py` with the `registration` family
      (`reg_witnessed` 3-wit/toad-2, `reg_weighted`, `reg_dip`, `reg_drt`,
      `reg_oversize`), signer-seed export, and generator-emitted offsets for
      `t/i/s/k/kt/n/nt/b/bt`; commit the new bundle; RED loader spec first;
      regeneration byte-stable; existing bundles byte-unchanged (drift
      check).

## Slice 2 — Haskell registration predicate

- [X] T114-S2 `Cardano.KERI.AID.Checkpoint.Registration`: `B`-code qb64,
      canonical `kt`/`nt`/`bt` re-spelling, E1–E9 slice checks, proof-token
      name, pure R3/R4/R6/R7/R8 predicate + typed errors; fixture-driven
      RED→GREEN spec (positives: 2-key, witnessed, weighted, owner-replay;
      negatives: squat, dip, drt, per-slice E1–E9, wrong-preimage/
      below-threshold signatures, and the A-001 offset-misdirection family:
      wrong offsets, overlapping spans, spans into `a`/other fields,
      code-prefix confusion, truncated slices, duplicated offsets).

## Slice 3 — Aiken mirror + shared-vector parity

- [X] T114-S3 `checkpoint/registration.ak` mirror + `gen-registration-vectors`
      generator + Aiken vector/parity suites asserting byte-identical
      encodings AND identical verdicts per vector (incl. the full
      offset-misdirection family — A-001 QB condition 1 gates acceptance);
      drift check wired.

## Slice 4 — hash-proof minting policy

- [X] T114-S4 `validators/hash_proof.ak` (H1–H4) + tests (honest 300 B /
      966 B / 1024 B mints, oversize, wrong-AID, multi-name, extra-quantity,
      burn branch) + size-tier measurement cells.

## Slice 5a — true 2-key/7-key registration shapes (Q-003 ruling: option B)

- [X] T114-S5a Extend the registration fixture family with `reg_2key`
      (≤1024 B unwitnessed 2-key icp) and `reg_7key` (≤1024 B unwitnessed
      GLEIF-shaped 7-key icp), seeds + offsets, existing bundles
      byte-unchanged; extend `GenRegistrationVectors.hs` +
      `registration_vectors.ak` with an honest signed scenario each; update
      the S1 loader spec's family assertions; regeneration byte-stable.

## Slice 5b — base64url encoder optimization (A-001 gate miss remediation)

- [X] T114-S5b Rewrite `cardano_keri/base64url.encode` from per-byte
      fold (~638K mem per 33-byte encode) to a 3-bytes-per-step encoder
      with byte-identical output; extend `base64url_tests.ak` parity
      coverage; full suite + S3 qb64 goldens green; re-measure the S5
      cells — target `reg_7key` ≥25% mem headroom.

## Slice 5 — checkpoint validator scaffold + Register branch

- [ ] T114-S5 `validators/checkpoint.ak` (`version`, `hash_proof_policy`,
      `network_id`, `d_reg`): `Register` mint branch composing R1–R8 (no
      fixed-input-count assumption — room for the #116 gate input, A-001
      QC), fail-closed spend (R10); ScriptContext end-to-end positives
      (2-key, 7-key GLEIF, witnessed 2-of-3, proof burned) + R1/R2/R5/R8/
      R10 negatives; registration-context measurement cells at 2-key and
      7-key — the A-001 measurement gate: <25% headroom ⇒ STOP + Q-file.

## Slice 6 — measurements report + finalization

- [ ] T114-S6 `specs/114-registration/MEASUREMENTS.md`: reported cells +
      ≥25% headroom verdict (or recorded rationale); close cell gaps.
- [ ] T114-S6b (orchestrator) PR body audit, `chore: drop gate.sh`,
      mark-ready Q-file to the epic owner.
