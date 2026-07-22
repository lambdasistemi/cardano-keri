# shellcheck shell=bash

set unstable := true

# List available recipes
default:
    @just --list

# --- offchain (Haskell) ---

# Format Haskell/cabal/nix sources
format-offchain:
    cd offchain && nix run --quiet .#format

# Check Haskell/cabal formatting without modifying files
format-check-offchain:
    cd offchain && nix run --quiet .#format-check

# Run hlint over Haskell sources
hlint:
    cd offchain && nix run --quiet .#hlint

# Run offchain unit tests (executes the binary)
unit match="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=()
    if [[ '{{ match }}' != "" ]]; then
        args+=(--match "{{ match }}")
    fi
    cd offchain && nix run --quiet .#unit-tests -- "${args[@]}"

# Build the offchain library + tests
build-offchain:
    cd offchain && nix build --quiet .#checks.x86_64-linux.unit-tests

# Build the whole offchain project (incl. e2e test component) from the dev shell,
# CHaP-offline via the Nix-local CHaP repo (issue #99 S9c) — no fetch of the
# secure https CHaP index (hackage over http + the git SRPs stay live). `cabal
# update` first generates the CHaP index cache from the nix-store repo (offline)
# and refreshes hackage (http); the build then compiles the CHaP stack + local
# project + e2e-tests from local source. cabal.project.devshell drops the https
# CHaP repository.
devshell-offchain:
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal build all --enable-tests -O0 --project-file=cabal.project.devshell'

# Run all live-boundary withDevnet smokes (Linux-only): the existing #99 cage
# positive plus the #114 permissionless checkpoint lifecycle boundary.
e2e:
    cd offchain && nix build --quiet -L .#checks.x86_64-linux.e2e

# Run only the #114 checkpoint boundary: real hash-proof/Register/Arm/Claim
# settlement plus production-validator Advance and Close rejections.
e2e-checkpoint:
    cd offchain && nix run --quiet .#e2e -- --match "#114 permissionless checkpoint boundary"

# --- checkpoint fixtures (#68) ---

# Regenerate the committed Aiken checkpoint fixtures from the Haskell encoder.
# One Haskell computation (reusing the Slice-2/3 codec modules) is the sole
# source of truth for every canonical byte string; `aiken fmt` then canonicalizes
# the emitted module so it also satisfies `format-check-onchain`.
gen-checkpoint-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-checkpoint-vectors -- ../onchain/lib/cardano_keri/checkpoint/vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/vectors.ak

# Drift check: regenerate the fixtures and fail if the committed copy diverges
# from a fresh regenerate (stale fixtures must FAIL the gate).
check-checkpoint-vectors: gen-checkpoint-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/vectors.ak

# Regenerate the committed Aiken enforcement vectors (#106) from the committed
# keripy fixtures via GenEnforcementVectors.hs. OFFLINE — reads the committed
# JSON, no keripy. One Haskell computation is the source of truth for the tip +
# evidence each scenario feeds convict_predicate/freeze_predicate; `aiken fmt`
# then canonicalizes the emitted module.
gen-enforcement-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-enforcement-vectors -- ../onchain/lib/cardano_keri/checkpoint/enforcement_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/enforcement_vectors.ak

# Drift check: regenerate the enforcement vectors and fail if the committed copy
# diverges from a fresh regenerate (stale vectors must FAIL the gate).
check-enforcement-vectors: gen-enforcement-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/enforcement_vectors.ak

# Regenerate the committed Aiken registration vectors (#114) from the committed
# keripy registration.json via GenRegistrationVectors.hs. OFFLINE — reads the
# committed JSON (signatures re-derived from the exported signer seeds), no
# keripy. One Haskell computation is the source of truth for every scenario's
# context/datum/evidence AND its verdict (the generator asserts the Haskell
# predicate verdict before emitting); `aiken fmt` then canonicalizes the module.
gen-registration-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-registration-vectors -- ../onchain/lib/cardano_keri/checkpoint/registration_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/registration_vectors.ak

# Drift check: regenerate the registration vectors and fail if the committed
# copy diverges from a fresh regenerate (stale vectors must FAIL the gate).
check-registration-vectors: gen-registration-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/registration_vectors.ak

# Regenerate the committed Aiken advance vectors (#115) from the committed
# keripy advance.json via GenAdvanceVectors.hs. OFFLINE — reads the committed
# JSON (signatures re-derived from the exported signer seeds), no keripy. One
# Haskell computation is the source of truth for every scenario's spent
# context/created datum/evidence AND its verdict (the generator asserts the
# Haskell predicate verdict before emitting); `aiken fmt` then canonicalizes
# the module.
gen-advance-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-advance-vectors -- ../onchain/lib/cardano_keri/checkpoint/advance_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/advance_vectors.ak

# Drift check: regenerate the advance vectors and fail if the committed copy
# diverges from a fresh regenerate (stale vectors must FAIL the gate).
check-advance-vectors: gen-advance-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/advance_vectors.ak

# Regenerate the isolated #116 freeze-bond parity vectors from the Haskell
# model. The generator is the sole source of wire bytes, role constants,
# parameter verdicts, and raw deadline-boundary verdicts.
gen-freeze-bond-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-freeze-bond-vectors -- ../onchain/lib/cardano_keri/checkpoint/freeze_bond_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/freeze_bond_vectors.ak

# Drift check: a fresh Haskell regenerate must reproduce the committed module.
check-freeze-bond-vectors: gen-freeze-bond-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/freeze_bond_vectors.ak

# Regenerate the 17 Lean-theorem verdicts from the pure Haskell lifecycle
# mirror. The generated Aiken module is never edited by hand.
gen-lifecycle-trace-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-lifecycle-trace-vectors -- ../onchain/lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak

# Drift check: Haskell is the sole source of theorem verdict fixtures.
check-lifecycle-trace-vectors: gen-lifecycle-trace-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak

# Enforce the 17-row Lean -> QuickCheck -> Aiken executable map, including
# generated-vector drift.
check-lean-traceability:
    ./scripts/check-lean-traceability.sh

# --- onchain (Aiken) ---

# Format Aiken sources
format-onchain:
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt

# Check Aiken formatting without modifying files
format-check-onchain:
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt --check

# Run Aiken tests + type-check
check-onchain:
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check

# Measure the schema-layer enforcement predicate ex-units (#106 Slice 6).
# An INVOCATION, not a headroom ASSERTION: aiken cannot assert its own ex-units
# in-test, so this runs the measurement tests with `--plain-numbers` (printing
# exact mem/cpu per test) and fails only if a measurement test fails to run/pass.
# The headroom verdict is the re-verifiable claim in specs/106-enforcement/MEASUREMENTS.md.
measure-enforcement:
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check --plain-numbers -m measure_convict -m measure_freeze

# Measure the hash-proof minting policy ex-units at the three size tiers
# (#114 S4: ~300 B class, 966 B GEDA-scale, 1024 B boundary). Same caveat as
# measure-enforcement: an INVOCATION printing exact mem/cpu per cell, not a
# headroom assertion — the verdict lives in specs/114-registration/MEASUREMENTS.md.
measure-hash-proof:
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check --plain-numbers -m measure_hash_proof

# Measure and mechanically gate the nine checkpoint ACCEPT paths: the six
# inherited #116 rows plus the three #114 Register contexts. Every row must
# pass and retain the 25%-headroom limits (10.5m memory, 7.5b CPU).
measure-checkpoint:
    #!/usr/bin/env bash
    set -euo pipefail
    results="$(mktemp)"
    trap 'rm -f "$results"' EXIT
    cd onchain
    nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#jq --command bash -euo pipefail -c '
      aiken check --plain-numbers -m measure_checkpoint | tee "$1"
      jq -e '\''
        [
          "measure_checkpoint_arm_2key",
          "measure_checkpoint_arm_7key",
          "measure_checkpoint_claim",
          "measure_checkpoint_convict_active",
          "measure_checkpoint_convict_armed",
          "measure_checkpoint_convict_frozen",
          "measure_checkpoint_register_2key",
          "measure_checkpoint_register_witnessed",
          "measure_checkpoint_register_7key"
        ] as $required
        | [.modules[].tests[] | select(.title | startswith("measure_checkpoint"))] as $tests
        | ($tests | map(.title)) as $actual
        | if ($actual | sort) != ($required | sort) then
            error("checkpoint measurement title mismatch: expected \($required | sort); actual \($actual | sort)")
          elif any($tests[]; .status != "pass") then
            error("checkpoint measurement did not pass: \([$tests[] | select(.status != "pass") | {title, status}])")
          elif any($tests[]; ((.execution_units? | type) != "object") or ((.execution_units.mem? | type) != "number") or ((.execution_units.cpu? | type) != "number")) then
            error("checkpoint measurement lacks execution units: \([$tests[] | select(((.execution_units? | type) != "object") or ((.execution_units.mem? | type) != "number") or ((.execution_units.cpu? | type) != "number")) | .title])")
          elif any($tests[]; .execution_units.mem > 10500000 or .execution_units.cpu > 7500000000) then
            error("checkpoint measurement exceeds hard limit: \([$tests[] | select(.execution_units.mem > 10500000 or .execution_units.cpu > 7500000000) | {title, execution_units}])")
          else
            $tests | map({title, status, execution_units})
          end
      '\'' "$1"
    ' _ "$results"

# --- BLAKE3 spike (pinned Aiken) ---

# Format the BLAKE3 spike with its pinned compiler
format-blake3:
    cd spikes/88-blake3-plutus && nix develop --quiet -c bash -euc 'nixfmt flake.nix; aiken fmt'

# Check BLAKE3 spike formatting with its pinned compiler
format-check-blake3:
    cd spikes/88-blake3-plutus && nix develop --quiet -c bash -euc 'nixfmt --check flake.nix; aiken fmt --check'

# Run BLAKE3 spike tests + type-check with its pinned compiler
check-blake3:
    cd spikes/88-blake3-plutus && nix develop --quiet -c aiken check

# Verify the pinned BLAKE3 compiler artifact and version
compiler-check-blake3:
    cd spikes/88-blake3-plutus && nix flake check --no-eval-cache

# --- aggregate ---

# Format everything
format: format-offchain format-onchain format-blake3

# Check formatting everywhere
format-check: format-check-offchain format-check-onchain format-check-blake3

# Onchain CI gate (mirrors the Onchain job)
ci-onchain: format-check-onchain check-onchain measure-enforcement measure-hash-proof measure-checkpoint

# BLAKE3 spike CI gate (mirrors the BLAKE3 job)
ci-blake3: compiler-check-blake3 format-check-blake3 check-blake3

# Offchain CI gate (mirrors the Offchain + Dev shell jobs)
ci-offchain: build-offchain unit hlint format-check-offchain devshell-offchain check-checkpoint-vectors check-enforcement-vectors check-registration-vectors check-advance-vectors check-freeze-bond-vectors check-lean-traceability

# Full CI gate (mirrors .github/workflows/ci.yml)
ci: ci-onchain ci-blake3 ci-offchain
