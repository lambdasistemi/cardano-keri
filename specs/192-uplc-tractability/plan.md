# Implementation plan — exact-UPLC tractability

## Context and fixed decisions

- Base: `1473885a1a16d5d993b6d0c475566e086bf50dfb`.
- Issue lane: `/code/cardano-keri-issue-192`, branch
  `feat/192-uplc-tractability`.
- Production blueprint output at intake:
  `/nix/store/i9iys7lxzni9k22a2k6w6y0s6cryphha-keri-plutus-blueprint-silent`,
  SHA-256 `896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c`.
  Revalidated at the exact base with `offchain/flake.lock` SHA-256
  `a56d8745879591a68b3e3f893099a6dc638a96cf58f883779b4bcb9e83f4668a`.
  This is intake evidence, not a hard-coded accepted output path.
- Clean exact-base baseline: `just ci` exited 0 in 620 seconds; captured log
  SHA-256
  `2a3a721c4e9f961e43faf4473cc532869d0a62b10c20289da09912f4d0d23ff0`.
- The compiled bridge lives below `offchain/` because its frozen public Nix
  surfaces are `offchain#blaster` and `offchain#checks...blaster`. The existing
  `lean/` project remains the abstract, kernel-checked lifecycle model.
- PAIR is the default topology. This ticket crosses artifact, compiler,
  evaluator, ledger-purpose, solver, and claim boundaries, and no approved
  host sandbox/attestation launcher exists for LIGHT.
- `workhorse-usage=NORMAL`; nested cheap tools are unavailable unless the PAIR
  brief names an independently approved launcher and budget.

## Architecture

```text
tracked onchain source + aiken.lock
          │
          ▼
offchain#plutus-blueprint (only UPLC source)
          │ exact jq -er selector + cardinality/non-empty checks
          ▼
hash-bound generated Lean source/import files
          │ #import_uplc + pinned V3 preparation
          ▼
purpose smokes + live builtin/preparation probes
          │
          ▼
dispatch/signature solver legs
          │ terminal verdict adapter
          ▼
TRACTABILITY-RESULT + offchain#blaster/check + just blaster
```

The source derivation receives the existing fixed-output `blueprint` directly;
it never accepts a path argument or environment fallback. A small tracked
audit/result surface records hashes and decisions, while raw build logs remain
build evidence rather than prose.

## Invariants

1. **Artifact identity:** the imported blob is byte-derived from the exact Nix
   blueprint selected by a unique non-empty title. A comparator binds title,
   blueprint hash, program hash, source commit, and lock hash.
2. **No ambient fallback:** no code path names or probes
   `onchain/plutus.json`; the known ambient file may exist without affecting
   any derivation.
3. **Pin closure:** every acceptance input resolves to an immutable lock node;
   raw dependency declarations and existing Lean CI contain no mutable pin.
4. **Purpose agreement:** parameters precede one V3 context; reward/certify
   smokes reach their respective entrypoints, while a wrong purpose fails.
5. **Live evaluator proof:** a builtin claim is derived from decoded production
   bytes and the real preparation/CEK run, not dependency source alone.
6. **Terminal solver vocabulary:** every leg maps to Valid, counterexample, or
   a named failing class. Timeout/Undetermined cannot map to success.
7. **Honest claim:** `blasterProven` is visible and Valid is never described as
   a Lean kernel proof.
8. **Runnable check:** the Nix check invokes the same executable/build path
   exposed to developers, and a seeded negative proves it can fail.

## Ordered slices

### Slice S1 — Pin and extract the exact artifact

Owned behavior surface: `offchain/flake.nix`, `offchain/flake.lock`, a new
`offchain/blaster/` Lean project and extraction/audit support, the existing
Lean CI invocation if required, `justfile`, and narrowly scoped documentation.

- Add immutable inputs for Lean-Blaster, PlutusCoreBlaster,
  CardanoLedgerApiBlaster, Lean, Z3, and their closure.
- Replace the acceptance-critical `nixpkgs#lean4` workflow path with the pinned
  repository identity; record the future raw-revision bump owner.
- Create the Nix-owned extraction source using unique, non-empty `jq -er`
  selections from the existing blueprint derivation.
- Establish `just blaster`, package `blaster`, and executable check `blaster`
  early, initially proving artifact identity and extraction controls.
- RED control: baseline lacks `just blaster`; seeded duplicate/empty selection
  and ambient-path probes must fail.

### Slice S2 — Prepare real programs and purposes

Owned behavior surface: the new bridge project and Nix wiring only.

- Import production `checkpoint`, `hash_proof`, and the three observer programs
  using `#import_uplc`.
- Derive parameter arity from the actual blueprint schemas/source and apply
  parameters followed by exactly one mint/spend/reward/certify V3 context.
- Add known-good reward and certify smokes for lifecycle, advance, and
  enforcement observers plus wrong-purpose RED controls.
- Prepare checkpoint and hash-proof at explicitly recorded fuel.
- Decode production UPLC, inventory reached builtins, and exercise the pinned
  `expectedArgs`/CEK path, including live `xor_bytearray`, before classifying or
  filing an upstream defect.
- RED control: wrong purpose and a deliberately too-low preparation-fuel
  control fail for the intended reason.

### Slice S3 — Measure solver envelope and publish the verdict

Owned behavior surface: bridge properties, result/audit documentation, and
the same Nix/just entrypoint.

- Run the unknown/malformed spend-redeemer dispatch property over prepared
  production checkpoint.
- Run the insufficient-controller-evidence signature property over a
  signature-required production checkpoint branch.
- Add a terminal verdict adapter and fixed timeout so Valid/counterexample are
  distinguishable from timeout, Undetermined, skip, or missing output.
- Capture fuel, solver options/seed/statistics, wall time, hardware, artifact
  identities, purpose and boundary classification per leg.
- Publish `TRACTABILITY-RESULT`; PASS requires every non-waivable leg. FAIL
  records the limiting class and parks #193–#195 for milestone re-scope.
- Prove the final Nix check can fail through a seeded failing verdict before
  restoring and matching the clean hashes.

Each slice is bisect-safe, uses the same evolving ignored `gate.sh`, receives a
fresh PAIR runtime, and is accepted independently before task stamping/push.

## Frozen verification commands

These commands may be supplemented by narrower slice RED commands but cannot
be removed, replaced, or weakened:

```sh
nix build --no-link ./offchain#plutus-blueprint --print-out-paths
just blaster
cd offchain && nix build -L .#blaster
cd offchain && nix build -L .#checks.x86_64-linux.blaster
git status --short --branch
```

After behavior changes, `just ci` is also the final local pre-push repository
gate. Final acceptance runs the frozen commands from a clean issue worktree
and preserves complete output, exit code, and wall time.

## Evidence schema

Every command record contains:

- exact UTC start/end, wall seconds, command, CWD, exit status, and complete
  stdout/stderr log hash;
- exact `HEAD`, source commit, branch, clean-status output, and host facts
  (`uname`, architecture, CPU model/count, memory);
- blueprint store path and SHA-256, exactly selected title, normalized
  unapplied-program SHA-256, `offchain/flake.lock` SHA-256, and every resolved
  lock-node owner/repo/revision/nar hash;
- Lean/Lean-Blaster/PlutusCoreBlaster/CardanoLedgerApiBlaster/Z3/Aiken/nixpkgs
  versions or revisions, plus the raw-revision bump owner;
- per preparation: program/title, purpose, parameters, context convention,
  fuel, reached/residual/unsupported builtins, `expectedArgs` observation,
  verdict, limiting class, and wall time;
- per solver leg: property ID, purpose, purpose-only vs full
  `validScriptContext`, raw-`Data`/decoder boundary, fuel, options, seed,
  timeout, statistics, wall time, verdict, proof label, and limiting class;
- negative control: seeded defect, expected failure signal, actual non-zero
  exit, restoration identity, and post-restore GREEN hash;
- final `TRACTABILITY-RESULT: PASS|FAIL`, follow-on disposition, upstream issue
  link if proven, and explicit trust/unsupported-semantics notes.

## Acceptance and stop rules

The ticket owner accepts only matching driver/navigator commits followed by
fresh gate execution and source verification. Any ambiguous artifact identity,
mutable pin, source restoration failure, missing live builtin evidence,
timeout/Undetermined proposed as proof, or ambient blueprint acceptance stops
the slice. A failed tractability leg is frozen as the real result and escalated;
the property is not weakened and the leg is not retried until green.
