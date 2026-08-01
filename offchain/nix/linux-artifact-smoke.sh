#!/usr/bin/env bash
# linux-artifact-smoke — smoke-test Linux release artifacts.
#
# Usage:
#   linux-artifact-smoke \
#     --artifacts-dir <dir> \
#     --artifact-version <version> \
#     --executable-name <name> \
#     --expected-version <version>
#
# Checks (all must pass or the script exits 1):
#   1. An AppImage exists in <dir> and can be extracted
#   2. The extracted binary runs and prints <expected-version>
#   3. The CA certificate bundle is present in the extracted closure
set -euo pipefail

ARTIFACTS_DIR=""
ARTIFACT_VERSION=""
EXECUTABLE_NAME=""
EXPECTED_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
    --artifact-version) ARTIFACT_VERSION="$2"; shift 2 ;;
    --executable-name) EXECUTABLE_NAME="$2"; shift 2 ;;
    --expected-version) EXPECTED_VERSION="$2"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

for var in ARTIFACTS_DIR ARTIFACT_VERSION EXECUTABLE_NAME EXPECTED_VERSION; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: --${var,,//_/-} is required" >&2
    exit 1
  fi
done

if [[ ! -d "$ARTIFACTS_DIR" ]]; then
  echo "FAIL: artifacts directory not found: $ARTIFACTS_DIR" >&2
  exit 1
fi

echo "=== linux-artifact-smoke ==="
echo "  artifacts-dir:    $ARTIFACTS_DIR"
echo "  artifact-version: $ARTIFACT_VERSION"
echo "  executable-name:  $EXECUTABLE_NAME"
echo "  expected-version: $EXPECTED_VERSION"
echo ""

FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=1; }
pass() { echo "PASS: $*"; }

# ── 1. Find and extract the AppImage ──────────────────────────────────
appimage="$(find "$ARTIFACTS_DIR" -maxdepth 1 -name '*.AppImage' -type f | head -1 || true)"
if [[ -z "$appimage" ]]; then
  fail "no AppImage found in $ARTIFACTS_DIR"
  echo ""
  echo "linux-artifact-smoke: FAILED" >&2
  exit 1
fi
echo "--- AppImage: $(basename "$appimage")"

extract_dir="$(mktemp -d)"
# --appimage-extract works without FUSE (unpacks into squashfs-root/).
if ! "$appimage" --appimage-extract >/dev/null 2>&1; then
  # Fall back: some AppImages need the flag before any other arg.
  if ! (cd "$extract_dir" && "$appimage" --appimage-extract >/dev/null 2>&1); then
    fail "could not extract AppImage (tried --appimage-extract)"
    rm -rf "$extract_dir"
    echo ""
    echo "linux-artifact-smoke: FAILED" >&2
    exit 1
  fi
fi

# The extraction creates squashfs-root/ in the current directory.
if [[ -d squashfs-root ]]; then
  mv squashfs-root "$extract_dir/squashfs-root"
fi

if [[ ! -d "$extract_dir/squashfs-root" ]]; then
  fail "AppImage extraction did not produce squashfs-root/"
  rm -rf "$extract_dir"
  echo ""
  echo "linux-artifact-smoke: FAILED" >&2
  exit 1
fi
pass "AppImage extracted"

# ── 2. Find and run the binary, check version ─────────────────────────
bin="$(find "$extract_dir/squashfs-root" -name "$EXECUTABLE_NAME" -type f | head -1 || true)"
if [[ -z "$bin" ]]; then
  fail "no '$EXECUTABLE_NAME' binary found in extracted AppImage"
  rm -rf "$extract_dir"
  echo ""
  echo "linux-artifact-smoke: FAILED" >&2
  exit 1
fi

chmod +x "$bin" 2>/dev/null || true
output="$("$bin" --version 2>&1)" || {
  fail "'$EXECUTABLE_NAME --version' exited non-zero"
  rm -rf "$extract_dir"
  echo ""
  echo "linux-artifact-smoke: FAILED" >&2
  exit 1
}

if [[ "$output" == *"$EXPECTED_VERSION"* ]]; then
  pass "version output contains '$EXPECTED_VERSION': $output"
else
  fail "version output '$output' does not contain '$EXPECTED_VERSION'"
fi

# ── 3. CA certificate bundle check ────────────────────────────────────
# The ckeri wrapper exports SSL_CERT_FILE pointing at the cacert bundle.
# After extraction, verify the bundle file actually exists in the closure.
ca_found=0
# Check for the standard nix cacert paths.
for ca_path in \
  "$extract_dir"/squashfs-root/nix/store/*/etc/ssl/certs/ca-bundle.crt \
  "$extract_dir"/squashfs-root/nix/store/*/etc/ca-certificates/ca-bundle.crt \
  "$extract_dir"/squashfs-root/etc/ssl/certs/ca-bundle.crt; do
  if [[ -f "$ca_path" ]]; then
    ca_found=1
    pass "CA bundle found: $ca_path"
    break
  fi
done

if [[ $ca_found -eq 0 ]]; then
  # Also check if the wrapper script references SSL_CERT_FILE and the
  # target exists.
  wrapper="$(find "$extract_dir/squashfs-root" -name "$EXECUTABLE_NAME" -path '*/bin/*' -type f | head -1 || true)"
  if [[ -n "$wrapper" ]] && grep -q 'SSL_CERT_FILE' "$wrapper" 2>/dev/null; then
    cert_path="$(grep -oP 'SSL_CERT_FILE="\K[^"]+' "$wrapper" 2>/dev/null | head -1 || true)"
    if [[ -n "$cert_path" ]]; then
      # The path may be absolute (nix store) — check inside the squashfs.
      if [[ -f "$extract_dir/squashfs-root$cert_path" ]] || [[ -f "$cert_path" ]]; then
        ca_found=1
        pass "CA bundle found via SSL_CERT_FILE: $cert_path"
      fi
    fi
  fi
fi

if [[ $ca_found -eq 0 ]]; then
  fail "CA certificate bundle not found in extracted AppImage closure"
fi

# ── Cleanup and summary ───────────────────────────────────────────────
rm -rf "$extract_dir"

echo ""
if [[ $FAIL -ne 0 ]]; then
  echo "linux-artifact-smoke: FAILED" >&2
  exit 1
fi
echo "linux-artifact-smoke: all checks passed"
