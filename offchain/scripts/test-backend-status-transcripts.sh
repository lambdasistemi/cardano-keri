#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator=${BACKEND_TRANSCRIPT_VALIDATOR:-$script_dir/check-backend-status-transcripts.sh}
aid=EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi
binary=/nix/store/00000000000000000000000000000000-ckeri/bin/ckeri

if [[ ! -x "$validator" ]]; then
  printf 'RED: missing executable validator: %s\n' "$validator" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
raw_dir="$work_dir/raw"
mkdir -p "$raw_dir"

write_raw() {
  local backend=$1 source=$2 file=$3
  local lag=0
  [[ $backend == local ]] && lag=unknown
  printf 'source %s as_of_slot 100 tip_lag_slots %s aid %s state registered watchable true\n' \
    "$source" "$lag" "$aid" >"$file"
}

write_raw local local "$raw_dir/local.raw"
write_raw endpoint https://ckeri.dev.plutimus.com "$raw_dir/endpoint.raw"
write_raw koios https://preprod.koios.rest/api/v1 "$raw_dir/koios.raw"

raw_hash() {
  sha256sum "$raw_dir/$1" | awk '{print $1}'
}

valid="$work_dir/valid.txt"
{
  printf '%s\n' \
    'evidence-version: 1' \
    'source-commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'backend-code-commit: dddddddddddddddddddddddddddddddddddddddd' \
    'candidate-build-handoff-sha256: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' \
    'candidate-out-link: /code/tmp/cardano-keri-177/ckeri-package' \
    'candidate-store-path: /nix/store/00000000000000000000000000000000-ckeri' \
    'source-store: /code/source-store' \
    'source-store-sha256-before: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'source-store-sha256-after: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'store-copy: /code/tmp/cardano-keri-177/local-store' \
    'store-copy-sha256-preopen: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'store-copy-sha256-postopen: cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    'local-as-of-source: transactional-store-watermark' \
    'endpoint-as-of-source: endpoint-response' \
    'koios-as-of-source: supporting-checkpoint-transaction-slot-compared-with-fresh-tip' \
    'record: 1' \
    'backend: local' \
    "aid: $aid" \
    'utc: 2026-08-02T16:00:00Z' \
    'operator: paolino via cardano-keri#177 driver pane %5284' \
    'host: test-host' \
    'pane: %5284' \
    "binary: $binary" \
    'binary-sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'store: /code/tmp/cardano-keri-177/local-store' \
    'source: local' \
    'cwd: /tmp' \
    "command: $binary status --aid $aid --backend local --store /code/tmp/cardano-keri-177/local-store --manifest /code/cardano-keri-177-backends/deploy/preprod/m1-manifest.json --board-manifest /code/cardano-keri-177-backends/deploy/preprod/board-manifest.json" \
    'raw-file: local.raw' \
    "raw-sha256: $(raw_hash local.raw)" \
    'exit-status: 0' \
    'result: success' \
    'record: 2' \
    'backend: endpoint' \
    "aid: $aid" \
    'utc: 2026-08-02T16:01:00Z' \
    'operator: paolino via cardano-keri#177 driver pane %5284' \
    'host: test-host' \
    'pane: %5284' \
    "binary: $binary" \
    'binary-sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'store: n/a' \
    'source: https://ckeri.dev.plutimus.com' \
    'cwd: /tmp' \
    "command: $binary status --aid $aid --endpoint https://ckeri.dev.plutimus.com" \
    'raw-file: endpoint.raw' \
    "raw-sha256: $(raw_hash endpoint.raw)" \
    'exit-status: 0' \
    'result: success' \
    'record: 3' \
    'backend: koios' \
    "aid: $aid" \
    'utc: 2026-08-02T16:02:00Z' \
    'operator: paolino via cardano-keri#177 driver pane %5284' \
    'host: test-host' \
    'pane: %5284' \
    "binary: $binary" \
    'binary-sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'store: n/a' \
    'source: https://preprod.koios.rest/api/v1' \
    'cwd: /tmp' \
    "command: $binary status --aid $aid --backend koios --manifest /code/cardano-keri-177-backends/deploy/preprod/m1-manifest.json --board-manifest /code/cardano-keri-177-backends/deploy/preprod/board-manifest.json" \
    'raw-file: koios.raw' \
    "raw-sha256: $(raw_hash koios.raw)" \
    'exit-status: 0' \
    'result: success'
} >"$valid"

pass_count=0
reject_count=0

expect_pass() {
  local name=$1 transcript=$2
  shift 2
  if ! bash "$validator" --transcript "$transcript" "$@" >"$work_dir/output" 2>&1; then
    printf 'FAIL: expected pass: %s\n' "$name" >&2
    sed 's/^/  /' "$work_dir/output" >&2
    exit 1
  fi
  pass_count=$((pass_count + 1))
}

expect_reject() {
  local name=$1 reason=$2 transcript=$3
  shift 3
  if bash "$validator" --transcript "$transcript" "$@" >"$work_dir/output" 2>&1; then
    printf 'FAIL: expected rejection: %s\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fqi -- "$reason" "$work_dir/output"; then
    printf 'FAIL: rejection %s did not name reason %q\n' "$name" "$reason" >&2
    sed 's/^/  /' "$work_dir/output" >&2
    exit 1
  fi
  reject_count=$((reject_count + 1))
}

drop_first_field() {
  local field=$1 output=$2
  awk -v prefix="$field: " '
    !removed && index($0, prefix) == 1 { removed = 1; next }
    { print }
  ' "$valid" >"$output"
}

replace_first_field() {
  local field=$1 value=$2 output=$3
  awk -v prefix="$field: " -v replacement="$field: $value" '
    !replaced && index($0, prefix) == 1 { print replacement; replaced = 1; next }
    { print }
  ' "$valid" >"$output"
}

remove_command_flag() {
  local record=$1 flag=$2 output=$3
  awk -v wanted_record="$record" -v flag="$flag" '
    /^record: / { current_record = $2 }
    current_record == wanted_record && /^command: / {
      sub(" --" flag " [^ ]+", "", $0)
    }
    { print }
  ' "$valid" >"$output"
}

expect_pass 'valid transcript with raw reconciliation' "$valid" --raw-dir "$raw_dir"
expect_pass 'valid transcript without raw reconciliation' "$valid"

printf 'ERROR: endpoint unavailable\n' >"$raw_dir/endpoint-fail.raw"
fail_hash="$(raw_hash endpoint-fail.raw)"
fail_closed="$work_dir/valid-fail-closed.txt"
awk -v hash="$fail_hash" '
  /^record: / { current_record = $2 }
  current_record == 2 && /^raw-file: / { print "raw-file: endpoint-fail.raw"; next }
  current_record == 2 && /^raw-sha256: / { print "raw-sha256: " hash; next }
  current_record == 2 && /^exit-status: / { print "exit-status: 7"; next }
  current_record == 2 && /^result: / { print "result: fail-closed"; next }
  { print }
' "$valid" >"$fail_closed"
expect_pass 'truthful nonempty fail-closed raw capture' "$fail_closed" --raw-dir "$raw_dir"

for field in evidence-version source-commit backend-code-commit candidate-build-handoff-sha256 candidate-out-link candidate-store-path source-store source-store-sha256-before source-store-sha256-after store-copy store-copy-sha256-preopen store-copy-sha256-postopen local-as-of-source endpoint-as-of-source koios-as-of-source; do
  fixture="$work_dir/missing-$field.txt"
  drop_first_field "$field" "$fixture"
  expect_reject "missing $field" "missing $field" "$fixture"
done

fixture="$work_dir/invalid-evidence-version.txt"
replace_first_field evidence-version 2 "$fixture"
expect_reject 'unsupported evidence version' 'evidence-version must be 1' "$fixture"

for field in source-commit backend-code-commit; do
  fixture="$work_dir/invalid-$field.txt"
  replace_first_field "$field" not-a-40-character-commit "$fixture"
  expect_reject "invalid $field shape" "invalid $field" "$fixture"
done

fixture="$work_dir/invalid-build-handoff.txt"
replace_first_field candidate-build-handoff-sha256 not-a-sha256 "$fixture"
expect_reject 'invalid build handoff hash shape' 'invalid candidate-build-handoff-sha256' "$fixture"

fixture="$work_dir/source-store-mutated.txt"
replace_first_field source-store-sha256-after dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd "$fixture"
expect_reject 'source store changed after capture' 'source store hash changed' "$fixture"

fixture="$work_dir/copy-preopen-drift.txt"
replace_first_field store-copy-sha256-preopen dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd "$fixture"
expect_reject 'copy did not match source before open' 'copy pre-open hash does not match' "$fixture"

fixture="$work_dir/candidate-path-drift.txt"
replace_first_field candidate-store-path /nix/store/11111111111111111111111111111111-ckeri "$fixture"
expect_reject 'binary is not from candidate package' 'binary does not match candidate-store-path' "$fixture"

fixture="$work_dir/non-ticket-copy.txt"
replace_first_field store-copy /tmp/unscoped-store "$fixture"
expect_reject 'store copy is outside ticket scope' 'provenance paths' "$fixture"

fixture="$work_dir/local-provenance-drift.txt"
replace_first_field local-as-of-source wall-clock "$fixture"
expect_reject 'local slot provenance drift' 'transactional store watermark' "$fixture"

fixture="$work_dir/endpoint-provenance-drift.txt"
replace_first_field endpoint-as-of-source request-time "$fixture"
expect_reject 'endpoint slot provenance drift' 'endpoint response' "$fixture"

fixture="$work_dir/koios-provenance-drift.txt"
replace_first_field koios-as-of-source fresh-tip-only "$fixture"
expect_reject 'Koios slot provenance drift' 'supporting records' "$fixture"

for field in utc operator host pane binary binary-sha256 store source cwd command exit-status result raw-file raw-sha256; do
  fixture="$work_dir/missing-$field.txt"
  drop_first_field "$field" "$fixture"
  expect_reject "missing $field" "missing $field" "$fixture"
done

fixture="$work_dir/aid-drift.txt"
replace_first_field aid EWrongAidOnOneRecord "$fixture"
expect_reject 'one record has a different AID' 'accepted AID' "$fixture"

for value in partial ok; do
  fixture="$work_dir/result-$value.txt"
  replace_first_field result "$value" "$fixture"
  expect_reject "invalid result $value" 'result must be success or fail-closed' "$fixture"
done

fixture="$work_dir/positional-command.txt"
replace_first_field command "$binary status $aid --backend local --store /code/tmp/cardano-keri-177/local-store" "$fixture"
expect_reject 'retired positional command' 'command shape' "$fixture"

fixture="$work_dir/missing-backend-setting.txt"
replace_first_field command "$binary status --aid $aid --backend local" "$fixture"
expect_reject 'local command missing store' 'command shape' "$fixture"

for record in 1 3; do
  backend_name=local
  [[ $record -eq 3 ]] && backend_name=koios
  for flag in manifest board-manifest; do
    fixture="$work_dir/$backend_name-missing-$flag.txt"
    remove_command_flag "$record" "$flag" "$fixture"
    expect_reject "$backend_name command missing --$flag" 'requires absolute manifest settings' "$fixture"
  done
done

fixture="$work_dir/backend-command-drift.txt"
replace_first_field command "$binary status --aid $aid --backend koios" "$fixture"
expect_reject 'command names another backend' 'command backend does not match' "$fixture"

fixture="$work_dir/unsafe-command.txt"
replace_first_field command "$binary status --aid $aid --backend local --store /code/tmp/store ; curl https://example.invalid" "$fixture"
expect_reject 'command contains shell composition' 'unsafe command text' "$fixture"

fixture="$work_dir/two-records.txt"
awk '/^record: 3$/ { exit } { print }' "$valid" >"$fixture"
expect_reject 'fewer than three records' 'exactly 3 records' "$fixture"

fixture="$work_dir/four-records.txt"
awk '
  /^record: 3$/ { copy = 1 }
  copy { duplicate = duplicate $0 ORS }
  { print }
  END {
    sub(/^record: 3/, "record: 4", duplicate)
    printf "%s", duplicate
  }
' "$valid" >"$fixture"
expect_reject 'more than three records' 'exactly 3 records' "$fixture"

fixture="$work_dir/duplicate-backend.txt"
awk '
  /^backend: koios$/ && !replaced { print "backend: endpoint"; replaced = 1; next }
  { print }
' "$valid" >"$fixture"
expect_reject 'duplicate backend' 'exactly one record per backend' "$fixture"

for raw_file in local.raw endpoint.raw koios.raw; do
  corrupt_dir="$work_dir/corrupt-${raw_file%.raw}"
  mkdir -p "$corrupt_dir"
  cp "$raw_dir"/*.raw "$corrupt_dir/"
  printf 'corruption\n' >>"$corrupt_dir/$raw_file"
  expect_reject "hash drift in $raw_file" 'raw hash mismatch' "$valid" --raw-dir "$corrupt_dir"
done

printf 'source https://ckeri.dev.plutimus.com as_of_slot 100 tip_lag_slots unknown aid %s state registered watchable true\n' \
  "$aid" >"$raw_dir/endpoint-unknown.raw"
endpoint_unknown_hash="$(raw_hash endpoint-unknown.raw)"
fixture="$work_dir/endpoint-unknown-lag.txt"
awk -v hash="$endpoint_unknown_hash" '
  /^record: / { current_record = $2 }
  current_record == 2 && /^raw-file: / { print "raw-file: endpoint-unknown.raw"; next }
  current_record == 2 && /^raw-sha256: / { print "raw-sha256: " hash; next }
  { print }
' "$valid" >"$fixture"
expect_reject 'only local may report unknown tip lag' 'numeric tip_lag_slots' "$fixture" --raw-dir "$raw_dir"

{
  printf 'capture annotation that is not command output\n'
  cat "$raw_dir/local.raw"
} >"$raw_dir/annotated.raw"
annotated_hash="$(raw_hash annotated.raw)"
fixture="$work_dir/annotated-success.txt"
awk -v hash="$annotated_hash" '
  /^raw-file: local.raw$/ && !file_done { print "raw-file: annotated.raw"; file_done = 1; next }
  /^raw-sha256: / && !hash_done { print "raw-sha256: " hash; hash_done = 1; next }
  { print }
' "$valid" >"$fixture"
expect_reject 'annotated multiline success raw' 'exactly one non-empty renderer line' "$fixture" --raw-dir "$raw_dir"

renderer_fail_hash="$(raw_hash endpoint.raw)"
fixture="$work_dir/fail-closed-renderer.txt"
awk -v hash="$renderer_fail_hash" '
  /^record: / { current_record = $2 }
  current_record == 2 && /^raw-file: / { print "raw-file: endpoint.raw"; next }
  current_record == 2 && /^raw-sha256: / { print "raw-sha256: " hash; next }
  current_record == 2 && /^exit-status: / { print "exit-status: 7"; next }
  current_record == 2 && /^result: / { print "result: fail-closed"; next }
  { print }
' "$valid" >"$fixture"
expect_reject 'fail-closed raw cannot be a success renderer line' 'fail-closed raw resembles successful renderer output' "$fixture" --raw-dir "$raw_dir"

: >"$raw_dir/empty-fail.raw"
empty_hash="$(raw_hash empty-fail.raw)"
fixture="$work_dir/empty-fail-closed.txt"
awk -v hash="$empty_hash" '
  /^record: / { current_record = $2 }
  current_record == 2 && /^raw-file: / { print "raw-file: empty-fail.raw"; next }
  current_record == 2 && /^raw-sha256: / { print "raw-sha256: " hash; next }
  current_record == 2 && /^exit-status: / { print "exit-status: 7"; next }
  current_record == 2 && /^result: / { print "result: fail-closed"; next }
  { print }
' "$valid" >"$fixture"
expect_reject 'fail-closed raw must contain the closed error' 'fail-closed raw is empty' "$fixture" --raw-dir "$raw_dir"

fixture="$work_dir/unsafe-raw-path.txt"
replace_first_field raw-file ../outside.raw "$fixture"
expect_reject 'raw file escapes raw directory' 'unsafe raw-file' "$fixture" --raw-dir "$raw_dir"

# Composition is detected mechanically: the declared backend must agree with
# both its command selector and the common renderer's exact `source VALUE`
# line. This fixture points a local record at endpoint-shaped output while
# updating the hash, so hash-only validation cannot accidentally catch it.
cp "$raw_dir/endpoint.raw" "$raw_dir/borrowed.raw"
borrowed_hash="$(raw_hash borrowed.raw)"
fixture="$work_dir/tier-borrowed-output.txt"
awk -v hash="$borrowed_hash" '
  /^raw-file: local.raw$/ && !file_done { print "raw-file: borrowed.raw"; file_done = 1; next }
  /^raw-sha256: / && !hash_done { print "raw-sha256: " hash; hash_done = 1; next }
  { print }
' "$valid" >"$fixture"
expect_reject 'tier-borrowed raw output' 'raw source does not match backend' "$fixture" --raw-dir "$raw_dir"

printf 'PASS: %d accepted controls, %d rejected controls\n' "$pass_count" "$reject_count"
