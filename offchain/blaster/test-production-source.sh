#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app="${1:-$script_dir/blaster}"
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

fail() {
  printf 'test-production-source: %s\n' "$*" >&2
  exit 1
}

clean_cwd="$fixtures/clean"
ambient_cwd="$fixtures/ambient"
mkdir -p "$clean_cwd" "$ambient_cwd"
sentinel="$ambient_cwd/plutus.json"
sentinel_code="ambient-blueprint-must-never-be-read-192"
printf '%s\n' \
  "{\"validators\":[{\"title\":\"checkpoint.checkpoint.spend\",\"compiledCode\":\"$sentinel_code\"}]}" \
  >"$sentinel"

# Prove the synthetic ambient source is plausible and detectable before the
# expected RED on the absent production entry point.
[[ "$(jq -er --arg title "checkpoint.checkpoint.spend" \
  '.validators[] | select(.title == $title) | .compiledCode' "$sentinel")" \
  == "$sentinel_code" ]] || fail "ambient sentinel positive control failed"

captured_rc=0
jq -er 'error("capture-live")' "$sentinel" \
  >"$fixtures/capture.out" 2>"$fixtures/capture.err" || captured_rc=$?
[[ $captured_rc -ne 0 ]] || fail "failure-capture control did not fail"
grep -Fq "capture-live" "$fixtures/capture.err" \
  || fail "failure-capture control lost the expected diagnostic"

if [[ ! -x "$app" ]]; then
  printf 'RED: required no-argument production entry point absent: %s\n' \
    "$app" >&2
  exit 67
fi

(cd "$clean_cwd" && "$app") >"$fixtures/clean.out"
(cd "$ambient_cwd" && \
  CKERI_BLUEPRINT="$sentinel" \
  KERI_BLUEPRINT="$sentinel" \
  BLASTER_BLUEPRINT="$sentinel" \
  "$app") >"$fixtures/ambient.out"

cmp "$fixtures/clean.out" "$fixtures/ambient.out" \
  || fail "ambient CWD/environment changed production output"
if grep -Fq "$sentinel_code" "$fixtures/ambient.out"; then
  fail "production output contains the ambient blueprint sentinel"
fi

argument_rc=0
"$app" "$sentinel" \
  >"$fixtures/argument.out" 2>"$fixtures/argument.err" || argument_rc=$?
[[ $argument_rc -ne 0 ]] \
  || fail "production entry point accepted a blueprint path argument"

printf '%s\n' \
  'PASS: production entry point ignores ambient blueprints and rejects paths'
