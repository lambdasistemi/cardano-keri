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

# Check mechanical size limits for the applied checkpoint and checkpoint_observer
# programs, measuring the exact byte stream the final off-chain builder deploys.
#
# Binding artifact (NOTE-011/012): the builder consumes the FLAKE-OWNED blueprint
# (compiled with the off-chain flake's Aiken 1.1.21, NOT the justfile-pinned
# 1.1.23) and serializes parameters via the Haskell
# `serialiseUPLC (uncheckedDeserialiseUPLC code `applyDataArg` ...)` path. That
# path and `aiken blueprint apply` produce identical bytes for the SAME
# blueprint, so the gate must (a) build the SAME compiler-owned blueprint the
# builder consumes and (b) apply/serialize via the SAME Haskell path. Proven
# against HEAD: Aiken 1.1.21 raw checkpoint 23,052 -> Haskell application
# 23,124 (the trusted expectedCheckpointSizeBudget baseline).
#
# Source set (NOTE-012): the gate compiles the LIVE owned Aiken sources being
# verified (tracked modifications AND new untracked observer production files),
# filtering only generated/build artifacts (build/, plutus.json) — never
# `git archive HEAD`, which would measure the previous commit. After commit
# this live set converges to the git-tree set the flake builder consumes.
check-checkpoint-deployability:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp_build="$(mktemp -d)"
    trap 'rm -rf "$tmp_build"' EXIT

    # The Haskell serializer: the builder's exact serialiseUPLC/applyProgram
    # parameter-application path. Written to the temp dir (never the repo).
    # Every heredoc payload line and both delimiters stay at the recipe
    # indentation; just strips that common indentation before executing.
    cat > "$tmp_build/serializer.hs" <<'SERIALIZER_EOF'
    {-# LANGUAGE OverloadedStrings #-}
    module Main (main) where
    import qualified Data.ByteString as BS
    import qualified Data.ByteString.Short as SBS
    import Data.Char (isDigit)
    import Data.Text (Text)
    import qualified Data.Text as T
    import qualified Data.Text.IO as TIO
    import PlutusCore qualified as PLC
    import PlutusCore.Data (Data (..))
    import PlutusLedgerApi.V3 (serialiseUPLC, uncheckedDeserialiseUPLC)
    import UntypedPlutusCore (Program (..), applyProgram)
    import UntypedPlutusCore qualified as UPLC
    import System.Environment (getArgs)
    import Numeric (showHex)
    decodeHex :: Text -> Maybe BS.ByteString
    decodeHex t | odd (T.length t) = Nothing | otherwise = BS.pack <$> go (T.unpack t)
      where go [] = Just []; go (a:b:r) = do { h <- hexDigit a; l <- hexDigit b; (h*16+l :) <$> go r }; go _ = Nothing
            hexDigit c | isDigit c = Just (fromIntegral (fromEnum c - fromEnum c0)) | c >= ca && c <= cf = Just (fromIntegral (fromEnum c - fromEnum ca + 10)) | otherwise = Nothing
            c0 = T.head (T.pack "0"); ca = T.head (T.pack "a"); cf = T.head (T.pack "f")
    applyDataArg prog dat = let Program _ v _ = prog; arg = Program () v (UPLC.Constant () (PLC.Some (PLC.ValueOf PLC.DefaultUniData dat))) in either (error . show) id (applyProgram prog arg)
    toHex = concatMap (pad2 . (`showHex` "")) . BS.unpack
      where pad2 s = if length s == 1 then "0" ++ s else s
    main :: IO ()
    main = do
        args <- getArgs
        let (mode, hexfile, outhex, rest) = case args of { (m:h:o:r) -> (m,h,o,r); _ -> error "usage" }
        hex <- TIO.readFile hexfile
        code <- maybe (fail "bad hex") (pure . SBS.toShort) (decodeHex (T.strip hex))
        let prog = uncheckedDeserialiseUPLC code
        out <- case (mode, rest) of
          ("observer_lifecycle", [ver, hp, dreg]) -> do
            hpB <- maybe (fail "hp") pure (decodeHex (T.pack hp))
            pure (serialiseUPLC (prog `applyDataArg` I (read ver) `applyDataArg` B hpB `applyDataArg` I (read dreg)))
          ("observer_advance", [ver]) ->
            pure (serialiseUPLC (prog `applyDataArg` I (read ver)))
          ("observer_enforcement", [ver]) ->
            pure (serialiseUPLC (prog `applyDataArg` I (read ver)))
          ("checkpoint", [ver, lh, ah, eh, dreg, bond, window]) -> do
            lhB <- maybe (fail "lh") pure (decodeHex (T.pack lh))
            ahB <- maybe (fail "ah") pure (decodeHex (T.pack ah))
            ehB <- maybe (fail "eh") pure (decodeHex (T.pack eh))
            pure (serialiseUPLC (prog `applyDataArg` I (read ver) `applyDataArg` B lhB `applyDataArg` B ahB `applyDataArg` B ehB `applyDataArg` I (read dreg) `applyDataArg` I (read bond) `applyDataArg` I (read window)))
          _ -> fail "bad mode"
        let outBS = SBS.fromShort out
        writeFile outhex (toHex outBS)
        print (BS.length outBS)
    SERIALIZER_EOF

    # The inner gate script, run inside the offchain dev shell (ghc/cabal/jq/
    # b2sum/xxd). Written to temp to avoid nested-quoting collisions.
    cat > "$tmp_build/inner.sh" <<'INNER_EOF'
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$1"
    repo="$2"

    # 1. The compiler-owned blueprint: the off-chain flake's Aiken (1.1.21), the
    #    same compiler that builds the blueprint the final builder consumes.
    #    Stderr/exit is left visible so a failed acquisition names itself.
    cd "$repo/offchain"
    nix build --impure --expr '
      let flake = builtins.getFlake (toString ./.);
          pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
      in pkgs.aiken' -o "$tmp/aiken"
    aiken_bin="$tmp/aiken/bin/aiken"

    # 2. Compile the LIVE owned Aiken sources (tracked modifications + new
    #    untracked observer files), filtering only generated/build artifacts
    #    (build/, plutus.json). Never `git archive HEAD`. The pinned Aiken
    #    emits NO compiler diagnostics when stdout is not a TTY and exits 1
    #    silently (NOTE-008), so the build is wrapped in `script -qec` to give
    #    it a pseudo-TTY and surface the real error.
    mkdir -p "$tmp/work"
    tar -C "$repo/onchain" --exclude='./build' --exclude='./plutus.json' -cf - . \
      | tar -C "$tmp/work" -xf -
    cd "$tmp/work"
    rm -rf build plutus.json
    script -qec "\"$aiken_bin\" build -t silent" /dev/null
    blueprint="$tmp/work/plutus.json"

    # 3. Compile the serializer with the project's own package environment.
    #    Stderr/exit is left visible so a failed compile names itself. The
    #    recipe is self-contained: it first establishes the project package
    #    environment (dist-newstyle/packagedb) via the project's own devshell
    #    project configuration, never assuming another recipe already
    #    populated it.
    cd "$repo/offchain"
    cabal update --project-file=cabal.project.devshell
    cabal build -O0 --project-file=cabal.project.devshell --only-dependencies cardano-keri:e2e-tests
    cabal exec -v0 --project-file=cabal.project.devshell -- ghc -O2 \
      "$tmp/serializer.hs" -o "$tmp/serializer"

    # 4. Extract raw compiled code for the four programs (selected by module +
    #    validator name via their blueprint titles, never by handler purpose).
    lc_raw="$tmp/lc.raw.hex"
    ad_raw="$tmp/ad.raw.hex"
    ef_raw="$tmp/ef.raw.hex"
    cp_raw="$tmp/cp.raw.hex"
    jq -r '.validators[] | select(.title=="checkpoint_observer.observer_lifecycle.withdraw") | .compiledCode' "$blueprint" > "$lc_raw"
    jq -r '.validators[] | select(.title=="checkpoint_observer.observer_advance.withdraw") | .compiledCode' "$blueprint" > "$ad_raw"
    jq -r '.validators[] | select(.title=="checkpoint_observer.observer_enforcement.withdraw") | .compiledCode' "$blueprint" > "$ef_raw"
    jq -r '.validators[] | select(.title=="checkpoint.checkpoint.spend") | .compiledCode' "$blueprint" > "$cp_raw"
    if [ ! -s "$lc_raw" ] || [ "$(cat "$lc_raw")" = "null" ]; then
      echo "ERROR: observer_lifecycle validator not found in blueprint" >&2
      exit 1
    fi
    if [ ! -s "$ad_raw" ] || [ "$(cat "$ad_raw")" = "null" ]; then
      echo "ERROR: observer_advance validator not found in blueprint" >&2
      exit 1
    fi
    if [ ! -s "$ef_raw" ] || [ "$(cat "$ef_raw")" = "null" ]; then
      echo "ERROR: observer_enforcement validator not found in blueprint" >&2
      exit 1
    fi
    if [ ! -s "$cp_raw" ] || [ "$(cat "$cp_raw")" = "null" ]; then
      echo "ERROR: checkpoint validator not found in blueprint" >&2
      exit 1
    fi

    # 5. Apply the frozen parameters via the builder's Haskell path, in the
    #    off-chain order: observer_lifecycle(version=0, hash_proof_policy,
    #    d_reg=1000000000); observer_advance(version=0);
    #    observer_enforcement(version=0); then checkpoint(version=0,
    #    lifecycle_hash, advance_hash, enforcement_hash, d_reg=1000000000,
    #    freeze_bond=5000000, freeze_window=500). Each observer hash is the
    #    PlutusV3 script hash (blake2b-224 of 0x03 ++ applied bytes) of its
    #    fully-applied program. observer_advance must be <= 15333 (>=800 slack).
    hp_policy="4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"
    lc_size=$("$tmp/serializer" observer_lifecycle "$lc_raw" "$tmp/lc.applied.hex" 0 "$hp_policy" 1000000000)
    lc_hash=$( { printf '\x03'; xxd -r -p "$tmp/lc.applied.hex"; } | b2sum -l 224 | awk '{print $1}' )
    ad_size=$("$tmp/serializer" observer_advance "$ad_raw" "$tmp/ad.applied.hex" 0)
    ad_hash=$( { printf '\x03'; xxd -r -p "$tmp/ad.applied.hex"; } | b2sum -l 224 | awk '{print $1}' )
    ef_size=$("$tmp/serializer" observer_enforcement "$ef_raw" "$tmp/ef.applied.hex" 0)
    ef_hash=$( { printf '\x03'; xxd -r -p "$tmp/ef.applied.hex"; } | b2sum -l 224 | awk '{print $1}' )
    cp_size=$("$tmp/serializer" checkpoint "$cp_raw" "$tmp/cp.applied.hex" 0 "$lc_hash" "$ad_hash" "$ef_hash" 1000000000 5000000 500)

    echo "Derived observer_lifecycle script hash:    $lc_hash"
    echo "Derived observer_advance script hash:      $ad_hash"
    echo "Derived observer_enforcement script hash:  $ef_hash"
    echo "observer_lifecycle applied size:    $lc_size bytes"
    echo "observer_advance applied size:      $ad_size bytes"
    echo "observer_enforcement applied size:  $ef_size bytes"
    echo "checkpoint applied size:            $cp_size bytes"

    if [ "$lc_size" -ge 16133 ]; then
      echo "ERROR: observer_lifecycle applied size >= 16133 bytes ($lc_size)" >&2
      exit 1
    fi
    if [ "$ad_size" -gt 15333 ]; then
      echo "ERROR: observer_advance applied size > 15333 bytes ($ad_size; need >=800 slack)" >&2
      exit 1
    fi
    if [ "$ad_size" -ge 16133 ]; then
      echo "ERROR: observer_advance applied size >= 16133 bytes ($ad_size)" >&2
      exit 1
    fi
    if [ "$ef_size" -ge 16133 ]; then
      echo "ERROR: observer_enforcement applied size >= 16133 bytes ($ef_size)" >&2
      exit 1
    fi
    if [ "$cp_size" -ge 16133 ]; then
      echo "ERROR: checkpoint applied size >= 16133 bytes ($cp_size)" >&2
      exit 1
    fi
    INNER_EOF
    chmod +x "$tmp_build/inner.sh"

    # Run the gate inside the offchain dev shell.
    repo_root="$PWD"
    cd offchain && nix develop --quiet -c bash "$tmp_build/inner.sh" "$tmp_build" "$repo_root"

# Onchain CI gate (mirrors the Onchain job)
ci-onchain: format-check-onchain check-onchain check-checkpoint-deployability measure-enforcement measure-hash-proof measure-checkpoint

# BLAKE3 spike CI gate (mirrors the BLAKE3 job)
ci-blake3: compiler-check-blake3 format-check-blake3 check-blake3

# Offchain CI gate (mirrors the Offchain + Dev shell jobs)
ci-offchain: build-offchain unit hlint format-check-offchain devshell-offchain check-checkpoint-vectors check-enforcement-vectors check-registration-vectors check-advance-vectors check-freeze-bond-vectors check-lean-traceability

# Permanent source guard: reject the widened max-tx override token in
# executable harness, workflow, and configuration surfaces. Clearly labelled
# historical measurement/spec records under specs/ and narrative docs under
# docs/ are outside the scan set and may still mention the temporary 32 KiB
# fiction. Markdown inside the scanned executable surfaces is not exempt.
# The forbidden digit token is assembled at runtime so this recipe never
# contains a contiguous match for its own needle.
check-no-widened-max-tx-size:
    #!/usr/bin/env bash
    set -euo pipefail
    forbid="$(printf '%d' $(( 32000 + 768 )))"
    # Executable / configuration / harness / workflow surfaces only.
    mapfile -t hits < <(
        git grep -nI -F -- "$forbid" -- \
            justfile \
            gate.sh \
            offchain \
            onchain \
            scripts \
            .github \
            ':(exclude)specs/**' \
            ':(exclude)docs/**' \
            || true
    )
    if [ "${#hits[@]}" -gt 0 ]; then
        echo "ERROR: forbidden widened max-tx override token '${forbid}' found in executable/configuration surfaces:" >&2
        printf '%s\n' "${hits[@]}" >&2
        exit 1
    fi
    echo "OK: no widened max-tx override token in executable/configuration surfaces"

# Full CI gate (mirrors .github/workflows/ci.yml)
ci: ci-onchain ci-blake3 ci-offchain check-no-widened-max-tx-size
