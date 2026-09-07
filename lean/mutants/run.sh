#!/usr/bin/env bash
# Issue 365 semantic-atom mutation campaign.
#
# Required CLI (gate-v2):
#   lean/mutants/run.sh --list          emits TSV `ATOM <id> <severity>` + `THEOREM <qualified-name>`
#   lean/mutants/run.sh --run <campaign-dir>
#     emits <campaign-dir>/summary.tsv, <campaign-dir>/axioms.log,
#           <campaign-dir>/receipts/{CHECKPOINT-MUTANTS.md,REGISTRY-MUTANTS.md}
#
# Inventory is derived from the frozen ledger `lean/SEMANTIC-ATOMS.md` and
# dynamically from compiled Cage/Samaritan theorem declarations. Refuses
# missing, duplicate, unexpected members and empty extents.
#
# Each counted mutant applies exactly one intended production edit in an
# isolated copy, compiles the model/module first, reaches a named owning
# theorem/witness, and fails for its semantic reason. Syntax/import/setup/
# sorryAx crashes and unrelated downstream failures are excluded, never
# counted. Identity control must survive. Structural discounts are named
# globally and per affected row. Equivalent/shadowed mutants are replaced or
# leave the row BLOCKED, never counted as killed.
#
# Operator set (finite, frozen): guard relax/delete, liveness force-false,
# evidence swap, effect omit/retain/stale/swap/misdirect, refusal/terminal/
# composition edge remove/invent, one-sided correspondence break.
# Stopping reason: frozen-ledger (one right-reason kill per atom row + one
# witness/kill per theorem row). Honest limit: finite declared fault model,
# not a claim of zero possible survivors.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
if ! ROOT=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null); then ROOT=$(cd "$HERE/../.." && pwd); fi
LEAN="$ROOT/lean"
LEDGER="$LEAN/SEMANTIC-ATOMS.md"
SPEC="$HERE/mutants.txt"
WITDIR="$HERE/witnesses"
# Lean toolchain must match gate-v2 final leg.
LAKE=(nix shell --no-write-lock-file "$ROOT/offchain#lean" --command lake)
STRUCTURAL="T7_step_iff_stepFn T9_juvenility_is_consumer_only"
OPERATORS="guard-relax/delete liveness-force-false evidence-swap effect-omit/retain/stale/swap/misdirect refusal/terminal/composition-edge-remove/invent one-sided-correspondence-break"

ledger_atoms() {
  awk -F'|' '/^\| (CP|RG|CG|SM)-[0-9]+ / {
    id=$2; sev=$6; gsub(/^ +| +$/, "", id); gsub(/^ +| +$/, "", sev);
    print "ATOM\t" id "\t" sev
  }' "$LEDGER" | sort
}

ledger_theorems() {
  awk -F'|' '/^\| TH-[0-9]+ / {
    th=$3; gsub(/^ +| +$/, "", th); gsub(/`/, "", th);
    print "THEOREM\t" th
  }' "$LEDGER" | sort
}

discovered_theorems() {
  {
    grep -h '^theorem ' "$LEAN/CardanoKeri/Cage.lean" | sed -E 's/^theorem ([A-Za-z0-9_]+).*/THEOREM\tCage.\1/'
    grep -h '^theorem ' "$LEAN/CardanoKeri/Samaritan.lean" | sed -E 's/^theorem ([A-Za-z0-9_]+).*/THEOREM\tSamaritan.\1/'
    grep -h '^theorem ' "$WITDIR/TH-19.lean" | sed -E 's/^theorem ([A-Za-z0-9_]+).*/THEOREM\tMutants.\1/'
    grep -h '^theorem ' "$WITDIR/TH-20.lean" | sed -E 's/^theorem ([A-Za-z0-9_]+).*/THEOREM\tMutants.\1/'
  } | sort
}

cmd_list() {
  test -f "$LEDGER" || { echo "run.sh --list: missing ledger $LEDGER" >&2; exit 1; }
  tmp=$(mktemp -d /tmp/keri-365-list-XXXXXX)
  trap 'rm -rf "$tmp"' EXIT
  ledger_atoms > "$tmp/ledger-atoms.tsv"
  ledger_theorems > "$tmp/ledger-theorems.tsv"
  discovered_theorems > "$tmp/discovered-theorems.tsv"
  # Refuse empty extents.
  test "$(wc -l < "$tmp/ledger-atoms.tsv")" -eq 79 || { echo "run.sh --list: ledger atoms != 79" >&2; cat "$tmp/ledger-atoms.tsv" >&2; exit 1; }
  test "$(wc -l < "$tmp/ledger-theorems.tsv")" -eq 20 || { echo "run.sh --list: ledger theorems != 20" >&2; exit 1; }
  test "$(wc -l < "$tmp/discovered-theorems.tsv")" -eq 20 || { echo "run.sh --list: discovered theorems != 20" >&2; cat "$tmp/discovered-theorems.tsv" >&2; exit 1; }
  # Refuse duplicates.
  test "$(cut -f2 "$tmp/ledger-atoms.tsv" | sort -u | wc -l)" -eq 79 || { echo "run.sh --list: duplicate atom IDs" >&2; exit 1; }
  test "$(cut -f2 "$tmp/ledger-theorems.tsv" | sort -u | wc -l)" -eq 20 || { echo "run.sh --list: duplicate theorems" >&2; exit 1; }
  # Refuse drift between ledger and compiled declarations (Cage/Samaritan + Mutants additive).
  if ! diff -u "$tmp/ledger-theorems.tsv" "$tmp/discovered-theorems.tsv" >&2; then
    echo "run.sh --list: ledger theorems drift from compiled Cage/Samaritan+Mutants declarations" >&2
    exit 1
  fi
  # Cold-worktree acceptance (audit-1 PROVENANCE finding): establish the
  # compiled modules this list needs before the #check inventory. Never rely
  # on owner-warmed oleans; the compiled-declaration check below is retained.
  if ! (cd "$LEAN" && nix shell --no-write-lock-file "$ROOT/offchain#lean" --command lake build CardanoKeri.CheckpointGoals CardanoKeri.RegistryGoals CardanoKeri.Cage CardanoKeri.Samaritan > "$tmp/list-build.log" 2>&1); then
    echo "run.sh --list: build of compiled modules failed (a cold worktree builds its own oleans first)" >&2
    cat "$tmp/list-build.log" >&2
    exit 1
  fi
  # Compiled-declaration reconciliation: every Cage/Samaritan theorem must #check.
  # A spelling-only row (grep match in a comment, stale name) may not close this.
  {
    echo "import CardanoKeri.Cage"
    echo "import CardanoKeri.Samaritan"
    cut -f2 "$tmp/discovered-theorems.tsv" | grep -E '^(Cage|Samaritan)\.' | while read -r th; do
      echo "#check CardanoKeri.$th"
    done
  } > "$tmp/InventoryCheck.lean"
  if ! (cd "$LEAN" && nix shell --no-write-lock-file "$ROOT/offchain#lean" --command lake env lean "$tmp/InventoryCheck.lean" > "$tmp/inventory-check.log" 2>&1); then
    echo "run.sh --list: compiled #check inventory failed (spelling-only or unknown declaration)" >&2
    cat "$tmp/inventory-check.log" >&2
    exit 1
  fi
  # Additive assertions live under owned witnesses/; they must compile clean.
  if ! (cd "$LEAN" && nix shell --no-write-lock-file "$ROOT/offchain#lean" --command lake env lean "$WITDIR/TH-19.lean" > "$tmp/additive-19.log" 2>&1); then
    echo "run.sh --list: additive TH-19 clean compile failed" >&2
    cat "$tmp/additive-19.log" >&2
    exit 1
  fi
  if ! (cd "$LEAN" && nix shell --no-write-lock-file "$ROOT/offchain#lean" --command lake env lean "$WITDIR/TH-20.lean" > "$tmp/additive-20.log" 2>&1); then
    echo "run.sh --list: additive TH-20 clean compile failed" >&2
    cat "$tmp/additive-20.log" >&2
    exit 1
  fi
  cat "$tmp/ledger-atoms.tsv"
  cat "$tmp/ledger-theorems.tsv"
  rm -rf "$tmp"
  trap - EXIT
}

# --- helpers for --run ---
count_needle() { # needle-file target-file -> count
  perl -0777 -e 'local $/; open(N,"<",$ARGV[0]); my $n=<N>; open(F,"<",$ARGV[1]); my $s=<F>; my $c=()=$s=~/\Q$n\E/g; print $c' "$1" "$2"
}
apply_needle() { # needle repl target
  perl -0777 -i -e 'local $/; open(N,"<",$ARGV[0]); my $n=<N>; open(R,"<",$ARGV[1]); my $r=<R>; my $f=$ARGV[2]; open(F,"<",$f); my $s=<F>; close F; $s =~ s/\Q$n\E/$r/; open(O,">",$f); print O $s; close O' "$1" "$2" "$3"
}

# Parse mutants.txt into $work/specs/: each record
#   ### <mutant-id> | <desc> [| atom=<ATOM>] [| theorem=TH-XX]
#   @@@ <Module>
#   <<<
#   needle
#   >>>
#   replacement
# Emits per-mutant .spec (desc, module, atom, theorem-throw), .needle, .repl.
# Atom specs (atom=CP/RG/CG/SM) count toward 79; AUX theorem-row sensitivity
# specs (theorem=TH-XX, no atom) count only toward their theorem row (e.g., TH-06).
parse_specs() {
  local work=$1
  mkdir -p "$work/specs"
  rm -f "$work/specs"/*.spec "$work/specs"/*.needle "$work/specs"/*.repl 2>/dev/null || true
  perl -0ne '
    while (/^### (\S+) \| ([^\n]*)\n\@\@\@ (\S+)\n<<<\n(.*?)\n>>>\n(.*?)(?=\n### |\z)/smg) {
      my ($n,$d,$f,$a,$b)=($1,$2,$3,$4,$5); $b =~ s/\n\z//;
      my $atom = "";
      if ($d =~ /atom\s*=\s*((?:CP|RG|CG|SM)-[0-9]+)/) { $atom = $1; }
      my $throw = "";
      if ($d =~ /theorem\s*=\s*(TH-[0-9]+)/) { $throw = $1; }
      open(O,">","'"$work"'/specs/$n.spec"); print O "$d\n$f\n$atom\n$throw\n"; close O;
      open(O,">","'"$work"'/specs/$n.needle"); print O $a; close O;
      open(O,">","'"$work"'/specs/$n.repl"); print O $b; close O;
    }' "$SPEC"
}

# Map atom -> mutant (first spec claiming that atom). Prints warnings for dupes.
# AUX theorem specs (atom empty, theorem=TH-XX) are ignored here; see aux map below.
atom_mutant_map() {
  local work=$1
  : > "$work/atom-map.tsv"
  for spec in "$work"/specs/*.spec; do
    [ -e "$spec" ] || continue
    n=$(basename "$spec" .spec)
    atom=$(sed -n 3p "$spec")
    [ -n "$atom" ] || continue
    if grep -q "^$atom	" "$work/atom-map.tsv" 2>/dev/null; then
      echo "WARN duplicate mutant for $atom: $n (first wins)" >> "$work/campaign.log"
    else
      printf '%s\t%s\n' "$atom" "$n" >> "$work/atom-map.tsv"
    fi
  done
  sort -o "$work/atom-map.tsv" "$work/atom-map.tsv"
}

# Map theorem throw (TH-XX) -> AUX sensitivity mutant (first spec with theorem=TH-XX, no atom).
# AUX mutants obey exact-edit/model-compile/wrong-reason/provenance like atoms
# but count only toward their theorem row, never toward 79 atoms.
aux_mutant_map() {
  local work=$1
  : > "$work/aux-map.tsv"
  for spec in "$work"/specs/*.spec; do
    [ -e "$spec" ] || continue
    n=$(basename "$spec" .spec)
    atom=$(sed -n 3p "$spec"); throw=$(sed -n 4p "$spec")
    [ -z "$atom" ] || continue
    [ -n "$throw" ] || continue
    if grep -q "^$throw	" "$work/aux-map.tsv" 2>/dev/null; then
      echo "WARN duplicate AUX mutant for $throw: $n (first wins)" >> "$work/campaign.log"
    else
      printf '%s\t%s\n' "$throw" "$n" >> "$work/aux-map.tsv"
    fi
  done
  sort -o "$work/aux-map.tsv" "$work/aux-map.tsv"
}

# Witness validation (RECOVERY-021): factored canonical/non-vacuous check.
# Args: <ledger-name> <file> where ledger-name is e.g. Cage.applyBatch_delegated_eq.
#   rc 0: valid (no diagnostic on either stream).
#   rc 1: trivial/reflexive witness (example True or := by rfl), diagnostic WITNESS-NONVACUOUS.
#   rc 2: absent exact canonical CardanoKeri.<ledger-name> on an example line,
#          diagnostic WITNESS-EXACT-MISSING.
#   rc 3: missing witness file, diagnostic WITNESS-MISSING.
validate_witness() {
  local ledger_name=$1 wit=$2
  local canonical="CardanoKeri.$ledger_name"
  if [ ! -f "$wit" ]; then
    echo "WITNESS-MISSING $wit: no such witness file" >&2
    return 3
  fi
  if grep -Eq '^example[[:space:]]*:[[:space:]]*True([[:space:]]|:=)|^example.*:= *by +rfl' "$wit"; then
    echo "WITNESS-NONVACUOUS $wit: trivial witness (example True or := by rfl)" >&2
    return 1
  fi
  if grep -Eq '(^|[^A-Za-z])sorry([^A-Za-z]|$)' "$wit"; then
    echo "WITNESS-NONVACUOUS $wit: sorry is forbidden" >&2
    return 1
  fi
  if ! awk -v T="$canonical" '
      /^example[[:space:]]*:/ { in_example=1 }
      in_example && index($0,T) { found=1 }
      in_example && /^(def|theorem|namespace|end)[[:space:]]/ { in_example=0 }
      END { exit !found }
    ' "$wit"; then
    echo "WITNESS-EXACT-MISSING $wit: exact theorem application missing ($canonical not in an example declaration)" >&2
    return 2
  fi
  return 0
}

cmd_check_witness() {
  validate_witness "$1" "$2"
}

# Axiom acceptance predicate (NOTE-023): exact theorem account, zero sorryAx.
# Args: <expected> <observed> <sorry_count>.
#   rc 0: accepted (no diagnostic on either stream).
#   rc 1: sorryAx present, diagnostic AXIOMS-SORRY.
#   rc 2: account mismatch, diagnostic AXIOMS-ACCOUNT.
check_axioms() {
  local expected=$1 observed=$2 sorry=$3
  if [ "$sorry" != "0" ]; then
    echo "AXIOMS-SORRY observed=$observed sorryAx=$sorry (requires zero sorryAx)" >&2
    return 1
  fi
  if [ "$observed" != "$expected" ]; then
    echo "AXIOMS-ACCOUNT expected=$expected observed=$observed (requires exact account)" >&2
    return 2
  fi
  return 0
}

cmd_check_axioms() {
  check_axioms "$1" "$2" "$3"
}

thmlines_for() { # goals-file -> thmlines file
  awk '/^theorem /{split($2,a," "); print NR, a[1]}' "$1" > "$2"
}
names_for_lines() { # thmlines-file, reads line numbers on stdin
  local thmlines=$1
  while read -r ln; do
    awk -v L="$ln" '$1<=L{n=$2} END{print n}' "$thmlines"
  done | sort -u | tr '\n' ' '
}

cmd_run() {
  local campaign=$1
  mkdir -p "$campaign/receipts"
  local log="$campaign/raw.log"
  : > "$log"
  say() { echo "$*" | tee -a "$log"; }
  local head_sha
  head_sha=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
  local ledger_hash runner_hash spec_hash
  ledger_hash=$(sha256sum "$LEDGER" | cut -d' ' -f1)
  runner_hash=$(sha256sum "$HERE/run.sh" | cut -d' ' -f1)
  spec_hash=$(sha256sum "$SPEC" | cut -d' ' -f1)
  local started
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  say "CAMPAIGN $started source=$head_sha ledger=$ledger_hash runner=$runner_hash spec=$spec_hash"
  say "OPERATORS $OPERATORS"
  say "DISCOUNT structural theorems, never counted as a kill: $STRUCTURAL"
  say "STOPPING frozen-ledger: one right-reason kill per 79 atom rows + one witness/kill per 20 theorem rows"

  # Frozen-gate provenance (audit-1 PROVENANCE finding): the invoking frozen
  # gate identifies itself via MUTATION_GATE_FILE; direct owner runs fall back
  # to the ignored root gate.sh (documented). A missing resolved gate fails
  # fast here; drift across the run is caught by the pre/post identity check.
  if [ -n "${MUTATION_GATE_FILE:-}" ]; then
    gate_file="$MUTATION_GATE_FILE"
  else
    gate_file="$ROOT/gate.sh"
  fi
  if [ ! -f "$gate_file" ]; then
    say "GATE-MISSING resolved gate not found: $gate_file (invoke via a frozen gate exporting MUTATION_GATE_FILE, or provide ignored $ROOT/gate.sh for direct owner runs)"
    return 1
  fi
  gate_hash=$(sha256sum "$gate_file" | cut -d' ' -f1)
  say "GATE resolved=$gate_file sha256=$gate_hash"

  # Work copy with build cache for incremental mutant builds.
  local wlean="$campaign/work-lean"
  rm -rf "$wlean"
  mkdir -p "$wlean"
  cp -r "$LEAN/." "$wlean/"
  # Baseline: authoritative tree must build (counts toward budget).
  local builds_spent=0
  BUDGET_MAX="${BUDGET_MAX:-210}"
  if [ "$BUDGET_MAX" -gt 210 ]; then say "BUDGET_MAX $BUDGET_MAX above hard ceiling 210; clamping to 210"; BUDGET_MAX=210; fi
  lean_run() {
    local wd=$1; shift
    local lf=$1; shift
    if [ "$builds_spent" -ge "$BUDGET_MAX" ]; then
      say "BUDGET-EXHAUSTED builds_spent=$builds_spent budget=$BUDGET_MAX refusing next Lean invocation ($*)"
      return 2
    fi
    builds_spent=$((builds_spent+1))
    if (cd "$wd" && "${LAKE[@]}" "$@" > "$lf" 2>&1); then
      return 0
    else
      return 1
    fi
  }
  say "BASELINE build on authoritative tree (budget max $BUDGET_MAX)"
  baseline_ok=0; axioms_ok=0
  if lean_run "$LEAN" "$campaign/baseline-build.log" build; then
    say "BASELINE green builds_spent=$builds_spent"
    baseline_ok=1
  else
    rc=$?; if [ "$rc" = "2" ]; then say "BASELINE REFUSED budget-exhausted (no invocation, builds_spent=$builds_spent)"; else say "BASELINE FAILED (see baseline-build.log) builds_spent=$builds_spent"; fi
  fi

  parse_specs "$campaign"
  atom_mutant_map "$campaign"
  aux_mutant_map "$campaign"

  # Pre-run hashes of authoritative inputs (CLEAN proof; Fix6). No wall time/HEAD (deterministic file hashes only).
  {
    sha256sum "$LEDGER"
    sha256sum "$gate_file"
    sha256sum "$LEAN/CardanoKeri/Checkpoint.lean"
    sha256sum "$LEAN/CardanoKeri/CheckpointGoals.lean"
    sha256sum "$LEAN/CardanoKeri/Registry.lean"
    sha256sum "$LEAN/CardanoKeri/RegistryGoals.lean"
    sha256sum "$LEAN/CardanoKeri/Cage.lean"
    sha256sum "$LEAN/CardanoKeri/Samaritan.lean"
    sha256sum "$HERE/run.sh"
    sha256sum "$SPEC"
  } > "$campaign/pre-hashes.tsv"
  if [ -d "$WITDIR" ]; then find "$WITDIR" -type f | sort | xargs sha256sum >> "$campaign/pre-hashes.tsv"; fi
  if [ -d "$HERE/sensors" ]; then find "$HERE/sensors" -type f | sort | xargs sha256sum >> "$campaign/pre-hashes.tsv"; fi

  # Ledger inventories (sorted).
  ledger_atoms | cut -f2 > "$campaign/ledger-atom-ids.txt"
  ledger_theorems | cut -f2 > "$campaign/ledger-theorem-names.txt"

  # Theorem line maps for attribution.
  thmlines_for "$LEAN/CardanoKeri/CheckpointGoals.lean" "$campaign/thmlines-checkpoint.txt"
  thmlines_for "$LEAN/CardanoKeri/RegistryGoals.lean" "$campaign/thmlines-registry.txt"
  # Cage/Samaritan theorems live in their own files; attribute by file+line.
  grep -n '^theorem ' "$LEAN/CardanoKeri/Cage.lean" | sed -E 's/^([0-9]+):theorem ([A-Za-z0-9_]+).*/\1 \2/' > "$campaign/thmlines-cage.txt"
  grep -n '^theorem ' "$LEAN/CardanoKeri/Samaritan.lean" | sed -E 's/^([0-9]+):theorem ([A-Za-z0-9_]+).*/\1 \2/' > "$campaign/thmlines-samaritan.txt"

  restore_all() {
    cp "$LEAN/CardanoKeri/Checkpoint.lean" "$wlean/CardanoKeri/Checkpoint.lean"
    cp "$LEAN/CardanoKeri/CheckpointGoals.lean" "$wlean/CardanoKeri/CheckpointGoals.lean"
    cp "$LEAN/CardanoKeri/Registry.lean" "$wlean/CardanoKeri/Registry.lean"
    cp "$LEAN/CardanoKeri/RegistryGoals.lean" "$wlean/CardanoKeri/RegistryGoals.lean"
    cp "$LEAN/CardanoKeri/Cage.lean" "$wlean/CardanoKeri/Cage.lean"
    cp "$LEAN/CardanoKeri/Samaritan.lean" "$wlean/CardanoKeri/Samaritan.lean"
  }

  # Identity control: first spec needle with replacement = needle.
  local first_spec
  first_spec=$(ls "$campaign"/specs/*.spec 2>/dev/null | sort | head -n 1 || true)
  local control_result="MISSING"
  if [ -n "$first_spec" ]; then
    n=$(basename "$first_spec" .spec)
    cp "$campaign/specs/$n.needle" "$campaign/M0.needle"
    cp "$campaign/M0.needle" "$campaign/M0.repl"
    # Identity uses Checkpoint module of first spec if Checkpoint else its own module.
    mod=$(sed -n 2p "$first_spec")
    restore_all
    # No edit (needle=replacement would be no-op); verify clean work copy builds goals.
    if lean_run "$wlean" "$campaign/M0.model.log" build CardanoKeri.Checkpoint CardanoKeri.Registry CardanoKeri.Cage CardanoKeri.Samaritan; then
      if lean_run "$wlean" "$campaign/M0.goals.log" build CardanoKeri.CheckpointGoals CardanoKeri.RegistryGoals CardanoKeri.Cage CardanoKeri.Samaritan; then
        say "CONTROL M0-identity-control: SURVIVED as the control must (needle = replacement; the instrument reports a survivor)"
        control_result="SURVIVED"
      else
        rc=$?; if [ "$rc" = "2" ]; then say "CONTROL M0-identity-control: REFUSED budget-exhausted (no invocation)"; control_result="FAILED"; else say "CONTROL M0-identity-control: FAILED — the instrument reds an unchanged model; the campaign is void"; control_result="FAILED"; fi
      fi
    else
      rc=$?; if [ "$rc" = "2" ]; then say "CONTROL M0-identity-control: REFUSED budget-exhausted (no invocation)"; control_result="FAILED"; else say "CONTROL M0-identity-control: FAILED — clean work copy does not build"; control_result="FAILED"; fi
    fi
  else
    say "CONTROL M0-identity-control: MISSING — no mutant specs to derive identity needle"
    control_result="MISSING"
  fi

  # Per-atom campaign.
  : > "$campaign/atom-results.tsv"
  local atoms_killed=0 atoms_total=79 blocked=0 excluded_wrong=0
  while read -r atom; do
    mut=$(awk -v A="$atom" -F'\t' '$1==A{print $2}' "$campaign/atom-map.tsv" || true)
    if [ -z "$mut" ]; then
      printf 'ATOM\t%s\tBLOCKED\t-\tmissing-spec\n' "$atom" >> "$campaign/atom-results.tsv"
      say "$atom: BLOCKED missing mutant spec"
      blocked=$((blocked+1))
      continue
    fi
    spec="$campaign/specs/$mut.spec"
    desc=$(sed -n 1p "$spec"); mod=$(sed -n 2p "$spec")
    needle="$campaign/specs/$mut.needle"; repl="$campaign/specs/$mut.repl"
    target="$wlean/CardanoKeri/$mod.lean"
    if [ ! -f "$target" ]; then
      printf 'ATOM\t%s\tBLOCKED\t%s\tunknown-module-%s\n' "$atom" "$mut" "$mod" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): BLOCKED unknown module $mod"
      blocked=$((blocked+1))
      continue
    fi
    restore_all
    c=$(count_needle "$needle" "$target")
    if [ "$c" != "1" ]; then
      printf 'ATOM\t%s\tBLOCKED\t%s\tneedle-count-%s\n' "$atom" "$mut" "$c" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): BLOCKED needle applies $c times (need exactly 1)"
      blocked=$((blocked+1))
      continue
    fi
    # Bind applied blob hash for provenance.
    apply_needle "$needle" "$repl" "$target"
    applied_hash=$(sha256sum "$target" | cut -d' ' -f1)
    # Model/module compile leg depends on target.
    model_ok=0; goals_ok=0; failing=""; discounted=""
    case "$mod" in
      Checkpoint)
        if lean_run "$wlean" "$campaign/$mut.model.log" build CardanoKeri.Checkpoint; then model_ok=1; else rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before model invocation)"; blocked=$((blocked+1)); continue; fi; fi
        if [ "$model_ok" = "1" ]; then
          if lean_run "$wlean" "$campaign/$mut.goals.log" build CardanoKeri.CheckpointGoals; then goals_ok=1; else rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before goals invocation)"; blocked=$((blocked+1)); continue; fi; fi
          if [ "$goals_ok" = "0" ]; then
            failing_lines=$(grep -oE 'error: CardanoKeri/CheckpointGoals\.lean:[0-9]+:[0-9]+' "$campaign/$mut.goals.log" | cut -d: -f3 || true)
            failing=$(echo "$failing_lines" | names_for_lines "$campaign/thmlines-checkpoint.txt")
          fi
        fi
        ;;
      Registry)
        if lean_run "$wlean" "$campaign/$mut.model.log" build CardanoKeri.Registry; then model_ok=1; else rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before model invocation)"; blocked=$((blocked+1)); continue; fi; fi
        if [ "$model_ok" = "1" ]; then
          # Registry mutants are observed via RegistryGoals and Cage (which instantiates Registry).
          if lean_run "$wlean" "$campaign/$mut.goals.log" build CardanoKeri.RegistryGoals CardanoKeri.Cage; then goals_ok=1; else rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before goals invocation)"; blocked=$((blocked+1)); continue; fi; fi
          if [ "$goals_ok" = "0" ]; then
            failing_reg=$(grep -oE 'error: CardanoKeri/RegistryGoals\.lean:[0-9]+:[0-9]+' "$campaign/$mut.goals.log" | cut -d: -f3 | names_for_lines "$campaign/thmlines-registry.txt" || true)
            failing_cage_lines=$(grep -oE 'error: CardanoKeri/Cage\.lean:[0-9]+:[0-9]+' "$campaign/$mut.goals.log" | cut -d: -f3 || true)
            failing_cage=""
            if [ -n "$failing_cage_lines" ]; then
              failing_cage=$(for ln in $failing_cage_lines; do awk -v L="$ln" '$1<=L{n=$2} END{print n}' "$campaign/thmlines-cage.txt"; done | sort -u | tr '\n' ' ')
            fi
            failing="$failing_reg $failing_cage"
          fi
        fi
        ;;
      Cage|Samaritan)
        # Monolithic modules: compile a generated model-only prefix (mutated defs
        # with theorems stubbed to `example : True`) before the full
        # theorem-bearing module. Only the second leg may be RED; syntax/import/
        # definition errors in the first leg are wrong-reason.
        awk '
          /^theorem / { print "example : True := trivial"; skip=1; next }
          skip && /^(def |theorem |instance |structure |inductive |abbrev |end |namespace |open |import |\/-!|--|#)/ { skip=0 }
          !skip
        ' "$target" > "$wlean/ModelOnlyCheck.lean"
        if lean_run "$wlean" "$campaign/$mut.modelonly.log" env lean ModelOnlyCheck.lean; then
          model_ok=1
          # NOTE-025 additive leg for CG-03/CG-09: prefix passed, so append the
          # exact additive assertion and recompile the same file as the second
          # leg (replaces full Cage build, same 2-build budget). Any non-sorry
          # failure is the exact additive token.
          if [ "$atom" = "CG-03" ] || [ "$atom" = "CG-09" ]; then
            additive_start=$(( $(wc -l < "$wlean/ModelOnlyCheck.lean") + 1 ))
            if [ "$atom" = "CG-03" ]; then
              cat >> "$wlean/ModelOnlyCheck.lean" <<'EOF'
namespace CardanoKeri.Mutants
open CardanoKeri.Cage
theorem CG03_ownerAndHook_requires_hook : authorized .ownerAndHook ⟨true, false⟩ = false := by decide
end CardanoKeri.Mutants
EOF
              additive_token="Mutants.CG03_ownerAndHook_requires_hook"
            else
              cat >> "$wlean/ModelOnlyCheck.lean" <<'EOF'
namespace CardanoKeri.Mutants
open CardanoKeri.Cage
open CardanoKeri.Registry
theorem CG09_refundAll_returns_exact_bond (p : Params) (acc : Acc) (r : Request) (acc'' : Acc) :
    (routeValue .refundAll p acc r acc'').refunds = acc.refunds ++ [(r.owner, r.op.bond p)] := by
  simp [routeValue]
end CardanoKeri.Mutants
EOF
              additive_token="Mutants.CG09_refundAll_returns_exact_bond"
            fi
            if lean_run "$wlean" "$campaign/$mut.model.log" env lean ModelOnlyCheck.lean; then
              goals_ok=1; failing=""
            else
              rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before additive invocation)"; blocked=$((blocked+1)); continue; fi
              goals_ok=0
              if grep -q 'sorryAx' "$campaign/$mut.model.log"; then
                failing="SORRYAX"
              elif grep -qE 'unknown (package|identifier)|failed to import|syntax error|unexpected' "$campaign/$mut.model.log"; then
                failing="WRONG-REASON"
              elif grep -oE 'ModelOnlyCheck\.lean:[0-9]+:[0-9]+' "$campaign/$mut.model.log" | cut -d: -f2 | awk -v S="$additive_start" '$1 >= S {found=1} END{exit !found}'; then
                failing="$additive_token"
              else
                failing="WRONG-REASON"
              fi
            fi
          elif lean_run "$wlean" "$campaign/$mut.model.log" build "CardanoKeri.$mod"; then
            goals_ok=1; failing=""
          else
            rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before full invocation)"; blocked=$((blocked+1)); continue; fi
            goals_ok=0
            failing_lines=$(grep -oE "error: CardanoKeri/$mod\.lean:[0-9]+:[0-9]+" "$campaign/$mut.model.log" | cut -d: -f3 || true)
            failing=""
            if [ -n "$failing_lines" ]; then
              failing=$(for ln in $failing_lines; do awk -v L="$ln" '$1<=L{n=$2} END{print n}' "$campaign/thmlines-$(echo "$mod" | tr 'A-Z' 'a-z').txt"; done | sort -u | tr '\n' ' ')
            fi
            if grep -q 'sorryAx' "$campaign/$mut.model.log"; then
              failing="SORRYAX"
            elif [ -z "${failing// /}" ]; then
              if grep -qE 'unknown (package|identifier)|failed to import|syntax error|unexpected' "$campaign/$mut.model.log"; then
                failing="WRONG-REASON"
              fi
            fi
          fi
        else
          rc=$?; if [ "$rc" = "2" ]; then printf 'ATOM\t%s\tBLOCKED\t%s\tbudget-exhausted\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"; say "$atom ($mut): BLOCKED budget-exhausted (refused before modelonly)"; blocked=$((blocked+1)); continue; fi
          model_ok=0; goals_ok=0; failing="MODEL-FAIL"
          # Model-only failed: mutated defs do not elaborate (syntax/definition).
        fi
        ;;
      *)
        say "$atom ($mut): BLOCKED unknown module $mod"
        printf 'ATOM\t%s\tBLOCKED\t%s\tunknown-module\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"
        blocked=$((blocked+1))
        continue
        ;;
    esac
    # Classify.
    if [ "$model_ok" != "1" ]; then
      # For Checkpoint/Registry, model must compile; else wrong-reason.
      printf 'ATOM\t%s\tEXCLUDED\t%s\tmodel-compile-fail\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): EXCLUDED wrong-reason (mutated model does not compile; blob=$applied_hash)"
      excluded_wrong=$((excluded_wrong+1))
      continue
    fi
    if [ "$goals_ok" = "1" ]; then
      printf 'ATOM\t%s\tSURVIVED\t%s\tgoals-still-build\n' "$atom" "$mut" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): SURVIVED (goals still build) — $desc"
      continue
    fi
    # Goals red: separate structural vs counted.
    counted=""; disc=""
    for t in $failing; do
      case " $STRUCTURAL " in *" $t "*) disc="$disc $t";; *) counted="$counted $t";; esac
    done
    # Cage/Samaritan broad correspondence mirrors are structural for atom
    # attribution when a specific owning theorem also reds; name them per row
    # but never count them alone. (Handled by requiring non-empty counted.)
    if [ "$failing" = "SORRYAX" ] || [ "$failing" = "WRONG-REASON" ]; then
      printf 'ATOM\t%s\tEXCLUDED\t%s\t%s\n' "$atom" "$mut" "$failing" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): EXCLUDED wrong-reason ($failing)"
      excluded_wrong=$((excluded_wrong+1))
      continue
    fi
    if [ -z "${counted// /}" ]; then
      printf 'ATOM\t%s\tSURVIVED\t%s\tstructural-only%s\n' "$atom" "$mut" "$disc" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): SURVIVED except structural (only$disc red) — $desc"
      continue
    fi
    # Right-reason kill: observed non-structural failing set must intersect the
    # frozen ledger owning set for this atom; a random theorem failure is
    # EXCLUDED unrelated-downstream, never KILLED.
    owning_raw=$(awk -F'|' -v A="$atom" 'index($2, A) > 0 {t=$5; print t}' "$LEDGER" | head -n 1)
    owning=$(echo "$owning_raw" | tr ',' ' ' | tr -d '`' | tr -s ' ' '\n' | sed -E 's/^ +| +$//g' | grep -v '^$' | sort -u | tr '\n' ' ')
    inter=""
    for t in $counted; do case " $owning " in *" $t "*) inter="$inter $t";; esac; done
    if [ -z "${inter// /}" ]; then
      printf 'ATOM\t%s\tEXCLUDED\t%s\tunrelated-downstream failing:%s owning:%s\n' "$atom" "$mut" "$counted" "$owning" >> "$campaign/atom-results.tsv"
      say "$atom ($mut): EXCLUDED unrelated-downstream (failing:$counted not in owning:$owning)"
      excluded_wrong=$((excluded_wrong+1))
      continue
    fi
    printf 'ATOM\t%s\tKILLED\t%s\t%s|%s\n' "$atom" "$mut" "$inter" "$disc" >> "$campaign/atom-results.tsv"
    say "$atom ($mut): RED for the right reason (failing:$inter (of$counted); discounted:${disc:- none}; blob=$applied_hash) — $desc"
    atoms_killed=$((atoms_killed+1))
  done < "$campaign/ledger-atom-ids.txt"

  # Per-theorem witnesses.
  : > "$campaign/theorem-results.tsv"
  local th_killed=0 th_total=20
  while read -r thname; do
    # Witness file: witnesses/<THROW>.lean where THROW like TH-01? Map via ledger row?
    # Ledger row number is not in theorem name; resolve via ledger lookup.
    throw=$(awk -F'|' -v T="$thname" '{t=$3; gsub(/^ +| +$/, "", t); gsub(/`/, "", t); if (t==T) {r=$2; gsub(/^ +| +$/, "", r); print r}}' "$LEDGER")
    wit="$WITDIR/$throw.lean"
    if [ ! -f "$wit" ]; then
      printf 'THEOREM\t%s\tMISSING\tMISSING\t%s\n' "$thname" "$throw" >> "$campaign/theorem-results.tsv"
      say "$thname ($throw): BLOCKED missing witness $wit"
      blocked=$((blocked+1))
      continue
    fi
    if vw_diag=$(validate_witness "$thname" "$wit" 2>&1); then
      : # valid witness: exact canonical application present, no trivial example
    else
      vw_rc=$?
      if [ "$vw_rc" = "1" ]; then
        printf 'THEOREM\t%s\tMALFORMED\tMISSING\t%s\n' "$thname" "$throw" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED non-vacuous assertion required (example True/by rfl) [$vw_diag]"
      else
        printf 'THEOREM\t%s\tMALFORMED\tMISSING\t%s\n' "$thname" "$throw" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED exact theorem application missing (CardanoKeri.$thname not on example line) [$vw_diag]"
      fi
      blocked=$((blocked+1))
      continue
    fi
    if lean_run "$LEAN" "$campaign/$throw.wit-clean.log" env lean "$wit"; then
      reached="REACHED"
      say "$thname ($throw): witness REACHED"
    else
      rc=$?; if [ "$rc" = "2" ]; then printf 'THEOREM\t%s\tBLOCKED\tMISSING\t%s\n' "$thname" "$throw:budget-exhausted" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED budget-exhausted (refused before clean witness)"; blocked=$((blocked+1)); continue; fi
      printf 'THEOREM\t%s\tUNREACHED\tMISSING\t%s\n' "$thname" "$throw" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED witness UNREACHED (clean witness fails)"; blocked=$((blocked+1)); continue
    fi
    # Relevant kill via shared production evidence (no extra builds, no stale oleans):
    # after clean REACHED, reuse the relevant atom's already-observed KILLED
    # production failure (no extra builds, no stale oleans). Clean witnesses run in
    # authoritative ($LEAN) with clean oleans; atom kills ran in isolated work copy
    # with fresh mutated oleans. TH-06 uses a dedicated AUX mutant (2 extra builds).
    # Full-run use: 158 (atoms) + 20 (clean witnesses) + 2 (TH-06 AUX model+full)
    # + 12 (TH-03/08/09/12 AUX sensors: clean sensor, mutated prefix, mutated
    # sensor) + 5 closeout = 197 (budget 210).
    short=$(echo "$thname" | sed -E 's/^(Cage|Samaritan)\.//')
    # Shared-kill search (NOTE-022): exact-token match on BOTH ledger owning set
    # and observed failing set (field 5 before `|`, tokenized). Scan all KILLED
    # atom rows deterministically (sorted by atom id); pick first exact match.
    # Never substring-match or count a merely mentioned theorem.
    # TH-06 has no owning atom; its dedicated AUX sensitivity mutant is handled
    # below (NOTE-005: single edit to `bypassed` making `Inv` hold, actual
    # `bypassed_breaks_inv` must go red). Do not fall through to shared CG-06.
    if [ "$thname" = "Cage.bypassed_breaks_inv" ]; then
      aux_mut=$(awk -F'\t' '$1=="TH-06"{print $2}' "$campaign/aux-map.tsv" || true)
      if [ -z "$aux_mut" ]; then
        printf 'THEOREM\t%s\t%s\tMISSING\tno-aux-TH-06\n' "$thname" "$reached" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED no AUX sensitivity mutant for TH-06 (need theorem=TH-06)"
        blocked=$((blocked+1))
        continue
      fi
      # Apply AUX mutant: exact single edit, model-only must compile, full must
      # fail at `bypassed_breaks_inv` (actual declaration, not same-scenario proxy).
      aux_spec="$campaign/specs/$aux_mut.spec"; aux_mod=$(sed -n 2p "$aux_spec")
      aux_target="$wlean/CardanoKeri/$aux_mod.lean"
      restore_all
      c=$(count_needle "$campaign/specs/$aux_mut.needle" "$aux_target")
      if [ "$c" != "1" ]; then
        printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED AUX needle applies $c times (need exactly 1)"
        blocked=$((blocked+1))
        continue
      fi
      apply_needle "$campaign/specs/$aux_mut.needle" "$campaign/specs/$aux_mut.repl" "$aux_target"
      aux_blob=$(sha256sum "$aux_target" | cut -d' ' -f1)
      awk '
        /^theorem / { print "example : True := trivial"; skip=1; next }
        skip && /^(def |theorem |instance |structure |inductive |abbrev |end |namespace |open |import |\/-!|--|#)/ { skip=0 }
        !skip
      ' "$aux_target" > "$wlean/ModelOnlyCheck.lean"
      if lean_run "$wlean" "$campaign/$aux_mut.modelonly.log" env lean ModelOnlyCheck.lean; then
        aux_model_ok=1
      else
        rc=$?; if [ "$rc" = "2" ]; then printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED AUX budget-exhausted (refused before modelonly)"; blocked=$((blocked+1)); continue; fi
        printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): EXCLUDED AUX model-only fails (mutated defs do not elaborate; blob=$aux_blob)"
        excluded_wrong=$((excluded_wrong+1))
        continue
      fi
      if lean_run "$wlean" "$campaign/$aux_mut.full.log" build "CardanoKeri.$aux_mod"; then
        printf 'THEOREM\t%s\t%s\tSURVIVED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): SURVIVED AUX $aux_mut (full still builds; no kill)"
        continue
      else
        rc=$?; if [ "$rc" = "2" ]; then printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED AUX budget-exhausted (refused before full)"; blocked=$((blocked+1)); continue; fi
        aux_fail_lines=$(grep -oE "error: CardanoKeri/$aux_mod\.lean:[0-9]+:[0-9]+" "$campaign/$aux_mut.full.log" | cut -d: -f3 || true)
        aux_failing=""
        if [ -n "$aux_fail_lines" ]; then
          aux_failing=$(for ln in $aux_fail_lines; do awk -v L="$ln" '$1<=L{n=$2} END{print n}' "$campaign/thmlines-cage.txt"; done | sort -u | tr '\n' ' ')
        fi
        if grep -q 'sorryAx' "$campaign/$aux_mut.full.log"; then
          printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): EXCLUDED AUX sorryAx"
          excluded_wrong=$((excluded_wrong+1))
          continue
        fi
        if echo " $aux_failing " | grep -q " bypassed_breaks_inv "; then
          printf 'THEOREM\t%s\t%s\tKILLED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): KILLED by AUX $aux_mut (failing:$aux_failing; blob=$aux_blob)"
          th_killed=$((th_killed+1))
        else
          printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): EXCLUDED AUX failure does not cover bypassed_breaks_inv (failing:$aux_failing)"
          excluded_wrong=$((excluded_wrong+1))
        fi
      fi
      continue
    fi
    # NOTE-026 AUX sensor rows (TH-03/08/09/12): dedicated single-edit
    # production mutant + generated concrete sensor under owned
    # lean/mutants/sensors (example-only, no theorem declarations). Two builds
    # per AUX (modelonly prefix + sensor recompile). Exact row attribution is
    # a sensor error at/after sensor_start following a green mutated prefix.
    if [ "$throw" = "TH-03" ] || [ "$throw" = "TH-08" ] || [ "$throw" = "TH-09" ] || [ "$throw" = "TH-12" ]; then
      aux_mut=$(awk -F'\t' -v T="$throw" '$1==T{print $2}' "$campaign/aux-map.tsv" || true)
      if [ -z "$aux_mut" ]; then
        printf 'THEOREM\t%s\t%s\tMISSING\tno-aux-%s\n' "$thname" "$reached" "$throw" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED no AUX sensitivity mutant for $throw (need theorem=$throw)"
        blocked=$((blocked+1))
        continue
      fi
      aux_spec="$campaign/specs/$aux_mut.spec"; aux_mod=$(sed -n 2p "$aux_spec")
      aux_target="$wlean/CardanoKeri/$aux_mod.lean"
      sensor_src="$HERE/sensors/AUX-${throw/TH-/TH}.sensor.lean"
      if [ ! -f "$sensor_src" ]; then
        printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED missing sensor $sensor_src"
        blocked=$((blocked+1))
        continue
      fi
      if grep -Eq '^[[:space:]]*theorem ' "$sensor_src"; then
        printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): EXCLUDED sensor declares a theorem (sensors must be example-only)"
        excluded_wrong=$((excluded_wrong+1))
        continue
      fi
      if grep -Eq '(^|[^A-Za-z])sorry([^A-Za-z]|$)' "$sensor_src"; then
        printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): EXCLUDED sensor contains sorry"
        excluded_wrong=$((excluded_wrong+1))
        continue
      fi
      # The concrete sensor must first compile against the clean model. This
      # prevents syntax/type errors or a false clean premise from masquerading
      # as a mutation kill.
      restore_all
      awk '
        /^theorem / { print "example : True := trivial"; skip=1; next }
        skip && /^(def |theorem |instance |structure |inductive |abbrev |end |namespace |open |import |\/\-!|--|#)/ { skip=0 }
        !skip
      ' "$aux_target" > "$wlean/ModelOnlyCheck.lean"
      cat "$sensor_src" >> "$wlean/ModelOnlyCheck.lean"
      if lean_run "$wlean" "$campaign/$aux_mut.sensor-clean.log" env lean ModelOnlyCheck.lean; then
        :
      else
        rc=$?; if [ "$rc" = "2" ]; then printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED AUX budget-exhausted (refused before clean sensor)"; blocked=$((blocked+1)); continue; fi
        printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): EXCLUDED AUX sensor does not compile on clean model"
        excluded_wrong=$((excluded_wrong+1))
        continue
      fi
      restore_all
      c=$(count_needle "$campaign/specs/$aux_mut.needle" "$aux_target")
      if [ "$c" != "1" ]; then
        printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): BLOCKED AUX needle applies $c times (need exactly 1)"
        blocked=$((blocked+1))
        continue
      fi
      apply_needle "$campaign/specs/$aux_mut.needle" "$campaign/specs/$aux_mut.repl" "$aux_target"
      aux_blob=$(sha256sum "$aux_target" | cut -d' ' -f1)
      awk '
        /^theorem / { print "example : True := trivial"; skip=1; next }
        skip && /^(def |theorem |instance |structure |inductive |abbrev |end |namespace |open |import |\/-!|--|#)/ { skip=0 }
        !skip
      ' "$aux_target" > "$wlean/ModelOnlyCheck.lean"
      if lean_run "$wlean" "$campaign/$aux_mut.modelonly.log" env lean ModelOnlyCheck.lean; then
        aux_model_ok=1
      else
        rc=$?; if [ "$rc" = "2" ]; then printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED AUX budget-exhausted (refused before modelonly)"; blocked=$((blocked+1)); continue; fi
        printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): EXCLUDED AUX model-only fails (mutated defs do not elaborate; blob=$aux_blob)"
        excluded_wrong=$((excluded_wrong+1))
        continue
      fi
      sensor_start=$(( $(wc -l < "$wlean/ModelOnlyCheck.lean") + 1 ))
      cat "$sensor_src" >> "$wlean/ModelOnlyCheck.lean"
      if lean_run "$wlean" "$campaign/$aux_mut.sensor.log" env lean ModelOnlyCheck.lean; then
        printf 'THEOREM\t%s\t%s\tSURVIVED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): SURVIVED AUX $aux_mut (sensor still builds; no kill)"
        continue
      else
        rc=$?; if [ "$rc" = "2" ]; then printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"; say "$thname ($throw): BLOCKED AUX budget-exhausted (refused before sensor)"; blocked=$((blocked+1)); continue; fi
        if grep -q 'sorryAx' "$campaign/$aux_mut.sensor.log"; then
          printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): EXCLUDED AUX sensor sorryAx"
          excluded_wrong=$((excluded_wrong+1))
          continue
        fi
        if grep -qE 'unknown (package|identifier)|failed to import|syntax error|unexpected' "$campaign/$aux_mut.sensor.log"; then
          printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): EXCLUDED AUX sensor wrong-reason (import/syntax)"
          excluded_wrong=$((excluded_wrong+1))
          continue
        fi
        if grep -oE 'ModelOnlyCheck\.lean:[0-9]+:[0-9]+' "$campaign/$aux_mut.sensor.log" | cut -d: -f2 | awk -v S="$sensor_start" '$1 >= S {found=1} END{exit !found}'; then
          printf 'THEOREM\t%s\t%s\tKILLED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): KILLED by AUX $aux_mut (sensor error at/after line $sensor_start; blob=$aux_blob)"
          th_killed=$((th_killed+1))
        else
          printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$aux_mut" >> "$campaign/theorem-results.tsv"
          say "$thname ($throw): EXCLUDED AUX sensor failure not on generated sensor (no error at/after line $sensor_start)"
          excluded_wrong=$((excluded_wrong+1))
        fi
      fi
      continue
    fi
    shared_pick=""; shared_atom=""
    while IFS=$(printf '\t') read -r _ aid verdict mut detail; do
      [ "$verdict" = "KILLED" ] || continue
      fail_part=$(echo "$detail" | cut -d'|' -f1)
      if ! printf '%s\n' "$fail_part" | tr -s ' ' '\n' | grep -Fxq "$short"; then
        continue
      fi
      owning_raw=$(awk -F'|' -v A="$aid" '{id=$2; gsub(/^ +| +$/, "", id); if (id==A) {print $5}}' "$LEDGER" | head -n 1)
      owning_toks=$(echo "$owning_raw" | tr ',' '\n' | tr -d '`' | tr -s ' ' '\n' | sed -E 's/^ +| +$//g' | grep -v '^$' | sort -u)
      if ! printf '%s\n' "$owning_toks" | grep -Fxq "$short"; then
        continue
      fi
      shared_pick="$mut"
      shared_atom="$aid"
      break
    done < <(grep -P "^ATOM\t" "$campaign/atom-results.tsv" | sort -t "$(printf '\t')" -k2,2)
    if [ -n "$shared_pick" ]; then
      printf 'THEOREM\t%s\t%s\tKILLED\t%s\n' "$thname" "$reached" "$shared_pick" >> "$campaign/theorem-results.tsv"
      say "$thname ($throw): KILLED via shared production kill $shared_pick ($shared_atom exactly owns+fails $short)"
      th_killed=$((th_killed+1))
    else
      printf 'THEOREM\t%s\t%s\tBLOCKED\t%s\n' "$thname" "$reached" "no-shared-kill" >> "$campaign/theorem-results.tsv"
      say "$thname ($throw): BLOCKED no shared KILLED row exactly owns+fails $short"
      blocked=$((blocked+1))
    fi
  done < "$campaign/ledger-theorem-names.txt"

  # Axiom account on a clean copy (no .lake).
  local clean="$campaign/clean"
  rm -rf "$clean"; mkdir -p "$clean"
  (cd "$LEAN" && tar --exclude=.lake -cf - .) | (cd "$clean" && tar -xf -)
  {
    echo "import CardanoKeri.CheckpointGoals"
    echo "import CardanoKeri.RegistryGoals"
    echo "import CardanoKeri.Cage"
    echo "import CardanoKeri.Samaritan"
    grep -hoE '^theorem\s+[A-Za-z0-9_]+' "$LEAN/CardanoKeri/CheckpointGoals.lean" | awk '{print "#print axioms CardanoKeri.Checkpoint." $2}'
    grep -hoE '^theorem\s+[A-Za-z0-9_]+' "$LEAN/CardanoKeri/RegistryGoals.lean" | awk '{print "#print axioms CardanoKeri.Registry." $2}'
    grep -hoE '^theorem\s+[A-Za-z0-9_]+' "$LEAN/CardanoKeri/Cage.lean" | awk '{print "#print axioms CardanoKeri.Cage." $2}'
    grep -hoE '^theorem\s+[A-Za-z0-9_]+' "$LEAN/CardanoKeri/Samaritan.lean" | awk '{print "#print axioms CardanoKeri.Samaritan." $2}'
  } > "$campaign/Axioms.lean"
  if lean_run "$clean" "$campaign/clean-build.log" build CardanoKeri.CheckpointGoals CardanoKeri.RegistryGoals CardanoKeri.Cage CardanoKeri.Samaritan; then
    if lean_run "$clean" "$campaign/axioms.log" env lean "$campaign/Axioms.lean"; then
    ax_count=$(grep -c "depends on axioms\|does not depend" "$campaign/axioms.log" || true)
    sorry_count=$(grep -c sorryAx "$campaign/axioms.log" || true)
    say "AXIOMS clean build: $ax_count theorems; sorryAx: $sorry_count"
    expected_ax=$(($(grep -c '^theorem ' "$LEAN/CardanoKeri/CheckpointGoals.lean" || true) + $(grep -c '^theorem ' "$LEAN/CardanoKeri/RegistryGoals.lean" || true) + $(grep -c '^theorem ' "$LEAN/CardanoKeri/Cage.lean" || true) + $(grep -c '^theorem ' "$LEAN/CardanoKeri/Samaritan.lean" || true)))
    if ax_diag=$(check_axioms "$expected_ax" "$ax_count" "$sorry_count" 2>&1); then
      axioms_ok=1
    else
      ax_rc=$?
      say "AXIOMS REJECTED expected=$expected_ax observed=$ax_count sorryAx=$sorry_count rc=$ax_rc [$ax_diag]"
      blocked=$((blocked+1))
    fi
    else
      rc=$?; if [ "$rc" = "2" ]; then say "AXIOMS REFUSED budget-exhausted (no env-lean invocation)"; blocked=$((blocked+1)); else say "AXIOMS FAILED env-lean invocation failure (see axioms.log; preserved, not erased)"; blocked=$((blocked+1)); fi
    fi
  else
    rc=$?; if [ "$rc" = "2" ]; then say "AXIOMS REFUSED budget-exhausted (no invocations)"; blocked=$((blocked+1)); else say "AXIOMS clean build FAILED (see clean-build.log, axioms.log)"; blocked=$((blocked+1)); fi
    : > "$campaign/axioms.log"
    echo "AXIOMS FAILED" >> "$campaign/axioms.log"
  fi

  # Post-run hashes (CLEAN proof; Fix6). Authoritative inputs must be unchanged
  # during run (runner writes only to campaign dir, never to authoritative tree).
  # No wall time/HEAD here (deterministic file hashes only).
  {
    sha256sum "$LEDGER"
    sha256sum "$gate_file"
    sha256sum "$LEAN/CardanoKeri/Checkpoint.lean"
    sha256sum "$LEAN/CardanoKeri/CheckpointGoals.lean"
    sha256sum "$LEAN/CardanoKeri/Registry.lean"
    sha256sum "$LEAN/CardanoKeri/RegistryGoals.lean"
    sha256sum "$LEAN/CardanoKeri/Cage.lean"
    sha256sum "$LEAN/CardanoKeri/Samaritan.lean"
    sha256sum "$HERE/run.sh"
    sha256sum "$SPEC"
  } > "$campaign/post-hashes.tsv"
  if [ -d "$WITDIR" ]; then find "$WITDIR" -type f | sort | xargs sha256sum >> "$campaign/post-hashes.tsv"; fi
  if [ -d "$HERE/sensors" ]; then find "$HERE/sensors" -type f | sort | xargs sha256sum >> "$campaign/post-hashes.tsv"; fi
  if diff -u "$campaign/pre-hashes.tsv" "$campaign/post-hashes.tsv" > "$campaign/prepost.diff" 2>&1; then
    say "PREPOST clean (authoritative inputs unchanged during run)"
  else
    say "PREPOST MISMATCH (authoritative inputs changed during run; see prepost.diff)"
    blocked=$((blocked+1))
  fi

  # Summary (exact shapes asserted by gate-v2 + detailed rows).
  {
    # Detailed atom rows first (gate counts KILLED among them).
    # Normalize atom-results to gate shape: ATOM <id> <KILLED|...>
    # Our atom-results already use that shape with extra cols; emit as-is for detail,
    # but gate only counts $3==KILLED, so extra cols are fine.
    cat "$campaign/atom-results.tsv"
    cat "$campaign/theorem-results.tsv"
    # Control (exact).
    if [ "$control_result" = "SURVIVED" ]; then
      printf 'CONTROL\tidentity\tSURVIVED\n'
    else
      printf 'CONTROL\tidentity\t%s\n' "$control_result"
    fi
    # Totals (exact lines required by gate; emit actual values so RED fails honestly).
    # Gate greps exact TOTAL atoms 79 79 etc.; we emit actual killed counts.
    printf 'TOTAL\tatoms\t79\t%s\n' "$atoms_killed"
    printf 'TOTAL\ttheorems\t20\t%s\n' "$th_killed"
    printf 'EXCLUDED\twrong-reason\t%s\n' "$excluded_wrong"
    printf 'BLOCKED\t%s\n' "$blocked"
    printf 'STOP\tfrozen-ledger\n'
    printf 'BUDGET\tbuilds_spent\t%s\tbudget\t210\n' "$builds_spent"
    printf 'PROVENANCE\tsource\t%s\tledger\t%s\trunner\t%s\tspec\t%s\n' "$head_sha" "$ledger_hash" "$runner_hash" "$spec_hash"
  } > "$campaign/summary.tsv"

  say "SUMMARY atoms=$atoms_killed/79 theorems=$th_killed/20 blocked=$blocked excluded_wrong=$excluded_wrong builds_spent=$builds_spent"

  # Deterministic receipts (pure rendering; no wall time/HEAD; frozen bases + content hashes + digest).
  wit_hash="none"; if [ -d "$WITDIR" ]; then wit_hash=$( { find "$WITDIR" -type f | sort | xargs sha256sum 2>/dev/null; if [ -d "$HERE/sensors" ]; then find "$HERE/sensors" -type f | sort | xargs sha256sum 2>/dev/null; fi; } | sha256sum | cut -d" " -f1); fi
  summary_digest=$(cat "$campaign/atom-results.tsv" "$campaign/theorem-results.tsv" 2>/dev/null | sha256sum | cut -d" " -f1)
  render_receipts "$campaign" "$head_sha" "$ledger_hash" "$runner_hash" "$spec_hash" "$wit_hash" "$summary_digest" "$atoms_killed" "$th_killed" "$blocked" "$excluded_wrong" "$builds_spent" "$control_result" "$started"

  # Restore authoritative tree cleanliness (we only wrote into campaign dir).
  restore_all >/dev/null 2>&1 || true
  say "DONE campaign=$campaign"
  # NOTE-022: runner must be RED-nonzero whenever the campaign is not fully
  # GREEN (defective rc0 on campaign-021 proved). Closeout failures already
  # increment blocked; baseline failure would surface via blocked/excluded.
  if [ "$atoms_killed" -ne 79 ] || [ "$th_killed" -ne 20 ] || [ "$blocked" -ne 0 ] || [ "$excluded_wrong" -ne 0 ] || [ "$control_result" != "SURVIVED" ] || [ "$baseline_ok" != "1" ] || [ "$axioms_ok" != "1" ]; then
    say "CAMPAIGN RED atoms=$atoms_killed/79 theorems=$th_killed/20 blocked=$blocked excluded_wrong=$excluded_wrong control=$control_result baseline=$baseline_ok axioms=$axioms_ok (returning nonzero)"
    return 1
  fi
  say "CAMPAIGN GREEN atoms=79/79 theorems=20/20 blocked=0 excluded_wrong=0 control=SURVIVED"
  return 0
}

render_receipts() {
  local campaign=$1 head_sha=$2 ledger_hash=$3 runner_hash=$4 spec_hash=$5
  local wit_hash=$6 summary_digest=$7
  local atoms_killed=$8 th_killed=$9 blocked=${10} excluded_wrong=${11}
  local builds_spent=${12} control_result=${13} started=${14}
  local log="$campaign/raw.log"
  mkdir -p "$campaign/receipts"

  # Shared header.
  header() {
    cat <<HDR
# Issue 365 mutation campaign — generated receipt (do not hand-edit)

Generated by \`lean/mutants/run.sh --run\` from one raw run. The table(s) below
and the raw log are the same run, so tables can only say what the run did.

- Model base (frozen): 9b2e6b88937707cc2c571ae1e9e5f112dc248a30
- Ledger \`lean/SEMANTIC-ATOMS.md\` SHA-256: \`$ledger_hash\`
- Runner \`lean/mutants/run.sh\` SHA-256: \`$runner_hash\`
- Spec \`lean/mutants/mutants.txt\` SHA-256: \`$spec_hash\`
- Pre-slice base: e03b678a827077c05399421a40a7507d52db6ac5
- Terminal merged base: 370a23b64a581c7ad80681700a459372b8005ba9 (epic-owner C1+C2 release per S365-P4; this run binds the merged commit)
- Operator set (finite, frozen): \`$OPERATORS\`
- Build budget/use: \`builds_spent=$builds_spent / budget=210\` Lean command invocations per full run (one identity control + at most one canonical mutant per 79 atom rows + 20 theorem witness evaluations + clean axiom/build closeout). Stop before invocation 211.
- Stopping reason: \`frozen-ledger\` (one right-reason killed mutant per row + one witness/kill per theorem row; equivalent/shadowed mutants replaced or BLOCKED, never counted).
- Exclusions (\`wrong-reason\`): \`$excluded_wrong\` (syntax/import/setup/sorryAx/unrelated-downstream failures never count).
- Blocked rows: \`$blocked\`.
- Identity control: \`$control_result\` (unchanged control must survive to show the instrument can report a survivor).
- Structural discounts (global, never counted as owning kills): \`$STRUCTURAL\` plus broad correspondence mirrors (\`Cage.applyBatch_delegated_eq\`, \`Cage.delegated_is_registry\`) named per affected row; each affected row repeats its discounted set.
- Denominators (independent): semantic atoms \`$atoms_killed/79\`, theorem rows \`$th_killed/20\`.
- Honest limits: this finite declared fault model has no blocking survivors; it does not claim zero possible survivors.
- Witnesses+sensors SHA-256 (deterministic, sorted file list): $wit_hash
- Summary digest (deterministic atom+theorem results): $summary_digest

HDR
  }

  # Checkpoint receipt: CP atoms (40).
  {
    header
    echo "## Checkpoint atoms (40) — source/model \`CardanoKeri/Checkpoint.lean\`, owning theorems in \`CardanoKeri/CheckpointGoals.lean\`"
    echo ""
    echo "| Atom | Mutant | Verdict | Failing owning (structural aside) | Discounted |"
    echo "|---|---|---|---|---|"
    while read -r atom; do
      case "$atom" in CP-*) ;;
        *) continue;;
      esac
      line=$(grep -P "^ATOM\t$atom\t" "$campaign/atom-results.tsv" || echo -e "ATOM\t$atom\tMISSING")
      verdict=$(echo "$line" | cut -f3)
      mut=$(echo "$line" | cut -f4)
      rest=$(echo "$line" | cut -f5-)
      # Owning theorems from ledger for reference.
      owning=$(awk -F'|' -v A="$atom" '$2 ~ A {t=$5; gsub(/^ +| +$/, "", t); print t}' "$LEDGER" | head -n 1)
      printf '| %s | %s | %s | %s | %s |\n' "$atom" "$mut" "$verdict" "$rest" "$owning"
    done < "$campaign/ledger-atom-ids.txt"
    echo ""
    echo "## Theorem rows (20) — witness=REACHED + kill=KILLED per row (detail in Registry receipt; summary here)"
    echo ""
    echo "| Theorem | Witness | Kill mutant | Verdict |"
    echo "|---|---|---|---|"
    while read -r th; do
      line=$(grep -P "^THEOREM\t$(echo "$th" | sed -E 's/\./\\./g')\t" "$campaign/theorem-results.tsv" || echo -e "THEOREM\t$th\tMISSING")
      w=$(echo "$line" | cut -f3); k=$(echo "$line" | cut -f4); m=$(echo "$line" | cut -f5)
      printf '| `%s` | %s | %s | %s |\n' "$th" "$w" "$m" "$k"
    done < "$campaign/ledger-theorem-names.txt"
    echo ""
    echo "## Raw runtime evidence (not reproduced for determinism)"
    echo ""
    echo "Wall time and source HEAD are retained only in the campaign work-root raw.log (raw runtime evidence, not byte-for-byte reproducible). Deterministic tables/hashes/digest above are byte-for-byte reproducible on the same tree (frozen bases + content hashes + results)."
  } > "$campaign/receipts/CHECKPOINT-MUTANTS.md"

  # Registry receipt: RG (22) + CG (11) + SM (6).
  {
    header
    echo "## Registry atoms (22) — source/model \`CardanoKeri/Registry.lean\`"
    echo ""
    echo "| Atom | Mutant | Verdict | Failing owning (structural aside) | Discounted |"
    echo "|---|---|---|---|---|"
    while read -r atom; do
      case "$atom" in RG-*) ;;
        *) continue;;
      esac
      line=$(grep -P "^ATOM\t$atom\t" "$campaign/atom-results.tsv" || echo -e "ATOM\t$atom\tMISSING")
      verdict=$(echo "$line" | cut -f3)
      mut=$(echo "$line" | cut -f4)
      rest=$(echo "$line" | cut -f5-)
      owning=$(awk -F'|' -v A="$atom" '$2 ~ A {t=$5; gsub(/^ +| +$/, "", t); print t}' "$LEDGER" | head -n 1)
      printf '| %s | %s | %s | %s | %s |\n' "$atom" "$mut" "$verdict" "$rest" "$owning"
    done < "$campaign/ledger-atom-ids.txt"
    echo ""
    echo "## Cage atoms (11) — source/model \`CardanoKeri/Cage.lean\`"
    echo ""
    echo "| Atom | Mutant | Verdict | Failing owning (structural aside) | Discounted |"
    echo "|---|---|---|---|---|"
    while read -r atom; do
      case "$atom" in CG-*) ;;
        *) continue;;
      esac
      line=$(grep -P "^ATOM\t$atom\t" "$campaign/atom-results.tsv" || echo -e "ATOM\t$atom\tMISSING")
      verdict=$(echo "$line" | cut -f3)
      mut=$(echo "$line" | cut -f4)
      rest=$(echo "$line" | cut -f5-)
      owning=$(awk -F'|' -v A="$atom" '$2 ~ A {t=$5; gsub(/^ +| +$/, "", t); print t}' "$LEDGER" | head -n 1)
      printf '| %s | %s | %s | %s | %s |\n' "$atom" "$mut" "$verdict" "$rest" "$owning"
    done < "$campaign/ledger-atom-ids.txt"
    echo ""
    echo "## Samaritan atoms (6) — source/model \`CardanoKeri/Samaritan.lean\`"
    echo ""
    echo "| Atom | Mutant | Verdict | Failing owning (structural aside) | Discounted |"
    echo "|---|---|---|---|---|"
    while read -r atom; do
      case "$atom" in SM-*) ;;
        *) continue;;
      esac
      line=$(grep -P "^ATOM\t$atom\t" "$campaign/atom-results.tsv" || echo -e "ATOM\t$atom\tMISSING")
      verdict=$(echo "$line" | cut -f3)
      mut=$(echo "$line" | cut -f4)
      rest=$(echo "$line" | cut -f5-)
      owning=$(awk -F'|' -v A="$atom" '$2 ~ A {t=$5; gsub(/^ +| +$/, "", t); print t}' "$LEDGER" | head -n 1)
      printf '| %s | %s | %s | %s | %s |\n' "$atom" "$mut" "$verdict" "$rest" "$owning"
    done < "$campaign/ledger-atom-ids.txt"
    echo ""
    echo "## Theorem rows (20) — Cage/Samaritan non-vacuity (witness + relevant kill per row)"
    echo ""
    echo "| Row | Theorem | Witness surface (ledger) | Witness | Kill mutant | Verdict |"
    echo "|---|---|---|---|---|---|"
    while read -r th; do
      throw=$(awk -F'|' -v T="$th" '{t=$3; gsub(/^ +| +$/, "", t); gsub(/`/, "", t); if (t==T) {r=$2; gsub(/^ +| +$/, "", r); print r}}' "$LEDGER")
      surface=$(awk -F'|' -v T="$th" '{t=$3; gsub(/^ +| +$/, "", t); gsub(/`/, "", t); if (t==T) {s=$4; gsub(/^ +| +$/, "", s); print s}}' "$LEDGER")
      line=$(grep -P "^THEOREM\t$(echo "$th" | sed -E 's/\./\\./g')\t" "$campaign/theorem-results.tsv" || echo -e "THEOREM\t$th\tMISSING")
      w=$(echo "$line" | cut -f3); k=$(echo "$line" | cut -f4); m=$(echo "$line" | cut -f5)
      printf '| %s | `%s` | %s | %s | %s | %s |\n' "$throw" "$th" "$surface" "$w" "$m" "$k"
    done < "$campaign/ledger-theorem-names.txt"
    echo ""
    echo "## Raw runtime evidence (not reproduced for determinism)"
    echo ""
    echo "Wall time and source HEAD are retained only in the campaign work-root raw.log (raw runtime evidence, not byte-for-byte reproducible). Deterministic tables/hashes/digest above are byte-for-byte reproducible on the same tree (frozen bases + content hashes + results)."
  } > "$campaign/receipts/REGISTRY-MUTANTS.md"
}

usage() {
  echo "usage: run.sh --list | --run <campaign-dir> | --check-witness <ledger-name> <file> | --check-axioms <expected> <observed> <sorry>" >&2
  exit 2
}

case "${1:-}" in
  --list) cmd_list ;;
  --check-witness)
    test $# -eq 3 || usage
    cmd_check_witness "$2" "$3"
    ;;
  --check-axioms)
    test $# -eq 4 || usage
    cmd_check_axioms "$2" "$3" "$4"
    ;;
  --run)
    test $# -eq 2 || usage
    cmd_run "$2"
    ;;
  *) usage ;;
esac
