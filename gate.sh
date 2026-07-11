#!/usr/bin/env bash
# PR-life gate for cardano-keri #91 — genesis/registration decision record.
#
# This is a design/docs ticket: the deliverable is a decision-record amendment
# to specs/68-keystate-shape/{identity-model,system-architecture}.md plus the
# ticket-local specs/91-genesis-registration/{spec,plan,tasks}.md. There is no
# build or unit suite to run. The gate therefore enforces (1) doc hygiene and
# (2) the mechanical decision-acceptance check authored RED-first inside the
# decision slice. The gate is dropped in the last commit before mark-ready.
set -euo pipefail
cd "$(dirname "$0")"

# 1. No whitespace errors or leftover conflict markers on changed lines.
git diff --check

# 2. No conflict markers anywhere in the spec tree (belt-and-suspenders).
if git grep -qE '^(<<<<<<<|>>>>>>>) ' -- 'specs/**' 2>/dev/null; then
  echo "gate: leftover conflict markers in specs/"; exit 1
fi

# 3. Deliverable files must exist.
for f in specs/68-keystate-shape/identity-model.md \
         specs/68-keystate-shape/system-architecture.md; do
  [ -f "$f" ] || { echo "gate: missing deliverable $f"; exit 1; }
done

# 4. Decision-acceptance check — authored RED-first in the decision slice.
#    Tolerant while absent so the orchestrator's spec/plan/tasks commits pass;
#    once the slice lands it is executable and enforces the decision content.
if [ -x specs/91-genesis-registration/accept.sh ]; then
  specs/91-genesis-registration/accept.sh
fi

echo "gate: OK"
