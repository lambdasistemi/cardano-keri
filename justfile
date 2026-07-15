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

# Run the live-boundary withDevnet #99 cage Phase-2 smoke (Linux-only)
e2e:
    cd offchain && nix build --quiet -L .#checks.x86_64-linux.e2e

# --- checkpoint fixtures (#68) ---

# Regenerate the committed Aiken checkpoint fixtures from the Haskell encoder.
# One Haskell computation (reusing the Slice-2/3 codec modules) is the sole
# source of truth for every canonical byte string; `aiken fmt` then canonicalizes
# the emitted module so it also satisfies `format-check-onchain`.
gen-checkpoint-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-checkpoint-vectors -- ../onchain/lib/cardano_keri/checkpoint/vectors.ak'
    cd onchain && nix shell nixpkgs#aiken --command aiken fmt lib/cardano_keri/checkpoint/vectors.ak

# Drift check: regenerate the fixtures and fail if the committed copy diverges
# from a fresh regenerate (stale fixtures must FAIL the gate).
check-checkpoint-vectors: gen-checkpoint-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/vectors.ak

# --- onchain (Aiken) ---

# Format Aiken sources
format-onchain:
    cd onchain && nix shell nixpkgs#aiken --command aiken fmt

# Check Aiken formatting without modifying files
format-check-onchain:
    cd onchain && nix shell nixpkgs#aiken --command aiken fmt --check

# Run Aiken tests + type-check
check-onchain:
    cd onchain && nix shell nixpkgs#aiken --command aiken check

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
ci-onchain: format-check-onchain check-onchain

# BLAKE3 spike CI gate (mirrors the BLAKE3 job)
ci-blake3: compiler-check-blake3 format-check-blake3 check-blake3

# Offchain CI gate (mirrors the Offchain + Dev shell jobs)
ci-offchain: build-offchain unit hlint format-check-offchain devshell-offchain check-checkpoint-vectors

# Full CI gate (mirrors .github/workflows/ci.yml)
ci: ci-onchain ci-blake3 ci-offchain
