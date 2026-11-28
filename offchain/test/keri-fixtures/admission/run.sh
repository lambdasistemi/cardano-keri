#!/usr/bin/env bash
# regenerate the offline admission corpus and its comparison. No network transaction.
#   bash run.sh [output directory]      (default: ./evidence next to this script)
# Needs nix with flakes. keripy 1.3.5 comes from the pinned flake in the parent directory,
# Lean 4.27.0 from lean/flake.nix.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="$(mkdir -p "${1:-$HERE/evidence}" && cd "${1:-$HERE/evidence}" && pwd)"
export ADMISSION_OUT="$OUT"
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/keripy_admission.py" | sed "s/[ \t]*\$//" > "$OUT/keripy-summary.txt"
mkdir -p "$OUT/leanbuild/CardanoKeri"
nix shell --no-write-lock-file "path:$ROOT/lean#lean" --command bash -c "
  cd '$ROOT/lean' && lean -o '$OUT/leanbuild/CardanoKeri/Duplicity.olean' CardanoKeri/Duplicity.lean &&
  cd '$HERE' && LEAN_PATH='$OUT/leanbuild' lean --run Admission.lean '$OUT/lean-input.json'" > "$OUT/lean-output.jsonl"
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/compare.py" | tee "$OUT/direction-summary.txt"

# ---- stage B: thresholds on their own (keripy Tholder, Lean Threshold.satisfied, the Aiken codec)
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/thresholds.py"
nix shell --no-write-lock-file "path:$ROOT/lean#lean" --command bash -c "
  cd '$HERE' && LEAN_PATH='$OUT/leanbuild' lean --run Admission.lean thresholds '$OUT/thresholds.json'" > "$OUT/lean-thresholds.jsonl"
# The Aiken transcripts keep only the test section (no terminal control codes, carriage returns or trailing whitespace; the
# compiler notices of the copied project are dropped), so the tracked copies are deterministic.
# The generated module has failing tests by design (a failing test is a `false` answer of the codec), so it
# runs in a copy of the onchain project and never enters the repository's own test path.
bash "$ROOT/onchain/stage-dependencies.sh" "$ROOT/onchain" > /dev/null
rm -rf "$OUT/aiken-project" && mkdir -p "$OUT/aiken-project"
(cd "$ROOT/onchain" && tar cf - --exclude=./build/dist . ) | (cd "$OUT/aiken-project" && tar xf -)
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/gen_aiken_thresholds.py" "$OUT/aiken-project/lib/cardano_keri/checkpoint/admission_threshold_tests.ak"
(cd "$OUT/aiken-project" && script -qec "nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check -m 'admission_threshold_tests.{..}'" /dev/null) 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | sed 's/[ \t]*$//' | awk '/Collecting all tests scenarios/{p=1} p{print} /┕━.* tests \| /{exit}' > "$OUT/aiken-thresholds.txt" || true
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/compare_thresholds.py" | tee "$OUT/threshold-summary.txt"

# ---- stage A/C on the chain: inceptions through the Aiken registration predicate (same copy of the onchain project)
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/registration.py" gen "$OUT/aiken-project/lib/cardano_keri/checkpoint/admission_registration_tests.ak"
(cd "$OUT/aiken-project" && script -qec "nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check -m 'admission_registration_tests.{..}'" /dev/null) 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | sed 's/[ \t]*$//' | awk '/Collecting all tests scenarios/{p=1} p{print} /┕━.* tests \| /{exit}' > "$OUT/aiken-registration.txt" || true
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/registration.py" compare "$OUT/aiken-registration.txt" | tee "$OUT/registration-summary.txt"

# ---- stage C on the chain: rotations through the Aiken advance predicate
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/advance.py" gen "$OUT/aiken-project/lib/cardano_keri/checkpoint/admission_advance_tests.ak"
(cd "$OUT/aiken-project" && script -qec "nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken --command aiken check -m 'admission_advance_tests.{..}'" /dev/null) 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | sed 's/[ \t]*$//' | awk '/Collecting all tests scenarios/{p=1} p{print} /┕━.* tests \| /{exit}' > "$OUT/aiken-advance.txt" || true
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/advance.py" compare "$OUT/aiken-advance.txt" | tee "$OUT/advance-summary.txt"

# ---- the revised matrix, with completeness checks that fail the run (a missing receipt, a missing row, a run that did not complete)
nix develop --no-write-lock-file "$HERE/.." --command python "$HERE/matrix.py" "$OUT" "$OUT/matrix"
