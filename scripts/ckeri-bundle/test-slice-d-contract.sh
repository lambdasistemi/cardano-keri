#!/usr/bin/env bash
# Executable Slice D contract for INV-246-D1..D5.
# Producer identity comes from Nix evaluation or generated producer output,
# never from prose or from the artifact under test.
set -euo pipefail

failures=0

note_failure() {
  local row=$1 detail=$2
  printf 'PROOF-ROW id=%s outcome=COULD-NOT-EVALUATE detail=%s\n' "$row" "$detail"
  failures=$((failures + 1))
}

expect_rejected() {
  local row=$1 label=$2 diagnostic=$3
  shift 3
  local output rc
  set +e
  output=$("$@" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    printf 'PROOF-ROW id=%s outcome=REFUTED detail=%s-accepted\n' "$row" "$label"
    failures=$((failures + 1))
    return
  fi
  if [ -n "$diagnostic" ] && [[ $output != *"$diagnostic"* ]]; then
    printf 'PROOF-ROW id=%s outcome=COULD-NOT-EVALUATE detail=%s-wrong-diagnostic rc=%s\n' \
      "$row" "$label" "$rc"
    failures=$((failures + 1))
    return
  fi
  printf 'PROOF-CONTROL id=%s label=%s rc=%s outcome=REFUTED\n' \
    "$row" "$label" "$rc"
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ckeri-slice-d.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

for command in git jq nix sha256sum tar; do
  command -v "$command" >/dev/null 2>&1 \
    || { echo "test-slice-d-contract: missing command: $command" >&2; exit 1; }
done

# Materialise the current tracked working-tree bytes into a clean temporary Git
# source. This keeps the flake's self revision and the checker's Git revision
# identical even during the pre-commit GREEN run.
snapshot=$work/source
mkdir -p "$snapshot"
git -C "$REPO_ROOT" ls-files -z \
  | tar --null -C "$REPO_ROOT" -T - -cf - \
  | tar -xf - -C "$snapshot"
git -C "$snapshot" init -q
git -C "$snapshot" config user.name slice-d-contract
git -C "$snapshot" config user.email slice-d-contract@example.invalid
git -C "$snapshot" add .
git -C "$snapshot" commit -q -m 'test fixture: current tracked source'

producer_aiken() {
  local root=$1
  nix eval --raw --impure --expr \
    "let f = builtins.getFlake (toString ${root}/offchain); p = import f.inputs.aikenNixpkgs { system = builtins.currentSystem; }; in p.aiken.version"
}

lock_rev() {
  local root=$1 name=$2
  jq -er --arg name "$name" \
    '.nodes[$name].locked.rev | select(type == "string" and length > 0)' \
    "$root/offchain/flake.lock"
}

make_identity_fixture() {
  local root=$1 aiken=$2 variant=$3 output=$4
  local commit lock_sha lean_rev plc_rev ledger_rev toolchain blueprint_sha
  commit=$(git -C "$root" rev-parse HEAD)
  lock_sha=$(sha256sum "$root/offchain/flake.lock" | cut -d ' ' -f1)
  lean_rev=$(lock_rev "$root" leanBlaster)
  plc_rev=$(lock_rev "$root" plutusCoreBlaster)
  ledger_rev=$(lock_rev "$root" cardanoLedgerApiBlaster)
  toolchain="aiken=$aiken;lean-blaster=$lean_rev;plutus-core-blaster=$plc_rev;cardano-ledger-api-blaster=$ledger_rev"
  blueprint_sha=$(printf 'slice-d-static-fixture' | sha256sum | cut -d ' ' -f1)
  jq -n \
    --arg commit "$commit" \
    --arg aiken "$aiken" \
    --arg toolchain "$toolchain" \
    --arg variant "$variant" \
    --arg lock_sha "$lock_sha" \
    --arg lean "$lean_rev" \
    --arg plc "$plc_rev" \
    --arg ledger "$ledger_rev" \
    --arg blueprint_sha "$blueprint_sha" '
      {
        schema:"cardano-keri-baseline-v1",
        identity:{
          commit:$commit,
          aiken:$aiken,
          validating_aiken:$aiken,
          toolchain:$toolchain,
          variant:$variant,
          ledger_language:"PlutusV3",
          era:"post-Conway",
          built_from:"source",
          selection:"explicit-era-binding",
          version_derived:"defaultFunSemanticsVariantC",
          lock_sha256:$lock_sha,
          blueprint_sha256:$blueprint_sha,
          upstream:{
            lean_blaster:$lean,
            plutus_core_blaster:$plc,
            cardano_ledger_api_blaster:$ledger
          }
        },
        blueprint_sha256:$blueprint_sha,
        records:[]
      }' > "$output"
}

aiken=$(producer_aiken "$snapshot")
checker=$snapshot/scripts/ckeri-bundle/check-published-bytes.sh

echo '=== INV-246-D1: every identity field is producer-bound ==='

# Reproduce the exact Slice-C escape: move the editable prose and the bytes
# together while leaving the pinned flake producer unchanged. The current
# checker accepts this; the repaired checker must reject it specifically on the
# Aiken producer binding.
attack=$work/prose-attack
cp -a "$snapshot" "$attack"
mutant_aiken="${aiken}.coordinated-prose-mutant"
sed -i "s/| Aiken | \`$aiken\`/| Aiken | \`$mutant_aiken\`/" \
  "$attack/docs/architecture/blaster-tractability.md"
git -C "$attack" add docs/architecture/blaster-tractability.md
git -C "$attack" commit -q -m 'mutant: move prose with artifact'
make_identity_fixture "$attack" "$mutant_aiken" \
  defaultFunSemanticsVariantE "$work/prose-mutant.json"
expect_rejected INV-246-D1 coordinated-prose-and-artifact aiken \
  env -u CKERI_EXPECTED_AIKEN -u CKERI_EXPECTED_COMMIT \
    -u CKERI_EXPECTED_TOOLCHAIN -u CKERI_PRODUCER_RECORD \
    bash "$attack/scripts/ckeri-bundle/check-published-bytes.sh" \
      "$work/prose-mutant.json"

# D-v3 quantifies over the artifact's field set. Adding a new string field must
# be RED without adding its spelling to the checker.
make_identity_fixture "$snapshot" "$aiken" \
  defaultFunSemanticsVariantE "$work/extra-field.json"
jq '.identity["gate-generated-field"] = "unauthenticated"' \
  "$work/extra-field.json" > "$work/extra-field-mutant.json"
expect_rejected INV-246-D1 quantified-new-field producer \
  env -u CKERI_EXPECTED_AIKEN -u CKERI_EXPECTED_COMMIT \
    -u CKERI_EXPECTED_TOOLCHAIN -u CKERI_PRODUCER_RECORD \
    bash "$checker" "$work/extra-field-mutant.json"

echo '=== INV-246-D2: complete current compiled denominator ==='
cat > "$work/blueprint.json" <<'JSON'
{
  "validators": [
    {"title":"alpha.alpha.mint","parameters":[],"compiledCode":"0102"},
    {"title":"alpha.alpha.spend","parameters":[],"compiledCode":"0102"},
    {"title":"beta.beta.spend","parameters":[{"title":"p"}],"compiledCode":"0304"}
  ]
}
JSON

commit=$(git -C "$snapshot" rev-parse HEAD)
lock_sha=$(sha256sum "$snapshot/offchain/flake.lock" | cut -d ' ' -f1)
lean_rev=$(lock_rev "$snapshot" leanBlaster)
plc_rev=$(lock_rev "$snapshot" plutusCoreBlaster)
ledger_rev=$(lock_rev "$snapshot" cardanoLedgerApiBlaster)
toolchain="aiken=$aiken;lean-blaster=$lean_rev;plutus-core-blaster=$plc_rev;cardano-ledger-api-blaster=$ledger_rev"
set +e
producer_output=$(env \
  BASELINE_COMMIT="$commit" \
  BASELINE_AIKEN="$aiken" \
  BASELINE_TOOLCHAIN="$toolchain" \
  BASELINE_VARIANT=defaultFunSemanticsVariantE \
  BASELINE_ERA=post-Conway \
  BASELINE_SELECTION=explicit-era-binding \
  BASELINE_VERSION_DERIVED=defaultFunSemanticsVariantC \
  BASELINE_VERIFICATION_RECEIPT=manifest-verification \
  BASELINE_LOCK_SHA256="$lock_sha" \
  BASELINE_LEAN_BLASTER_REV="$lean_rev" \
  BASELINE_PLUTUS_CORE_REV="$plc_rev" \
  BASELINE_LEDGER_API_REV="$ledger_rev" \
  bash "$snapshot/offchain/blaster/make-baseline-manifest.sh" \
    "$work/blueprint.json" "$work/manifest.json" 2>&1)
producer_rc=$?
set -e
if [ "$producer_rc" -ne 0 ]; then
  printf 'PROOF-ROW id=INV-246-D2 outcome=REFUTED detail=producer-rejected-n-greater-than-one rc=%s\n' \
    "$producer_rc"
  failures=$((failures + 1))
elif ! jq -e '
    (.records | length) == 3
    and ([.records[].title] | unique | length) == 3
    and ([.records[].compiledCodeHash] | unique | length) == 2
    and ([.records[] | (.title | type == "string")
      and (.compiledCodeHash | test("^[0-9a-f]{64}$"))] | all)
  ' "$work/manifest.json" >/dev/null; then
  note_failure INV-246-D2 denominator-not-rederived-from-three-title-two-program-blueprint
else
  echo 'PROOF-ROW id=INV-246-D2 outcome=ESTABLISHED titles=3 programs=2 source=producer-output'
fi

echo '=== INV-246-D3: explicit post-Conway Variant E ==='
make_identity_fixture "$snapshot" "$aiken" \
  defaultFunSemanticsVariantC "$work/variant-c.json"
expect_rejected INV-246-D3 explicit-variant-c variant \
  bash "$checker" "$work/variant-c.json"
make_identity_fixture "$snapshot" "$aiken" \
  defaultFunSemanticsVariantE "$work/variant-missing.json"
jq 'del(.identity.variant)' "$work/variant-missing.json" \
  > "$work/variant-missing-mutant.json"
expect_rejected INV-246-D3 unnamed-variant variant \
  bash "$checker" "$work/variant-missing-mutant.json"
echo 'PROOF-ROW id=INV-246-D3 outcome=ESTABLISHED variant=defaultFunSemanticsVariantE controls=2'

check_reconciliation() {
  local manifest=$1 reconciliation=$2 scratch=$3
  [ -s "$manifest" ] && [ -s "$reconciliation" ] || return 2
  jq -er '
    .records | length > 1
    and ([.records[] | (.title | type == "string" and length > 0)] | all)
    and ([.records[] | ((.compiledCodeHash // .programHash // "")
      | test("^[0-9a-f]{64}$"))] | all)
  ' "$manifest" >/dev/null || return 1
  jq -r '.records[] | [.title, (.compiledCodeHash // .programHash)] | @tsv' \
    "$manifest" | LC_ALL=C sort > "$scratch/current.tsv"
  awk -F'|' '
    /^\| `[^`]+` \|/ {
      for (i = 2; i <= 5; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
        gsub(/`|\*\*/, "", $i)
      }
      print $2 "\t" $3 "\t" $4 "\t" tolower($5)
    }
  ' "$reconciliation" | LC_ALL=C sort > "$scratch/reconciliation.tsv"
  [ "$(wc -l < "$scratch/current.tsv")" -eq \
    "$(wc -l < "$scratch/reconciliation.tsv")" ] || return 1
  cut -f1 "$scratch/current.tsv" > "$scratch/current.titles"
  cut -f1 "$scratch/reconciliation.tsv" > "$scratch/reconciliation.titles"
  cmp -s "$scratch/current.titles" "$scratch/reconciliation.titles" || return 1
  awk -F '\t' '
    NR == FNR { current[$1] = $2; next }
    !($1 in current) || current[$1] != $3 { bad = 1 }
    $4 == "added" && $2 != "-" && $2 != "—" { bad = 1 }
    $4 == "carried" && $2 != $3 { bad = 1 }
    $4 == "changed" && $2 == $3 { bad = 1 }
    $4 != "added" && $4 != "carried" && $4 != "changed" { bad = 1 }
    END { exit bad }
  ' "$scratch/current.tsv" "$scratch/reconciliation.tsv" || return 1
  prior_rows=$(awk -F '\t' '$2 != "-" && $2 != "—" { n++ } END { print n+0 }' \
    "$scratch/reconciliation.tsv")
  prior_programs=$(awk -F '\t' '$2 != "-" && $2 != "—" { print $2 }' \
    "$scratch/reconciliation.tsv" | LC_ALL=C sort -u | wc -l)
  [ "$prior_rows" -eq 23 ] && [ "$prior_programs" -eq 8 ] || return 1
  for disposition in carried changed added; do
    grep -q $'\t'"$disposition"'$' "$scratch/reconciliation.tsv" || return 1
  done
}

echo '=== INV-246-D4: reconcile the prior 23/8 inventory to the built denominator ==='
published=${CKERI_PUBLISHED_MANIFEST:-}
reconciliation=$REPO_ROOT/specs/246-post-conway-e-baseline/reconciliation.md
if [ -z "$published" ] || [ ! -s "$published" ]; then
  note_failure INV-246-D4 built-manifest-not-supplied
elif check_reconciliation "$published" "$reconciliation" "$work"; then
  echo 'PROOF-ROW id=INV-246-D4 outcome=ESTABLISHED prior_titles=23 prior_programs=8 source=built-artifact'
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    note_failure INV-246-D4 reconciliation-or-built-manifest-absent
  else
    printf 'PROOF-ROW id=INV-246-D4 outcome=REFUTED detail=row-by-row-reconciliation-mismatch\n'
    failures=$((failures + 1))
  fi
fi

check_limitations() {
  local limitations=$1
  [ -s "$limitations" ] || return 2
  for class in duplicate-key claim-record filesystem-namespace; do
    grep -qi "$class" "$limitations" || return 1
  done
  awk '
    function close_section() {
      if (inside && (!owner || !followup)) bad = 1
    }
    /^## LIM-/ {
      close_section()
      inside = 1
      owner = 0
      followup = 0
      count++
      next
    }
    inside && /^- Owner: / { owner = 1 }
    inside && /^- Follow-up ID: / && ($0 ~ /#[0-9]+|T[0-9]+-[A-Z][0-9]+/) {
      followup = 1
    }
    END {
      close_section()
      if (count < 3 || bad) exit 1
    }
  ' "$limitations"
}

echo '=== INV-246-D5: owned limitations with filed follow-ups ==='
limitations=$REPO_ROOT/specs/246-post-conway-e-baseline/limitations.md
if check_limitations "$limitations"; then
  echo 'PROOF-ROW id=INV-246-D5 outcome=ESTABLISHED classes=duplicate-key,claim-record,filesystem-namespace'
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    note_failure INV-246-D5 limitations-artifact-absent
  else
    printf 'PROOF-ROW id=INV-246-D5 outcome=REFUTED detail=unowned-or-unfiled-limitation\n'
    failures=$((failures + 1))
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "test-slice-d-contract: RED failures=$failures" >&2
  exit 1
fi

echo 'test-slice-d-contract: GREEN all Slice D rows established'
