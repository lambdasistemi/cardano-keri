#!/usr/bin/env bash
# Stage the Singular registry package for compiling this project.
#
# `aiken.toml` names `singular/registry`, which is not a GitHub release of its
# own: it is the `onchain/` project of the public Singular repository at one
# commit. This script fetches that commit, requires its content hash to be the
# pinned one, and places its sources where Aiken looks for a downloaded
# package, `build/packages/singular-registry`. Every other dependency is
# resolved by Aiken as before.
#
# Run it before `aiken check`, `aiken build` or any script that copies this
# directory to compile it:
#
#   bash onchain/stage-dependencies.sh [<onchain directory>]
#
# `aiken-singular-consumer/flake.nix` pins the same commit.
set -euo pipefail

revision=d69ab005c3b710aeebf033d3c5cd08c56feb5643
nar_hash='sha256-vV5/4mW4O4NwAsr8rAyTZUhH3pvqlBmsAJQIHUqTVfA='

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target=$(realpath "${1:-$here}")
[[ -f "$target/aiken.toml" ]] || { echo "no aiken.toml in $target" >&2; exit 1; }

prefetch=$(nix flake prefetch --json "github:lambdasistemi/singular/$revision")
fetched_hash=$(sed -nE 's/.*"hash":"([^"]*)".*/\1/p' <<< "$prefetch")
source_path=$(sed -nE 's/.*"storePath":"([^"]*)".*/\1/p' <<< "$prefetch")
[[ "$fetched_hash" == "$nar_hash" ]] || {
  echo "fetched content hash $fetched_hash is not the pinned $nar_hash" >&2
  exit 1
}

packages="$target/build/packages"
rm -rf "$packages/singular-registry"
mkdir -p "$packages"
cp -r "$source_path/onchain" "$packages/singular-registry"
rm -rf "$packages/singular-registry/build"
chmod -R u+w "$packages/singular-registry"

# Aiken trusts a package directory listed here and does not fetch it.
if [[ ! -f "$packages/packages.toml" ]] || ! grep -Fq 'name = "singular/registry"' "$packages/packages.toml"; then
  cat >> "$packages/packages.toml" <<'EOF'
[[packages]]
name = "singular/registry"
version = "0.0.0"
requirements = []
source = "github"

EOF
fi
echo "staged singular/registry at $revision into $packages/singular-registry"
