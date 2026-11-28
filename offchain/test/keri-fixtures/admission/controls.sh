#!/usr/bin/env bash
# Controls of the instruments: each mutation of a copy of the recorded evidence must make the check fail, and the
# unmodified evidence must pass. Needs nix (keripy's shell only supplies a Python interpreter).
#   bash controls.sh [evidence directory]        (default: ./evidence)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EV="$(cd "${1:-$HERE/evidence}" && pwd)"
PY=(nix develop --no-write-lock-file "$HERE/.." --command python)
fail=0

expect() { # name, expected exit (0 or nonzero), command...
  local name="$1" want="$2"; shift 2
  if "$@" > /dev/null 2>&1; then got=0; else got=1; fi
  if [ "$want" = "$got" ]; then echo "ok    $name"; else echo "FAIL  $name (expected exit $want, got $got)"; fail=1; fi
}

mutate() { # name, python statement over d (the loaded json) for a file
  local name="$1" file="$2" stmt="$3" tmp; tmp="$(mktemp -d)"; cp -r "$EV"/. "$tmp"/
  "${PY[@]}" -c "
import json,sys
p='$tmp/$file'
d=json.load(open(p))
$stmt
json.dump(d,open(p,'w'))"
  if err="$("${PY[@]}" "$HERE/matrix.py" "$tmp" "$tmp/out" 2>&1 >/dev/null)"; then echo "FAIL  $name (the matrix was written)"; fail=1
  elif echo "$err" | grep -q "completeness checks failed"; then echo "ok    $name: $(echo "$err" | sed -n 2p | cut -c1-90)"
  else echo "FAIL  $name (failed for another reason: $(echo "$err" | tail -1 | cut -c1-90))"; fail=1; fi
  rm -rf "$tmp"
}

expect "unmodified evidence passes" 0 "${PY[@]}" "$HERE/matrix.py" "$EV" "$(mktemp -d)/out"
mutate "an Aiken advance verdict is missing" advance-comparison.json "d.pop()"
mutate "an Aiken advance verdict is empty" advance-comparison.json "d[0]['chain']=''"
mutate "a registration verdict is missing" registration-comparison.json "d.pop()"
mutate "a threshold result is missing" thresholds-comparison.json "d[0]['lean']='no row'"
mutate "a model row is missing" comparison.json "d.pop(0)"
mutate "a persisted event loses its stored-bytes equality" keripy-results.json "d['cases'][0]['steps'][-1]['readback']['storedBytesEqual']=False"
mutate "a persisted event has another SAID at its position" keripy-results.json "d['cases'][0]['steps'][-1]['readback']['saidAtSn']='x'"
mutate "a context step was not persisted" keripy-results.json "d['cases'][3]['steps'][0]['outcome']='escrowed'"

# the comparison itself: flip the model's verdict for R01 and require the comparison to report a disagreement
tmp="$(mktemp -d)"; cp "$EV/keripy-results.json" "$tmp/"
sed 's/^\({"case":"R01",.*"rotationValid":\)true/\1false/' "$EV/lean-output.jsonl" > "$tmp/lean-output.jsonl"
cmp -s "$EV/lean-output.jsonl" "$tmp/lean-output.jsonl" && { echo "FAIL  the control did not change the model output"; fail=1; }
if ADMISSION_OUT="$tmp" "${PY[@]}" "$HERE/compare.py" | grep -q "^R01 subject WE-REFUSE"; then echo "ok    a flipped model verdict for R01 is reported as a disagreement"; else echo "FAIL  flipped verdict not reported"; fail=1; fi
exit $fail
