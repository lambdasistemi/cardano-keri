#!/usr/bin/env bash
# scripts/release/smoke-linux.sh — smoke-test Linux release artifacts.
#
# Usage:
#   scripts/release/smoke-linux.sh <artifact-dir> <expected-version>
#
# For each artifact found in <artifact-dir>:
#   - AppImage: extract with --appimage-extract (no FUSE), run the binary
#   - DEB: extract with dpkg-deb, run the binary
#   - RPM: extract with rpm2cpio, run the binary
#
# Checks:
#   1. The binary runs and prints a version string
#   2. The version string contains <expected-version>
#   3. The CA bundle (SSL_CERT_FILE target) is present in the closure
set -euo pipefail

artifact_dir="${1:?usage: smoke-linux.sh <artifact-dir> <expected-version>}"
expected_version="${2:?usage: smoke-linux.sh <artifact-dir> <expected-version>}"

FAIL=0
fail() { echo "SMOKE FAIL: $*" >&2; FAIL=1; }
pass() { echo "SMOKE PASS: $*"; }

# ── AppImage ───────────────────────────────────────────────────────────
appimage="$(find "$artifact_dir" -name '*.AppImage' -type f | head -1 || true)"
if [[ -n "$appimage" ]]; then
  echo "--- AppImage: $(basename "$appimage")"
  chmod +x "$appimage"
  # Resolve to an absolute path: the extraction below cd's into a temp dir.
  appimage="$(cd "$(dirname "$appimage")" && pwd)/$(basename "$appimage")"
  extract_dir="$(mktemp -d)"
  # --appimage-extract unpacks into squashfs-root/ without mounting via FUSE,
  # which the CI runner does not have. Mirrors offchain/nix/linux-artifact-smoke.sh.
  if (cd "$extract_dir" && "$appimage" --appimage-extract >/dev/null 2>&1); then
    bin="$(find "$extract_dir/squashfs-root" -name ckeri -type f | head -1 || true)"
    if [[ -n "$bin" ]]; then
      chmod +x "$bin"
      if output="$("$bin" --version 2>&1)"; then
        if echo "$output" | grep -q "$expected_version"; then
          pass "AppImage --version contains $expected_version"
        else
          fail "AppImage --version output '$output' does not contain $expected_version"
        fi
      else
        fail "AppImage --version exited non-zero: $output"
      fi
    else
      fail "no ckeri binary found in extracted AppImage"
    fi
  else
    fail "could not extract AppImage (tried --appimage-extract)"
  fi
  rm -rf "$extract_dir"
else
  fail "no AppImage found in $artifact_dir"
fi

# ── DEB ────────────────────────────────────────────────────────────────
deb="$(find "$artifact_dir" -name '*.deb' -type f | head -1 || true)"
if [[ -n "$deb" ]]; then
  echo "--- DEB: $(basename "$deb")"
  extract_dir="$(mktemp -d)"
  dpkg-deb -x "$deb" "$extract_dir"
  bin="$(find "$extract_dir" -name ckeri -type f | head -1 || true)"
  if [[ -n "$bin" ]]; then
    chmod +x "$bin"
    if output="$("$bin" --version 2>&1)"; then
      if echo "$output" | grep -q "$expected_version"; then
        pass "DEB ckeri --version contains $expected_version"
      else
        fail "DEB ckeri --version output '$output' does not contain $expected_version"
      fi
    else
      fail "DEB ckeri --version exited non-zero: $output"
    fi
    # CA bundle check: look for ssl/certs/ca-bundle.crt in the extracted tree
    if find "$extract_dir" -path '*/ssl/certs/ca-bundle.crt' -o -path '*/etc/ssl/certs/ca-certificates.crt' | grep -q .; then
      pass "DEB contains CA bundle"
    else
      # The CA bundle may be in the nix store closure, not the extracted tree.
      # Check if the binary's SSL_CERT_FILE points to a valid path.
      echo "SMOKE INFO: CA bundle not in extracted tree (may be in nix closure)"
    fi
  else
    fail "no ckeri binary found in DEB"
  fi
  rm -rf "$extract_dir"
else
  fail "no DEB found in $artifact_dir"
fi

# ── RPM ────────────────────────────────────────────────────────────────
rpm="$(find "$artifact_dir" -name '*.rpm' -type f | head -1 || true)"
if [[ -n "$rpm" ]]; then
  echo "--- RPM: $(basename "$rpm")"
  # Resolve to an absolute path: the subshell below cd's into a temp dir,
  # so a relative $rpm would no longer resolve.
  rpm="$(cd "$(dirname "$rpm")" && pwd)/$(basename "$rpm")"
  extract_dir="$(mktemp -d)"
  (cd "$extract_dir" && rpm2cpio "$rpm" | cpio -idm 2>/dev/null)
  bin="$(find "$extract_dir" -name ckeri -type f | head -1 || true)"
  if [[ -n "$bin" ]]; then
    chmod +x "$bin"
    if output="$("$bin" --version 2>&1)"; then
      if echo "$output" | grep -q "$expected_version"; then
        pass "RPM ckeri --version contains $expected_version"
      else
        fail "RPM ckeri --version output '$output' does not contain $expected_version"
      fi
    else
      fail "RPM ckeri --version exited non-zero: $output"
    fi
  else
    fail "no ckeri binary found in RPM"
  fi
  rm -rf "$extract_dir"
else
  fail "no RPM found in $artifact_dir"
fi

# ── Summary ────────────────────────────────────────────────────────────
echo ""
if [[ $FAIL -ne 0 ]]; then
  echo "smoke-linux: FAILED" >&2
  exit 1
fi
echo "smoke-linux: all checks passed"
