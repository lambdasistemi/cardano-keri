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
declare -A forbid_ino=()
forbid_paths=()
alias_mps=()

path_under_forbidden() {
  local p=$1 real
  for real in "${forbid_paths[@]}"; do
    case "$p" in
      "$real"|"$real"/*) return 0 ;;
    esac
  done
  return 1
}

for root in "${forbids[@]}"; do
  [ -n "$probed" ] && probed="$probed,"
  probed="$probed$root"
  if [ -e "$root" ]; then
    ino=$(stat -c '%d:%i' "$root")
    forbid_ino["$ino"]=1
    real=$(readlink -f "$root" || printf '%s' "$root")
    forbid_paths+=("$real")
  fi
done

# Reconcile the mount table to forbidden inodes before hiding anything.
# A bind made on a different path is the same inode, not a new name to
# enumerate later.
while IFS= read -r mp; do
  [ -n "$mp" ] || continue
  [ -e "$mp" ] || continue
  mp_ino=$(stat -c '%d:%i' "$mp" 2>/dev/null) || continue
  mp_real=$(readlink -f "$mp" 2>/dev/null || printf '%s' "$mp")
  if [ -n "${forbid_ino[$mp_ino]:-}" ] || path_under_forbidden "$mp_real"; then
    alias_mps+=("$mp")
  fi
done < <(findmnt -nro TARGET 2>/dev/null || true)

# Hide the parent so $root itself does not remain as an empty
# readable tmpfs mount point.
for root in "${forbids[@]}"; do
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

# Cover surviving mounts of the same inodes / same tree.
for mp in "${alias_mps[@]}"; do
  [ -n "$mp" ] || continue
  [ "$mp" = / ] && continue
  if [ -r "$mp" ]; then
    mount -t tmpfs tmpfs "$mp" 2>/dev/null || true
  fi
done

for root in "${forbids[@]}"; do
  if [ -r "$root" ]; then
    echo "forbidden root still readable: $root" >&2
    readable=$((readable + 1))
  fi
done
for mp in "${alias_mps[@]}"; do
  [ -n "$mp" ] || continue
  if [ -r "$mp" ]; then
    echo "forbidden tree still reachable via mount alias $mp" >&2
    readable=$((readable + 1))
  fi
done
while IFS= read -r mp; do
  [ -n "$mp" ] || continue
  [ -r "$mp" ] || continue
  mp_ino=$(stat -c '%d:%i' "$mp" 2>/dev/null) || continue
  if [ -n "${forbid_ino[$mp_ino]:-}" ]; then
    echo "forbidden inode still mounted at $mp" >&2
    readable=$((readable + 1))
  fi
done < <(findmnt -nro TARGET 2>/dev/null || true)

for fdpath in /proc/self/fd/*; do
  n=${fdpath##*/}
  [[ $n =~ ^[0-9]+$ ]] || continue
  [ "$n" -le 2 ] && continue
  dest=$(readlink "$fdpath" || true)
  fd_ino=$(stat -c '%d:%i' "$fdpath" 2>/dev/null || true)
  dest_real=$(readlink -f "$fdpath" 2>/dev/null || true)
  hit=0
  if [ -n "$fd_ino" ] && [ -n "${forbid_ino[$fd_ino]:-}" ]; then
    hit=1
  fi
  if [ -n "$dest_real" ] && path_under_forbidden "$dest_real"; then
    hit=1
  fi
  if [ -n "$dest" ]; then
    for mp in "${alias_mps[@]}"; do
      case "$dest" in
        "$mp"|"$mp"/*) hit=1 ;;
      esac
    done
    for real in "${forbid_paths[@]}"; do
      case "$dest" in
        "$real"|"$real"/*) hit=1 ;;
      esac
    done
  fi
  if [ "$hit" -eq 1 ]; then
    echo "forbidden root reachable via inherited fd $n -> ${dest:-inode:$fd_ino}" >&2
    readable=$((readable + 1))
    eval "exec ${n}<&-"
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
