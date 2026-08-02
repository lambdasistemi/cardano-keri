#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
selector="${1:-$script_dir/extract-program.jq}"
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

fail() {
  printf 'test-extraction: %s\n' "$*" >&2
  exit 1
}

# Harness controls run before the RED assertion. They distinguish a missing
# selector from an unavailable shell/jq, broken fixture creation, or dead
# failure-capture path.
[[ $((20 + 22)) -eq 42 ]] || fail "bash arithmetic control failed"
printf '%s\n' '{"control":"live"}' >"$fixtures/harness.json"
[[ "$(jq -er '.control' "$fixtures/harness.json")" == "live" ]] \
  || fail "jq/fixture positive control failed"
captured_rc=0
jq -er 'error("capture-live")' "$fixtures/harness.json" \
  >"$fixtures/capture.out" 2>"$fixtures/capture.err" || captured_rc=$?
[[ $captured_rc -ne 0 ]] || fail "failure-capture control did not fail"
grep -Fq "capture-live" "$fixtures/capture.err" \
  || fail "failure-capture control lost the expected diagnostic"

if [[ ! -f "$selector" ]]; then
  printf 'RED: required selector absent after live harness controls: %s\n' \
    "$selector" >&2
  exit 66
fi

title="checkpoint.checkpoint.spend"

run_selector() {
  local input="$1"
  jq -er --arg title "$title" -f "$selector" "$input"
}

write_fixture() {
  local name="$1"
  local json="$2"
  printf '%s\n' "$json" >"$fixtures/$name.json"
}

expect_failure() {
  local name="$1"
  local diagnostic="$2"
  local rc=0

  run_selector "$fixtures/$name.json" \
    >"$fixtures/$name.out" 2>"$fixtures/$name.err" || rc=$?
  [[ $rc -ne 0 ]] || fail "$name unexpectedly succeeded"
  grep -Fq "$diagnostic" "$fixtures/$name.err" \
    || fail "$name failed without diagnostic: $diagnostic"
}

write_fixture valid \
  '{"validators":[{"title":"checkpoint.checkpoint.spend","compiledCode":"aa11"}]}'
write_fixture missing \
  '{"validators":[{"title":"other.validator.spend","compiledCode":"aa11"}]}'
write_fixture renamed \
  '{"validators":[{"title":"checkpoint.checkpoint.renamed","compiledCode":"aa11"}]}'
write_fixture malformed_title \
  '{"validators":[{"title":null,"compiledCode":"aa11"}]}'
write_fixture duplicate_identical \
  '{"validators":[{"title":"checkpoint.checkpoint.spend","compiledCode":"aa11"},{"title":"checkpoint.checkpoint.spend","compiledCode":"aa11"}]}'
write_fixture duplicate_differing \
  '{"validators":[{"title":"checkpoint.checkpoint.spend","compiledCode":"aa11"},{"title":"checkpoint.checkpoint.spend","compiledCode":"bb22"}]}'
write_fixture null \
  '{"validators":[{"title":"checkpoint.checkpoint.spend","compiledCode":null}]}'
write_fixture empty \
  '{"validators":[{"title":"checkpoint.checkpoint.spend","compiledCode":""}]}'
write_fixture non_string \
  '{"validators":[{"title":"checkpoint.checkpoint.spend","compiledCode":{"hex":"aa11"}}]}'
write_fixture missing_validators '{}'
write_fixture malformed_validators '{"validators":{"title":"checkpoint.checkpoint.spend"}}'

[[ "$(run_selector "$fixtures/valid.json")" == "aa11" ]] \
  || fail "valid unique non-empty selector result mismatch"

cardinality_diagnostic="expected exactly one validator title: $title"
compiled_code_diagnostic="compiledCode must be a non-empty string: $title"
validators_diagnostic="blueprint validators must be an array"

expect_failure missing "$cardinality_diagnostic"
expect_failure renamed "$cardinality_diagnostic"
expect_failure malformed_title "$cardinality_diagnostic"
expect_failure duplicate_identical "$cardinality_diagnostic"
expect_failure duplicate_differing "$cardinality_diagnostic"
expect_failure null "$compiled_code_diagnostic"
expect_failure empty "$compiled_code_diagnostic"
expect_failure non_string "$compiled_code_diagnostic"
expect_failure missing_validators "$validators_diagnostic"
expect_failure malformed_validators "$validators_diagnostic"

printf '%s\n' \
  'PASS: exact extraction selector positive and rejection controls executed'
