#!/usr/bin/env bash
# Run a command in a mount namespace where each --forbid root is a
# tmpfs, so the path is unreadable. Any still-readable forbidden root
# is RED. worktree_access=none is only printed after that measurement.
set -euo pipefail

usage() {
  echo "usage: $0 --forbid ROOT [--forbid ROOT ...] -- COMMAND [ARGS...]" >&2
  exit 2
}

forbids=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --forbid)
      [ "$#" -ge 2 ] || usage
      forbids+=("$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *) usage ;;
  esac
done
[ "$#" -ge 1 ] || usage
[ "${#forbids[@]}" -ge 1 ] || usage

inner=$(mktemp)
trap 'rm -f "$inner"' EXIT
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
  printf 'forbids=('
  for root in "${forbids[@]}"; do
    printf ' %q' "$root"
  done
  printf ' )\n'
  cat <<'INNER'
readable=0
probed=""
for root in "${forbids[@]}"; do
  [ -n "$probed" ] && probed="$probed,"
  probed="$probed$root"
  # Hide the parent so $root itself does not remain as an empty
  # readable tmpfs mount point.
  target=$(dirname "$root")
  while [ ! -e "$target" ] && [ "$target" != / ]; do
    target=$(dirname "$target")
  done
  if [ "$target" = /tmp ] || [ "$target" = / ]; then
    mkdir -p /tmp/ms-keri-8
    mount -t tmpfs tmpfs /tmp/ms-keri-8
  elif [ -e "$target" ]; then
    mount -t tmpfs tmpfs "$target"
  fi
done
for root in "${forbids[@]}"; do
  if [ -r "$root" ]; then
    echo "forbidden root still readable: $root" >&2
    readable=$((readable + 1))
  fi
done
echo "AUDIT-ISOLATION forbidden=$probed readable=$readable instrument=unshare-mount-tmpfs window=single-entry"
if [ "$readable" -ne 0 ]; then
  echo "worktree_access is not none: readable=$readable" >&2
  exit 1
fi
INNER
  printf 'exec'
  for a in "$@"; do
    printf ' %q' "$a"
  done
  printf '\n'
} >"$inner"
chmod 700 "$inner"

unshare --user --map-root-user --mount bash "$inner"
