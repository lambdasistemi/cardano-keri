#!/usr/bin/env bash
# PROVISIONAL local link of the December builder with a validator candidate, on a local chain.
#
# Pairs one builder binary with one validator blueprint, deploys a registry on Singular's local fixture (a node and the
# Koios-shaped facade), books four inceptions with the installed commands, folds each, reads each checkpoint back with the
# installed `ckeri checkpoint` and `ckeri status`, and keeps what each transaction declares. Every receipt it writes is
# provisional: the validator candidate retains its parsed fallback. Nothing touches a public network.
#
# usage (all required; the paths are the caller's), inside the development shell of offchain/:
#   CKERI SINGULAR DEVNET NODE_ENV BLUEPRINT WORK PASSPHRASE   as in fold-journey.sh
#   EXPORTS=<directory>   the kli export streams: b-empty.cesr, i01.cesr, i02.cesr, d-seal.cesr
set -uo pipefail
for name in CKERI SINGULAR DEVNET NODE_ENV BLUEPRINT WORK PASSPHRASE EXPORTS; do
    [[ -n "${!name:-}" ]] || { echo "link-dec9: $name is not set" >&2; exit 2; }
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENACT_PV11="${ENACT_PV11:-$HERE/enact-pv11.sh}"
INSPECT="${INSPECT:-$HERE/inspect-tx.sh}"
mkdir -p "$WORK"
log() { printf '%s\n' "$*" | tee -a "$WORK/link.log"; }
STAGE=start
first_failure=
fail() { log "FIRST FAILING STAGE: $STAGE: $*"; exit 1; }
# with CONTINUE=1 a refused identity is recorded and the next one is tried; the first refusal stays the first
refused() { [[ -n "$first_failure" ]] || first_failure="$STAGE: $*"; log "REFUSED: $STAGE: $*"; }
export SINGULAR_PASSPHRASE="$PASSPHRASE"
MAGIC=42
log "PROVISIONAL LINK RECEIPT: validator candidate retains the parsed fallback; binding attribution (reconstruction or fallback) is unresolved in these receipts"
log "binding: ckeri $CKERI sha256 $(sha256sum "$CKERI" | cut -c1-64)"
log "binding: blueprint $BLUEPRINT sha256 $(sha256sum "$BLUEPRINT" | cut -c1-64)"
log "binding: singular $SINGULAR sha256 $(sha256sum "$SINGULAR" | cut -c1-64); devnet $DEVNET sha256 $(sha256sum "$DEVNET" | cut -c1-64)"
log "binding: this script sha256 $(sha256sum "${BASH_SOURCE[0]}" | cut -c1-64); NODE_ENV $NODE_ENV sha256 $(sha256sum "$NODE_ENV" | cut -c1-64)"
ENTRIES="${ENTRIES:-b-empty:empty i01:empty i02:empty d-seal:nested}"
for f in $(for e in $ENTRIES; do echo "${e%%:*}"; done); do log "export: $f $(stat -c %s "$EXPORTS/$f.cesr") bytes sha256 $(sha256sum "$EXPORTS/$f.cesr" | cut -c1-64)"; done

STAGE=wallets
"$SINGULAR" wallet create --vault "$WORK/booker.vault" --network-magic $MAGIC >/dev/null 2>&1 || fail "wallet create booker"
"$SINGULAR" wallet create --vault "$WORK/folder.vault" --network-magic $MAGIC >/dev/null 2>&1 || fail "wallet create folder"
BOOKER=$("$SINGULAR" wallet address --vault "$WORK/booker.vault" --network-magic $MAGIC | tail -1)
FOLDER=$("$SINGULAR" wallet address --vault "$WORK/folder.vault" --network-magic $MAGIC | tail -1)
log "booker $BOOKER"; log "folder $FOLDER"

STAGE=fixture
( source "$NODE_ENV"; TMPDIR="$WORK" exec "$DEVNET" --evidence-dir "$WORK/evidence" \
    --fund-address "$BOOKER:6:5000000000" --fund-address "$FOLDER:4:500000000" ) \
    >"$WORK/fixture.out" 2>"$WORK/fixture.err" &
FIXTURE_PID=$!
trap 'kill "$FIXTURE_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 120); do grep -q providerUrl "$WORK/fixture.out" 2>/dev/null && break; sleep 1; done
grep -q providerUrl "$WORK/fixture.out" || fail "the fixture did not report its settings: $(tail -3 "$WORK/fixture.err")"
URL=$(jq -r .providerUrl "$WORK/fixture.out"); TIME_DIR=$(jq -r .networkTimeDirectory "$WORK/fixture.out"); SOCKET=$(jq -r .privateProbeSocket "$WORK/fixture.out")
log "facade $URL; network time $TIME_DIR; node socket $SOCKET"
for _ in $(seq 1 120); do [[ "$(grep -c "^devnet: funded" "$WORK/fixture.err" 2>/dev/null || true)" == 2 ]] && break; sleep 1; done
[[ "$(grep -c "^devnet: funded" "$WORK/fixture.err")" == 2 ]] || fail "the fixture did not fund the two wallets"
STAGE=protocol-transition
( source "$NODE_ENV"; $ENACT_PV11 "$SOCKET" ) >"$WORK/enact-pv11.log" 2>&1 || fail "the protocol transition to 11 failed: $(tail -3 "$WORK/enact-pv11.log")"
for waited in $(seq 1 300); do curl -s "$URL/tip" >/dev/null || true; [[ "$(jq -r .protocolMajor "$TIME_DIR/time-manifest.json" 2>/dev/null)" == 11 ]] && break; sleep 1; done
[[ "$(jq -r .protocolMajor "$TIME_DIR/time-manifest.json")" == 11 ]] || fail "the facade's network time did not reach protocol 11"
log "ok: local fixture at protocol version 11"
EPOCH=$(curl -s "$URL/tip" | jq -r '.[0].epoch_no')
curl -s "$URL/epoch_params?_epoch_no=$EPOCH" >"$WORK/epoch-params.json"
log "effective parameters (the facade's epoch_params, epoch $EPOCH, read at $(date -u +%Y-%m-%dT%H:%M:%SZ)): $(jq -c '.[0] | {epoch_no, max_tx_ex_mem, max_tx_ex_steps, max_tx_size, max_block_ex_mem, max_block_ex_steps, protocol_major}' "$WORK/epoch-params.json")"
log "genesis in effect: E2E_GENESIS_DIR $( ( source "$NODE_ENV" >/dev/null 2>&1; echo "$E2E_GENESIS_DIR" ) ) alonzo $( ( source "$NODE_ENV" >/dev/null 2>&1; jq -c '{maxTxExUnits, maxBlockExUnits}' "$E2E_GENESIS_DIR/alonzo-genesis.json" ) )"

common=(--network-magic $MAGIC --blueprint "$BLUEPRINT" --timeout-seconds 300)
provider=(--koios-url "$URL" --network-time "$TIME_DIR")
cd "$WORK"
STAGE=deploy
"$CKERI" registry deploy "${common[@]}" "${provider[@]}" --funding-address "$BOOKER" --vault "$WORK/booker.vault" \
    --release-identity-out "$WORK/release-identity.json" --reference-record-out "$WORK/reference-outputs.json" \
    --registration-cost 1000000 --minimum-tip 500000 --process-time 90000 --booking-width 5000 \
    --deposit 1000000000 --freeze-bond 5000000 --premium 2000000 --minimum-ada 2000000 --termination-carrier 1500000 \
    >"$WORK/deploy.out" 2>"$WORK/deploy.err" || fail "registry deploy: $(tail -5 "$WORK/deploy.err")"
log "ok: registry deployed; release identity and reference record kept:"
sed 's/^/  release-identity: /' "$WORK/release-identity.json" | tee -a "$WORK/link.log" >/dev/null
sed 's/^/  reference-outputs: /' "$WORK/reference-outputs.json" | tee -a "$WORK/link.log" >/dev/null
sed 's/^/  deploy: /' "$WORK/deploy.out" | tee -a "$WORK/link.log" >/dev/null

txsize() { curl -s -X POST "$URL/tx_cbor" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$1\"]}" | jq -r '.[0].cbor' >"$WORK/$2.hex"; log "  $2: signed size $(( $(wc -c <"$WORK/$2.hex") / 2 )) bytes"; ( source "$NODE_ENV"; $INSPECT "$WORK/$2.hex" ) >"$WORK/$2.inspect" 2>"$WORK/$2.inspect.err" || log "  $2: inspect failed: $(tail -2 "$WORK/$2.inspect.err")"; }
for entry in $ENTRIES; do
    name=${entry%%:*}; kind=${entry##*:}
    STAGE="register $name"
    "$CKERI" registry register "${common[@]}" "${provider[@]}" --funding-address "$BOOKER" --vault "$WORK/booker.vault" \
        --release-identity "$WORK/release-identity.json" --reference-record "$WORK/reference-outputs.json" \
        --kli-export "$EXPORTS/$name.cesr" >"$WORK/register-$name.out" 2>"$WORK/register-$name.err" \
        || { if [[ "${CONTINUE:-0}" == 1 ]]; then refused "registry register $name ($kind anchors): $(head -c 600 "$WORK/register-$name.err")"; continue; else fail "registry register $name ($kind anchors): $(tail -6 "$WORK/register-$name.err")"; fi; }
    REQ=$(sed -n 's/^booking-output: //p' "$WORK/register-$name.out"); BOOKTX=$(sed -n 's/^booking-transaction: //p' "$WORK/register-$name.out"); PREMINT=$(sed -n 's/^premint-transaction: //p' "$WORK/register-$name.out")
    [[ -n "$REQ" ]] || fail "register $name reported no booking output"
    log "ok: booked $name ($kind anchors): premint $PREMINT booking $BOOKTX output $REQ"
    txsize "$BOOKTX" "booking-$name"; txsize "$PREMINT" "premint-$name"
    STAGE="fold $name"
    "$CKERI" registry fold "${common[@]}" "${provider[@]}" --funding-address "$FOLDER" --vault "$WORK/folder.vault" \
        --release-identity "$WORK/release-identity.json" --reference-record "$WORK/reference-outputs.json" \
        --pending "$REQ" >"$WORK/fold-$name.out" 2>"$WORK/fold-$name.err" \
        || { if [[ "${CONTINUE:-0}" == 1 ]]; then refused "registry fold $name: $(head -c 600 "$WORK/fold-$name.err")"; continue; else fail "registry fold $name: $(tail -8 "$WORK/fold-$name.err")"; fi; }
    FOLDTX=$(sed -n 's/^fold-transaction: //p' "$WORK/fold-$name.out")
    log "ok: folded $name: fold $FOLDTX consuming $REQ"
    txsize "$FOLDTX" "fold-$name"
done

STAGE=readback
readback() { # readback <command> <name> <aid> -> the output is kept
    "$CKERI" "$1" --aid "$3" --koios-url "$URL" --network-time "$TIME_DIR" --network-magic $MAGIC \
        --release-identity "$WORK/release-identity.json" --reference-record "$WORK/reference-outputs.json" --blueprint "$BLUEPRINT" \
        >"$WORK/readback-$1-$2.out" 2>"$WORK/readback-$1-$2.err"
    local code=$?
    log "== ckeri $1 --aid $3   (exit $code)"
    sed 's/^/  /' "$WORK/readback-$1-$2.out" | tee -a "$WORK/link.log" >/dev/null
    [[ $code == 0 ]] || log "  stderr: $(tail -4 "$WORK/readback-$1-$2.err")"
    return $code
}
declare -A AID=( [b-empty]=BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTw [i01]=DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ [i02]=EEnwnQUz696trMrSNOKKH9b2CKz5xTF-fgCquWHuiLgA [d-seal]=DNBKsjJ0K7SrOhNovUYV5ObQIkq3GgFrr4UgozLJd4c3 [d-empty]=DNBKsjJ0K7SrOhNovUYV5ObQIkq3GgFrr4UgozLJd4c3 [d-next]=DNBKsjJ0K7SrOhNovUYV5ObQIkq3GgFrr4UgozLJd4c3 [d-zero-next]=DNBKsjJ0K7SrOhNovUYV5ObQIkq3GgFrr4UgozLJd4c3 )
for kv in ${ENTRY_AIDS:-}; do AID[${kv%%=*}]=${kv#*=}; done
rc=0
for name in $(for e in $ENTRIES; do echo "${e%%:*}"; done); do for command in checkpoint status; do readback "$command" "$name" "${AID[$name]}" || { rc=1; log "FIRST FAILING STAGE: readback $command $name (exit $?)"; }; done; done
[[ -z "$first_failure" ]] || log "FIRST REFUSAL OF THE RUN: $first_failure"
log "PROVISIONAL LINK RUN ENDED (readback status $rc)"
exit $rc
