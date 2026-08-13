#!/usr/bin/env bash
# Slice C RED contract. Each named invariant is shown able to fail before
# any clean assembly is accepted. Production surfaces are required after
# the in-process oracles, so a missing assembler cannot hide a vacuous
# completeness proof.
set -euo pipefail

fail() { echo "bundle-contract: FAIL: $*" >&2; exit 1; }

bundle_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$bundle_dir/../.." && pwd)
checker=${1:-$repo_root/scripts/check-blaster-identity-consistency.sh}
[ -x "$checker" ] || fail "identity checker is not executable: $checker"
[ -e "$repo_root/.git" ] || fail "repository root is absent: $repo_root"

work=$(mktemp -d "${TMPDIR:-/tmp}/ckeri-bundle-contract.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

# Compact coverage token the gate requires on every ESTABLISHED record.
coverage_token=parsed-document

expect_red() { # label expected-diagnostic command...
  local label=$1 expected=$2 out rc
  shift 2
  set +e
  out=$("$@" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$label unexpectedly exited 0"
  [[ $out == *"$expected"* ]] \
    || fail "$label exited $rc without naming '$expected': $out"
  printf 'RED-PROOF invariant=%s rc=%s diagnostic=%s outcome=REFUTED\n' \
    "$label" "$rc" "$expected"
}

# ---------------------------------------------------------------------------
# Completeness oracle (C6–C8, C10–C12). Tree walks may contribute; they
# may not define coverage. An empty inventory is MEASUREMENT-FAILED, never
# a zero.
# ---------------------------------------------------------------------------
check_completeness() { # inventory assembly
  local inventory=$1 assembly=$2
  local declared=0 present=0 missing=0 modes_checked=0 mode_mismatch=0
  local path origin mode required assembled actual_mode

  if [ ! -e "$inventory" ]; then
    echo "AUDIT-BUNDLE-COMPLETENESS declared=0 present=0 missing=0 modes_checked=0 mode_mismatch=0 inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
    echo "MEASUREMENT-FAILED: inventory absent: $inventory" >&2
    return 1
  fi
  if [ ! -r "$inventory" ]; then
    echo "AUDIT-BUNDLE-COMPLETENESS declared=0 present=0 missing=0 modes_checked=0 mode_mismatch=0 inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
    echo "MEASUREMENT-FAILED: inventory unreadable: $inventory" >&2
    return 1
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
    return 1
  fi

  missing=$((declared - present))
  local outcome=ESTABLISHED
  if [ "$missing" -ne 0 ] || [ "$mode_mismatch" -ne 0 ]; then
    outcome=REFUTED
  fi
  echo "AUDIT-BUNDLE-COMPLETENESS declared=$declared present=$present missing=$missing modes_checked=$modes_checked mode_mismatch=$mode_mismatch inventory=$inventory instrument=ckeri-bundle/check-completeness window=single-assembly coverage=$coverage_token outcome=$outcome"
  if [ "$missing" -ne 0 ]; then
    echo "declared artifact missing: missing=$missing declared=$declared" >&2
    return 1
  fi
  if [ "$mode_mismatch" -ne 0 ]; then
    echo "declared mode mismatch: mode_mismatch=$mode_mismatch" >&2
    return 1
  fi
  return 0
}

mkdir -p "$work/assembly/ok" "$work/assembly/omit" "$work/assembly/mode"
printf '%s\n' $'entry.sh\ttracked\t755\t1' $'notes.txt\ttracked\t644\t1' \
  > "$work/inventory.txt"
printf '%s\n' '#!/bin/sh' 'echo ok' > "$work/assembly/ok/entry.sh"
printf '%s\n' 'notes' > "$work/assembly/ok/notes.txt"
chmod 755 "$work/assembly/ok/entry.sh"
chmod 644 "$work/assembly/ok/notes.txt"
cp -a "$work/assembly/ok/entry.sh" "$work/assembly/omit/entry.sh"
chmod 755 "$work/assembly/omit/entry.sh"
cp -a "$work/assembly/ok/." "$work/assembly/mode/"
chmod 644 "$work/assembly/mode/entry.sh"

expect_red INV-246-C8-omitted-declared-artifact \
  'declared artifact missing' \
  check_completeness "$work/inventory.txt" "$work/assembly/omit"
: > "$work/empty-inventory.txt"
expect_red INV-246-C11-empty-inventory \
  'MEASUREMENT-FAILED: inventory unexpectedly empty' \
  check_completeness "$work/empty-inventory.txt" "$work/assembly/ok"
expect_red INV-246-C11-absent-inventory \
  'MEASUREMENT-FAILED: inventory absent' \
  check_completeness "$work/no-such-inventory.txt" "$work/assembly/ok"
expect_red INV-246-C7-declared-mode-mismatch \
  'declared mode mismatch' \
  check_completeness "$work/inventory.txt" "$work/assembly/mode"

check_completeness "$work/inventory.txt" "$work/assembly/ok" \
  > "$work/complete.out"
grep -Eq '^AUDIT-BUNDLE-COMPLETENESS declared=2 present=2 missing=0 modes_checked=2 mode_mismatch=0 ' \
  "$work/complete.out" \
  || fail "clean completeness oracle did not publish declared beside missing"
grep -Fq "coverage=$coverage_token outcome=ESTABLISHED" "$work/complete.out" \
  || fail "clean completeness oracle omitted the coverage boundary"

# ---------------------------------------------------------------------------
# Claim schema (C3, C4, C5, C13). A GREEN with no prior falsifier is
# incomplete. Advance needs two distinctly purposed E records.
# ---------------------------------------------------------------------------
check_claim_schema() { # claims-file
  local claims=$1
  local line kind outcome purpose variant has_falsifier=0 claims_n=0
  local without_falsifier=0 established_unbounded=0
  local advance_n=0 purposes=""

  [ -r "$claims" ] || {
    echo "AUDIT-CLAIM-SCHEMA claims=0 with_falsifier=0 without_falsifier=0 reached_by=missing instrument=ckeri-bundle/check-claim-schema window=claims-file outcome=COULD-NOT-EVALUATE layer=MEASUREMENT-FAILED"
    echo "MEASUREMENT-FAILED: claims file unreadable: $claims" >&2
    return 1
  }

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
      [ "$variant" = defaultFunSemanticsVariantE ] \
        || echo "advance record missing E variant: $line" >&2
    fi
  done < "$claims"

  local distinct=0
  for _ in $purposes; do
    distinct=$((distinct + 1))
  done

  local schema_outcome=ESTABLISHED
  if [ "$claims_n" -eq 0 ] || [ "$without_falsifier" -ne 0 ] \
    || [ "$established_unbounded" -ne 0 ]; then
    schema_outcome=REFUTED
  fi
  echo "AUDIT-CLAIM-SCHEMA claims=$claims_n with_falsifier=$has_falsifier without_falsifier=$without_falsifier reached_by=ckeri-bundle/check-claim-schema instrument=ckeri-bundle/check-claim-schema window=claims-file coverage=$coverage_token outcome=$schema_outcome"
  echo "AUDIT-ADVANCE-RECORDS count=$advance_n distinct_purposes=$distinct instrument=ckeri-bundle/check-claim-schema window=claims-file coverage=$coverage_token outcome=$schema_outcome"

  if [ "$claims_n" -eq 0 ]; then
    echo "MEASUREMENT-FAILED: no claims examined" >&2
    return 1
  fi
  if [ "$without_falsifier" -ne 0 ]; then
    echo "GREEN with no falsifier: without_falsifier=$without_falsifier" >&2
    return 1
  fi
  if [ "$established_unbounded" -ne 0 ]; then
    echo "ESTABLISHED without coverage= boundary: $established_unbounded" >&2
    return 1
  fi
  if [ "$advance_n" -gt 0 ] && [ "$distinct" -lt 2 ]; then
    echo "advance family lacks two distinct purposes: count=$advance_n distinct=$distinct" >&2
    return 1
  fi
  return 0
}

cat > "$work/claims-green-only.txt" <<'EOF'
CLAIM id=p0-spend kind=spend variant=defaultFunSemanticsVariantE outcome=ESTABLISHED
EOF
cat > "$work/claims-no-coverage.txt" <<'EOF'
CLAIM id=p0-spend kind=spend variant=defaultFunSemanticsVariantE outcome=REFUTED
CLAIM id=p0-spend kind=spend variant=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED
CLAIM id=p0-spend-bare kind=spend variant=defaultFunSemanticsVariantE outcome=ESTABLISHED
EOF
cat > "$work/claims-one-advance.txt" <<'EOF'
CLAIM id=adv-1 kind=advance purpose=compatibility-refreeze variant=defaultFunSemanticsVariantE outcome=REFUTED
CLAIM id=adv-1 kind=advance purpose=compatibility-refreeze variant=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED
EOF
cat > "$work/claims-clean.txt" <<'EOF'
CLAIM id=p0-spend kind=spend variant=defaultFunSemanticsVariantE outcome=REFUTED
CLAIM id=p0-spend kind=spend variant=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED
CLAIM id=adv-compat kind=advance purpose=compatibility-refreeze variant=defaultFunSemanticsVariantE outcome=REFUTED
CLAIM id=adv-compat kind=advance purpose=compatibility-refreeze variant=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED
CLAIM id=adv-composed kind=advance purpose=p3-p6-composed variant=defaultFunSemanticsVariantE outcome=REFUTED
CLAIM id=adv-composed kind=advance purpose=p3-p6-composed variant=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED
EOF

expect_red INV-246-C3-green-without-falsifier \
  'GREEN with no falsifier' \
  check_claim_schema "$work/claims-green-only.txt"
expect_red INV-246-C13-established-without-coverage \
  'ESTABLISHED without coverage=' \
  check_claim_schema "$work/claims-no-coverage.txt"
expect_red INV-246-C4-single-advance-purpose \
  'advance family lacks two distinct purposes' \
  check_claim_schema "$work/claims-one-advance.txt"

# Finding class from auditor-C1-s1 schema-pairing-probe.sh
# (sha256 bf59a5bf565047c9f4061ada1ada564479804a80110543bb546dab135d39f834)
# against candidate 35e2ec92: a REFUTED claim must not license a
# different claim's ESTABLISHED, and a non-E Advance must fail.
cat > "$work/claims-orphan.txt" <<'EOF'
CLAIM id=a kind=spend variant=defaultFunSemanticsVariantE outcome=REFUTED
CLAIM id=b kind=spend variant=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED
EOF
cat > "$work/claims-wrong-variant.txt" <<'EOF'
CLAIM id=a kind=advance purpose=compatibility-refreeze variant=defaultFunSemanticsVariantA outcome=REFUTED
CLAIM id=a kind=advance purpose=compatibility-refreeze variant=defaultFunSemanticsVariantA coverage=parsed-document outcome=ESTABLISHED
CLAIM id=b kind=advance purpose=p3-p6-composed variant=defaultFunSemanticsVariantA outcome=REFUTED
CLAIM id=b kind=advance purpose=p3-p6-composed variant=defaultFunSemanticsVariantA coverage=parsed-document outcome=ESTABLISHED
EOF
expect_red INV-246-C3-orphan-claim-pairing \
  'ESTABLISHED without per-claim falsifier' \
  "$bundle_dir/check-claim-schema.sh" "$work/claims-orphan.txt"
expect_red INV-246-C4-advance-non-e-variant \
  'advance record is not variant E' \
  "$bundle_dir/check-claim-schema.sh" "$work/claims-wrong-variant.txt"

check_claim_schema "$work/claims-clean.txt" > "$work/schema.out"
grep -Fq 'without_falsifier=0' "$work/schema.out" \
  || fail "clean schema oracle did not publish without_falsifier=0"
grep -Fq 'AUDIT-ADVANCE-RECORDS count=4 distinct_purposes=2' "$work/schema.out" \
  || fail "clean schema oracle did not publish two advance purposes"

# ---------------------------------------------------------------------------
# Reproduction must refuse the issue worktree (C1, C2, C9).
# ---------------------------------------------------------------------------
check_reproduction() { # source worktree_access
  local source=$1 access=$2
  if [ "$source" != fresh-clone ]; then
    echo "AUDIT-REPRODUCTION source=$source worktree_access=$access entry_point=none exit=1 instrument=ckeri-bundle/reproduce window=single-run coverage=$coverage_token outcome=REFUTED"
    echo "reproduction is not a fresh clone: source=$source" >&2
    return 1
  fi
  if [ "$access" != none ]; then
    echo "AUDIT-REPRODUCTION source=$source worktree_access=$access entry_point=none exit=1 instrument=ckeri-bundle/reproduce window=single-run coverage=$coverage_token outcome=REFUTED"
    echo "reproduction still has worktree access: access=$access" >&2
    return 1
  fi
  echo "AUDIT-REPRODUCTION source=$source worktree_access=$access entry_point=scripts/ckeri-bundle/run.sh exit=0 instrument=ckeri-bundle/reproduce window=single-run coverage=$coverage_token outcome=ESTABLISHED"
  return 0
}

expect_red INV-246-C2-issue-worktree \
  'reproduction is not a fresh clone' \
  check_reproduction issue-worktree none
expect_red INV-246-C9-worktree-access \
  'reproduction still has worktree access' \
  check_reproduction fresh-clone issue-worktree

# C1: the entry point may not depend on a path outside the checkout
# and its declared pins. C2/C9 do not cover this — the desk-path
# retained receipt is the concrete case.
check_entry_pins() { # entry-file
  local entry=$1
  [ -r "$entry" ] || {
    echo "entry point unreadable: $entry" >&2
    return 1
  }
  if grep -E '/tmp/ms-keri-8' "$entry" >/dev/null; then
    echo "entry point depends on a path outside a fresh checkout: /tmp/ms-keri-8" >&2
    return 1
  fi
  return 0
}
printf '%s\n' '#!/bin/sh' \
  'cat /tmp/ms-keri-8/e190/t246/evidence/RED-baseline-receipt.md' \
  > "$work/entry-desk-path.sh"
expect_red INV-246-C1-desk-path-dependency \
  'path outside a fresh checkout' \
  check_entry_pins "$work/entry-desk-path.sh"

# C10: a completeness result that publishes missing=0 with no
# declared= denominator must go RED.
check_completeness_denominator() { # record-line
  local record=$1
  if grep -Eq 'missing=' <<<"$record" \
    && ! grep -Eq 'declared=' <<<"$record"; then
    echo "completeness missing= published without declared denominator" >&2
    return 1
  fi
  return 0
}
expect_red INV-246-C10-bare-missing-zero \
  'published without declared denominator' \
  check_completeness_denominator \
  'AUDIT-BUNDLE-COMPLETENESS missing=0 outcome=ESTABLISHED'

# C12: both branches must be falsified BEFORE the clean assembly
# is accepted. Accepting ESTABLISHED first violates the ordering.
check_completeness_order() { # log
  local log=$1
  local omit_ln empty_ln clean_ln
  omit_ln=$(grep -nE 'omitted-declared-artifact|INV-246-C8-omitted' "$log" \
    | head -1 | cut -d: -f1)
  empty_ln=$(grep -nE 'empty-or-unreadable-inventory|INV-246-C11-empty' "$log" \
    | head -1 | cut -d: -f1)
  clean_ln=$(grep -nE 'AUDIT-BUNDLE-COMPLETENESS .*outcome=ESTABLISHED' "$log" \
    | head -1 | cut -d: -f1)
  if [ -z "${omit_ln:-}" ] || [ -z "${empty_ln:-}" ]; then
    echo "both completeness branches were not falsified" >&2
    return 1
  fi
  if [ -n "${clean_ln:-}" ] \
    && { [ "$clean_ln" -lt "$omit_ln" ] || [ "$clean_ln" -lt "$empty_ln" ]; }; then
    echo "clean assembly accepted before both branches were falsified" >&2
    return 1
  fi
  return 0
}
cat > "$work/order-violated.log" <<'EOF'
AUDIT-BUNDLE-COMPLETENESS declared=2 present=2 missing=0 outcome=ESTABLISHED
AUDIT-SELFTEST leg=omitted-declared-artifact rc=1 outcome=REFUTED
AUDIT-SELFTEST leg=empty-or-unreadable-inventory rc=1 outcome=REFUTED
EOF
expect_red INV-246-C12-clean-before-both-branches \
  'clean assembly accepted before both branches were falsified' \
  check_completeness_order "$work/order-violated.log"

# C6: tree enumeration may contribute; it may not define coverage.
# A walk of the assembly that counts an untracked extra as a declared
# entry, while a declared path is missing, publishes the wrong
# denominator.
check_inventory_defines_coverage() { # inventory assembly record
  local inventory=$1 assembly=$2 record=$3
  local inv_declared walk_declared
  inv_declared=$(grep -cEv '^#|^$' "$inventory" || true)
  walk_declared=$(find "$assembly" -type f | wc -l)
  walk_declared=${walk_declared//[[:space:]]/}
  rec_declared=$(sed -n 's/.* declared=\([0-9]*\).*/\1/p' <<<"$record")
  if [ "$walk_declared" -ne "$inv_declared" ] \
    && [ "$rec_declared" = "$walk_declared" ]; then
    echo "tree walk defined coverage: declared=$rec_declared inventory=$inv_declared walk=$walk_declared" >&2
    return 1
  fi
  return 0
}
mkdir -p "$work/assembly/walk"
printf '%s\n' '#!/bin/sh' > "$work/assembly/walk/entry.sh"
printf '%s\n' 'extra' > "$work/assembly/walk/extra.txt"
printf '%s\n' 'also' > "$work/assembly/walk/also.txt"
# inventory still declares entry.sh + notes.txt (2). Walk sees 3 files.
# A record that takes declared= from the walk has let the tree define coverage.
expect_red INV-246-C6-tree-walk-defines-coverage \
  'tree walk defined coverage' \
  check_inventory_defines_coverage \
  "$work/inventory.txt" \
  "$work/assembly/walk" \
  'AUDIT-BUNDLE-COMPLETENESS declared=3 present=3 missing=0 outcome=ESTABLISHED'

# ---------------------------------------------------------------------------
# Published-bytes closure and check binding (carried rows).
# ---------------------------------------------------------------------------
check_published_bytes() { # bytes-file
  local bytes=$1
  local parsed_last parsed_first
  if [ ! -r "$bytes" ]; then
    echo "published bytes unreadable" >&2
    return 1
  fi
  if cmp -s <(printf '\xef\xbb\xbf') <(head -c 3 "$bytes"); then
    echo "published bytes carry a UTF-8 BOM; document parse is not the bytes" >&2
    return 1
  fi
  parsed_last=$(jq -er '.identity.variant' "$bytes")
  parsed_first=$(grep -oE '"variant":"[^"]+"' "$bytes" | head -1 \
    | sed 's/"variant":"//;s/"$//')
  if [ -z "$parsed_first" ] || [ "$parsed_last" != "$parsed_first" ]; then
    echo "second conforming parse differs: last_wins=$parsed_last first_wins=${parsed_first:-<none>}" >&2
    return 1
  fi
  local digest
  digest=$(sha256sum "$bytes" | cut -d ' ' -f 1)
  echo "AUDIT-ARTIFACT-BINDING digest=$digest instrument=sha256sum window=published-bytes coverage=$coverage_token outcome=ESTABLISHED"
  return 0
}

printf '%s\n' '{"identity":{"variant":"defaultFunSemanticsVariantE"}}' \
  > "$work/clean-bytes.json"
printf '%s' $'{"identity":{"variant":"defaultFunSemanticsVariantA","variant":"defaultFunSemanticsVariantE"}}' \
  > "$work/dup-variant.json"
printf '%s' $'\xef\xbb\xbf{"identity":{"variant":"defaultFunSemanticsVariantE"}}' \
  > "$work/bom.json"

expect_red INV-246-PUBLISHED-ARTIFACT-CLOSURE \
  'second conforming parse differs' \
  check_published_bytes "$work/dup-variant.json"
expect_red INV-246-ARTIFACT-CHECK-BINDING \
  'published bytes carry a UTF-8 BOM' \
  check_published_bytes "$work/bom.json"
check_published_bytes "$work/clean-bytes.json" > "$work/bytes.out"

# ---------------------------------------------------------------------------
# Falsifier reachability: a Slice C falsifier only inside the sandbox skip
# is unreachable from CI.
# ---------------------------------------------------------------------------
check_falsifier_reachability() { # runner-text
  local text=$1
  if grep -Eq 'omitted-declared-artifact|empty-or-unreadable-inventory|declared-mode-mismatch' \
    <<<"$text"; then
    if awk '
      /CKERI_BLASTER_SANDBOX_CHECK/ {skip=1}
      skip && /omitted-declared-artifact|empty-or-unreadable-inventory|declared-mode-mismatch/ {hit=1}
      /fi$/ && skip {skip=0}
      END {exit hit ? 0 : 1}
    ' <<<"$text" \
      && ! grep -Eq 'omitted-declared-artifact|empty-or-unreadable-inventory|declared-mode-mismatch' \
        <<<"$(awk '/CKERI_BLASTER_SANDBOX_CHECK/{p=1} p&&/fi$/{p=0;next} !p' <<<"$text")"; then
      echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=1 outcome=REFUTED"
      echo "shipped falsifier only reachable outside CKERI_BLASTER_SANDBOX_CHECK" >&2
      return 1
    fi
    echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=1 outcome=REFUTED"
    return 0
  fi
  echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=1 outcome=REFUTED"
  echo "shipped falsifier absent from runner" >&2
  return 1
}

cat > "$work/runner-host-only.txt" <<'EOF'
if [ "${CKERI_BLASTER_SANDBOX_CHECK:-0}" != 1 ]; then
  echo "AUDIT-SELFTEST leg=omitted-declared-artifact rc=1 outcome=REFUTED"
fi
EOF
expect_red INV-246-FALSIFIER-REACHABILITY \
  'shipped falsifier only reachable outside CKERI_BLASTER_SANDBOX_CHECK' \
  check_falsifier_reachability "$(cat "$work/runner-host-only.txt")"

# C5 is deliberately not FALSIFIER-REACHABILITY. A runner that reaches
# the completeness falsifiers but never invokes the schema check would
# let one green stand for both rows.
check_schema_reached_by_runner() { # runner-file
  local runner=$1
  if ! grep -Eq 'check-claim-schema|AUDIT-CLAIM-SCHEMA' "$runner"; then
    echo "schema check not reached by the gate runner" >&2
    return 1
  fi
  return 0
}
cat > "$work/runner-falsifiers-no-schema.txt" <<'EOF'
echo "AUDIT-SELFTEST leg=omitted-declared-artifact rc=1 outcome=REFUTED"
echo "AUDIT-SELFTEST leg=empty-or-unreadable-inventory rc=1 outcome=REFUTED"
echo "AUDIT-SELFTEST leg=declared-mode-mismatch rc=1 outcome=REFUTED"
EOF
expect_red INV-246-C5-schema-not-on-gate-runner \
  'schema check not reached by the gate runner' \
  check_schema_reached_by_runner "$work/runner-falsifiers-no-schema.txt"

# ---------------------------------------------------------------------------
# T246-F6 / INV-246-IDENTITY-LINE-PROTOCOL: the standing checker must
# publish expected_containers and missing_containers on a clean fixture.
# This is the first C-v2 fail and must stay the focused RED of this file
# against the pre-slice checker.
# ---------------------------------------------------------------------------
commit=4e840934deeb55aa9fd45a34fc516bb4c635bf81
aiken=1.1.23
variant=defaultFunSemanticsVariantE
era=post-Conway
selection=explicit-era-binding
version_derived=defaultFunSemanticsVariantC
verification_receipt=fixture-clean
toolchain='aiken=1.1.23;lean-blaster=62d2d59abda37e90097e655b40e27545bba16f3c;plutus-core-blaster=7cf5a78c54b9694ef093bf49edb5d3799b2a49c9;cardano-ledger-api-blaster=577e3eb03b5be09354cfdb1c0d0c12e9e16541a0'
lock_sha=96f9405089d9a28b305fae4fff9e657ec8363a157c326bcc66c3e232b8f92200
lean_blaster_rev=62d2d59abda37e90097e655b40e27545bba16f3c
plutus_core_rev=7cf5a78c54b9694ef093bf49edb5d3799b2a49c9
ledger_api_rev=577e3eb03b5be09354cfdb1c0d0c12e9e16541a0

jq -n '{
  validators: [range(0; 23) as $i | {
    title: ("fixture.validator." + ($i | tostring)),
    parameters: [range(0; ($i % 4)) | {name: ("p" + (. | tostring))}],
    compiledCode: (["00", "01", "02", "03", "04", "05", "06", "07"][$i % 8])
  }]
}' > "$work/blueprint.json"
blueprint_sha=$(sha256sum "$work/blueprint.json" | cut -d ' ' -f 1)
: > "$work/programs.jsonl"
while IFS=$'\t' read -r title params code; do
  program_sha=$(printf '%s' "$code" | sha256sum | cut -d ' ' -f 1)
  jq -cn --arg title "$title" --argjson params "$params" \
    --arg program_sha256 "$program_sha" \
    '{title:$title, params:$params, program_sha256:$program_sha256}' \
    >> "$work/programs.jsonl"
done < <(jq -r '.validators[] | [.title, ((.parameters // []) | length), .compiledCode] | @tsv' \
  "$work/blueprint.json")
jq -s . "$work/programs.jsonl" > "$work/programs.json"
jq -n \
  --arg commit "$commit" \
  --arg aiken "$aiken" \
  --arg toolchain "$toolchain" \
  --arg variant "$variant" \
  --arg era "$era" \
  --arg selection "$selection" \
  --arg version_derived "$version_derived" \
  --arg verification_receipt "$verification_receipt" \
  --arg lock_sha256 "$lock_sha" \
  --arg lean_blaster "$lean_blaster_rev" \
  --arg plutus_core "$plutus_core_rev" \
  --arg ledger_api "$ledger_api_rev" \
  --arg blueprint_sha256 "$blueprint_sha" \
  --slurpfile programs "$work/programs.json" '
  def identity: {
    commit:$commit, aiken:$aiken, toolchain:$toolchain, variant:$variant,
    ledger_language:"PlutusV3", era:$era,
    blueprint_sha256:$blueprint_sha256
  };
  ($programs[0]) as $ps |
  {
    schema:"cardano-keri-baseline-v1",
    identity:(identity + {
      built_from:"source",
      validating_aiken:$aiken,
      selection:$selection,
      version_derived:$version_derived,
      lock_sha256:$lock_sha256,
      upstream:{lean_blaster:$lean_blaster,
        plutus_core_blaster:$plutus_core,
        cardano_ledger_api_blaster:$ledger_api}
    }),
    blueprint_sha256:$blueprint_sha256,
    programs:$ps,
    records: (
      [(identity + {record:"manifest"})]
      + [$ps[] | identity + {record:"program", title:.title,
          params:.params, program_sha256:.program_sha256}]
      + [
          (identity + {record:"baseline"}),
          (identity + {record:"evaluation-identity"}),
          (identity + {record:"verification-receipt",
            receipt:$verification_receipt})
        ]
    )
  }' > "$work/manifest.json"

set +e
identity_out=$("$checker" \
  --repo-root "$repo_root" \
  --identity-manifest "$work/manifest.json" \
  --blueprint "$work/blueprint.json" \
  --expected-commit "$commit" \
  --expected-aiken "$aiken" \
  --expected-variant "$variant" \
  --expected-era "$era" \
  --expected-selection "$selection" \
  --expected-version-derived "$version_derived" \
  --expected-verification-receipt "$verification_receipt" \
  --expected-toolchain "$toolchain" \
  --expected-lock-sha256 "$lock_sha" \
  --expected-lean-blaster-rev "$lean_blaster_rev" \
  --expected-plutus-core-rev "$plutus_core_rev" \
  --expected-ledger-api-rev "$ledger_api_rev" 2>&1)
identity_rc=$?
set -e
printf '%s\n' "$identity_out" > "$work/identity.out"
[ "$identity_rc" -eq 0 ] \
  || fail "clean identity fixture was rejected: $identity_out"
if grep -Eq '^CBIC_IDENTITY_RESULT expected_containers=[1-9][0-9]*$' \
  "$work/identity.out" \
  && grep -Eq '^CBIC_IDENTITY_RESULT missing_containers=0$' \
    "$work/identity.out"; then
  printf 'GREEN-PROOF invariant=INV-246-C13-T246-F6-expected-containers rc=0\n'
else
  fail "INV-246-IDENTITY-LINE-PROTOCOL: standing checker did not publish expected_containers/missing_containers"
fi

# Production surfaces. Required after the oracles so a missing file cannot
# stand in for a property that was never shown able to fail.
for required in \
  "$bundle_dir/check-completeness.sh" \
  "$bundle_dir/check-claim-schema.sh" \
  "$bundle_dir/assemble.sh" \
  "$bundle_dir/run.sh" \
  "$bundle_dir/run-slice-c.sh" \
  "$bundle_dir/inventory.txt" \
  "$bundle_dir/check-published-bytes.sh" \
  "$bundle_dir/check-falsifier-reachability.sh" \
  "$bundle_dir/COVERAGE-BOUNDARY.md" \
  "$bundle_dir/isolate-run.sh"; do
  [ -e "$required" ] || fail "declared production surface missing: $required"
done

check_entry_pins "$bundle_dir/run.sh" \
  || fail "INV-246-C1: production entry point depends on a desk path"
check_schema_reached_by_runner "$repo_root/offchain/flake.nix" \
  || fail "INV-246-C5: flake-owned runner does not reach the schema check"

# Finding class from auditor-C1-s1 artifact-binding-subject-probe.sh
# (sha256 9c3b64613d7b0a6cbf028d3a5f385c6fac7b6f6378274fc0d6d852459a5cbb1f)
# against candidate 35e2ec92: binding must not be the toy fixture when
# the inventory names no published subject.
judge_binding_subject() {
  local out=$1
  local binding fixture subjects
  binding=$(sed -n 's/^AUDIT-ARTIFACT-BINDING digest=\([^ ]*\).*/\1/p' "$out")
  fixture=$(sha256sum "$bundle_dir/fixtures/clean-identity.json" | cut -d' ' -f1)
  subjects=$(grep -cE '(^|/)(plutus\.json|manifest\.json|blueprint\.json)([[:space:]]|$)' \
    "$bundle_dir/inventory.txt" || true)
  if [ "$subjects" -eq 0 ]; then
    echo "inventory names no published identity artifact" >&2
    return 1
  fi
  if [ -z "$binding" ] || [ "$binding" = "$fixture" ]; then
    echo "artifact-binding verdict is over the toy fixture, not published identity bytes" >&2
    return 1
  fi
  return 0
}
expect_red INV-246-ARTIFACT-BINDING-TOY-SUBJECT \
  'declared artifact missing from source: published/manifest.json' \
  "$bundle_dir/run.sh" "$work/bind-missing"
cp -a "$bundle_dir" "$work/bundle-copy"
mkdir -p "$work/bundle-copy/published"
cp "$work/bundle-copy/fixtures/clean-identity.json" \
  "$work/bundle-copy/published/manifest.json"
expect_red INV-246-ARTIFACT-BINDING-TOY-COPY \
  'toy fixture, not published identity bytes' \
  "$work/bundle-copy/run.sh" "$work/bind-toy"
printf '%s\n' \
  '{"identity":{"variant":"defaultFunSemanticsVariantE","source":"not-the-toy"}}' \
  > "$work/bundle-copy/published/manifest.json"
"$work/bundle-copy/run.sh" "$work/bind-real" > "$work/bind.out"
judge_binding_subject "$work/bind.out" \
  || fail "non-toy published identity was not accepted as the binding subject"

# Finding class from auditor-C1-s1 reproduction-access-probe.sh
# (sha256 fa0c03e405659361f64991d9e5aac61e13c34d9d71ed85383cfe00d790876f82):
# worktree_access=none is RED unless isolation measured readable=0.
judge_isolation_record() {
  local record=$1
  if grep -Eq 'worktree_access=none' <<<"$record" \
    && ! grep -Eq 'readable=0' <<<"$record"; then
    echo "worktree_access=none is asserted, not measured" >&2
    return 1
  fi
  return 0
}
expect_red INV-246-C9-access-asserted-not-measured \
  'worktree_access=none is asserted, not measured' \
  judge_isolation_record \
  'AUDIT-REPRODUCTION source=fresh-clone worktree_access=none entry_point=scripts/ckeri-bundle/run.sh exit=0'
iso_out=$("$bundle_dir/isolate-run.sh" \
  --forbid "$repo_root" \
  --forbid /tmp/ms-keri-8/e190/t246 \
  -- true)
echo "$iso_out" | grep -Eq 'readable=0' \
  || fail "isolate-run did not measure readable=0: $iso_out"

echo "bundle-contract: OK"
