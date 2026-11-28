#!/usr/bin/env bash
# Controls of the instruments. Each mutation of a copy of the recorded evidence must make the normal reporting
# path (the comparison script that reads the receipt, and the matrix) exit non-zero with the stated reason, and the
# unmodified evidence must pass. Needs nix (the keripy shell supplies the Python interpreter).
#   bash controls.sh [evidence directory]        (default: ./evidence)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EV="$(cd "${1:-$HERE/evidence}" && pwd)"
PY=(nix develop --no-write-lock-file "$HERE/.." --command python)
fail=0
n=0

# run <name> <expected phrase> <env dir> -- command...   (expects exit non-zero and the phrase on stderr)
expect_reject() {
  local name="$1" phrase="$2" dir="$3"; shift 4
  local err; n=$((n + 1))
  if err="$(ADMISSION_OUT="$dir" "$@" 2>&1 >/dev/null)"; then echo "FAIL  $name: accepted"; fail=1
  elif grep -q -F "$phrase" <<<"$err"; then echo "ok    $name"
  else echo "FAIL  $name: rejected for another reason: $(tail -1 <<<"$err" | cut -c1-110)"; fail=1; fi
}

# mutate <file> <python statements over d (json) or lines (text)>; prints the new directory
copy() { local t; t="$(mktemp -d)"; cp -r "$EV"/. "$t"/; echo "$t"; }
json_edit() { "${PY[@]}" -c "
import json
p='$1/$2'
d=json.load(open(p))
$3
json.dump(d,open(p,'w'))" > /dev/null; }
text_edit() { "${PY[@]}" -c "
p='$1/$2'
lines=open(p).read().split('\n')
$3
open(p,'w').write('\n'.join(lines))" > /dev/null; }
jsonl_edit() { text_edit "$1" "$2" "$3"; }

REG=("${PY[@]}" "$HERE/registration.py" compare)
ADV=("${PY[@]}" "$HERE/advance.py" compare)
THR=("${PY[@]}" "$HERE/compare_thresholds.py")
CMP=("${PY[@]}" "$HERE/compare.py")
MAT=("${PY[@]}" "$HERE/matrix.py")

# the unmodified evidence passes every reporting path
t="$(copy)"; n=$((n + 1))
if ADMISSION_OUT="$t" "${CMP[@]}" >/dev/null 2>&1 && ADMISSION_OUT="$t" "${REG[@]}" "$t/aiken-registration.txt" >/dev/null 2>&1 \
   && ADMISSION_OUT="$t" "${ADV[@]}" "$t/aiken-advance.txt" >/dev/null 2>&1 && ADMISSION_OUT="$t" "${THR[@]}" >/dev/null 2>&1 \
   && ADMISSION_OUT="$t" "${MAT[@]}" "$t" "$t/matrix-rerun" >/dev/null 2>&1; then echo "ok    unmodified evidence passes every reporting path"; else echo "FAIL  unmodified evidence"; fail=1; fi

# 1. a threshold row removed from the comparison: the matrix reports the missing fixture
t="$(copy)"; json_edit "$t" thresholds-comparison.json "d=[r for r in d if r['id']!='T01']"
expect_reject "threshold fixture T01 missing from the comparison (matrix)" "threshold rows: missing ['T01']" "$t" -- "${MAT[@]}" "$t" "$t/o"

# 2. a model output removed: the comparison reports it instead of calling the case not comparable
t="$(copy)"; jsonl_edit "$t" lean-output.jsonl "lines=[l for l in lines if '\"case\":\"R01\"' not in l]"
expect_reject "model output for R01 removed (comparison)" "model results differ" "$t" -- "${CMP[@]}"

# 3. a typed verdict replaced by an unknown marker
t="$(copy)"; text_edit "$t" aiken-registration.txt "
i=[k for k,l in enumerate(lines) if 'reg_I02' in l][0]
j=[k for k in range(i,len(lines)) if lines[k].strip().startswith('│ |')][0]
lines[j]='    │ | Mystery'"
expect_reject "unknown verdict for I02 (registration comparison)" "unrecognized verdict 'Mystery'" "$t" -- "${REG[@]}" "$t/aiken-registration.txt"
expect_reject "unknown verdict for I02 (matrix)" "unrecognized verdict 'Mystery'" "$t" -- "${MAT[@]}" "$t" "$t/o"

# 4. an evaluation receipt removed (the empty signer subset of T01)
t="$(copy)"; text_edit "$t" aiken-thresholds.txt "lines=[l for l in lines if 'ev_T01_none' not in l]"
expect_reject "evaluation of T01 with no signer removed (threshold comparison)" "no result for ev_T01_none" "$t" -- "${THR[@]}"
expect_reject "evaluation of T01 with no signer removed (matrix)" "no result for ev_T01_none" "$t" -- "${MAT[@]}" "$t" "$t/o"

# 5. a context step keeps its accepted status while its stored bytes contradict the log
t="$(copy)"; json_edit "$t" keripy-results.json "
c=[c for c in d['cases'] if c['id']=='R01'][0]
c['steps'][0]['readback']['storedBytesEqual']=False"
expect_reject "context readback of R01's inception contradicts its status (matrix)" "R01: step icp is accepted without a consistent log readback" "$t" -- "${MAT[@]}" "$t" "$t/o"

# 6. a second, conflicting typed verdict under one test
t="$(copy)"; text_edit "$t" aiken-registration.txt "
i=[k for k,l in enumerate(lines) if 'reg_I02' in l][0]
j=[k for k in range(i,len(lines)) if lines[k].strip().startswith('│ |')][0]
lines.insert(j+1,'    │ | E2AidMismatch')"
expect_reject "two verdicts under I02 (registration comparison)" "reg_I02 has 2 verdict traces" "$t" -- "${REG[@]}" "$t/aiken-registration.txt"
expect_reject "two verdicts under I02 (matrix)" "reg_I02 has 2 verdict traces" "$t" -- "${MAT[@]}" "$t" "$t/o"

# 7. the completion summary removed from a suite
t="$(copy)"; text_edit "$t" aiken-registration.txt "lines=[l for l in lines if ' tests | ' not in l]"
expect_reject "no completion summary (registration comparison)" "no completion summary" "$t" -- "${REG[@]}" "$t/aiken-registration.txt"
expect_reject "no completion summary (matrix)" "no completion summary" "$t" -- "${MAT[@]}" "$t" "$t/o"
t="$(copy)"; text_edit "$t" aiken-advance.txt "lines=[l for l in lines if ' tests | ' not in l]"
expect_reject "no completion summary (advance comparison)" "no completion summary" "$t" -- "${ADV[@]}" "$t/aiken-advance.txt"

# further: an unexpected extra result, a missing advance result, a model threshold subset missing
t="$(copy)"; text_edit "$t" aiken-advance.txt "
i=[k for k,l in enumerate(lines) if 'adv_W09' in l][0]
lines=lines[:i]+lines[i+3:]"
expect_reject "advance result for W09 removed (advance comparison)" "no result for adv_W09" "$t" -- "${ADV[@]}" "$t/aiken-advance.txt"
t="$(copy)"; jsonl_edit "$t" lean-thresholds.jsonl "
import json
r=json.loads(lines[0]); r['satisfied'].pop('0'); lines[0]=json.dumps(r)"
expect_reject "model threshold result misses a signer subset (threshold comparison)" "does not hold exactly its" "$t" -- "${THR[@]}"
t="$(copy)"; json_edit "$t" keripy-results.json "d['cases']=[c for c in d['cases'] if c['id']!='X07']"
expect_reject "a corpus case missing from the keripy receipt (matrix)" "keripy results: missing ['X07']" "$t" -- "${MAT[@]}" "$t" "$t/o"

# the comparison itself: flip the model's verdict for R01 and require a disagreement to be reported
t="$(copy)"; text_edit "$t" lean-output.jsonl "lines=[l.replace('\"rotationValid\":true','\"rotationValid\":false') if '\"case\":\"R01\"' in l else l for l in lines]"
n=$((n + 1))
if ADMISSION_OUT="$t" "${CMP[@]}" 2>/dev/null | grep -q "^R01 subject WE-REFUSE"; then echo "ok    a flipped model verdict for R01 is reported as a disagreement"; else echo "FAIL  flipped verdict not reported"; fail=1; fi

echo "$n controls, $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail
