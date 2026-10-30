#!/usr/bin/env bash
# The same clean assembly runs as a Nix check and as a hosted/local app.
#
# It stages the reusable KERI libraries (onchain/lib) as the consumer's own
# library next to the committed compatibility tests, stages the published
# Singular registry package and the Aiken prelude as dependencies, compiles
# the whole graph with the pinned compiler, runs the compatibility tests and
# the retained KERI registration tests, and requires the discovered and the
# executed test identities to agree exactly. Every control below must fail
# for its stated reason, or the check fails.
set -euo pipefail
consumer_source=$1
keri_library=$2
singular_source=$3
stdlib_source=$4
mpf_source=$5
consumer_revision=$6
singular_revision=$7
singular_nar_hash=$8
receipt_dir=${9:-}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
if [[ -z "$receipt_dir" ]]; then
  receipt_dir="$work/receipts"
fi
mkdir -p "$receipt_dir"
receipt_dir=$(realpath "$receipt_dir")
exec > >(tee "$receipt_dir/check.log") 2>&1
export HOME="$work/home" NO_COLOR=1
mkdir -p "$HOME"
fail() { echo "FAIL: $*" >&2; exit 1; }

expected=d69ab005c3b710aeebf033d3c5cd08c56feb5643
compatibility_root=singular_compatibility
retained_module=cardano_keri/checkpoint/registration_tests

[[ "$singular_revision" == "$expected" ]] || fail 'wrong dependency revision'
[[ -f "$singular_source/onchain/aiken.toml" ]] || fail 'missing dependency source'
grep -Fxq 'name = "singular/registry"' "$singular_source/onchain/aiken.toml" \
  || fail 'dependency source is not the singular/registry package'
[[ -f "$keri_library/$retained_module.ak" ]] || fail 'missing KERI library'
[[ -d "$consumer_source/lib/$compatibility_root" ]] || fail 'missing compatibility tests'

aiken --version | tee "$receipt_dir/compiler.txt"
grep -q '^aiken v1\.1\.23' "$receipt_dir/compiler.txt" || fail 'wrong compiler'
grep -Fxq 'compiler = "v1.1.23"' "$consumer_source/aiken.toml" || fail 'consumer declares another compiler'

# The lock names exactly the three packages the consumer declares.
lock_packages() {
  sed -n '/^\[\[packages\]\]/,/^$/p' "$1" | grep -E '^(name|version) = ' | paste -d' ' - -
}
[[ "$(lock_packages "$consumer_source/aiken.lock")" == 'name = "aiken-lang/stdlib" version = "v2.2.0"
name = "aiken-lang/merkle-patricia-forestry" version = "v2.1.0"
name = "singular/registry" version = "0.0.0"' ]] || fail 'invalid or missing dependency lock'
cp "$consumer_source/aiken.toml" "$consumer_source/aiken.lock" "$consumer_source/flake.lock" "$receipt_dir/"

{
  printf 'consumer.commit=%s\n' "$consumer_revision"
  printf 'singular.commit=%s\nsingular.github.narHash=%s\n' "$singular_revision" "$singular_nar_hash"
  printf 'singular.package=singular/registry 0.0.0 (onchain/ at singular.commit)\n'
  printf 'compiler=%s\n' "$(cat "$receipt_dir/compiler.txt")"
  printf 'compiler.binary.sha256=%s\n' "$(sha256sum "$(command -v aiken)" | cut -d' ' -f1)"
  jq -r '.nodes.nixpkgs.locked | "compiler.nixpkgs.commit=\(.rev)\ncompiler.nixpkgs.narHash=\(.narHash)"' \
    "$consumer_source/flake.lock"
  jq -r '.nodes.singular.locked | "lock.singular.commit=\(.rev)\nlock.singular.narHash=\(.narHash)"' \
    "$consumer_source/flake.lock"
  printf 'stdlib=%s\nmerkle-patricia-forestry=%s\n' "$stdlib_source" "$mpf_source"
  echo '# sha256 of every staged Singular library and manifest file'
  (cd "$singular_source/onchain" && find aiken.toml aiken.lock lib -type f | LC_ALL=C sort | xargs sha256sum)
} > "$receipt_dir/identities.txt"
grep -Fxq "lock.singular.commit=$expected" "$receipt_dir/identities.txt" || fail 'flake lock pins another Singular commit'

# assemble <dir> [<singular package>] : the consumer project, sources only.
assemble() {
  local dir=$1 singular=${2:-$singular_source/onchain}
  mkdir -p "$dir/lib" "$dir/build/packages"
  cp "$consumer_source/aiken.toml" "$consumer_source/aiken.lock" "$dir/"
  cp -r "$consumer_source/lib/." "$dir/lib/"
  cp -r "$keri_library/." "$dir/lib/"
  cat > "$dir/build/packages/packages.toml" <<'EOF'
[[packages]]
name = "aiken-lang/stdlib"
version = "v2.2.0"
source = "github"

[[packages]]
name = "aiken-lang/merkle-patricia-forestry"
version = "v2.1.0"
source = "github"

[[packages]]
name = "singular/registry"
version = "0.0.0"
source = "github"
EOF
  cp -r "$stdlib_source" "$dir/build/packages/aiken-lang-stdlib"
  cp -r "$mpf_source" "$dir/build/packages/aiken-lang-merkle-patricia-forestry"
  cp -r "$singular" "$dir/build/packages/singular-registry"
  rm -rf "$dir/build/packages/singular-registry/build"
  chmod -R u+w "$dir"
}

# run_tests <dir> <json> <diagnostics> : compile everything, run the two sets.
# A compile failure prints nothing without a terminal, so the diagnostics are
# captured by re-running under a pseudo-terminal.
# Aiken reads a selector without a module path as a test-name pattern, so
# every compatibility module is selected by its full module path.
run_tests() {
  local dir=$1 json=$2 diagnostics=$3 rc=0 module selection=()
  while read -r module; do
    selection+=(-m "$module")
  done < <(
    cd "$dir/lib"
    find "$compatibility_root" -name '*.ak' | LC_ALL=C sort | sed 's/\.ak$//'
    echo "$retained_module"
  )
  (cd "$dir" && aiken check "${selection[@]}" > "$json") || rc=$?
  if [[ $rc -ne 0 && ! -s "$json" ]]; then
    (cd "$dir" && script -qec "aiken check ${selection[*]}" /dev/null < /dev/null > "$diagnostics" 2>&1) || true
  fi
  return $rc
}

# discovered <dir> : every test declared in the compatibility namespace and
# in the retained registration module, as module.test.
discovered() {
  local dir=$1
  (
    cd "$dir/lib"
    find "$compatibility_root" -name '*.ak' | LC_ALL=C sort
    echo "$retained_module.ak"
  ) | while read -r file; do
    sed -nE 's/^test ([a-z0-9_]+)\(.*/\1/p' "$dir/lib/$file" | sed "s|^|${file%.ak}.|"
  done | LC_ALL=C sort
}

# executed <json> : every test the run reports, as module.test status.
executed() {
  jq -r '.modules[] | .name as $m | .tests[] | "\($m).\(.title) \(.status)"' "$1" | LC_ALL=C sort
}

# agree <discovered> <executed> : nonzero, identical identities, all passed.
agree() {
  local found=$1 ran=$2
  [[ -s "$found" ]] || { echo 'no test discovered'; return 1; }
  grep -q "^$compatibility_root/" "$found" || { echo 'no compatibility test discovered'; return 1; }
  grep -q "^$retained_module\." "$found" || { echo 'no retained registration test discovered'; return 1; }
  if ! diff <(cat "$found") <(cut -d' ' -f1 "$ran"); then
    echo 'discovered and executed test identities differ'
    return 1
  fi
  if grep -v ' pass$' "$ran"; then
    echo 'a test did not pass'
    return 1
  fi
}

main="$work/main"
assemble "$main"
# Formatting of the committed consumer sources, before the KERI library is
# staged next to them (that library is format-checked by the onchain job).
fmt_dir="$work/format"
mkdir -p "$fmt_dir"
cp "$consumer_source/aiken.toml" "$fmt_dir/"
cp -r "$consumer_source/lib" "$fmt_dir/"
chmod -R u+w "$fmt_dir"
(cd "$fmt_dir" && aiken fmt --check) || fail 'compatibility tests are not formatted'

run_tests "$main" "$receipt_dir/aiken-check.json" "$receipt_dir/aiken-check-diagnostics.log" \
  || fail 'the consumer did not compile or a test failed (see aiken-check.json or aiken-check-diagnostics.log)'
cmp "$main/aiken.lock" "$consumer_source/aiken.lock" || fail 'fresh resolution differs from tracked lock'
discovered "$main" > "$receipt_dir/discovered.txt"
executed "$receipt_dir/aiken-check.json" > "$receipt_dir/executed.txt"
agree "$receipt_dir/discovered.txt" "$receipt_dir/executed.txt" || fail 'test identities do not agree'
compatibility_count=$(grep -c "^$compatibility_root/" "$receipt_dir/discovered.txt")
retained_count=$(grep -c "^$retained_module\." "$receipt_dir/discovered.txt")
{
  echo "compatibility tests (KERI and Singular imported together): $compatibility_count discovered, $compatibility_count executed and passed"
  echo "retained KERI registration tests (legacy registration predicate, reused unchanged): $retained_count discovered, $retained_count executed and passed"
  echo 'redesigned application correspondence (KERI approval policy against the Singular fold): not established by this check'
} | tee "$receipt_dir/agreement.txt"

# --- controls: each must fail, for its stated reason ---

# A skipped test: the same agreement refuses a run that lost one identity.
jq 'del(.modules[0].tests[0])' "$receipt_dir/aiken-check.json" > "$work/skipped.json"
executed "$work/skipped.json" > "$work/skipped.txt"
if agree "$receipt_dir/discovered.txt" "$work/skipped.txt" > "$receipt_dir/control-skipped-test.log" 2>&1; then
  fail 'skipped-test control accepted'
fi
grep -q 'discovered and executed test identities differ' "$receipt_dir/control-skipped-test.log" \
  || fail 'skipped-test control failed for another reason'
echo 'control: a run missing one discovered test is refused'

# A broken interface: the Singular package no longer exports approval_for.
# Singular itself still compiles; only its consumers lose the value.
broken="$work/broken-interface"
cp -r "$singular_source/onchain" "$work/singular-unexported"
chmod -R u+w "$work/singular-unexported"
sed -i 's/^pub fn approval_for(/fn approval_for(/' "$work/singular-unexported/lib/singular_state/fold.ak"
grep -q '^fn approval_for(' "$work/singular-unexported/lib/singular_state/fold.ak" \
  || fail 'broken-interface control did not apply'
assemble "$broken" "$work/singular-unexported"
if run_tests "$broken" "$work/broken.json" "$receipt_dir/control-broken-interface.log"; then
  fail 'broken-interface control compiled'
fi
grep -q 'aiken::check::unknown::module_field' "$receipt_dir/control-broken-interface.log" \
  && grep -q "unknown import 'approval_for'" "$receipt_dir/control-broken-interface.log" \
  || fail 'broken-interface control failed for another reason'
echo 'control: a Singular package without approval_for is refused at compilation'

# A broken import: the compatibility tests name a module that does not exist.
missing="$work/broken-import"
assemble "$missing"
sed -i 's|^use singular_state/preimage\.{|use singular_state/preimages.{|' \
  "$missing/lib/$compatibility_root/interface_tests.ak"
grep -q '^use singular_state/preimages\.{' "$missing/lib/$compatibility_root/interface_tests.ak" \
  || fail 'broken-import control did not apply'
if run_tests "$missing" "$work/missing.json" "$receipt_dir/control-broken-import.log"; then
  fail 'broken-import control compiled'
fi
grep -Eq 'aiken::check::unknown::module[[:space:]]*$' "$receipt_dir/control-broken-import.log" \
  && grep -q 'singular_state/preimages' "$receipt_dir/control-broken-import.log" \
  || fail 'broken-import control failed for another reason'
echo 'control: an import of a module Singular does not publish is refused at compilation'

# A changed commitment, one per field of the published registration approval:
# the approval no longer commits that field. The package still compiles; the
# compatibility test naming that field must fail, and no retained KERI
# registration test may change verdict.
# field | line in registration_preimage | replacement | test that must fail
commitment_controls=(
  "registry|      registry,|      registry: RegistryIdentity { policy: #\"\", name: #\"\" },|registry_is_committed"
  "key|      key,|      key: #\"\",|key_is_committed"
  "holding-stake-part|      holding_address,|      holding_address: Address { ..holding_address, stake_credential: None },|holding_stake_part_is_committed"
  "holding-payment-part|      holding_address,|      holding_address: Address { ..holding_address, payment_credential: address.VerificationKey(#\"\") },|holding_payment_part_is_committed"
  "initial-datum|      initial_datum: datum_hash,|      initial_datum: #\"\",|initial_checkpoint_datum_is_committed"
  "deposit|      deposit,|      deposit: 0,|deposit_is_committed"
)
for control in "${commitment_controls[@]}"; do
  IFS='|' read -r field line replacement test <<< "$control"
  mutant="$work/singular-without-$field"
  cp -r "$singular_source/onchain" "$mutant"
  chmod -R u+w "$mutant"
  preimage="$mutant/lib/singular_state/preimage.ak"
  awk -v line="$line" -v replacement="$replacement" '
    /^pub fn registration_preimage\(/ { inside = 1 }
    inside && $0 == line && !done { print replacement; done = 1; next }
    inside && /^}/ { inside = 0 }
    { print }
    END { if (!done) exit 1 }
  ' "$singular_source/onchain/lib/singular_state/preimage.ak" > "$preimage" \
    || fail "$field commitment control did not apply"
  assemble "$work/changed-$field" "$mutant"
  if run_tests "$work/changed-$field" "$receipt_dir/control-changed-$field.json" "$receipt_dir/control-changed-$field.log"; then
    fail "$field commitment control passed"
  fi
  [[ -s "$receipt_dir/control-changed-$field.json" ]] || fail "$field commitment control did not compile"
  executed "$receipt_dir/control-changed-$field.json" | grep -v ' pass$' > "$receipt_dir/control-changed-$field.txt" || true
  grep -Fxq "$compatibility_root/interface_tests.$test fail" "$receipt_dir/control-changed-$field.txt" \
    || fail "$field commitment control failed for another reason"
  if grep -q "^$retained_module\." "$receipt_dir/control-changed-$field.txt"; then
    fail "$field commitment control changed a retained registration test"
  fi
  echo "control: a Singular approval that does not commit the $field fails $test"
done

# The same checker refuses a lock naming another package set, before compiling.
mkdir "$work/invalid-consumer"
cp -r "$consumer_source/." "$work/invalid-consumer/"
chmod -R u+w "$work/invalid-consumer"
sed -i 's/^version = "v2.2.0"$/version = "v2.1.0"/' "$work/invalid-consumer/aiken.lock"
if bash "$0" "$work/invalid-consumer" "$keri_library" "$singular_source" "$stdlib_source" "$mpf_source" \
    "$consumer_revision" "$singular_revision" "$singular_nar_hash" \
    "$receipt_dir/InvalidLock" > "$receipt_dir/control-invalid-lock.log" 2>&1; then
  fail 'invalid lock accepted'
fi
grep -q 'FAIL: invalid or missing dependency lock' "$receipt_dir/control-invalid-lock.log" \
  || fail 'invalid lock failed for another reason'
echo 'control: a lock naming another package version is refused'

echo "PASS: KERI libraries and singular/registry at $expected compile together under $(cat "$receipt_dir/compiler.txt"); $compatibility_count compatibility and $retained_count retained registration tests discovered, executed and passed; every control refused"
