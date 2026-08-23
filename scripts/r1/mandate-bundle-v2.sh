#!/usr/bin/env bash
# Reproduce the R1 measured-source manifest for a git revision.
set -euo pipefail

rev=${1:?usage: mandate-bundle-v2.sh <git-rev>}
root=$(cd "$(dirname "$0")/../.." && pwd)

paths=(
  .github/workflows/ci.yml
  justfile
  offchain/flake.nix
  offchain/flake.lock
  onchain/aiken.toml
  onchain/lib/cardano_keri/checkpoint/message.ak
  onchain/lib/cardano_keri/m12/event_decoder.ak
  onchain/lib/cardano_keri/m12/event_key.ak
  onchain/lib/cardano_keri/m12/event_key_vectors.ak
  onchain/lib/cardano_keri/m12/record.ak
  onchain/lib/cardano_keri/m12/cursor.ak
  onchain/lib/cardano_keri/m12/types.ak
  onchain/validators/s0_skeleton_tests.ak
  scripts/r1/mandate-bundle-v2.sh
  specs/m11-r1-event-key/spec.md
  specs/m11-r1-event-key/plan.md
  specs/m11-r1-event-key/modules-model.md
  specs/m11-r1-event-key/data-model.md
  specs/m11-r1-event-key/functions-model.md
  specs/m11-r1-event-key/tasks.md
  specs/m11-r1-event-key/event-key-vectors-v2.tsv
  specs/m11-r1-event-key/flake-input-declaration-v2.tsv
)

printf '# digest\tmode\tpath\n'
for path in "${paths[@]}"; do
  digest=$(git -C "$root" show "$rev:$path" | sha256sum | awk '{print $1}')
  mode=$(git -C "$root" ls-tree "$rev" -- "$path" | awk '{print $1}')
  [[ -n $mode ]] || {
    printf 'missing-path:%s@%s\n' "$path" "$rev" >&2
    exit 1
  }
  printf '%s\t%s\t%s\n' "$digest" "$mode" "$path"
done
