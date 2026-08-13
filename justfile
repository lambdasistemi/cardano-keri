# shellcheck shell=bash

set unstable := true

# List available recipes
default:
    @just --list

# --- offchain (Haskell) ---

# Format Haskell/cabal/nix sources
format-offchain:
    cd offchain && nix run --quiet --no-write-lock-file .#format

# Check Haskell/cabal formatting without modifying files
format-check-offchain:
    cd offchain && nix run --quiet --no-write-lock-file .#format-check

# Run hlint over Haskell sources
hlint:
    cd offchain && nix run --quiet --no-write-lock-file .#hlint

# Run offchain unit tests (executes the binary)
unit match="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=()
    if [[ '{{ match }}' != "" ]]; then
        args+=(--match "{{ match }}")
    fi
    cd offchain && nix run --quiet --no-write-lock-file .#unit-tests -- "${args[@]}"

# Build the offchain library + tests
build-offchain:
    cd offchain && nix build --quiet --no-write-lock-file .#checks.x86_64-linux.unit-tests

# Run the release-script derivation and manifest unit tests. An optional
# match narrows the suite to one focused population (#254 S254-1B).
deployment-unit match="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=()
    if [[ '{{ match }}' != "" ]]; then
        args+=(--match "{{ match }}")
    fi
    cd offchain && nix run --quiet --no-write-lock-file .#deployment-tests -- "${args[@]}"

# Run checkpoint indexer codec tests (executes the binary).
indexer-unit:
    cd offchain && nix run --quiet --no-write-lock-file .#indexer-tests

# #177 Slice 1: run the focused cli-tests suite plus the packaged ckeri
# status/backend --help surface and fork-retirement absence checks through
# one strict-PATH app (node-free, deterministic).
backend-check:
    cd offchain && nix run --quiet --no-write-lock-file .#backend-check

# #177 Slice 2: exercise the deterministic transcript validator and every
# approved negative control. Live raw-file reconciliation remains an explicit
# validator invocation because CI has no ticket-runtime captures.
backend-transcript-check:
    ./scripts/test-backend-status-transcripts.sh
    ./scripts/check-backend-status-transcripts.sh --transcript deploy/preprod/m1-backend-status-acceptance.txt
    nix run --quiet --no-write-lock-file path:./offchain#backend-transcript-check
    nix build --quiet --no-write-lock-file --no-link path:./offchain#checks.x86_64-linux.backend-transcript-check

# #181 Slice 1: coherent input/runtime seam focused tests — plural payer
# addresses through one engine transaction (payerUtxosTx) and the
# indexer-neutral TransactionRuntime call-order/fail-closed/signing proofs.
transaction-path-check:
    cd offchain && nix develop --quiet --no-write-lock-file -c cabal test deployment-tests -O0 \
        --test-options='--match "classifyEvaluation" --match "signWithCardanoCliKey" --match "runTransactionOperation"'
    cd offchain && nix develop --quiet --no-write-lock-file -c cabal test indexer-tests -O0 \
        --test-options='--match "payerUtxosTx"'

# #181 Slice 2A: focused shared build/sign kernel. The focused executable
# enforces a non-zero Hspec example count, so a stale matcher fails closed.
# Gate-visible recipe name: transaction-build-sign-check:
transaction-build-sign-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    matcher='{{ matcher }}'
    test_options=()
    if [[ -n "$matcher" ]]; then
        test_options+=("--test-option=--match=$matcher")
    fi
    cd offchain
    nix develop --quiet --no-write-lock-file -c cabal test transaction-build-sign-tests -O0 \
        --test-show-details=direct "${test_options[@]}"

# #181 Slice 2B: focused in-process Publisher migration. Mirrors
# transaction-build-sign-check's zero-example enforcement (the focused
# executable fails closed on a matcher selecting zero examples) and applies a
# restricted-PATH control: the suite runs with cardano-cli absent, and a
# command -v cardano-cli probe records that absence before the suite starts so
# "publishes without cardano-cli" is non-vacuous. The paired
# RestrictedPathSpec positive control proves the restriction mechanism can
# detect presence. Gate-visible recipe name: publisher-path-check:
publisher-path-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    restricted_path="$(dirname "$(command -v nix)")"
    echo "publisher-path-check: PATH=$restricted_path"
    if PATH="$restricted_path" command -v cardano-cli >/dev/null 2>&1; then
        echo "publisher-path-check: cardano-cli is reachable under the restricted PATH; the control is not meaningful" >&2
        exit 1
    fi
    echo "publisher-path-check: cardano-cli absent from the restricted PATH (expected)"
    matcher='{{ matcher }}'
    test_options=()
    if [[ -n "$matcher" ]]; then
        test_options+=("--test-option=--match=$matcher")
    fi
    cd offchain
    PATH="$restricted_path" nix develop --quiet --no-write-lock-file -c cabal test publisher-migration-tests -O0 \
        --test-show-details=direct "${test_options[@]}"

# #181 Slice 2C: focused in-process Registration migration. The dedicated
# runner fails on zero selected examples, while the PATH probe and paired
# RestrictedPathSpec make the external-command absence proof non-vacuous.
registration-path-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    restricted_path="$(dirname "$(command -v nix)")"
    echo "registration-path-check: PATH=$restricted_path"
    if PATH="$restricted_path" command -v cardano-cli >/dev/null 2>&1; then
        echo "registration-path-check: cardano-cli is reachable under the restricted PATH; the control is not meaningful" >&2
        exit 1
    fi
    echo "registration-path-check: cardano-cli absent from the restricted PATH (expected)"
    matcher='{{ matcher }}'
    test_options=()
    if [[ -n "$matcher" ]]; then
        test_options+=("--test-option=--match=$matcher")
    fi
    cd offchain
    PATH="$restricted_path" nix develop --quiet --no-write-lock-file -c cabal test registration-migration-tests -O0 \
        --test-show-details=direct "${test_options[@]}"

# #181 Slice 3: focused in-process Advance migration under a PATH that cannot
# resolve cardano-cli. The paired RestrictedPathSpec supplies the positive
# control and the focused runner rejects zero selected examples.
advance-path-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    restricted_path="$(dirname "$(command -v nix)")"
    echo "advance-path-check: PATH=$restricted_path"
    if PATH="$restricted_path" command -v cardano-cli >/dev/null 2>&1; then
        echo "advance-path-check: cardano-cli is reachable under the restricted PATH; the control is not meaningful" >&2
        exit 1
    fi
    echo "advance-path-check: cardano-cli absent from the restricted PATH (expected)"
    matcher='{{ matcher }}'
    test_options=()
    if [[ -n "$matcher" ]]; then
        test_options+=("--test-option=--match=$matcher")
    fi
    cd offchain
    PATH="$restricted_path" nix develop --quiet --no-write-lock-file -c cabal test advance-migration-tests -O0 \
        --test-show-details=direct "${test_options[@]}"

# #181 Slice 3: focused in-process Close migration restricted-PATH proof.
close-path-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    restricted_path="$(dirname "$(command -v nix)")"
    echo "close-path-check: PATH=$restricted_path"
    if PATH="$restricted_path" command -v cardano-cli >/dev/null 2>&1; then
        echo "close-path-check: cardano-cli is reachable under the restricted PATH; the control is not meaningful" >&2
        exit 1
    fi
    echo "close-path-check: cardano-cli absent from the restricted PATH (expected)"
    matcher='{{ matcher }}'
    test_options=()
    if [[ -n "$matcher" ]]; then
        test_options+=("--test-option=--match=$matcher")
    fi
    cd offchain
    PATH="$restricted_path" nix develop --quiet --no-write-lock-file -c cabal test close-migration-tests -O0 \
        --test-show-details=direct "${test_options[@]}"

# #181 Slice 3: focused endpoint-board post/update/retire restricted-PATH proof.
board-path-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    restricted_path="$(dirname "$(command -v nix)")"
    echo "board-path-check: PATH=$restricted_path"
    if PATH="$restricted_path" command -v cardano-cli >/dev/null 2>&1; then
        echo "board-path-check: cardano-cli is reachable under the restricted PATH; the control is not meaningful" >&2
        exit 1
    fi
    echo "board-path-check: cardano-cli absent from the restricted PATH (expected)"
    matcher='{{ matcher }}'
    test_options=()
    if [[ -n "$matcher" ]]; then
        test_options+=("--test-option=--match=$matcher")
    fi
    cd offchain
    PATH="$restricted_path" nix develop --quiet --no-write-lock-file -c cabal test board-migration-tests -O0 \
        --test-show-details=direct "${test_options[@]}"

# #181 Slice 2: static guard proving Publisher/Registration own no
# subprocess/cardano-cli transaction path, proven able to fail against its
# own positive-control fixture before trusting a clean scan of the real
# source.
deploy-register-no-cli-guard:
    ./scripts/check-deploy-register-no-cli.sh

# #181 Slice 4: production CLI composition under a PATH containing Nix but no
# cardano-cli. The source guard first proves its scanner against a deliberate
# shell-out fixture; the packaged executable's complete Nix closure is checked
# before it evaluates and renders help in the same restricted environment used
# by the earlier per-operation checks.
cli-composition-path-check:
    #!/usr/bin/env bash
    set -euo pipefail
    restricted_path="$(dirname "$(command -v nix)")"
    if [[ -n "${CKERI_RESTRICTED_PATH:-}" ]]; then
        restricted_path="$CKERI_RESTRICTED_PATH"
    fi
    echo "cli-composition-path-check: PATH=$restricted_path"
    if PATH="$restricted_path" command -v cardano-cli >/dev/null 2>&1; then
        echo "cli-composition-path-check: cardano-cli is reachable under the restricted PATH; the control is not meaningful" >&2
        exit 1
    fi
    echo "cli-composition-path-check: cardano-cli absent from the restricted PATH (expected)"
    ./scripts/check-deploy-register-no-cli.sh
    package="$(PATH="$restricted_path" nix build --quiet --no-link --no-write-lock-file --print-out-paths ./offchain#ckeri)"
    ./scripts/check-ckeri-closure-no-cli.sh "$package/bin/ckeri"
    PATH="$restricted_path" nix run --quiet --no-write-lock-file ./offchain#ckeri -- --help >/dev/null
    echo "cli-composition-path-check: packaged ckeri closure is clean and rendered help without cardano-cli"

# #181 Slice 2: restricted-PATH runtime control (DIRECTION-002). Sets an
# explicit PATH for the process that runs the focused Publisher/
# Registration/restricted-PATH suite, keeping only what nix/cabal need and
# nothing that provides cardano-cli; records the PATH in force and a
# command -v cardano-cli probe (expected non-zero) before the suite starts.
# This layer alone is not proof of anything — the paired RestrictedPathSpec.hs
# positive control is what makes the suite's silence about cardano-cli
# meaningful rather than vacuous.
deploy-register-path-check matcher="":
    #!/usr/bin/env bash
    set -euo pipefail
    matcher='{{ matcher }}'
    if [[ -z "$matcher" ]]; then
        just publisher-path-check
    fi
    just registration-path-check "$matcher"

# #176 Slice 1: run the query-endpoint contract suite (application-level
# JSON/freshness/transaction-count/board-authenticity tests).
query-endpoint-check:
    cd offchain && nix run --quiet --no-write-lock-file .#query-endpoint-check

# #176 Slice 1: static guard proving the query HTTP layer owns no mutable
# derived state (FR-4), proven able to fail against its own positive-control
# fixture before trusting a clean scan of the real source.
query-endpoint-cache-guard:
    ./scripts/check-query-endpoint-cache.sh

# #257 lasting focused recipe: the provider-neutral chain-query algebra, its
# #257: flake-owned check (offchain/flake.nix checks.<system>.query-algebra /
# apps.<system>.query-algebra) so `nix flake check` actually executes the
# preflight + focused proof suite, not just a manually-run justfile body.
query-algebra-check:
    cd offchain && nix run --quiet --no-write-lock-file .#query-algebra

# #240 T240-S1-13 lasting focused recipe: the permanent provider-free
# local-write-path family gate (five base-oracle capture suites plus the
# local write-path atomicity/reference-derivation/settlement proof, all
# GREEN, non-zero example counts). Flake-owned check
# (offchain/flake.nix checks.<system>.local-write-path-check /
# apps.<system>.local-write-path-check) so `nix flake check` actually
# executes it. This is the exact recipe name gate.sh's own preflight
# (S240-1) requires `just --list` to contain.
local-write-path-check:
    cd offchain && nix run --quiet --no-write-lock-file .#local-write-path-check

# Audit exact production UPLC extraction and the complete pinned Blaster graph.
blaster:
    cd offchain && nix run --quiet --no-write-lock-file .#blaster

# Check the opt-env-conf CLI surface and option/environment/YAML precedence.
check-ckeri-cli:
    cd offchain && nix build --quiet --no-write-lock-file .#ckeri
    ./scripts/check-ckeri-cli.sh ./offchain/result/bin/ckeri

# Check the raw M1 registration transcript and its settled transaction facts.
check-register-acceptance:
    ./scripts/check-register-acceptance-transcript.sh

# Check the raw M1 rotation/advance transcript, signing package, and tx facts.
check-advance-acceptance:
    ./scripts/check-advance-acceptance-transcript.sh

# Check the raw M1 register/close transcript, signatures, refund, and tx facts.
check-close-acceptance:
    ./scripts/check-close-acceptance-transcript.sh

# Check the raw two-seat endpoint-board journey and lifecycle evidence
check-board-acceptance:
    ./scripts/check-board-acceptance-transcripts.sh

# Build the whole offchain project (incl. e2e test component) from the dev shell,
# CHaP-offline via the Nix-local CHaP repo (issue #99 S9c) — no fetch of the
# secure https CHaP index (hackage over http + the git SRPs stay live). `cabal
# update` first generates the CHaP index cache from the nix-store repo (offline)
# and refreshes hackage (http); the build then compiles the CHaP stack + local
# project + e2e-tests from local source. cabal.project.devshell drops the https
# CHaP repository.
devshell-offchain:
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal build all --enable-tests -O0 --project-file=cabal.project.devshell'

# Run all live-boundary withDevnet smokes (Linux-only): the existing #99 cage
# positive plus the #114 permissionless checkpoint lifecycle boundary.
e2e:
    cd offchain && nix build --quiet --no-write-lock-file -L .#checks.x86_64-linux.e2e

# Run only the #136 register-small vertical.
e2e-checkpoint:
    cd offchain && nix run --quiet --no-write-lock-file .#e2e

# #175 live composition smoke: devnet up, post a real checkpoint
# registration, follow it over a real N2C socket, read it back from the
# follower store and match the datum. Always visible via `just --list` on
# every platform; the recipe itself decides support, never a silent Nix
# conditional. Linux/x86_64-only (spawns a real cardano-node) — elsewhere it
# fails loudly with a clear message instead of vanishing.
ci-live:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) ;;
        *)
            echo "ci-live: #175 follower live smoke requires Linux/x86_64 (spawns a real cardano-node); unsupported on $(uname -s)-$(uname -m)" >&2
            exit 1
            ;;
    esac
    cd offchain && nix run --quiet --no-write-lock-file .#follower-e2e

# --- checkpoint fixtures (#68) ---

# Regenerate the committed Aiken checkpoint fixtures from the Haskell encoder.
# One Haskell computation (reusing the Slice-2/3 codec modules) is the sole
# source of truth for every canonical byte string; `aiken fmt` then canonicalizes
# the emitted module so it also satisfies `format-check-onchain`.
gen-checkpoint-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-checkpoint-vectors -- ../onchain/lib/cardano_keri/checkpoint/vectors.ak'
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
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-enforcement-vectors -- ../onchain/lib/cardano_keri/checkpoint/enforcement_vectors.ak'
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
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-registration-vectors -- ../onchain/lib/cardano_keri/checkpoint/registration_vectors.ak'
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
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-advance-vectors -- ../onchain/lib/cardano_keri/checkpoint/advance_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/advance_vectors.ak

# Drift check: regenerate the advance vectors and fail if the committed copy
# diverges from a fresh regenerate (stale vectors must FAIL the gate).
check-advance-vectors: gen-advance-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/advance_vectors.ak

# Generate #117 Close message/address/signature vectors from the Haskell model.
gen-close-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-close-vectors -- ../onchain/lib/cardano_keri/checkpoint/close_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/close_vectors.ak

# Regenerate and reject any committed Haskell/Aiken Close vector drift.
check-close-vectors: gen-close-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/close_vectors.ak

# Regenerate the isolated #116 freeze-bond parity vectors from the Haskell
# model. The generator is the sole source of wire bytes, role constants,
# parameter verdicts, and raw deadline-boundary verdicts.
gen-freeze-bond-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-freeze-bond-vectors -- ../onchain/lib/cardano_keri/checkpoint/freeze_bond_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/freeze_bond_vectors.ak

# Drift check: a fresh Haskell regenerate must reproduce the committed module.
check-freeze-bond-vectors: gen-freeze-bond-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/freeze_bond_vectors.ak

# Regenerate the 17 Lean-theorem verdicts from the pure Haskell lifecycle
# mirror. The generated Aiken module is never edited by hand.
gen-lifecycle-trace-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-lifecycle-trace-vectors -- ../onchain/lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak

# Drift check: Haskell is the sole source of theorem verdict fixtures.
check-lifecycle-trace-vectors: gen-lifecycle-trace-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak

# --- migration shared types (#254) ---

# Regenerate the committed #254 shared migration-type parity vectors from the
# Haskell wire codec (Cardano.KERI.AID.Migration.Types) via
# GenMigrationTypesVectors.hs. OFFLINE. The module is never hand edited: it
# carries both the inputs the Aiken suite builds its values from and the
# expected encodings, and the generator refuses to emit a set whose named
# mutations collide. `aiken fmt` then canonicalizes the emitted module.
gen-migration-types-vectors:
    mkdir -p onchain/lib/cardano_keri/migration
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-migration-types-vectors -- ../onchain/lib/cardano_keri/migration/types_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/migration/types_vectors.ak

# Drift check: Haskell is the sole source of the shared migration wire bytes,
# so a stale or hand-touched vector module must FAIL the gate.
check-migration-types-vectors: gen-migration-types-vectors
    git diff --exit-code onchain/lib/cardano_keri/migration/types_vectors.ak

# #254 S254-1B: regenerate the Aiken checkpoint-migration fixtures from
# GenCheckpointMigrationVectors.hs. OFFLINE. The module is never hand edited.
# The generator signs with real Ed25519 keys and refuses to emit a set whose
# golden quorum is not accepted or whose named authority negatives are not
# actually refused by the oracle, so a control that cannot fail never ships.
gen-checkpoint-migration-vectors:
    mkdir -p onchain/lib/cardano_keri/migration
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-checkpoint-migration-vectors -- ../onchain/lib/cardano_keri/migration/checkpoint_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/migration/checkpoint_vectors.ak

# Drift check: Haskell is the sole source of the checkpoint-migration message
# bytes and signature material, so a stale or hand-touched vector module must
# FAIL the gate.
check-checkpoint-migration-vectors: gen-checkpoint-migration-vectors
    git diff --exit-code onchain/lib/cardano_keri/migration/checkpoint_vectors.ak

# #271 S271-1 / #254 S254-E: the adopted component's own parity gate. One
# Haskell computation is the sole source of every committed canonical byte
# string, commitment hash and marker name, and the checker carries its own
# negative control.
check-bounty-commitment-vectors:
    ./scripts/check-bounty-commitment-vectors.sh

# #254 S254-E: regenerate the entitlement-layer parity vectors from
# GenBountyEntitlementVectors.hs. OFFLINE. The module is never hand edited.
# The generator refuses to emit a set in which two evidence-field mutants share
# a digest, in which a mutant reproduces the honest digest, in which the honest
# verdict row is not accepted, or in which every verdict row agrees — so a
# vector set that could not distinguish anything never ships.
gen-bounty-entitlement-vectors:
    cd offchain && nix develop --quiet --no-write-lock-file -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-bounty-entitlement-vectors -- ../onchain/lib/cardano_keri/checkpoint/entitlement_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/entitlement_vectors.ak

# Drift check: Haskell is the sole source of the canonical enforcement-evidence
# digest and of the shared matcher's verdicts, so a stale or hand-touched
# vector module must FAIL. The checker carries its own negative control.
check-bounty-entitlement-vectors:
    ./scripts/check-bounty-entitlement-vectors.sh

# #254 T254-108: prove the EXACT changed compiled checkpoint family, derived
# from current source (never the frozen M8 baseline), rejects a named
# authority mutant and a named replay mutant under the pinned CEK machine.
checkpoint-migration-blaster:
    cd offchain && nix run --quiet --no-write-lock-file .#checkpoint-migration-blaster

# #254 T254-109: announce the corrected register's deployment identity from the
# live blueprint, and prove under the pinned CEK machine that the exact
# compiled program settles at its declared parameters and refuses one more.
checkpoint-register-blaster:
    cd offchain && nix run --quiet --no-write-lock-file .#checkpoint-register-blaster

# #254 T254-109: permanent census of every residual version reference on the
# deployment, derivation, blueprint, serialization and manifest surfaces. Each
# match is either cut or allowlisted with a concrete consumer. The self-test
# runs first, so every invocation shows the scanner still able to fail before
# its pass is believed.
check-version-remnant-sweep:
    ./scripts/check-version-remnant-sweep.sh --self-test
    ./scripts/check-version-remnant-sweep.sh

# #254 S254-E: prove the EXACT compiled entitlement family, derived from
# current source (never the frozen M8 baseline, which does not even contain the
# commitment program), accepts the honest matured reveal and rejects the named
# entitlement, age, scope and payout mutants under the pinned CEK machine.
# Emits one identity line per target and one row per mutant.
bounty-entitlement-blaster:
    cd offchain && nix run --quiet --no-write-lock-file .#bounty-entitlement-blaster

# Enforce the 17-row Lean -> QuickCheck -> Aiken executable map, including
# generated-vector drift.
check-lean-traceability:
    ./scripts/check-lean-traceability.sh

# Standing repository-CI contract (#234 Stage-D): every identity documented in
# the Blaster trust-base table must byte-match its authoritative flake.lock
# node. One canonical executable, shared by this recipe, ci-offchain, the
# workflow job, and the Stage-D gate.
check-blaster-identity-consistency:
    ./scripts/check-blaster-identity-consistency.sh

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

# #254 S254-E: measure and mechanically gate the four applied #271
# commitment-program ACCEPT paths. The component became part of a settlement
# path in S254-E — a hunter opens, matures and reveals a reservation inside the
# same story that arms or convicts — so its cost is now part of the entitled
# family's cost and needs its own row. Same caveat as measure-enforcement: an
# INVOCATION printing exact mem/cpu, plus an explicit title set and 25%-headroom
# limits over the measured maxima (517.76 K mem, 222.00 M cpu).
measure-bounty-commitment:
    #!/usr/bin/env bash
    set -euo pipefail
    results="$(mktemp)"
    trap 'rm -f "$results"' EXIT
    cd onchain
    nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#jq --command bash -euo pipefail -c '
      aiken check --plain-numbers -m measure_bounty_commitment | tee "$1"
      jq -e '\''
        [
          "measure_bounty_commitment_open",
          "measure_bounty_commitment_reveal",
          "measure_bounty_commitment_sweep",
          "measure_bounty_commitment_retire"
        ] as $required
        | [.modules[].tests[] | select(.title | startswith("measure_bounty_commitment"))] as $tests
        | ($tests | map(.title)) as $actual
        | if ($actual | sort) != ($required | sort) then
            error("commitment measurement title mismatch: expected \($required | sort); actual \($actual | sort)")
          elif any($tests[]; .status != "pass") then
            error("commitment measurement did not pass: \([$tests[] | select(.status != "pass") | {title, status}])")
          elif any($tests[]; ((.execution_units? | type) != "object") or ((.execution_units.mem? | type) != "number") or ((.execution_units.cpu? | type) != "number")) then
            error("commitment measurement lacks execution units: \([$tests[] | select(((.execution_units? | type) != "object") or ((.execution_units.mem? | type) != "number") or ((.execution_units.cpu? | type) != "number")) | .title])")
          elif any($tests[]; .execution_units.mem > 650000 or .execution_units.cpu > 280000000) then
            error("commitment measurement exceeds hard limit: \([$tests[] | select(.execution_units.mem > 650000 or .execution_units.cpu > 280000000) | {title, execution_units}])")
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
ci-offchain: build-offchain unit deployment-unit indexer-unit query-algebra-check local-write-path-check backend-check backend-transcript-check query-endpoint-check query-endpoint-cache-guard check-ckeri-cli check-register-acceptance check-advance-acceptance check-close-acceptance check-board-acceptance hlint format-check-offchain devshell-offchain check-checkpoint-vectors check-enforcement-vectors check-registration-vectors check-advance-vectors check-close-vectors check-freeze-bond-vectors check-migration-types-vectors check-bounty-commitment-vectors check-bounty-entitlement-vectors check-lean-traceability check-blaster-identity-consistency check-version-remnant-sweep

# #259: shared flake-lock guard — declared/locked reconciliation, justfile +
# workflow invocation guarding, and caller parity (INV-259-PARITY: required
# caller of both this recipe and .github/workflows/ci.yml).
check-flake-lock-guard:
    ./scripts/check-flake-lock-guard.sh

# Full CI gate (mirrors .github/workflows/ci.yml). INV-259-ASSERT: asserts
# offchain/flake.lock is byte-identical after every dependency below has run,
# and fails with the diff if not — every direct invocation in the
# dependencies above must therefore already carry --no-write-lock-file.
# Calls the shared script's own --assert-lock-unchanged mode rather than
# inlining the check, so its one property proof (in the script's own
# --self-test) exercises the exact code this recipe runs, not a copy of it;
# the guard's own INV-259-ASSERT caller-presence check requires this exact
# invocation to remain in this recipe.
ci: check-flake-lock-guard ci-onchain ci-blake3 ci-offchain
    ./scripts/check-flake-lock-guard.sh --assert-lock-unchanged
