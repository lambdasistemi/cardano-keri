# Exact-UPLC preparation and production tractability

Issue: [#192](https://github.com/lambdasistemi/cardano-keri/issues/192)
Parent: [#189](https://github.com/lambdasistemi/cardano-keri/issues/189)
Milestone: #8 — Blaster, compiled UPLC verification in Lean

## Outcome

Establish a reproducible, fail-loud path from the exact Nix-built Cardano-KERI
Aiken blueprint to pinned Lean/Blaster/Z3 checks, then publish the measured
preparation and solver envelope for the production `checkpoint` and
`hash_proof` programs. The result is an experiment with a non-waivable
verdict: a failed preparation or solver leg is reported and parks later Epic
#189 work; it is never retried until green or represented as proof.

## User stories

### US1 — Reproduce the exact artifact

As a reviewer, I can run one repository command from a clean checkout and know
that every imported UPLC byte came from the Nix-built production blueprint at
the recorded source and lock revisions, never from ignored worktree output.

### US2 — Observe the real preparation boundary

As a bridge author, I can see whether the pinned UPLC preparation machinery
accepts the production programs and their real Plutus V3 calling conventions,
including every production observer purpose and any live Batch-5 builtin.

### US3 — Decide tractability honestly

As the milestone desk, I receive a durable `TRACTABILITY-RESULT` whose solver
legs are terminal (`Valid` or counterexample), whose limits and trust boundary
are explicit, and whose failure parks follow-on bridge work instead of being
hidden by retries, timeouts, or weakened properties.

## Functional requirements

### FR-01 — Clean and singular source

- The source commit is recorded and the issue worktree is clean at evidence
  freeze.
- `nix build --no-link ./offchain#plutus-blueprint --print-out-paths` is the
  sole production UPLC source.
- No ignored or ambient `onchain/plutus.json` path is read, copied, hashed, or
  accepted by the bridge.
- Extraction uses `jq -er`, requires exactly one matching validator title and
  one non-empty `compiledCode`, and normalizes only the selected value.
- Evidence records blueprint SHA-256, exact title, unapplied-program SHA-256,
  source commit, and `offchain/flake.lock` SHA-256.

### FR-02 — Complete immutable toolchain

- Lean, Lean-Blaster, PlutusCoreBlaster, CardanoLedgerApiBlaster, Z3, Aiken,
  nixpkgs, and every transitive flake input are bound to immutable revisions in
  the lock graph. Acceptance-critical source declarations contain no `main`
  or other mutable branch pin.
- The existing `.github/workflows/ci.yml` Lean invocation using
  `nixpkgs#lean4` is either changed to the same immutable Lean identity or
  explicitly excluded with a recorded reason. This ticket chooses the former:
  acceptance-critical Lean CI must use the pinned repository identity.
- The durable result names the future owner for raw-revision bumps: the
  Cardano-KERI maintainer owning the Blaster Nix inputs and lock update command.

### FR-03 — Real imports and V3 arguments

- Production bytes enter Lean through `#import_uplc`.
- Preparation applies declared Aiken parameters first, then exactly one
  Plutus V3 `ScriptContext` term using the ledger convention for each purpose.
- Production `checkpoint` and `hash_proof` are prepared at recorded fuel.
- Each `observer_lifecycle`, `observer_advance`, and `observer_enforcement`
  program has an early rewarding (`withdraw`) smoke and certifying (`publish`)
  smoke. A wrong-purpose control is RED for each program.
- The bridge distinguishes mint, spend, reward, and certify conventions; an
  `else`/wrong-purpose path cannot be accepted as a successful smoke.

### FR-04 — Live Batch-5 and builtin audit

- The decoded production UPLC is inspected mechanically for builtin identity.
- The pinned PlutusCoreBlaster `expectedArgs` behavior is exercised on the
  actual preparation/CEK path for every reached Batch-5 builtin. In particular,
  Cardano-KERI's live `xor_bytearray` path is measured rather than inferred
  from dependency source.
- An upstream defect is claimed or filed only when the pinned production-byte
  run proves it. Any confirmed issue is linked in the durable result.
- The result lists builtin identity, preparation support, and solver treatment
  for every program exercised here. Uninterpreted crypto and hash-dependent
  claims are explicit; no semantic claim may exceed the solver's treatment.

### FR-05 — Terminal preparation and solver legs

- Both `checkpoint` and `hash_proof` prepare, or the run terminates with one
  named limiting class: `preparation/fuel`, `builtin support`,
  `solver verdict`, or `time budget`.
- Prepared production `checkpoint` runs one dispatch-class property: an
  unknown/malformed spend redeemer cannot be successful after dispatch.
- Prepared production `checkpoint` runs one signature-class property: a
  signature-required registration/advance shape with insufficient controller
  evidence cannot be successful.
- Each solver leg ends `Valid` or counterexample. `Undetermined`, timeout,
  missing output, skipped execution, and retry-until-green are hard failures.
- Each leg records artifact/program hash, title, purpose, fuel, options, seed,
  solver statistics, timeout, verdict, limiting class, wall time, and hardware.

### FR-06 — Honest boundary and claim vocabulary

- Every property states whether it is purpose-only or assumes a complete
  `validScriptContext`. Raw ledger `Data` is the boundary unless a typed
  decoder is itself in the checked property.
- `blasterProven` warnings remain visible in build output.
- A Blaster `Valid` result is labeled exactly `SMT-VALID (no proof term)`,
  never `KERNEL-PROVED`.

### FR-07 — Runnable and fail-loud surfaces

- The repository exposes `just blaster`.
- `cd offchain && nix build -L .#blaster` builds the runnable evidence path.
- `cd offchain && nix build -L .#checks.x86_64-linux.blaster` executes it as a
  Nix check rather than merely packaging a script.
- A negative control proves that the check can fail. Timeout and
  `Undetermined` must cause a non-zero exit.

### FR-08 — Durable decision artifact

- A tracked `TRACTABILITY-RESULT` records the full evidence schema, measured
  results, trust limits, exact commands, and final PASS/FAIL classification.
- FAIL is a valid ticket outcome. It explicitly parks #193–#195 and requests a
  milestone re-scope; it cannot be rewritten as PASS by weakening a property,
  increasing retries, or omitting a leg.

## Observable success criteria

1. From a clean issue worktree, all five frozen verification commands in
   `plan.md` terminate with complete captured evidence.
2. Artifact and toolchain records reconcile to the exact files and revisions
   used by the build.
3. Purpose smokes include known-good reward/certify paths and wrong-purpose
   RED controls.
4. The check's seeded negative control exits non-zero for the intended reason.
5. Both preparation legs and both checkpoint solver legs have terminal,
   non-`Undetermined` records.
6. `TRACTABILITY-RESULT` says PASS only if every non-waivable leg passes.

## Rejection behavior

The path fails without fallback on an absent, duplicate, renamed, null, empty,
or malformed title; ambient blueprint access; mutable acceptance pin; wrong
purpose; unsupported live builtin; exhausted preparation fuel; timeout;
`Undetermined`; missing statistics; hidden warning; unclassified verdict; or
dirty evidence source. No result is inferred from source inspection alone.

## Trust boundary

This ticket measures a compiled-UPLC SMT path. Its trust base includes exact
artifact extraction/import, UPLC decoding and preparation semantics, ledger
encodings, Blaster translation, Z3, fuel, Aiken, Nix, and all pinned inputs.
It does not prove the Aiken compiler, the whole Cardano ledger, liveness or
economics, deployment binding, or hash semantics represented as uninterpreted
functions. Purpose-only properties do not imply full ledger-context validity.

## Out of scope

- The 23-title/8-program authoritative inventory and complete bridge contract
  belong to #193.
- Source-mutation restoration across the production Nix boundary belongs to
  #194; this ticket still owns the local check negative control required by
  FR-07.
- Final CI policy, total bridge budget, taxonomy rollout, fresh-checkout audit,
  and `BRIDGE-FROZEN` belong to #195.
- Abstract lifecycle theorem changes, deployment binding, sibling contracts,
  and merge authority are excluded.
