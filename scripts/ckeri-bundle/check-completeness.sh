#!/usr/bin/env bash
# Declared-inventory completeness. Tree walks may contribute entries; they
# may not define coverage. Absent, unreadable or empty inventory is
# MEASUREMENT-FAILED, never a zero.
set -euo pipefail

usage() { echo "usage: $0 INVENTORY ASSEMBLY" >&2; exit 2; }
[ "$#" -eq 2 ] || usage
inventory=$1
assembly=$2
coverage_token=parsed-document

declared=0
present=0
missing=0
modes_checked=0
mode_mismatch=0

if [ ! -e "$inventory" ]; then
  echo "AUDIT-BUNDLE-COMPLETENESS declared=0 present=0 missing=0 modes_checked=0 mode_mismatch=0 inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
  echo "MEASUREMENT-FAILED: inventory absent: $inventory" >&2
  exit 1
fi
if [ ! -r "$inventory" ]; then
  echo "AUDIT-BUNDLE-COMPLETENESS declared=0 present=0 missing=0 modes_checked=0 mode_mismatch=0 inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
  echo "MEASUREMENT-FAILED: inventory unreadable: $inventory" >&2
  exit 1
fi

while IFS=$'\t' read -r path origin mode required || [ -n "${path:-}" ]; do
  [ -n "${path:-}" ] || continue
  [[ $path == \#* ]] && continue
  declared=$((declared + 1))
  assembled="$assembly/$path"
  if [ -e "$assembled" ]; then
    present=$((present + 1))
    modes_checked=$((modes_checked + 1))
    actual_mode=$(stat -c '%a' "$assembled")
    if [ "$actual_mode" != "$mode" ]; then
      mode_mismatch=$((mode_mismatch + 1))
    fi
  fi
done < "$inventory"

if [ "$declared" -eq 0 ]; then
  echo "AUDIT-BUNDLE-COMPLETENESS declared=0 present=0 missing=0 modes_checked=0 mode_mismatch=0 inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
  echo "MEASUREMENT-FAILED: inventory unexpectedly empty: $inventory" >&2
  exit 1
fi

missing=$((declared - present))
outcome=ESTABLISHED
if [ "$missing" -ne 0 ] || [ "$mode_mismatch" -ne 0 ]; then
  outcome=REFUTED
fi
echo "AUDIT-BUNDLE-COMPLETENESS declared=$declared present=$present missing=$missing modes_checked=$modes_checked mode_mismatch=$mode_mismatch inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly coverage=$coverage_token outcome=$outcome"
if [ "$missing" -ne 0 ]; then
  echo "declared artifact missing: missing=$missing declared=$declared" >&2
  exit 1
fi
if [ "$mode_mismatch" -ne 0 ]; then
  echo "declared mode mismatch: mode_mismatch=$mode_mismatch" >&2
  exit 1
fi
exit 0
