#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
# v4 frozen-gate identity (audit-1 PROVENANCE repair): the runner hashes the
# invoking frozen gate via this variable instead of ambient ignored state.
# Unset/empty keeps the documented direct-owner-run fallback (ignored
# $root/gate.sh resolved inside run.sh); a missing resolved gate fails fast.
export MUTATION_GATE_FILE="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
ledger="$root/lean/SEMANTIC-ATOMS.md"
runner="$root/lean/mutants/run.sh"
work=${MUTATION_GATE_WORK_ROOT:-$(mktemp -d /tmp/keri-365-gate-XXXXXX)}
cleanup=0
if [[ -z ${MUTATION_GATE_WORK_ROOT:-} ]]; then cleanup=1; fi
trap 'if [[ $cleanup == 1 ]]; then rm -rf "$work"; fi' EXIT
mkdir -p "$work"

git diff --check
test -f "$ledger"
test -x "$runner"

# v5 terminal base (NOTE-029): the candidate tree must descend from the exact
epic-owner C1+C2 merged base; fail fast before spending mutation builds.
terminal_base=370a23b64a581c7ad80681700a459372b8005ba9
git merge-base --is-ancestor "$terminal_base" HEAD

# The executable inventory is the runner's declared work extent. Reconcile it
# with the frozen, non-worker-writable ledger before spending mutation builds.
awk -F'|' '/^\| (CP|RG|CG|SM)-[0-9]+ / {
  id=$2; severity=$6; gsub(/^ +| +$/, "", id); gsub(/^ +| +$/, "", severity);
  print "ATOM\t" id "\t" severity
}' "$ledger" | sort > "$work/ledger-atoms.tsv"
awk -F'|' '/^\| TH-[0-9]+ / {
  theorem=$3; gsub(/^ +| +$/, "", theorem); gsub(/`/, "", theorem);
  print "THEOREM\t" theorem
}' "$ledger" | sort > "$work/ledger-theorems.tsv"
test "$(wc -l < "$work/ledger-atoms.tsv")" -eq 79
test "$(wc -l < "$work/ledger-theorems.tsv")" -eq 20
test "$(cut -f1,2 "$work/ledger-atoms.tsv" | sort -u | wc -l)" -eq 79
test "$(cut -f1,2 "$work/ledger-theorems.tsv" | sort -u | wc -l)" -eq 20

# A-001 additive freeze: mappings are supersets, the two new assertions are
# present, and the four concrete AUX sensors remain example-only and sorry-free.
awk -F'|' '$2 ~ /CG-03/ {found=1; ok=($5 ~ /ownerAndHook_trivial_breaks_inv/ && $5 ~ /Mutants.CG03_ownerAndHook_requires_hook/)} END {exit !(found && ok)}' "$ledger"
awk -F'|' '$2 ~ /CG-09/ {found=1; ok=($5 ~ /refundAll_never_locks/ && $5 ~ /Mutants.CG09_refundAll_returns_exact_bond/)} END {exit !(found && ok)}' "$ledger"
grep -Fx $'THEOREM\tMutants.CG03_ownerAndHook_requires_hook' "$work/ledger-theorems.tsv"
grep -Fx $'THEOREM\tMutants.CG09_refundAll_returns_exact_bond' "$work/ledger-theorems.tsv"
test "$(find "$root/lean/mutants/sensors" -maxdepth 1 -name 'AUX-TH*.sensor.lean' -type f | wc -l)" -eq 4
if grep -REq '^[[:space:]]*theorem |(^|[^A-Za-z])sorry([^A-Za-z]|$)' "$root/lean/mutants/sensors"; then
  echo "gate: sensors must be example-only and sorry-free" >&2
  exit 1
fi

# v4: 300s admits a genuinely cold worktree (measured 15s end-to-end cold
# --list: ~8s module build + nix/lean startup per invocation across the build,
# inventory, and additive legs); only this list timeout changed for cold
# acceptance.
timeout 300 "$runner" --list > "$work/runner-inventory.tsv"
"$runner" --check-witness Mutants.CG03_ownerAndHook_requires_hook "$root/lean/mutants/witnesses/TH-19.lean"
"$runner" --check-witness Mutants.CG09_refundAll_returns_exact_bond "$root/lean/mutants/witnesses/TH-20.lean"
awk -F'\t' '$1=="ATOM" { print $1 "\t" $2 "\t" $3 }' "$work/runner-inventory.tsv" | sort > "$work/runner-atoms.tsv"
awk -F'\t' '$1=="THEOREM" { print $1 "\t" $2 }' "$work/runner-inventory.tsv" | sort > "$work/runner-theorems.tsv"
diff -u "$work/ledger-atoms.tsv" "$work/runner-atoms.tsv"
diff -u "$work/ledger-theorems.tsv" "$work/runner-theorems.tsv"

"$runner" --run "$work/campaign"
summary="$work/campaign/summary.tsv"
test -s "$summary"
test "$(awk -F'\t' '$1=="ATOM" && $3=="KILLED" {n++} END {print n+0}' "$summary")" -eq 79
test "$(awk -F'\t' '$1=="THEOREM" && $3=="REACHED" && $4=="KILLED" {n++} END {print n+0}' "$summary")" -eq 20
grep -P '^THEOREM\tMutants\.CG03_ownerAndHook_requires_hook\tREACHED\tKILLED\t' "$summary"
grep -P '^THEOREM\tMutants\.CG09_refundAll_returns_exact_bond\tREACHED\tKILLED\t' "$summary"
grep -Fx $'CONTROL\tidentity\tSURVIVED' "$summary"
grep -Fx $'TOTAL\tatoms\t79\t79' "$summary"
grep -Fx $'TOTAL\ttheorems\t20\t20' "$summary"
grep -Fx $'EXCLUDED\twrong-reason\t0' "$summary"
grep -Fx $'BLOCKED\t0' "$summary"
grep -Fx $'STOP\tfrozen-ledger' "$summary"
awk -F'\t' '$1=="BUDGET" {found=1; ok=($2=="builds_spent" && $3<=210 && $4=="budget" && $5==210)} END {exit !(found && ok)}' "$summary"
test -f "$work/campaign/prepost.diff"
test ! -s "$work/campaign/prepost.diff"

cmp "$work/campaign/receipts/CHECKPOINT-MUTANTS.md" "$root/lean/CHECKPOINT-MUTANTS.md"
cmp "$work/campaign/receipts/REGISTRY-MUTANTS.md" "$root/lean/REGISTRY-MUTANTS.md"

# v5 terminal receipts: generated receipts must name the exact merged base.
# Falsification: a receipt still carrying the pending-premerge template fails.
grep -Fq 'Terminal merged base: 370a23b64a581c7ad80681700a459372b8005ba9' "$work/campaign/receipts/CHECKPOINT-MUTANTS.md"
grep -Fq 'Terminal merged base: 370a23b64a581c7ad80681700a459372b8005ba9' "$work/campaign/receipts/REGISTRY-MUTANTS.md"

# The campaign must produce its axiom account from a clean .lake and reject
# every escape axiom. The full build remains an independent final leg.
test -s "$work/campaign/axioms.log"
if grep -q 'sorryAx' "$work/campaign/axioms.log"; then
  echo "gate: sorryAx present in clean campaign axiom account" >&2
  exit 1
fi
(cd "$root/lean" && nix shell --no-write-lock-file ../offchain#lean --command lake build)

# Running in the authoritative tree may update no input. Deterministic tracked
# receipts were already compared byte-for-byte with the isolated regeneration.
git diff --check
echo "gate: GREEN atoms=79/79 theorem_rows=20/20 identity=SURVIVED wrong_reason=0 blocked=0"
