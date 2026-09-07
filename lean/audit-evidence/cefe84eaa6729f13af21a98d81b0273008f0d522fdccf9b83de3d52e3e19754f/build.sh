#!/usr/bin/env bash
set -euo pipefail
cd /code/cardano-keri-368/lean
evidence=$(cat /tmp/epic-367/to-368/evidence-path)
if test -e .lake; then mv .lake /tmp/epic-367/to-368/lake-before-release; fi
date -u +%FT%TZ > "$evidence/build-start.txt"
printf 'initial .lake absent\n' > "$evidence/build-precondition.txt"
set +e
nix shell --no-write-lock-file ../offchain#lean --command lake build > "$evidence/build.log" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$evidence/build.exit"
date -u +%FT%TZ > "$evidence/build-end.txt"
exit "$rc"
