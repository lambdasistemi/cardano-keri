#!/usr/bin/env bash
# The identities page states the revisions, terms, hashes and sizes of this
# generation; the whole stated set is compared with the whole derived set, and
# any difference fails the check.
#
#   bash scripts/check-identities.sh [PAGE]
#
# Default page: docs/architecture/registry-identities.md. The derived set is the
# Lean revision (git), the public Singular commit (onchain/stage-dependencies.sh)
# and the rows of scripts/registry-identities.sh, or of the file named by
# IDENTITIES_DERIVED (the rows of that script, for a run that already holds them).
#
# The check fails when the page has no markers or no rows, when its labels are
# not exactly the derived labels, when the number of rows is not the fixed one,
# when a derived value is empty, and when any stated value differs. After the
# real page passes, each of those failures is produced on a copy and must be
# refused: a check that cannot fail proves nothing.
set -euo pipefail

rows=21

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
page=${1:-$root/docs/architecture/registry-identities.md}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The Lean revision is the last commit that changed lean/: it needs the history.
if [[ $(git -C "$root" rev-parse --is-shallow-repository) == true ]]; then
  git -C "$root" fetch --quiet --unshallow
fi

derived_script=${IDENTITIES_DERIVED:-}
if [[ -z $derived_script ]]; then
  derived_script=$work/script-rows.txt
  bash "$root/scripts/registry-identities.sh" > "$derived_script"
fi

derived=$work/derived.txt
{
  printf 'Lean model revision|%s\n' "$(git -C "$root" log -1 --no-merges --format=%H -- lean)"
  printf 'Public Singular commit|%s\n' \
    "$(sed -nE 's/^revision=([0-9a-f]{40})$/\1/p' "$root/onchain/stage-dependencies.sh")"
  cat "$derived_script"
} > "$derived"

# The rows between the markers of a page, as label|value, in page order.
stated_rows() {
  sed -nE '/<!-- identities:begin -->/,/<!-- identities:end -->/{
    s/^\| ([^|]+[^ |]) \| `([^`]*)` \|$/\1|\2/p
  }' "$1"
}

# Compare a page with a derived file; print each difference, fail on any.
compare() {
  local page=$1 derived=$2 status=0 label want got
  grep -q '<!-- identities:begin -->' "$page" || { echo "no begin marker" >&2; return 1; }
  grep -q '<!-- identities:end -->' "$page" || { echo "no end marker" >&2; return 1; }
  stated_rows "$page" > "$work/stated.txt"
  [[ $(wc -l < "$derived") -eq $rows ]] || {
    echo "derived $(wc -l < "$derived") rows, not the fixed $rows" >&2; status=1; }
  [[ $(wc -l < "$work/stated.txt") -eq $rows ]] || {
    echo "the page states $(wc -l < "$work/stated.txt") rows, not the fixed $rows" >&2; status=1; }
  cut -d'|' -f1 "$derived" | sort > "$work/derived-labels.txt"
  cut -d'|' -f1 "$work/stated.txt" | sort > "$work/stated-labels.txt"
  diff "$work/derived-labels.txt" "$work/stated-labels.txt" > "$work/labels.diff" || {
    echo "the page's labels are not the derived labels:" >&2
    cat "$work/labels.diff" >&2
    status=1
  }
  while IFS='|' read -r label want; do
    [[ -n $want ]] || { echo "derived value of '$label' is empty" >&2; status=1; continue; }
    got=$(sed -n "s/^${label//\//\\/}|//p" "$work/stated.txt" | head -1)
    [[ $got == "$want" ]] || {
      echo "stated '$label': page has '$got', derivation gives '$want'" >&2; status=1; }
  done < "$derived"
  return $status
}

compare "$page" "$derived"
echo "identities page matches its derivation ($rows rows)"

# Controls: each failure the check promises, produced on a copy, must be refused.
refused() {
  local name=$1 page=$2 derived=$3
  if compare "$page" "$derived" 2> "$work/control.err"; then
    echo "control '$name' passed: the check cannot fail that way" >&2
    exit 1
  fi
  echo "control '$name' refused: $(head -1 "$work/control.err")"
}

# one character of one stated hash changed
awk '
  !done && /^\| Application script hash \|/ {
    sub(/`[0-9a-f]/, "`" (substr($0, index($0, "`") + 1, 1) == "0" ? "1" : "0"))
    done = 1
  }
  { print }
' "$page" > "$work/c-char.md"
cmp -s "$page" "$work/c-char.md" && { echo "character control left the page as it was" >&2; exit 1; }
refused "one character of a stated hash" "$work/c-char.md" "$derived"

# a stated row deleted
grep -v '^| State script hash |' "$page" > "$work/c-deleted.md"
cmp -s "$page" "$work/c-deleted.md" && { echo "deleted-row control left the page as it was" >&2; exit 1; }
refused "a stated row deleted" "$work/c-deleted.md" "$derived"

# an extra stated row
awk '/<!-- identities:end -->/ { print "| An extra row | `1` |" } { print }' "$page" > "$work/c-extra.md"
refused "an extra stated row" "$work/c-extra.md" "$derived"

# a derived label missing
grep -v '^Booking width' "$derived" > "$work/d-missing.txt"
refused "a derived label missing" "$page" "$work/d-missing.txt"

# a derived value empty
sed 's/^\(Network discriminator\)|.*/\1|/' "$derived" > "$work/d-empty.txt"
refused "a derived value empty" "$page" "$work/d-empty.txt"

# the block empty, and the markers gone
awk '/<!-- identities:begin -->/ { print; skip = 1; next } /<!-- identities:end -->/ { skip = 0 } !skip { print }' \
  "$page" > "$work/c-empty.md"
refused "an empty block" "$work/c-empty.md" "$derived"
grep -v 'identities:' "$page" > "$work/c-markers.md"
refused "no markers" "$work/c-markers.md" "$derived"
