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

# Run the release-script derivation and manifest unit tests.
deployment-unit:
    cd offchain && nix run --quiet .#deployment-tests

# Run checkpoint indexer codec tests (executes the binary).
indexer-unit:
    cd offchain && nix run --quiet .#indexer-tests

# Check the opt-env-conf CLI surface and option/environment/YAML precedence.
check-ckeri-cli:
    cd offchain && nix build --quiet .#ckeri
    ./scripts/check-ckeri-cli.sh ./offchain/result/bin/ckeri

# Check the raw M1 registration transcript and its settled transaction facts.
check-register-acceptance:
    ./scripts/check-register-acceptance-transcript.sh

# Check the raw M1 rotation/advance transcript, signing package, and tx facts.
check-advance-acceptance:
    ./scripts/check-advance-acceptance-transcript.sh

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

# Run only the #136 register-small vertical.
e2e-checkpoint:
    cd offchain && nix run --quiet .#e2e

# Run the #175 live-leg follower/fork drill with a private TMPDIR.
# Separate from `ci` so a docs fix does not pay for a devnet run.
# Exercises mismatch-tmp, mid-way orphan, no-op stop, then the healthy path.
#
# Non-index-mutating source path: build/run e2e-tests from the worktree via
# cabal inside `nix develop` so untracked GREEN sources are visible. Node,
# genesis, and blueprint come from flake-resolved store paths (never `git add`).
ci-live:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /code/tmp/cardano-keri-175
    run_root=$(mktemp -d /code/tmp/cardano-keri-175/run.XXXXXX)
    cleanup() { rm -rf "$run_root"; }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    match='#175 live follower indexes and removes a checkpoint across a real fork'
    # Resolve runtime deps without packaging the e2e suite from filtered git.
    blueprint=$(nix build --no-link --print-out-paths ./offchain#plutus-blueprint)
    clients_source=$(nix eval --impure --raw --expr 'let f = builtins.getFlake "git+file:///code/cardano-keri-175-follower?dir=offchain"; in f.inputs.cardano-node-clients.outPath')
    genesis=$(nix build --no-link --print-out-paths ./offchain#follower-genesis)
    node_pkg=$(nix build --no-link --print-out-paths 'github:IntersectMBO/cardano-node/10.7.0#packages.x86_64-linux.cardano-node')
    export E2E_GENESIS_DIR="$genesis/genesis"
    export KERI_CHECKPOINT_BLUEPRINT="$blueprint"
    export KERI_CAGE_BLUEPRINT="$blueprint"
    export PATH="${node_pkg}/bin:$PATH"
    # A-007: process CWD = pinned clients source (upstream relative pparams
    # fixture). Invoke via cabal run with explicit worktree --project-dir and
    # qualified cardano-keri:e2e-tests so in-place data-files resolve. No bare
    # list-bin/exec, no cardano_keri_datadir override, no fixture copy/stage.
    run_e2e() {
      nix develop ./offchain -c bash -c "
        set -euo pipefail
        cd \"$clients_source\"
        cabal run -O0 \
          --project-dir=/code/cardano-keri-175-follower/offchain \
          cardano-keri:e2e-tests -- --match \"$match\"
      "
    }
    export TMPDIR="$run_root"
    # Prove the shared index is empty (NOTE-015: no GREEN staging).
    if [[ -n "$(git diff --cached --name-only)" ]]; then
      echo "ci-live: shared index is not empty; refuse to run"
      git diff --cached --name-only
      exit 1
    fi

    # 1) deliberately mismatched independent TMP reference must fail named.
    unset KERI_S6_HEALTHY_NODE_LOG_CAPTURE || true
    export KERI_S6_EXPECTED_TMP_ROOT=/tmp/keri-s6-deliberately-wrong-root
    unset KERI_S6_CONTROL || true
    set +e
    mismatch_out=$(run_e2e 2>&1)
    mismatch_ec=$?
    set -e
    echo "===== S6-CONTROL-MISMATCH-TMP raw (exit=$mismatch_ec) ====="
    echo "$mismatch_out"
    if [[ "$mismatch_ec" -eq 0 ]]; then
      echo "ci-live: expected S6-PRIVATE-ROOT failure, got exit 0"
      exit 1
    fi
    if ! grep -q 'S6-PRIVATE-ROOT' <<<"$mismatch_out"; then
      echo "ci-live: mismatch control failed for the wrong reason"
      exit 1
    fi
    echo "S6-CONTROL-MISMATCH-TMP-OK"

    # 2) deliberate mid-way exception: failure + zero orphans for this root.
    export KERI_S6_EXPECTED_TMP_ROOT="$run_root"
    export KERI_S6_CONTROL=midway
    set +e
    midway_out=$(run_e2e 2>&1)
    midway_ec=$?
    set -e
    echo "===== S6-CONTROL-MIDWAY raw (exit=$midway_ec) ====="
    echo "$midway_out"
    if [[ "$midway_ec" -eq 0 ]]; then
      echo "ci-live: expected S6-MIDWAY-EXCEPTION failure, got exit 0"
      exit 1
    fi
    if ! grep -q 'S6-MIDWAY-EXCEPTION' <<<"$midway_out"; then
      echo "ci-live: midway control failed for the wrong reason"
      exit 1
    fi
    if pgrep -af "cardano-node run.*${run_root}" >/dev/null 2>&1; then
      echo "ci-live: orphan cardano-node remains after midway failure"
      pgrep -af "cardano-node run.*${run_root}" || true
      exit 1
    fi
    echo "S6-CONTROL-MIDWAY-NO-ORPHAN-OK"

    # 3) no-op #197 stop signal must fail node-still-running before DB mutation.
    export KERI_S6_CONTROL=noop-stop
    set +e
    noop_out=$(run_e2e 2>&1)
    noop_ec=$?
    set -e
    echo "===== S6-CONTROL-NOOP-STOP raw (exit=$noop_ec) ====="
    echo "$noop_out"
    if [[ "$noop_ec" -eq 0 ]]; then
      echo "ci-live: expected S6-NODE-STILL-RUNNING failure, got exit 0"
      exit 1
    fi
    if ! grep -q 'S6-NODE-STILL-RUNNING' <<<"$noop_out"; then
      echo "ci-live: noop-stop control failed for the wrong reason"
      exit 1
    fi
    if grep -q 'S6-NOOP-STOP-REACHED-DB-MUTATION' <<<"$noop_out"; then
      echo "ci-live: noop-stop reached DB mutation"
      exit 1
    fi
    if pgrep -af "cardano-node run.*${run_root}" >/dev/null 2>&1; then
      echo "ci-live: orphan cardano-node remains after noop-stop control"
      pgrep -af "cardano-node run.*${run_root}" || true
      exit 1
    fi
    echo "S6-CONTROL-NOOP-STOP-OK"

    # 4) healthy live leg: real register, follower read, rollback, absence.
    validate_healthy_node_log_capture() {
      mapfile -t healthy_node_log_records < <(
        grep '^S6-HEALTHY-NODE-LOG-CAPTURE socket=' <<<"$healthy_out" || true
      )
      if [[ "${#healthy_node_log_records[@]}" -ne 1 ]]; then
        echo "S6-HEALTHY-NODE-LOG-IDENTITY-FAIL expected=1 observed=${#healthy_node_log_records[@]}"
        return 1
      fi
      healthy_node_log_record=${healthy_node_log_records[0]}
      if [[ ! "$healthy_node_log_record" =~ ^S6-HEALTHY-NODE-LOG-CAPTURE\ socket=([^[:space:]]+)\ source=([^[:space:]]+)\ destination=([^[:space:]]+)$ ]]; then
        echo "S6-HEALTHY-NODE-LOG-IDENTITY-FAIL malformed-record=$healthy_node_log_record"
        return 1
      fi
      healthy_node_socket=${BASH_REMATCH[1]}
      healthy_node_log_source=${BASH_REMATCH[2]}
      healthy_node_log=${BASH_REMATCH[3]}
      if [[ "$healthy_node_socket" != "$run_root/"* ]] \
        || [[ "$healthy_node_log_source" != "${healthy_node_socket%/*}/node.log" ]] \
        || [[ "$healthy_node_log_source" != "$run_root/"* ]] \
        || [[ "$healthy_node_log" != "$healthy_node_log_capture" ]]; then
        echo "S6-HEALTHY-NODE-LOG-IDENTITY-FAIL socket=$healthy_node_socket source=$healthy_node_log_source destination=$healthy_node_log"
        return 1
      fi
      if [[ ! -f "$healthy_node_log" || -L "$healthy_node_log" || ! -s "$healthy_node_log" ]]; then
        echo "S6-HEALTHY-NODE-LOG-IDENTITY-FAIL capture-not-nonempty-regular=$healthy_node_log"
        return 1
      fi
      healthy_node_log_sha256=$(sha256sum "$healthy_node_log" | cut -d' ' -f1)
    }

    print_healthy_node_log_evidence() {
      echo "===== S6-HEALTHY-NODE-LOG source=$healthy_node_log_source sha256=$healthy_node_log_sha256 ====="
      cat "$healthy_node_log"
      echo "===== S6-HEALTHY-NODE-LOG-END ====="
    }

    unset KERI_S6_CONTROL || true
    export KERI_S6_EXPECTED_TMP_ROOT="$run_root"
    healthy_node_log_capture="$run_root/healthy-node.log"
    if [[ -e "$healthy_node_log_capture" ]]; then
      echo "S6-HEALTHY-NODE-LOG-IDENTITY-FAIL capture-preexists=$healthy_node_log_capture"
      exit 1
    fi
    export KERI_S6_HEALTHY_NODE_LOG_CAPTURE="$healthy_node_log_capture"
    set +e
    healthy_out=$(run_e2e 2>&1)
    healthy_ec=$?
    set -e
    echo "===== S6-CONTROL-HEALTHY raw (exit=$healthy_ec) ====="
    echo "$healthy_out"
    if ! validate_healthy_node_log_capture; then
      echo "ci-live: healthy node-log capture validation failed"
      exit 1
    fi
    if [[ "$healthy_ec" -ne 0 ]]; then
      print_healthy_node_log_evidence
      echo "ci-live: healthy run failed with exit $healthy_ec"
      exit 1
    fi
    if ! grep -q 'SC1_CHECKPOINT_FOUND' <<<"$healthy_out"; then
      print_healthy_node_log_evidence
      echo "ci-live: healthy run missing SC1_CHECKPOINT_FOUND"
      exit 1
    fi
    if ! grep -q 'CHAIN_B_ROLL_BACKWARD ' <<<"$healthy_out"; then
      print_healthy_node_log_evidence
      echo "ci-live: healthy run missing CHAIN_B_ROLL_BACKWARD marker"
      exit 1
    fi
    if ! grep -q 'CHAIN_B_ROLL_FORWARD ' <<<"$healthy_out"; then
      print_healthy_node_log_evidence
      echo "ci-live: healthy run missing CHAIN_B_ROLL_FORWARD marker"
      exit 1
    fi
    if ! grep -q 'CHAIN_A_CHECKPOINT_ABSENT=True' <<<"$healthy_out"; then
      print_healthy_node_log_evidence
      echo "ci-live: healthy run missing chain-A absence proof"
      exit 1
    fi
    if ! grep -q 'FORK_DRILL_COMPLETE' <<<"$healthy_out"; then
      print_healthy_node_log_evidence
      echo "ci-live: healthy run missing FORK_DRILL_COMPLETE"
      exit 1
    fi
    echo "S6-CONTROL-HEALTHY-OK"

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

# Generate #117 Close message/address/signature vectors from the Haskell model.
gen-close-vectors:
    mkdir -p onchain/lib/cardano_keri/checkpoint
    cd offchain && nix develop --quiet -c bash -c 'cabal update --project-file=cabal.project.devshell && cabal run -v0 -O0 --project-file=cabal.project.devshell gen-close-vectors -- ../onchain/lib/cardano_keri/checkpoint/close_vectors.ak'
    cd onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken fmt lib/cardano_keri/checkpoint/close_vectors.ak

# Regenerate and reject any committed Haskell/Aiken Close vector drift.
check-close-vectors: gen-close-vectors
    git diff --exit-code onchain/lib/cardano_keri/checkpoint/close_vectors.ak

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
ci-offchain: build-offchain unit deployment-unit indexer-unit check-ckeri-cli check-register-acceptance check-advance-acceptance hlint format-check-offchain devshell-offchain check-checkpoint-vectors check-enforcement-vectors check-registration-vectors check-advance-vectors check-close-vectors check-freeze-bond-vectors check-lean-traceability

# Full CI gate (mirrors .github/workflows/ci.yml)
ci: ci-onchain ci-blake3 ci-offchain
