#!/usr/bin/env bash
# The same clean source build runs as a Nix check and a hosted/local app.
set -euo pipefail
source_root=$1
singular_source=$2
consumer_revision=$3
singular_revision=$4
singular_nar_hash=$5
receipt_dir=${6:-}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
if [[ -z "$receipt_dir" ]]; then
  receipt_dir="$work/receipts"
fi
mkdir -p "$receipt_dir" "$work/consumer"
receipt_dir=$(realpath "$receipt_dir")
exec > >(tee "$receipt_dir/check.log") 2>&1
fail() { echo "FAIL: $*" >&2; exit 1; }
binding_axioms_ok() {
  grep -Fxq "'CardanoKeri.singular_step_binding' depends on axioms: [propext, Quot.sound]" "$1"
}
expected=a84b253730003c9b0a8961b80e2e5449ba480a62
[[ "$singular_revision" == "$expected" ]] || fail 'wrong dependency revision'
[[ -f "$singular_source/lakefile.toml" ]] || fail 'missing dependency source'
[[ "$(git -c safe.directory="$singular_source" -C "$singular_source" rev-parse HEAD)" == "$expected" ]] || fail 'checkout differs from dependency pin'
[[ "$(git -c safe.directory="$singular_source" -C "$singular_source" rev-parse 'HEAD^{tree}')" == 2979dcfc58b092313b0ce7fa0493722539b9ea65 ]] || fail 'wrong dependency tree'
[[ "$(cat "$source_root/lean-toolchain")" == leanprover/lean4:v4.27.0 ]] || fail 'wrong consumer toolchain'
[[ "$(cat "$singular_source/lean-toolchain")" == leanprover/lean4:v4.27.0 ]] || fail 'wrong dependency toolchain'
lean --version | tee "$receipt_dir/compiler.txt"
grep -q '^Lean (version 4.27.0,' "$receipt_dir/compiler.txt" || fail 'wrong compiler'
jq -e --arg rev "$expected" '
  .packages | length == 1 and
  .[0].name == "singular" and .[0].type == "git" and
  .[0].url == "https://github.com/lambdasistemi/singular.git" and
  .[0].rev == $rev and .[0].inputRev == $rev
' "$source_root/lake-manifest.json" >/dev/null || fail 'invalid or missing dependency lock'
cp "$source_root/lake-manifest.json" "$receipt_dir/lake-manifest.json"
cp "$source_root/flake.lock" "$receipt_dir/flake.lock"
printf 'consumer=%s\nsingular.commit=%s\nsingular.github.narHash=%s\nsingular.git.tree=2979dcfc58b092313b0ce7fa0493722539b9ea65\nsingular.checkout.hash=%s\n' \
  "$consumer_revision" "$singular_revision" "$singular_nar_hash" "$SINGULAR_CHECKOUT_HASH" > "$receipt_dir/identities.txt"
{
  jq -r '.nodes.nixpkgs.locked | "compiler.nixpkgs.commit=\(.rev)\ncompiler.nixpkgs.narHash=\(.narHash)"' \
    "$source_root/flake.lock"
  sha256sum "$(command -v lean)" "$(command -v lake)"
  sha256sum "$source_root/lakefile.lean" "$source_root/lake-manifest.json" \
    "$source_root/flake.lock" "$source_root/CardanoKeri/SingularBinding.lean" \
    "$source_root/SingularDependencyProbe.lean" "$singular_source/lean/Singular/Model.lean" \
    "$singular_source/lean/Singular.lean"
} >> "$receipt_dir/identities.txt"
# Only source files enter the work directory; no cached .olean products.
cp -r "$source_root"/. "$work/consumer/"
chmod -R u+w "$work/consumer"
rm -rf "$work/consumer/.lake"
mkdir -p "$work/consumer/.lake/packages/singular"
cp -r "$singular_source"/. "$work/consumer/.lake/packages/singular/"
chmod -R u+w "$work/consumer/.lake/packages/singular"
rm -rf "$work/consumer/.lake/packages/singular/.lake"
# fetchgit normalizes away the index. Reconstruct it only in our writable copy
# before verifying tracked bytes and modes against the pinned commit.
git -C "$work/consumer/.lake/packages/singular" read-tree HEAD
git -C "$work/consumer/.lake/packages/singular" config remote.origin.url \
  https://github.com/lambdasistemi/singular.git
[[ -z "$(git -C "$work/consumer/.lake/packages/singular" status --porcelain --untracked-files=all)" ]] || fail 'dirty dependency source'
cd "$work/consumer"
# Resolve the real Git requirement against the fixed checkout. The narrow
# transport redirect affects this command only; Lake still records the public
# URL and exact commit in its manifest. Network access is absent in the check.
env GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0="url.file://$singular_source.insteadOf" \
  GIT_CONFIG_VALUE_0=https://github.com/lambdasistemi/singular.git \
  lake update singular 2>&1 | tee "$receipt_dir/resolve.log"
cmp lake-manifest.json "$source_root/lake-manifest.json" || fail 'fresh Lake resolution differs from tracked lock'
lake build CardanoKeri CardanoKeriStatements Singular 2>&1 | tee "$receipt_dir/build.log"
[[ "$(git -C .lake/packages/singular rev-parse HEAD)" == "$expected" ]] || fail 'build consumed another dependency'
lake env lean SingularDependencyProbe.lean 2>&1 | tee "$receipt_dir/probe.log"
binding_axioms_ok "$receipt_dir/probe.log" \
  || fail 'binding is missing or its axiom set changed'
# Preserve upstream proof debt honestly; reject new debt in the consumer.
if grep -E "CardanoKeri.*uses 'sorry'" "$receipt_dir/build.log"; then
  fail 'consumer proof uses sorry'
fi
# Each mutant changes one input/result, retaining both imports and all setup.
sed '0,/reason == "edge-inadmissible"/s//reason == "no-approval"/' SingularDependencyProbe.lean > WrongResult.lean
sed '0,/canonicalRequest .updateActive/s//canonicalRequest .insertActive/' SingularDependencyProbe.lean > WrongAction.lean
for control in WrongResult WrongAction; do
  if lake env lean "$control.lean" > "$receipt_dir/$control.log" 2>&1; then
    fail "$control elaborated"
  fi
  grep -Fq 'did not evaluate to' "$receipt_dir/$control.log" || fail "$control failed for the wrong reason"
  echo "control: $control rejected by executable guard"
done
# The exact same axiom policy must refuse an admitted, unproved binding.
sed 's/:= rfl/:= by sorry/' CardanoKeri/SingularBinding.lean > ProofTrustControl.lean
printf '\n#print axioms CardanoKeri.singular_step_binding\n' >> ProofTrustControl.lean
lake env lean ProofTrustControl.lean > "$receipt_dir/ProofTrustControl.log" 2>&1
grep -q 'sorryAx' "$receipt_dir/ProofTrustControl.log" || fail 'proof-trust control did not inject proof debt'
if binding_axioms_ok "$receipt_dir/ProofTrustControl.log"; then
  fail 'proof debt accepted by binding trust policy'
fi
echo 'control: unproved binding rejected by the same axiom policy'
# Run this same checker at the missing-source and invalid-lock boundaries.
# Both fail before compilation, never as an accepted dependency skip.
mkdir "$work/invalid-consumer"
cp "$source_root/lean-toolchain" "$work/invalid-consumer/"
jq '.packages[0].rev = "0000000000000000000000000000000000000000"' \
  "$source_root/lake-manifest.json" > "$work/invalid-consumer/lake-manifest.json"
if bash "$0" "$work/invalid-consumer" "$singular_source" \
    "$consumer_revision" "$singular_revision" "$singular_nar_hash" \
    "$receipt_dir/InvalidLock" > "$receipt_dir/InvalidLock.log" 2>&1; then
  fail 'invalid lock accepted'
fi
grep -q 'FAIL: invalid or missing dependency lock' "$receipt_dir/InvalidLock.log" || fail 'invalid lock failed for another reason'
if bash "$0" "$source_root" "$work/missing-dependency" \
    "$consumer_revision" "$singular_revision" "$singular_nar_hash" \
    "$receipt_dir/MissingDependency" > "$receipt_dir/MissingDependency.log" 2>&1; then
  fail 'missing dependency accepted'
fi
grep -q 'FAIL: missing dependency source' "$receipt_dir/MissingDependency.log" || fail 'missing dependency failed for another reason'
echo 'controls: invalid dependency lock and missing dependency source rejected'
echo 'PASS: clean CardanoKeri + CardanoKeriStatements + Singular; public step binding uses only propext/Quot.sound; wrong-result/action rejected'
