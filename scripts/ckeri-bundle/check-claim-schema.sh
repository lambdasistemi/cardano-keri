#!/usr/bin/env bash
# Downstream claim schema: per-claim falsifier-before-GREEN, coverage
# boundary on every ESTABLISHED, and two distinctly purposed Advance E
# records.
set -euo pipefail

usage() { echo "usage: $0 CLAIMS" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
claims=$1
coverage_token=parsed-document

has_falsifier=0
claims_n=0
without_falsifier=0
established_unbounded=0
advance_n=0
purposes=""

if [ ! -r "$claims" ]; then
  echo "AUDIT-CLAIM-SCHEMA claims=0 with_falsifier=0 without_falsifier=0 reached_by=missing instrument=ckeri-bundle/check-claim-schema window=claims-file outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
  echo "MEASUREMENT-FAILED: claims file unreadable: $claims" >&2
  exit 1
fi

while IFS= read -r line || [ -n "${line:-}" ]; do
  [ -n "${line:-}" ] || continue
  [[ $line == CLAIM* ]] || continue
  claims_n=$((claims_n + 1))
  kind=$(sed -n 's/.* kind=\([^ ]*\).*/\1/p' <<<"$line")
  outcome=$(sed -n 's/.* outcome=\([^ ]*\).*/\1/p' <<<"$line")
  purpose=$(sed -n 's/.* purpose=\([^ ]*\).*/\1/p' <<<"$line")
  variant=$(sed -n 's/.* variant=\([^ ]*\).*/\1/p' <<<"$line")
  case "$outcome" in
    REFUTED) has_falsifier=1 ;;
    ESTABLISHED)
      if [ "$has_falsifier" -eq 0 ]; then
        without_falsifier=$((without_falsifier + 1))
      fi
      if [[ $line != *coverage=* ]]; then
        established_unbounded=$((established_unbounded + 1))
      fi
      ;;
  esac
  if [ "$kind" = advance ]; then
    advance_n=$((advance_n + 1))
    [ -n "$purpose" ] || purpose=unnamed
    case " $purposes " in
      *" $purpose "*) ;;
      *) purposes="$purposes $purpose" ;;
    esac
    if [ "$variant" != defaultFunSemanticsVariantE ]; then
      echo "advance record missing E variant: $line" >&2
    fi
  fi
done < "$claims"

distinct=0
for _ in $purposes; do
  distinct=$((distinct + 1))
done

schema_outcome=ESTABLISHED
if [ "$claims_n" -eq 0 ] || [ "$without_falsifier" -ne 0 ] \
  || [ "$established_unbounded" -ne 0 ]; then
  schema_outcome=REFUTED
fi
if [ "$advance_n" -gt 0 ] && [ "$distinct" -lt 2 ]; then
  schema_outcome=REFUTED
fi
echo "AUDIT-CLAIM-SCHEMA claims=$claims_n with_falsifier=$has_falsifier without_falsifier=$without_falsifier reached_by=ckeri-bundle/check-claim-schema instrument=ckeri-bundle/check-claim-schema window=claims-file coverage=$coverage_token outcome=$schema_outcome"
echo "AUDIT-ADVANCE-RECORDS count=$advance_n distinct_purposes=$distinct instrument=ckeri-bundle/check-claim-schema window=claims-file coverage=$coverage_token outcome=$schema_outcome"

if [ "$claims_n" -eq 0 ]; then
  echo "MEASUREMENT-FAILED: no claims examined" >&2
  exit 1
fi
if [ "$without_falsifier" -ne 0 ]; then
  echo "GREEN with no falsifier: without_falsifier=$without_falsifier" >&2
  exit 1
fi
if [ "$established_unbounded" -ne 0 ]; then
  echo "ESTABLISHED without coverage= boundary: $established_unbounded" >&2
  exit 1
fi
if [ "$advance_n" -gt 0 ] && [ "$distinct" -lt 2 ]; then
  echo "advance family lacks two distinct purposes: count=$advance_n distinct=$distinct" >&2
  exit 1
fi
exit 0
