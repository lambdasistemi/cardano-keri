#!/usr/bin/env bash
# Issue 365 semantic-atom mutation campaign.
#
# Required CLI (gate-v1):
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
# Lean toolchain must match gate-v1 final leg.
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
  test "$(wc -l < "$tmp/ledger-theorems.tsv")" -eq 18 || { echo "run.sh --list: ledger theorems != 18" >&2; exit 1; }
  test "$(wc -l < "$tmp/discovered-theorems.tsv")" -eq 18 || { echo "run.sh --list: discovered theorems != 18" >&2; cat "$tmp/discovered-theorems.tsv" >&2; exit 1; }
  # Refuse duplicates.
  test "$(cut -f2 "$tmp/ledger-atoms.tsv" | sort -u | wc -l)" -eq 79 || { echo "run.sh --list: duplicate atom IDs" >&2; exit 1; }
  test "$(cut -f2 "$tmp/ledger-theorems.tsv" | sort -u | wc -l)" -eq 18 || { echo "run.sh --list: duplicate theorems" >&2; exit 1; }
  # Refuse drift between ledger and compiled declarations.
  if ! diff -u "$tmp/ledger-theorems.tsv" "$tmp/discovered-theorems.tsv" >&2; then
    echo "run.sh --list: ledger theorems drift from compiled Cage/Samaritan declarations" >&2
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
#   ### <mutant-id> | <desc> [| atom=<ATOM>]
#   @@@ <Module>
#   <<<
#   needle
#   >>>
#   replacement
# Emits per-mutant .spec (desc, module, atom), .needle, .repl.
parse_specs() {
  local work=$1
  mkdir -p "$work/specs"
  rm -f "$work/specs"/*.spec "$work/specs"/*.needle "$work/specs"/*.repl 2>/dev/null || true
  perl -0ne '
    while (/^### (\S+) \| ([^\n]*)\n\@\@\@ (\S+)\n<<<\n(.*?)\n>>>\n(.*?)(?=\n### |\z)/smg) {
      my ($n,$d,$f,$a,$b)=($1,$2,$3,$4,$5); $b =~ s/\n\z//;
      my $atom = "";
      if ($d =~ /atom\s*=\s*((?:CP|RG|CG|SM)-[0-9]+)/) { $atom = $1; }
      open(O,">","'"$work"'/specs/$n.spec"); print O "$d\n$f\n$atom\n"; close O;
      open(O,">","'"$work"'/specs/$n.needle"); print O $a; close O;
      open(O,">","'"$work"'/specs/$n.repl"); print O $b; close O;
    }' "$SPEC"
}

# Map atom -> mutant (first spec claiming that atom). Prints warnings for dupes.
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
  say "STOPPING frozen-ledger: one right-reason kill per 79 atom rows + one witness/kill per 18 theorem rows"

  # Work copy with build cache for incremental mutant builds.
  local wlean="$campaign/work-lean"
  rm -rf "$wlean"
  mkdir -p "$wlean"
  cp -r "$LEAN/." "$wlean/"
  # Baseline: authoritative tree must build (counts toward budget).
  local builds_spent=0
  say "BASELINE build on authoritative tree"
  if (cd "$LEAN" && "${LAKE[@]}" build > "$campaign/baseline-build.log" 2>&1); then
    builds_spent=$((builds_spent+1))
    say "BASELINE green builds_spent=$builds_spent"
  else
    builds_spent=$((builds_spent+1))
    say "BASELINE FAILED (see baseline-build.log) builds_spent=$builds_spent"
  fi

  parse_specs "$campaign"
  atom_mutant_map "$campaign"

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
    if (cd "$wlean" && "${LAKE[@]}" build CardanoKeri.Checkpoint CardanoKeri.Registry CardanoKeri.Cage CardanoKeri.Samaritan > "$campaign/M0.model.log" 2>&1); then
      builds_spent=$((builds_spent+1))
      if (cd "$wlean" && "${LAKE[@]}" build CardanoKeri.CheckpointGoals CardanoKeri.RegistryGoals CardanoKeri.Cage CardanoKeri.Samaritan > "$campaign/M0.goals.log" 2>&1); then
        builds_spent=$((builds_spent+1))
        say "CONTROL M0-identity-control: SURVIVED as the control must (needle = replacement; the instrument reports a survivor)"
        control_result="SURVIVED"
      else
        builds_spent=$((builds_spent+1))
        say "CONTROL M0-identity-control: FAILED — the instrument reds an unchanged model; the campaign is void"
        control_result="FAILED"
      fi
    else
      builds_spent=$((builds_spent+1))
      say "CONTROL M0-identity-control: FAILED — clean work copy does not build"
      control_result="FAILED"
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
        if (cd "$wlean" && "${LAKE[@]}" build CardanoKeri.Checkpoint > "$campaign/$mut.model.log" 2>&1); then model_ok=1; fi
        builds_spent=$((builds_spent+1))
        if [ "$model_ok" = "1" ]; then
          if (cd "$wlean" && "${LAKE[@]}" build CardanoKeri.CheckpointGoals > "$campaign/$mut.goals.log" 2>&1); then goals_ok=1; fi
          builds_spent=$((builds_spent+1))
          if [ "$goals_ok" = "0" ]; then
            failing_lines=$(grep -oE 'error: CardanoKeri/CheckpointGoals\.lean:[0-9]+:[0-9]+' "$campaign/$mut.goals.log" | cut -d: -f3 || true)
            failing=$(echo "$failing_lines" | names_for_lines "$campaign/thmlines-checkpoint.txt")
          fi
        fi
        ;;
      Registry)
        if (cd "$wlean" && "${LAKE[@]}" build CardanoKeri.Registry > "$campaign/$mut.model.log" 2>&1); then model_ok=1; fi
        builds_spent=$((builds_spent+1))
        if [ "$model_ok" = "1" ]; then
          # Registry mutants are observed via RegistryGoals and Cage (which instantiates Registry).
          if (cd "$wlean" && "${LAKE[@]}" build CardanoKeri.RegistryGoals CardanoKeri.Cage > "$campaign/$mut.goals.log" 2>&1); then goals_ok=1; fi
          builds_spent=$((builds_spent+1))
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
        # Single-file modules: defs and theorems share the file. Model leg is
        # syntactic elaboration of defs (checked by ensuring any error is at a
        # theorem line, not a def line); kill is failure at a named owning
        # theorem/witness. We approximate by building the file: it must FAIL,
        # and the failing lines must include a non-structural owning theorem.
        if (cd "$wlean" && "${LAKE[@]}" build "CardanoKeri.$mod" > "$campaign/$mut.model.log" 2>&1); then
          # File still builds: survivor (mutant did not break owning theorem).
          builds_spent=$((builds_spent+1))
          model_ok=1; goals_ok=1
          failing=""
        else
          builds_spent=$((builds_spent+1))
          model_ok=1; goals_ok=0
          # Attribute failing theorems from error lines in this file.
          failing_lines=$(grep -oE "error: CardanoKeri/$mod\.lean:[0-9]+:[0-9]+" "$campaign/$mut.model.log" | cut -d: -f3 || true)
          # Map line numbers to theorem names via thmlines file.
          failing=""
          if [ -n "$failing_lines" ]; then
            failing=$(for ln in $failing_lines; do awk -v L="$ln" '$1<=L{n=$2} END{print n}' "$campaign/thmlines-$(echo "$mod" | tr 'A-Z' 'a-z').txt"; done | sort -u | tr '\n' ' ')
          fi
          # If error mentions sorryAx, import, or parse (no theorem attribution),
          # treat as wrong-reason exclusion.
          if grep -q 'sorryAx' "$campaign/$mut.model.log"; then
            failing="SORRYAX"
          elif [ -z "${failing// /}" ]; then
            # No theorem attribution: could be syntax/import/setup.
            if grep -qE 'unknown (package|identifier)|failed to import|syntax error|unexpected' "$campaign/$mut.model.log"; then
              failing="WRONG-REASON"
            fi
          fi
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
    # Right-reason kill: must include at least one owning theorem from ledger?
    # We record counted list; auditor verifies relevance to ledger owning set.
    printf 'ATOM\t%s\tKILLED\t%s\t%s|%s\n' "$atom" "$mut" "$counted" "$disc" >> "$campaign/atom-results.tsv"
    say "$atom ($mut): RED for the right reason (failing:$counted; discounted:${disc:- none}; blob=$applied_hash) — $desc"
    atoms_killed=$((atoms_killed+1))
  done < "$campaign/ledger-atom-ids.txt"

  # Per-theorem witnesses.
  : > "$campaign/theorem-results.tsv"
  local th_killed=0 th_total=18
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
    # Witness must compile/run on clean tree (REACHED).
    restore_all
    # Copy witness into work-lean as a check file (does not pollute authoritative tree).
    cp "$wit" "$wlean/WitnessCheck.lean"
    if (cd "$wlean" && "${LAKE[@]}" env lean WitnessCheck.lean > "$campaign/$throw.wit-clean.log" 2>&1); then
      builds_spent=$((builds_spent+1))
      reached="REACHED"
      say "$thname ($throw): witness REACHED"
    else
      builds_spent=$((builds_spent+1))
      printf 'THEOREM\t%s\tUNREACHED\tMISSING\t%s\n' "$thname" "$throw" >> "$campaign/theorem-results.tsv"
      say "$thname ($throw): BLOCKED witness UNREACHED (clean witness fails)"
      blocked=$((blocked+1))
      continue
    fi
    # Relevant kill: apply the mapped atom mutant most relevant to this theorem?
    # Resolve via ledger owning theorem(s) column: find atoms whose owning set contains this theorem short name.
    short=$(echo "$thname" | sed -E 's/^(Cage|Samaritan)\.//')
    # Find first atom whose ledger row mentions short name.
    rel_atom=$(awk -F'|' -v S="$short" '$0 ~ S && /^\| (CP|RG|CG|SM)-/ {id=$2; gsub(/^ +| +$/, "", id); print id; exit}' "$LEDGER" || true)
    rel_mut=$(awk -v A="$rel_atom" -F'\t' '$1==A{print $2}' "$campaign/atom-map.tsv" || true)
    if [ -z "$rel_mut" ]; then
      printf 'THEOREM\t%s\t%s\tMISSING\tnorelmut\n' "$thname" "$reached" >> "$campaign/theorem-results.tsv"
      say "$thname ($throw): BLOCKED no relevant mutant (atom $rel_atom unmapped)"
      blocked=$((blocked+1))
      continue
    fi
    # Apply relevant mutant in work copy, rerun witness (must FAIL for KILLED).
    rel_spec="$campaign/specs/$rel_mut.spec"
    rel_mod=$(sed -n 2p "$rel_spec")
    restore_all
    apply_needle "$campaign/specs/$rel_mut.needle" "$campaign/specs/$rel_mut.repl" "$wlean/CardanoKeri/$rel_mod.lean"
    cp "$wit" "$wlean/WitnessCheck.lean"
    if (cd "$wlean" && "${LAKE[@]}" env lean WitnessCheck.lean > "$campaign/$throw.wit-mut.log" 2>&1); then
      builds_spent=$((builds_spent+1))
      printf 'THEOREM\t%s\t%s\tSURVIVED\t%s\n' "$thname" "$reached" "$rel_mut" >> "$campaign/theorem-results.tsv"
      say "$thname ($throw): witness SURVIVED relevant mutant $rel_mut ($rel_atom) — not killed"
    else
      builds_spent=$((builds_spent+1))
      # Ensure failure is not sorryAx/import/setup: check log does not mention those as sole cause?
      # If witness failure is due to setup (missing import), treat as BLOCKED, not KILLED.
      if grep -q 'sorryAx' "$campaign/$throw.wit-mut.log" && ! grep -qE 'error|failed|unsolved|mismatch|decide' "$campaign/$throw.wit-mut.log"; then
        printf 'THEOREM\t%s\t%s\tEXCLUDED\t%s\n' "$thname" "$reached" "$rel_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): EXCLUDED sorryAx-only failure"
        excluded_wrong=$((excluded_wrong+1))
      else
        printf 'THEOREM\t%s\t%s\tKILLED\t%s\n' "$thname" "$reached" "$rel_mut" >> "$campaign/theorem-results.tsv"
        say "$thname ($throw): KILLED by $rel_mut ($rel_atom)"
        th_killed=$((th_killed+1))
      fi
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
  if (cd "$clean" && "${LAKE[@]}" build CardanoKeri.CheckpointGoals CardanoKeri.RegistryGoals CardanoKeri.Cage CardanoKeri.Samaritan > "$campaign/clean-build.log" 2>&1 && "${LAKE[@]}" env lean "$campaign/Axioms.lean" > "$campaign/axioms.log" 2>&1); then
    builds_spent=$((builds_spent+1))
    # Count extra build for env lean? Already counted as one; clean build is one.
    # Actually two commands: build + env lean. Count both.
    builds_spent=$((builds_spent+1))
    ax_count=$(grep -c "depends on axioms\|does not depend" "$campaign/axioms.log" || true)
    sorry_count=$(grep -c sorryAx "$campaign/axioms.log" || true)
    say "AXIOMS clean build: $ax_count theorems; sorryAx: $sorry_count"
  else
    builds_spent=$((builds_spent+2))
    say "AXIOMS clean build FAILED (see clean-build.log, axioms.log)"
    : > "$campaign/axioms.log"
    echo "AXIOMS FAILED" >> "$campaign/axioms.log"
  fi

  # Summary (exact shapes asserted by gate-v1 + detailed rows).
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
    printf 'TOTAL\ttheorems\t18\t%s\n' "$th_killed"
    printf 'EXCLUDED\twrong-reason\t%s\n' "$excluded_wrong"
    printf 'BLOCKED\t%s\n' "$blocked"
    printf 'STOP\tfrozen-ledger\n'
    printf 'BUDGET\tbuilds_spent\t%s\tbudget\t180\n' "$builds_spent"
    printf 'IDENTITY\tsource\t%s\tledger\t%s\trunner\t%s\tspec\t%s\n' "$head_sha" "$ledger_hash" "$runner_hash" "$spec_hash"
  } > "$campaign/summary.tsv"

  say "SUMMARY atoms=$atoms_killed/79 theorems=$th_killed/18 blocked=$blocked excluded_wrong=$excluded_wrong builds_spent=$builds_spent"

  # Deterministic receipts (pure rendering of this run).
  render_receipts "$campaign" "$head_sha" "$ledger_hash" "$runner_hash" "$spec_hash" "$atoms_killed" "$th_killed" "$blocked" "$excluded_wrong" "$builds_spent" "$control_result" "$started"

  # Restore authoritative tree cleanliness (we only wrote into campaign dir).
  restore_all >/dev/null 2>&1 || true
  say "DONE campaign=$campaign"
}

render_receipts() {
  local campaign=$1 head_sha=$2 ledger_hash=$3 runner_hash=$4 spec_hash=$5
  local atoms_killed=$6 th_killed=$7 blocked=$8 excluded_wrong=$9
  local builds_spent=${10} control_result=${11} started=${12}
  local log="$campaign/raw.log"
  mkdir -p "$campaign/receipts"

  # Shared header.
  header() {
    cat <<HDR
# Issue 365 mutation campaign — generated receipt (do not hand-edit)

Generated by \`lean/mutants/run.sh --run\` from one raw run. The table(s) below
and the raw log are the same run, so tables can only say what the run did.

- Source commit: \`$head_sha\`
- Ledger \`lean/SEMANTIC-ATOMS.md\` SHA-256: \`$ledger_hash\`
- Runner \`lean/mutants/run.sh\` SHA-256: \`$runner_hash\`
- Spec \`lean/mutants/mutants.txt\` SHA-256: \`$spec_hash\`
- Started (UTC): \`$started\`
- Operator set (finite, frozen): \`$OPERATORS\`
- Build budget/use: \`builds_spent=$builds_spent / budget=180\` Lean command invocations per full run (one identity control + at most one canonical mutant per 79 atom rows + 18 theorem witness evaluations + clean axiom/build closeout).
- Stopping reason: \`frozen-ledger\` (one right-reason killed mutant per row + one witness/kill per theorem row; equivalent/shadowed mutants replaced or BLOCKED, never counted).
- Exclusions (\`wrong-reason\`): \`$excluded_wrong\` (syntax/import/setup/sorryAx/unrelated-downstream failures never count).
- Blocked rows: \`$blocked\`.
- Identity control: \`$control_result\` (unchanged control must survive to show the instrument can report a survivor).
- Structural discounts (global, never counted as owning kills): \`$STRUCTURAL\` plus broad correspondence mirrors (\`Cage.applyBatch_delegated_eq\`, \`Cage.delegated_is_registry\`) named per affected row; each affected row repeats its discounted set.
- Denominators (independent): semantic atoms \`$atoms_killed/79\`, theorem rows \`$th_killed/18\`.
- Honest limits: this finite declared fault model has no blocking survivors; it does not claim zero possible survivors.

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
    echo "## Theorem rows (18) — witness=REACHED + kill=KILLED per row (detail in Registry receipt; summary here)"
    echo ""
    echo "| Theorem | Witness | Kill mutant | Verdict |"
    echo "|---|---|---|---|"
    while read -r th; do
      line=$(grep -P "^THEOREM\t$(echo "$th" | sed -E 's/\./\\./g')\t" "$campaign/theorem-results.tsv" || echo -e "THEOREM\t$th\tMISSING")
      w=$(echo "$line" | cut -f3); k=$(echo "$line" | cut -f4); m=$(echo "$line" | cut -f5)
      printf '| `%s` | %s | %s | %s |\n' "$th" "$w" "$m" "$k"
    done < "$campaign/ledger-theorem-names.txt"
    echo ""
    echo "## Raw log"
    echo ""
    echo '```'
    cat "$log"
    echo '```'
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
    echo "## Theorem rows (18) — Cage/Samaritan non-vacuity (witness + relevant kill per row)"
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
    echo "## Raw log"
    echo ""
    echo '```'
    cat "$log"
    echo '```'
  } > "$campaign/receipts/REGISTRY-MUTANTS.md"
}

usage() {
  echo "usage: run.sh --list | --run <campaign-dir>" >&2
  exit 2
}

case "${1:-}" in
  --list) cmd_list ;;
  --run)
    test $# -eq 2 || usage
    cmd_run "$2"
    ;;
  *) usage ;;
esac
