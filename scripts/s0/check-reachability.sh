#!/usr/bin/env bash
# Executable real / invalid / hollow controls for the seven S0 handlers.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=token.sh
source "$here/token.sh"

EXPECTED_TOOL_SHA=c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689
REQUIRED_TESTS=(
  accept_s0_append
  reject_s0_append_said
  reject_s0_append_aid
  reject_s0_append_proof
  accept_s0_cursor
  reject_s0_cursor_proof
  accept_s0_lineage
  reject_s0_lineage_identity
  accept_s0_escrow
  reject_s0_escrow_grade
  accept_s0_staging
  reject_s0_staging_said
  reject_s0_staging_oversize
  accept_s0_predicates
  reject_s0_predicates_keys
  accept_s0_reference
  reject_s0_reference_datum
)

usage() {
  printf 'usage: %s self-test|verify --repo DIR --aiken ABS --evidence-dir DIR\n' \
    "$0" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
mode=$1
shift
[[ "$mode" == self-test || "$mode" == verify ]] || usage

repo=
aiken=
evidence_dir=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo=$2
      shift 2
      ;;
    --aiken)
      aiken=$2
      shift 2
      ;;
    --evidence-dir)
      evidence_dir=$2
      shift 2
      ;;
    *) usage ;;
  esac
done
[[ -n "$repo" && -n "$aiken" && -n "$evidence_dir" ]] || usage
repo=$(cd "$repo" && pwd)
mkdir -p "$evidence_dir"
evidence_dir=$(cd "$evidence_dir" && pwd)
[[ -x "$aiken" ]] || {
  printf 'S0-REACH-FAIL missing-aiken path=%s\n' "$aiken" >&2
  exit 32
}
tool_sha=$(sha256sum "$aiken" | awk '{print $1}')
if [[ "$tool_sha" != "$EXPECTED_TOOL_SHA" ]]; then
  printf 'S0-REACH-FAIL toolchain-hash expected=%s actual=%s\n' \
    "$EXPECTED_TOOL_SHA" "$tool_sha" >&2
  exit 32
fi

tests=$repo/onchain/validators/s0_skeleton_tests.ak
if [[ ! -f "$tests" ]]; then
  printf 'S0-REACH-FAIL missing-tests path=%s\n' "$tests" >&2
  exit 33
fi
for name in "${REQUIRED_TESTS[@]}"; do
  if ! command grep -Eq "^test[[:space:]]+${name}[[:space:]]*\\(" "$tests"; then
    printf 'S0-REACH-FAIL missing-test name=%s\n' "$name" >&2
    exit 34
  fi
done
if command grep -Eq 'g1_c4_input_393|g1_c4_input_966' "$tests"; then
  printf 'S0-REACH-FAIL reused-broken-g1-c4-fixture\n' >&2
  exit 34
fi

write_hollow() {
  local dest=$1
  cat >"$dest/s0_append.ak" <<'EOF'
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/types.{HistoricalProof, RecordState}
pub type AppendRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
  proof: HistoricalProof,
}
validator s0_append {
  spend(
    _d: Option<RecordState>,
    _r: AppendRedeemer,
    _s: OutputReference,
    _t: Transaction,
  ) { True }
  else(_x) { fail }
}
EOF
  cat >"$dest/s0_cursor.ak" <<'EOF'
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/types.{CursorState, HistoricalProof}
pub type CursorRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
  proof: HistoricalProof,
}
validator s0_cursor {
  spend(
    _d: Option<CursorState>,
    _r: CursorRedeemer,
    _s: OutputReference,
    _t: Transaction,
  ) { True }
  else(_x) { fail }
}
EOF
  cat >"$dest/s0_lineage.ak" <<'EOF'
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/types.{LineageAction, LineageState}
pub type LineageRedeemer { action: LineageAction }
validator s0_lineage {
  spend(
    _d: Option<LineageState>,
    _r: LineageRedeemer,
    _s: OutputReference,
    _t: Transaction,
  ) { True }
  else(_x) { fail }
}
EOF
  cat >"$dest/s0_maintenance_escrow.ak" <<'EOF'
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/types.{EscrowAction, EscrowState, EvidenceGrade}
pub type EscrowRedeemer { action: EscrowAction, grade: EvidenceGrade }
validator s0_maintenance_escrow {
  spend(
    _d: Option<EscrowState>,
    _r: EscrowRedeemer,
    _s: OutputReference,
    _t: Transaction,
  ) { True }
  else(_x) { fail }
}
EOF
  cat >"$dest/s0_staging_proof_token.ak" <<'EOF'
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
pub type StagingRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  off_i: Int,
  off_d: Int,
}
validator s0_staging_proof_token {
  mint(_r: StagingRedeemer, _p: PolicyId, _t: Transaction) { True }
  else(_x) { fail }
}
EOF
  cat >"$dest/s0_consumer_predicates.ak" <<'EOF'
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/types.{CursorPolicy, CursorState}
pub type PredicateRedeemer { policy: CursorPolicy }
validator s0_consumer_predicates {
  spend(
    _d: Option<CursorState>,
    _r: PredicateRedeemer,
    _s: OutputReference,
    _t: Transaction,
  ) { True }
  else(_x) { fail }
}
EOF
  cat >"$dest/s0_reference_cursor_consumer.ak" <<'EOF'
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/types.{CursorPolicy}
pub type ReferenceConsumerRedeemer { policy: CursorPolicy, expected_lineage: PolicyId }
validator s0_reference_cursor_consumer {
  spend(
    _d: Option<Data>,
    _r: ReferenceConsumerRedeemer,
    _s: OutputReference,
    _t: Transaction,
  ) { True }
  else(_x) { fail }
}
EOF
}

s0_acquire_token

if [[ "$mode" == self-test ]]; then
  tmp=$(mktemp -d)
  trap 's0_release_token; rm -rf "$tmp"' EXIT INT TERM
  mkdir -p "$tmp/onchain"
  rsync -a --delete \
    --exclude plutus.json \
    "$repo/onchain/" "$tmp/onchain/"
  write_hollow "$tmp/onchain/validators"
  set +e
  s0_run_aiken hollow-check \
    "$evidence_dir/hollow-aiken-check.log" \
    "$evidence_dir/pre-build-avail-bytes.txt" \
    env -C "$tmp/onchain" "$aiken" check -m 's0_skeleton_tests.{..}'
  hollow_rc=$?
  set -e
  if ((hollow_rc == 0)); then
    printf 'S0-REACH-FAIL hollow-handlers-accepted\n' >&2
    exit 35
  fi
  reject_n=0
  for name in "${REQUIRED_TESTS[@]}"; do
    [[ "$name" == reject_* ]] && reject_n=$((reject_n + 1))
  done
  if ! command grep -Fq "${reject_n} failed" "$evidence_dir/hollow-aiken-check.log"; then
    printf 'S0-REACH-FAIL hollow-did-not-fail-reject-tests expected=%s\n' \
      "$reject_n" >&2
    exit 35
  fi
  printf 'S0-REACH-SELF-TEST-PASS hollow_exit=%s\n' "$hollow_rc"
  exit 0
fi

set +e
s0_run_aiken real-check \
  "$evidence_dir/aiken-check.log" \
  "$evidence_dir/pre-build-avail-bytes.txt" \
  env -C "$repo/onchain" "$aiken" check -m 's0_skeleton_tests.{..}'
real_rc=$?
set -e
if ((real_rc != 0)); then
  printf 'S0-REACH-FAIL real-tests-failed exit=%s\n' "$real_rc" >&2
  exit "$real_rc"
fi
for name in "${REQUIRED_TESTS[@]}"; do
  if ! command grep -Eq "$name" "$evidence_dir/aiken-check.log"; then
    printf 'S0-REACH-FAIL test-not-reported name=%s\n' "$name" >&2
    exit 36
  fi
done
printf 'S0-REACH-VERIFY-PASS tests=%d\n' "${#REQUIRED_TESTS[@]}"
