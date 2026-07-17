#!/usr/bin/env bash
# Reproducible keripy fixture regeneration for #106.
#
# keripy is not packaged in nixpkgs, and pysodium's ctypes lookup does not
# honor LD_LIBRARY_PATH on NixOS. This wrapper pins python + libsodium via nix,
# installs keripy at a fixed version into a uv venv, and exports SODIUM_LIB so
# gen_fixtures.py can patch ctypes.util.find_library.
#
# NETWORK: the first run downloads keripy==1.3.5 (uv caches afterward). This is
# therefore NOT wired into the offline `just ci` gate; it is a manual/opt-in
# regeneration + drift target. The committed fixtures under fixtures/ are the
# durable source of truth the Haskell/Aiken suites consume; this script only
# reproduces them.
set -euo pipefail

KERI_VERSION="1.3.5"
VENV="${KERI_VENV:-/tmp/keri-venv-106}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SODIR="$(nix build nixpkgs#libsodium --no-link --print-out-paths)/lib"
export SODIUM_LIB="$SODIR/libsodium.so"

nix shell nixpkgs#python312 nixpkgs#uv --command bash -euc '
  VENV="'"$VENV"'"
  if [ ! -x "$VENV/bin/python" ]; then
    uv venv --python python3.12 "$VENV"
  fi
  uv pip install --python "$VENV/bin/python" "keri=='"$KERI_VERSION"'" >/dev/null
  "$VENV/bin/python" "'"$HERE"'/gen_fixtures.py"
'
