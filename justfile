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

# Assert the offchain dev shell yields a working toolchain (offline)
devshell-offchain:
    #!/usr/bin/env bash
    set -euo pipefail
    cd offchain
    nix develop --quiet -c bash -euc '
      cabal --version
      fourmolu -m check $(find . -name "*.hs" -not -path "./dist-newstyle/*")
      find . -name "*.cabal" -not -path "./dist-newstyle/*" | xargs cabal-fmt -c
      hlint $(find . -name "*.hs" -not -path "./dist-newstyle/*")
    '

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
ci-offchain: build-offchain unit hlint format-check-offchain devshell-offchain

# Full CI gate (mirrors .github/workflows/ci.yml)
ci: ci-onchain ci-blake3 ci-offchain
