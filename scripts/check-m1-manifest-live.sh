#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

manifest="${1:-deploy/preprod/m1-manifest.json}"
manifest_path="$(realpath "$manifest")"
source_commit="$(
  jq -er '
    .source.commit
    | select(type == "string" and test("^[0-9a-f]{40}$"))
  ' "$manifest"
)"

git cat-file -e "${source_commit}^{commit}"

temporary_parent="${TMPDIR:-/tmp}"
verification_root="$(mktemp -d "$temporary_parent/ckeri-m1-verify.XXXXXX")"
release_checkout="$verification_root/release"
cleanup() {
  if git worktree list --porcelain | grep -Fqx "worktree $release_checkout"; then
    git worktree remove --force "$release_checkout"
  fi
  rmdir "$verification_root"
}
trap cleanup EXIT

git worktree add --quiet --detach "$release_checkout" "$source_commit"
test "$(git -C "$release_checkout" rev-parse HEAD)" = "$source_commit"
echo "source checkout: $source_commit"

(
  cd "$release_checkout/offchain"
  nix run --quiet .#ckeri -- \
    manifest verify \
    --manifest "$manifest_path" \
    --source-repo "$release_checkout"
)
