#!/usr/bin/env bash
set -euo pipefail
material_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${KERI_SOURCE:=$(cd -- "$material_dir/../.." && pwd)}"
: "${SINGULAR_SOURCE:=$KERI_SOURCE/lean/.lake/packages/singular}"
: "${LEAN_BIN:=$(command -v lean)}"
: "${PYTHON_BIN:=$(command -v python3)}"
: "${TMPDIR:=/tmp}"
run_id=$(date -u +%Y%m%dT%H%M%S)-$$
: "${RUN_DIR:=$TMPDIR/freshness-economics-$run_id}"
export KERI_SOURCE SINGULAR_SOURCE LEAN_BIN TMPDIR RUN_DIR
# Fail before writing receipts into a source checkout or reusing a run directory.
"$PYTHON_BIN" -c 'import pathlib,sys; out,keri,singular = map(lambda p: pathlib.Path(p).resolve(), sys.argv[1:]); assert not out.exists(), "RUN_DIR must be new"; assert not out.is_relative_to(keri) and not out.is_relative_to(singular), "RUN_DIR must be outside source checkouts"' "$RUN_DIR" "$KERI_SOURCE" "$SINGULAR_SOURCE"
mkdir -p "$RUN_DIR" "$TMPDIR"
cp "$material_dir/run.sh" "$RUN_DIR/run.sh.input"
cp "$material_dir/build.py" "$RUN_DIR/build.py.input"
printf '%q ' systemd-run --user --scope --unit="freshness-economics-$run_id" -p MemoryMax=12G -- timeout 1800 "$PYTHON_BIN" "$material_dir/build.py" "$@" > "$RUN_DIR/command.txt"
printf '\n' >> "$RUN_DIR/command.txt"
set +e
systemd-run --user --scope --unit="freshness-economics-$run_id" -p MemoryMax=12G -- timeout 1800 "$PYTHON_BIN" "$material_dir/build.py" "$@" 2>&1 | tee "$RUN_DIR/build.log"
result=${PIPESTATUS[0]}
set -e
printf '%s\n' "$result" > "$RUN_DIR/exit-code.txt"
sha256sum "$RUN_DIR/build.log" > "$RUN_DIR/build.log.sha256"
exit "$result"
