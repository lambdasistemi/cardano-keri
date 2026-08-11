#!/usr/bin/env bash
set -euo pipefail

fail() { echo "baseline-manifest-producer: FAIL: $*" >&2; exit 1; }

[ "$#" -eq 2 ] || fail "usage: $0 BLUEPRINT OUTPUT"
blueprint=$1
output=$2

for name in BASELINE_COMMIT BASELINE_AIKEN BASELINE_TOOLCHAIN BASELINE_VARIANT \
  BASELINE_ERA BASELINE_SELECTION BASELINE_VERSION_DERIVED \
  BASELINE_VERIFICATION_RECEIPT BASELINE_LOCK_SHA256 \
  BASELINE_LEAN_BLASTER_REV BASELINE_PLUTUS_CORE_REV BASELINE_LEDGER_API_REV; do
  [ -n "${!name:-}" ] || fail "unnamed producer input: $name"
done
[ "$BASELINE_VARIANT" = defaultFunSemanticsVariantE ] \
  || fail "variant producer input moved: expected defaultFunSemanticsVariantE, got $BASELINE_VARIANT"
[ "$BASELINE_ERA" = post-Conway ] \
  || fail "era producer input moved: expected post-Conway, got $BASELINE_ERA"
[ "$BASELINE_VERSION_DERIVED" != "$BASELINE_VARIANT" ] \
  || fail "version-derived selection cannot stand in for explicit variant"
[ -r "$blueprint" ] || fail "cannot read blueprint: $blueprint"

jq -e '.validators | type == "array" and length > 0' "$blueprint" >/dev/null 2>&1 \
  || fail "blueprint schema: validators must be a non-empty array"
jq -e '[.validators[].title | type == "string" and length > 0 and test("^[^[:space:]]+$")] | all' \
  "$blueprint" >/dev/null 2>&1 || fail "blueprint schema: title"
jq -e '[.validators[].compiledCode | type == "string" and length > 0 and
  test("^[0-9A-Fa-f]+$") and ((length % 2) == 0)] | all' \
  "$blueprint" >/dev/null 2>&1 || fail "blueprint schema: compiledCode"
jq -e '[.validators[] | ((.parameters // []) | type) == "array"] | all' \
  "$blueprint" >/dev/null 2>&1 || fail "blueprint schema: parameters"

titles=$(jq -er '.validators | length' "$blueprint")
programs=$(jq -er '[.validators[].compiledCode] | unique | length' "$blueprint")
[ "$titles" -eq 23 ] || fail "computed title cardinality moved: expected=23 actual=$titles"
[ "$programs" -eq 8 ] || fail "computed program cardinality moved: expected=8 actual=$programs"
jq -e '([.validators[].title] | length) == ([.validators[].title] | unique | length)' \
  "$blueprint" >/dev/null 2>&1 || fail "blueprint schema: duplicate title"

work=$(mktemp -d "${TMPDIR:-/tmp}/baseline-manifest-producer.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
blueprint_sha256=$(sha256sum "$blueprint" | cut -d ' ' -f 1)
: > "$work/programs.jsonl"
while IFS=$'\t' read -r title params code; do
  program_sha256=$(printf '%s' "$code" | sha256sum | cut -d ' ' -f 1)
  jq -cn --arg title "$title" --argjson params "$params" \
    --arg program_sha256 "$program_sha256" \
    '{title:$title, params:$params, program_sha256:$program_sha256}' \
    >> "$work/programs.jsonl"
done < <(jq -r '.validators[] | [.title, ((.parameters // []) | length), .compiledCode] | @tsv' "$blueprint")
jq -s . "$work/programs.jsonl" > "$work/programs.json"

jq -n \
  --arg commit "$BASELINE_COMMIT" \
  --arg aiken "$BASELINE_AIKEN" \
  --arg toolchain "$BASELINE_TOOLCHAIN" \
  --arg variant "$BASELINE_VARIANT" \
  --arg era "$BASELINE_ERA" \
  --arg selection "$BASELINE_SELECTION" \
  --arg version_derived "$BASELINE_VERSION_DERIVED" \
  --arg verification_receipt "$BASELINE_VERIFICATION_RECEIPT" \
  --arg blueprint_sha256 "$blueprint_sha256" \
  --arg lock_sha256 "$BASELINE_LOCK_SHA256" \
  --arg lean_blaster "$BASELINE_LEAN_BLASTER_REV" \
  --arg plutus_core "$BASELINE_PLUTUS_CORE_REV" \
  --arg ledger_api "$BASELINE_LEDGER_API_REV" \
  --slurpfile rows "$work/programs.json" '
  def identity: {
    commit:$commit, aiken:$aiken, toolchain:$toolchain,
    variant:$variant, ledger_language:"PlutusV3", era:$era,
    blueprint_sha256:$blueprint_sha256
  };
  ($rows[0]) as $program_rows |
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
    programs:$program_rows,
    records:(
      [(identity + {record:"manifest"})]
      + [$program_rows[] | identity + {record:"program", title:.title,
          params:.params, program_sha256:.program_sha256}]
      + [
          (identity + {record:"baseline"}),
          (identity + {record:"evaluation-identity"}),
          (identity + {record:"verification-receipt",
            receipt:$verification_receipt})
        ]
    )
  }' > "$output"
