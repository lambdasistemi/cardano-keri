#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
args=("$@")
for ((index = 0; index < ${#args[@]}; index++)); do
  if [[ ${args[$index]} == --transcript && $((index + 1)) -lt ${#args[@]} ]]; then
    resolved=$(realpath -e -- "${args[$((index + 1))]}")
    case $resolved in
      "$repo_root"/*) args[$((index + 1))]=$resolved ;;
      *)
        printf 'ERROR: transcript symlink escapes repository: %s\n' "$resolved" >&2
        exit 1
        ;;
    esac
  fi
done
exec "$repo_root/offchain/scripts/check-backend-status-transcripts.sh" "${args[@]}"
