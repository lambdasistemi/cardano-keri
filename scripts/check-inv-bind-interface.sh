#!/usr/bin/env bash
# #291 INV-BIND interface census: exact field allowlists for the four
# submitted production types, plus a planted-locator self-test.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
locator_re='off_(t|i|s|d|k|kt|n|nt|b|bt|br|ba)|(re|ae|ene|rf)Off(T|I|S|D|K|Kt|N|Nt|B|Bt|Br|Ba)'

extract_fields() {
  local file=$1
  local type=$2
  python_like_extract "$file" "$type"
}

python_like_extract() {
  local file=$1
  local type=$2
  perl -0777 -ne '
    my $type = $ARGV[1];
    if (/(?:pub type|data)\s+\Q'"$type"'\E\b[^{]*\{(.*?)\}/s) {
      my $body = $1;
      $body =~ s/--[^\n]*//g;
      $body =~ s/\/\/\/[^\n]*//g;
      $body =~ s/\{-[^-]*-\}//g;
      while ($body =~ /(?:^|,|\n)\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::|::)/g) {
        print "$1\n";
      }
    }
  ' "$file"
}

fields_of() {
  extract_fields "$@" | awk 'NF' | sort -u
}

has_locator() {
  printf '%s\n' "$1" | grep -Eq "$locator_re"
}

self_test() {
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  printf '%s\n' 'pub type Probe { off_t: Int, reOffI: Int, eneOffD: Int }' >"$tmp/probe.ak"
  local planted
  planted=$(fields_of "$tmp/probe.ak" Probe | tr '\n' ' ')
  if ! printf '%s\n' "$planted" | grep -Eq "$locator_re"; then
    echo "self-test failed: planted locators were not parsed ($planted)" >&2
    exit 1
  fi
  printf '%s\n' 'data Clean = Clean { reEventBytes :: Int, reCtrlSigs :: Int }' >"$tmp/clean.hs"
  local clean
  clean=$(fields_of "$tmp/clean.hs" Clean)
  if has_locator "$clean"; then
    echo "self-test failed: clean shape reported a locator" >&2
    exit 1
  fi
}

exact_shape() {
  local label=$1
  local file=$2
  local type=$3
  shift 3
  local expected
  expected=$(printf '%s\n' "$@" | sort -u)
  local got
  got=$(fields_of "$file" "$type")
  if [[ "$got" != "$expected" ]]; then
    echo "GATE-FAIL $label fields got=$(printf '%s' "$got" | tr '\n' ',') expected=$(printf '%s' "$expected" | tr '\n' ',')" >&2
    exit 1
  fi
  if has_locator "$got"; then
    echo "GATE-FAIL $label still has a caller locator field" >&2
    exit 1
  fi
}

self_test

exact_shape registration \
  "$root/onchain/lib/cardano_keri/checkpoint/registration.ak" \
  RegistrationEvidence \
  event_bytes ctrl_sigs wit_receipts
exact_shape registration-hs \
  "$root/offchain/lib/Cardano/KERI/AID/Checkpoint/Registration.hs" \
  RegistrationEvidence \
  reEventBytes reCtrlSigs reWitReceipts
exact_shape advance \
  "$root/onchain/lib/cardano_keri/checkpoint/advance.ak" \
  AdvanceEvidence \
  event_bytes wit_cut wit_add ctrl_sigs wit_receipts
exact_shape advance-hs \
  "$root/offchain/lib/Cardano/KERI/AID/Checkpoint/Advance.hs" \
  AdvanceEvidence \
  aeEventBytes aeWitCut aeWitAdd aeCtrlSigs aeWitReceipts
exact_shape enforcement \
  "$root/onchain/lib/cardano_keri/checkpoint/enforcement.ak" \
  EnforcementEvidence \
  event_bytes native_sn said revealed_keys next_keys cur_threshold \
  next_threshold toad ctrl_sigs wit_sigs
exact_shape enforcement-hs \
  "$root/offchain/lib/Cardano/KERI/AID/Checkpoint/Enforcement.hs" \
  EnforcementEvidence \
  eneEventBytes eneNativeSn eneSaid eneRevealedKeys eneNextKeys \
  eneCurThreshold eneNextThreshold eneToad eneCtrlSigs eneWitSigs
exact_shape hash-proof \
  "$root/onchain/validators/hash_proof.ak" \
  HashProofRedeemer \
  input_bytes cesr_aid

case ${1-} in
--self-test)
  echo 'INV-BIND-ABI interfaces=4 exact_shapes=4 caller_locator_fields=0 self_test=pass'
  exit 0
  ;;
"" )
  echo 'INV-BIND-ABI interfaces=4 exact_shapes=4 caller_locator_fields=0 self_test=pass'
  exit 0
  ;;
*)
  echo "usage: $0 [--self-test]" >&2
  exit 64
  ;;
esac
