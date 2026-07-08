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

# Assert the offchain dev shell can build with cabal
devshell-offchain:
    cd offchain && nix develop --quiet -c cabal build all -O0

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

# --- aggregate ---

# Format everything
format: format-offchain format-onchain

# Check formatting everywhere
format-check: format-check-offchain format-check-onchain

# Onchain CI gate (mirrors the Onchain job)
ci-onchain: format-check-onchain check-onchain

# Offchain CI gate (mirrors the Offchain + Dev shell jobs)
ci-offchain: build-offchain unit hlint format-check-offchain devshell-offchain

# Full CI gate (mirrors .github/workflows/ci.yml)
ci: ci-onchain ci-offchain
