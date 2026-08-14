#!/usr/bin/env bash
# Bind a verdict to the published bytes. Every carried identity field is
# reconciled against a producer-owned record: either the record emitted beside
# the built manifest, or the static identity evaluated from the producing Nix
# derivation. Neither editable prose nor an expected-value environment variable
# is an authority. A second decoded identity key -- any JSON spelling -- is RED.
set -euo pipefail

usage() { echo "usage: $0 BYTES" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
bytes=$1
coverage_token=parsed-document
expected_variant=defaultFunSemanticsVariantE

[ -r "$bytes" ] || {
  echo "published bytes unreadable: $bytes" >&2
  exit 1
}

if [ "$(head -c 3 "$bytes" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published bytes carry a UTF-8 BOM; document parse is not the bytes" >&2
  exit 1
fi

if ! jq -e . "$bytes" >/dev/null 2>&1; then
  echo "published bytes are not a JSON document" >&2
  exit 1
fi

# Structural closure over decoded identity leaf paths. A textual key regex
# cannot see "\u0063ommit"; jq --stream can. Repeated keys on later records are
# different paths and are not this object.
dup_path=
dup_first=
dup_last=
while IFS= read -r path; do
  [ -n "$path" ] || continue
  mapfile -t vals < <(jq --stream -c --argjson p "$path" \
    'select(.[0] == $p and (length == 2) and (.[1] != null)) | .[1]' \
    "$bytes")
  if [ "${#vals[@]}" -gt 1 ]; then
    dup_path=$path
    dup_first=${vals[0]}
    dup_last=${vals[${#vals[@]}-1]}
    break
  fi
done < <(jq --stream -r '
  select(.[0][0] == "identity"
    and (length == 2)
    and (.[1] != null))
  | (.[0] | tojson)' "$bytes" | LC_ALL=C sort -u)

if [ -n "$dup_path" ]; then
  echo "AUDIT-SELFTEST leg=second-conforming-parse-differs rc=1 outcome=REFUTED"
  echo "second conforming parse differs: path=$dup_path last_wins=$dup_last first_wins=$dup_first" >&2
  exit 1
fi

find_producer_root() {
  local d
  if [ -n "${CKERI_REPO_ROOT:-}" ]; then
    if [ -f "$CKERI_REPO_ROOT/offchain/flake.lock" ]; then
      printf '%s\n' "$CKERI_REPO_ROOT"
      return 0
    fi
    if [ -f "$CKERI_REPO_ROOT/flake.lock" ]; then
      printf '%s\n' "$(cd "$CKERI_REPO_ROOT/.." && pwd)"
      return 0
    fi
  fi
  d=$(cd "$(dirname "$0")/../.." && pwd)
  if [ -f "$d/offchain/flake.lock" ]; then
    printf '%s\n' "$d"
    return 0
  fi
  if git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1; then
    d=$(git -C "$d" rev-parse --show-toplevel)
    if [ -f "$d/offchain/flake.lock" ]; then
      printf '%s\n' "$d"
      return 0
    fi
  fi
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    d=$(git rev-parse --show-toplevel)
    if [ -f "$d/offchain/flake.lock" ]; then
      printf '%s\n' "$d"
      return 0
    fi
  fi
  return 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/published-identity.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

producer_root=$(find_producer_root || true)
producer_record=
dynamic_record=0
candidate=$(dirname "$bytes")/producer-identity.json
if [ -r "$candidate" ] && jq -e 'type == "object"' "$candidate" >/dev/null 2>&1; then
  producer_record=$candidate
  dynamic_record=1
fi

# Gate mutants of the realized manifest live in a scratch directory, away from
# its sibling producer record. Reuse the supplied artifact's record only when
# the candidate carries the same top-level blueprint digest. Unrelated static
# fixtures must remain bound to the producer evaluated from their own source.
if [ -z "$producer_record" ] \
  && [ -n "${CKERI_PUBLISHED_MANIFEST:-}" ] \
  && [ -r "$CKERI_PUBLISHED_MANIFEST" ]; then
  candidate=$(dirname "$CKERI_PUBLISHED_MANIFEST")/producer-identity.json
  bytes_blueprint=$(jq -r '.blueprint_sha256 // empty' "$bytes")
  published_blueprint=$(jq -r '.blueprint_sha256 // empty' "$CKERI_PUBLISHED_MANIFEST")
  if [ -n "$bytes_blueprint" ] \
    && [ "$bytes_blueprint" = "$published_blueprint" ] \
    && [ -r "$candidate" ] \
    && jq -e 'type == "object"' "$candidate" >/dev/null 2>&1; then
    producer_record=$candidate
    dynamic_record=1
  fi
fi

if [ -z "$producer_record" ] && [ -n "$producer_root" ]; then
  system=$(nix eval --raw --impure --expr builtins.currentSystem 2>/dev/null) || {
    echo "published identity producer cannot be evaluated: Nix system unavailable" >&2
    exit 1
  }
  if ! nix eval --json \
      "$producer_root/offchain#packages.$system.blaster-baseline-manifest.producerStaticIdentity" \
      > "$work/producer-static.json"; then
    echo "published identity producer cannot be evaluated from the baseline derivation" >&2
    exit 1
  fi
  producer_record=$work/producer-static.json
fi

if [ -z "$producer_record" ]; then
  echo "published identity producer record cannot be resolved" >&2
  exit 1
fi

# Legacy Slice-C fixtures carry a subset of the static identity. Production
# manifests carry the complete identity plus blueprint_sha256 and therefore
# require the dynamic record emitted by the manifest producer.
jq -e '.identity | type == "object"' "$bytes" >/dev/null 2>&1 || {
  echo "published identity producer binding is absent" >&2
  exit 1
}
jq -S '.identity' "$bytes" > "$work/actual.json"
jq -S . "$producer_record" > "$work/producer.json"

variant=$(jq -r '.identity.variant // empty' "$bytes")
commit=$(jq -r '.identity.commit // empty' "$bytes")
aiken=$(jq -r '.identity.aiken // empty' "$bytes")
toolchain=$(jq -r '.identity.toolchain // empty' "$bytes")
expected_commit=$(jq -r '.commit // empty' "$producer_record")
expected_aiken=$(jq -r '.aiken // empty' "$producer_record")
expected_toolchain=$(jq -r '.toolchain // empty' "$producer_record")

if [ "$variant" != "$expected_variant" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published identity variant is not $expected_variant" >&2
  exit 1
fi
if [ -z "$commit" ] || [ "$commit" != "$expected_commit" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published identity commit is not the source identity" >&2
  exit 1
fi
if [ -z "$aiken" ] || [ "$aiken" != "$expected_aiken" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published identity aiken is not the producer binding" >&2
  exit 1
fi
if [ -z "$toolchain" ] || [ "$toolchain" != "$expected_toolchain" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published identity toolchain is not the producer binding" >&2
  exit 1
fi

unexpected=$(jq -r --slurpfile producer "$work/producer.json" '
  .identity as $actual
  | [$actual | paths(type != "object" and type != "array") as $p
      | select(($producer[0] | getpath($p)) == null)
      | select($p != ["blueprint_sha256"])
      | ($p | map(tostring) | join("."))]
  | .[0] // empty
' "$bytes")
if [ -n "$unexpected" ]; then
  echo "published identity field is not producer-bound: producer has no field '$unexpected'" >&2
  exit 1
fi

mismatch=$(jq -r --slurpfile producer "$work/producer.json" '
  .identity as $actual
  | [$actual | paths(type != "object" and type != "array") as $p
      | select($p != ["blueprint_sha256"])
      | select(getpath($p) != ($producer[0] | getpath($p)))
      | ($p | map(tostring) | join("."))]
  | .[0] // empty
' "$bytes")
if [ -n "$mismatch" ]; then
  echo "published identity $mismatch is not the producer binding" >&2
  exit 1
fi

if jq -e '.identity | has("blueprint_sha256")' "$bytes" >/dev/null \
  && [ "$dynamic_record" -ne 1 ]; then
  if [ -z "$producer_root" ]; then
    echo "published identity blueprint_sha256 lacks a dynamic producer record" >&2
    exit 1
  fi
  set +e
  built_producer=$(cd "$producer_root/offchain" \
    && nix build --no-link --print-out-paths \
      .#blaster-baseline-manifest 2>/dev/null)
  build_rc=$?
  set -e
  built_producer=$(printf '%s\n' "$built_producer" | tail -1)
  if [ "$build_rc" -ne 0 ] \
    || [ ! -r "$built_producer/producer-identity.json" ]; then
    echo "published identity blueprint_sha256 lacks a resolvable dynamic producer record" >&2
    exit 1
  fi
  producer_record=$built_producer/producer-identity.json
  jq -S . "$producer_record" > "$work/producer.json"
  dynamic_record=1
fi

if [ "$dynamic_record" -eq 1 ] && ! cmp -s "$work/actual.json" "$work/producer.json"; then
  echo "published identity is not exactly the dynamic producer record" >&2
  exit 1
fi

digest=$(sha256sum "$bytes" | cut -d ' ' -f 1)
echo "AUDIT-ARTIFACT-BINDING digest=$digest instrument=sha256sum window=published-bytes coverage=$coverage_token outcome=ESTABLISHED"
exit 0
