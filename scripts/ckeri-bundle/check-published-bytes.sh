#!/usr/bin/env bash
# Bind a verdict to the published bytes. Expected COMMIT + TOOLCHAIN +
# VARIANT come from the producer pins (or the checkout's source
# identity), never from the bytes under test. A second decoded
# identity key — any JSON spelling — is RED.
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

# Structural closure over decoded identity keys. A textual key regex
# cannot see "\u0063ommit"; jq --stream can. Repeated keys on later
# records are a different path and are not this object.
dup_field=
dup_first=
dup_last=
while IFS= read -r field; do
  [ -n "$field" ] || continue
  mapfile -t vals < <(jq --stream -r --arg f "$field" \
    'select(.[0] == ["identity",$f] and (length == 2) and (.[1] != null)) | .[1]' \
    "$bytes")
  if [ "${#vals[@]}" -gt 1 ]; then
    dup_field=$field
    dup_first=${vals[0]}
    dup_last=${vals[${#vals[@]}-1]}
    break
  fi
done < <(jq --stream -r '
  select(.[0][0] == "identity"
    and (.[0]|length) == 2
    and (length == 2)
    and (.[1] != null))
  | .[0][1]' "$bytes" | sort -u)

if [ -n "$dup_field" ]; then
  echo "AUDIT-SELFTEST leg=second-conforming-parse-differs rc=1 outcome=REFUTED"
  echo "second conforming parse differs: field=$dup_field last_wins=$dup_last first_wins=$dup_first" >&2
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

producer_lock_rev() {
  jq -er --arg n "$1" \
    '.nodes[$n].locked.rev | select(type == "string" and length > 0)' \
    "$2"
}

producer_aiken_from_trust_base() {
  # The flake binds aikenPkgs.aiken.version; that version is not a
  # lock field. The trust-base table is the producer-side document.
  sed -n 's/^| Aiken | `\([^`]*\)`.*/\1/p' "$1" | head -1
}

expected_commit=${CKERI_EXPECTED_COMMIT:-}
expected_aiken=${CKERI_EXPECTED_AIKEN:-}
expected_toolchain=${CKERI_EXPECTED_TOOLCHAIN:-}

producer_root=
if [ -z "$expected_commit" ] || [ -z "$expected_aiken" ] \
  || [ -z "$expected_toolchain" ]; then
  producer_root=$(find_producer_root || true)
fi

if [ -z "$expected_commit" ]; then
  if [ -n "$producer_root" ] \
    && git -C "$producer_root" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    expected_commit=$(git -C "$producer_root" rev-parse HEAD)
  elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    expected_commit=$(git rev-parse HEAD)
  else
    echo "published identity commit cannot be resolved: no producer pin and no git source identity" >&2
    exit 1
  fi
fi

if [ -z "$expected_aiken" ] || [ -z "$expected_toolchain" ]; then
  if [ -z "$producer_root" ]; then
    echo "published identity toolchain cannot be resolved: no producer pin and no checkout lock" >&2
    exit 1
  fi
  lock=$producer_root/offchain/flake.lock
  docs=$producer_root/docs/architecture/blaster-tractability.md
  [ -r "$lock" ] || {
    echo "published identity toolchain cannot be resolved: flake.lock unreadable" >&2
    exit 1
  }
  if [ -z "$expected_aiken" ]; then
    [ -r "$docs" ] || {
      echo "published identity aiken cannot be resolved: trust-base table unreadable" >&2
      exit 1
    }
    expected_aiken=$(producer_aiken_from_trust_base "$docs")
    [ -n "$expected_aiken" ] || {
      echo "published identity aiken cannot be resolved: trust-base table has no Aiken version" >&2
      exit 1
    }
  fi
  if [ -z "$expected_toolchain" ]; then
    lean_rev=$(producer_lock_rev leanBlaster "$lock") \
      || { echo "published identity toolchain cannot be resolved: leanBlaster rev missing" >&2; exit 1; }
    plc_rev=$(producer_lock_rev plutusCoreBlaster "$lock") \
      || { echo "published identity toolchain cannot be resolved: plutusCoreBlaster rev missing" >&2; exit 1; }
    led_rev=$(producer_lock_rev cardanoLedgerApiBlaster "$lock") \
      || { echo "published identity toolchain cannot be resolved: cardanoLedgerApiBlaster rev missing" >&2; exit 1; }
    expected_toolchain="aiken=${expected_aiken};lean-blaster=${lean_rev};plutus-core-blaster=${plc_rev};cardano-ledger-api-blaster=${led_rev}"
  fi
fi

variant=$(jq -r '.identity.variant // empty' "$bytes")
commit=$(jq -r '.identity.commit // empty' "$bytes")
aiken=$(jq -r '.identity.aiken // empty' "$bytes")
toolchain=$(jq -r '.identity.toolchain // empty' "$bytes")

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

digest=$(sha256sum "$bytes" | cut -d ' ' -f 1)
echo "AUDIT-ARTIFACT-BINDING digest=$digest instrument=sha256sum window=published-bytes coverage=$coverage_token outcome=ESTABLISHED"
exit 0
