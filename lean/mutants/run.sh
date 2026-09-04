#!/usr/bin/env bash
# The checkpoint machine's mutation campaign (lean4 rule: a passing build proves nothing about
# whether a theorem constrains the definition it names).
#
#   lean/mutants/run.sh [<work-dir>]        # from anywhere; writes <work-dir>/campaign.log and
#                                           # lean/CHECKPOINT-MUTANTS.md (table + raw log) from that log
#
# For every record of mutants.txt (`### <name> | <what it breaks>`, `@@@ <module>`, the needle between
# `<<<` and `>>>`, the replacement after `>>>`): copy lean/ (with its build cache) to the work dir, apply
# the mutant by exact text replacement — refused unless the needle occurs exactly once — rebuild the
# model (it must compile, or the red is for the wrong reason), rebuild the goals (it must fail), read
# the failing theorem names off the error lines. A mutant is RED FOR THE RIGHT REASON when a theorem
# outside the STRUCTURAL list fails: T7_step_iff_stepFn mirrors Step in stepFn and T9's proof enumerates
# every constructor, so both red on almost any Step mutant and say nothing about the guard.
#
# The runner emits its own controls into the log, so the receipt can only say what the run did:
#   CONTROL identity  — the needle equal to its replacement: the goals must still build (SURVIVED as
#                       the control must), or the instrument cannot report a survivor;
#   DISCOUNT          — the structural theorems, named once in the header and per row.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); LEAN=$(cd "$HERE/.." && pwd)
W=${1:-$(mktemp -d /tmp/ck-mutants-XXXX)}; mkdir -p "$W"
LOG=$W/campaign.log; : > "$LOG"
STRUCTURAL="T7_step_iff_stepFn T9_juvenility_is_consumer_only"
LAKE="nix shell nixpkgs#lean4 -c lake"
say() { echo "$*" | tee -a "$LOG"; }
say "CAMPAIGN $(date -u +%Y-%m-%dT%H:%M:%SZ) lean=$LEAN head=$(git -C "$LEAN" rev-parse --short HEAD 2>/dev/null || echo ?) mutants=$(grep -c '^### ' "$HERE/mutants.txt")"
say "DISCOUNT structural theorems, never counted as a kill: $STRUCTURAL"
rm -rf "$W/lean"; cp -r "$LEAN" "$W/lean"
awk '/^theorem /{split($2,a," "); print NR, a[1]}' "$LEAN/CardanoKeri/CheckpointGoals.lean" > "$W/thmlines.txt"
names_for_lines() { while read -r ln; do awk -v L="$ln" '$1<=L{n=$2} END{print n}' "$W/thmlines.txt"; done | sort -u | tr '\n' ' '; }
restore() { cp "$LEAN/CardanoKeri/Checkpoint.lean" "$W/lean/CardanoKeri/Checkpoint.lean"; cp "$LEAN/CardanoKeri/CheckpointGoals.lean" "$W/lean/CardanoKeri/CheckpointGoals.lean"; }
count_needle() { perl -0777 -e 'local $/; open(N,"<",$ARGV[0]); my $n=<N>; open(F,"<",$ARGV[1]); my $s=<F>; my $c=()=$s=~/\Q$n\E/g; print $c' "$1" "$2"; }
apply_needle() { perl -0777 -i -e 'local $/; open(N,"<",$ARGV[0]); my $n=<N>; open(R,"<",$ARGV[1]); my $r=<R>; my $f=$ARGV[2]; open(F,"<",$f); my $s=<F>; close F; $s =~ s/\Q$n\E/$r/; open(O,">",$f); print O $s; close O' "$1" "$2" "$3"; }
# one mutant: prints the verdict line; returns 0 when the goals still build (survivor), 1 when red, 2 when refused
run_one() { # name file needle repl
  local n=$1 file=$2 needle=$3 repl=$4
  local target="$W/lean/CardanoKeri/$file.lean"
  restore
  local c; c=$(count_needle "$needle" "$target")
  if [ "$c" != "1" ]; then say "$n: REFUSED needle applies $c times"; return 2; fi
  apply_needle "$needle" "$repl" "$target"
  if ! (cd "$W/lean" && $LAKE build CardanoKeri.Checkpoint > "$W/$n.model.log" 2>&1); then say "$n: RED for the WRONG reason (the mutated model does not compile)"; return 2; fi
  if (cd "$W/lean" && $LAKE build CardanoKeri.CheckpointGoals > "$W/$n.goals.log" 2>&1); then return 0; fi
  local failing; failing=$(grep -oE 'error: CardanoKeri/CheckpointGoals\.lean:[0-9]+:[0-9]+' "$W/$n.goals.log" | cut -d: -f3 | names_for_lines)
  local counted="" discounted=""
  for t in $failing; do case " $STRUCTURAL " in *" $t "*) discounted="$discounted $t";; *) counted="$counted $t";; esac; done
  echo "$counted|$discounted" > "$W/$n.verdict"; return 1
}
# the identity control, emitted by the runner itself
perl -0ne 'print "$1" if /^### M1-\S+ \| [^\n]*\n\@\@\@ \S+\n<<<\n(.*?)\n>>>/sm' "$HERE/mutants.txt" > "$W/M0.needle"
cp "$W/M0.needle" "$W/M0.repl"
if run_one M0-identity-control Checkpoint "$W/M0.needle" "$W/M0.repl"; then say "CONTROL M0-identity-control: SURVIVED as the control must (needle = replacement; the instrument reports a survivor)"; else say "CONTROL M0-identity-control: FAILED — the instrument reds an unchanged model; the campaign is void"; exit 1; fi
ok=0; total=0; survivors=0
perl -0ne 'while (/^### (\S+) \| ([^\n]*)\n\@\@\@ (\S+)\n<<<\n(.*?)\n>>>\n(.*?)(?=\n### |\z)/smg) { my ($n,$d,$f,$a,$b)=($1,$2,$3,$4,$5); $b =~ s/\n\z//; open(O,">","'"$W"'/$n.spec"); print O "$d\n$f\n"; close O; open(O,">","'"$W"'/$n.needle"); print O $a; close O; open(O,">","'"$W"'/$n.repl"); print O $b; close O; }' "$HERE/mutants.txt"
for spec in $(ls "$W"/M[1-9]*.spec | sort -V); do
  n=$(basename "$spec" .spec); desc=$(sed -n 1p "$spec"); file=$(sed -n 2p "$spec"); total=$((total+1))
  run_one "$n" "$file" "$W/$n.needle" "$W/$n.repl"; st=$?
  if [ $st -eq 2 ]; then continue; fi
  if [ $st -eq 0 ]; then say "$n: SURVIVED (goals still build) — $desc"; survivors=$((survivors+1)); continue; fi
  IFS='|' read -r counted discounted < "$W/$n.verdict"
  if [ -z "${counted// /}" ]; then say "$n: SURVIVED except structural (only${discounted} red) — $desc"; survivors=$((survivors+1)); continue; fi
  ok=$((ok+1)); say "$n: RED for the right reason (failing:${counted}; discounted:${discounted:- none}) — $desc"
done
say "TOTAL $ok/$total red for the right reason, $survivors survivor(s), structural discounted: $STRUCTURAL"
# the axiom account, on a clean copy (no build cache: a campaign's oleans can change the answer)
rm -rf "$W/clean"; mkdir -p "$W/clean"; (cd "$LEAN" && tar --exclude=.lake -cf - .) | (cd "$W/clean" && tar -xf -)
{ echo "import CardanoKeri.CheckpointGoals"; grep -oE '^theorem\s+[A-Za-z0-9_'"'"']+' "$LEAN/CardanoKeri/CheckpointGoals.lean" | awk '{print "#print axioms CardanoKeri.Checkpoint." $2}'; } > "$W/Axioms.lean"
if (cd "$W/clean" && $LAKE build CardanoKeri.Checkpoint CardanoKeri.CheckpointGoals > "$W/clean-build.log" 2>&1 && $LAKE env lean "$W/Axioms.lean" > "$W/axioms.log" 2>&1); then
  say "AXIOMS clean build: $(grep -c "depends on axioms\|does not depend" "$W/axioms.log") theorems; $(grep -o "depends on axioms: \[[^]]*\]\|does not depend on any axioms" "$W/axioms.log" | sort | uniq -c | sed -E "s/^ *([0-9]+) (.*)/\1 × \2/" | paste -sd ";" -); sorryAx: $(grep -c sorryAx "$W/axioms.log"); Classical.choice: $(grep -c Classical.choice "$W/axioms.log")"
else say "AXIOMS clean build FAILED (see $W/clean-build.log, $W/axioms.log)"; fi
# the receipt: the table and the raw log, both from this run
OUT=$LEAN/CHECKPOINT-MUTANTS.md
{
cat <<HDR
# Checkpoint machine — mutation campaign (third slice: D-039, D-040)

Generated by \`lean/mutants/run.sh\` from \`lean/mutants/mutants.txt\`; the table below and the raw
log are the same run, so the table can only say what the run did. The lean4 rule: a passing build
proves nothing about whether a theorem constrains the definition it names, so each guard or effect
is broken in a scratch copy of \`CardanoKeri/Checkpoint.lean\`, the model rebuilt (it must compile),
\`CardanoKeri/CheckpointGoals.lean\` rebuilt (it must fail), and the failing theorems read off the
error lines. \`stepFn\` is left intact, so \`T7_step_iff_stepFn\` reds on every \`Step\` mutant and
\`T9_juvenility_is_consumer_only\` (its proof enumerates the constructors) on every arity change: both
are structural and never counted; each row shows what it discounted. The runner's identity control
(needle equal to replacement) runs first and must survive, so the instrument is shown able to report
a survivor. The campaign ends at its set point — one mutant per guard or effect the slice added or
amended, the statement auditor's rows as a floor, the legacy guards of the earlier campaigns re-run —
and does not claim there are no other survivors.

| Mutant | What it breaks | Theorems that caught it (structural aside) | Discounted |
|---|---|---|---|
HDR
grep -E '^M[0-9]+-\S+: RED for the right reason' "$LOG" | sed -E 's/^(M[0-9]+-[^:]+): RED for the right reason \(failing: ?([^;]*); discounted: ?([^)]*)\) — (.*)$/| \1 | \4 | \2 | \3 |/' | sed -E 's/ +\|/ |/g; s/\| +/| /g'
grep -E 'SURVIVED' "$LOG" | grep -v '^CONTROL' | sed -E 's/^/| /; s/$/ | — | — |/' || true
cat <<TAIL

## Raw log

\`\`\`
$(cat "$LOG")
\`\`\`
TAIL
} > "$OUT"
echo "receipt: $OUT"
