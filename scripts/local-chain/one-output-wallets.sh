#!/usr/bin/env bash
# Every registry command run from a wallet that holds exactly one ada-only output, on a local chain.
#
# A freshly funded wallet holds one output. Public Singular funds a transaction and collateralises it from
# one ada-only output of the wallet; the commands must too. This script funds four throwaway wallets with a
# single output each (a deployer, a booker, a folder, a returner) on public Singular's local-chain fixture
# (moved to protocol version 11, as preprod is), then runs, one wallet to each command:
#   deploy   from the deployer's single output
#   register from the booker's single output
#   fold     from the folder's single output, the supplied-state path on the node socket and the named path on the facade
#   return   from the returner's single output, after the request's deadline
# and records what each did. With MODE=baseline it records and exits 0 whatever happened, so that the behaviour
# of a build can be read; with MODE=assert each command must succeed and the transaction must settle.
#
# usage: the variables of fold-journey.sh (CKERI SINGULAR DEVNET NODE_ENV BLUEPRINT WORK PASSPHRASE), and
# MODE=baseline|assert.
set -euo pipefail
for name in CKERI SINGULAR DEVNET NODE_ENV BLUEPRINT WORK PASSPHRASE MODE; do
    [[ -n "${!name:-}" ]] || { echo "local-chain-one-output-wallets: $name is not set" >&2; exit 2; }
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/../../offchain/deployment-test/fixtures"
ENACT_PV11="${ENACT_PV11:-$HERE/enact-pv11.sh}"
mkdir -p "$WORK"
log() { printf '%s\n' "$*" | tee -a "$WORK/outputs.log"; }
fail() { log "FAIL: $*"; exit 1; }
export SINGULAR_PASSPHRASE="$PASSPHRASE"
MAGIC=42

wallet() { # wallet <name> -> address
    "$SINGULAR" wallet create --vault "$WORK/$1.vault" --network-magic $MAGIC >/dev/null
    "$SINGULAR" wallet address --vault "$WORK/$1.vault" --network-magic $MAGIC | tail -1
}
FUNDER=$(wallet funder)       # several outputs: it deploys the registry the others use and books for them
DEPLOYER=$(wallet deployer); BOOKER=$(wallet booker); FOLDER=$(wallet folder); RETURNER=$(wallet returner)

( source "$NODE_ENV"; TMPDIR="$WORK" exec "$DEVNET" --evidence-dir "$WORK/evidence" \
    --fund-address "$FUNDER:8:5000000000" \
    --fund-address "$DEPLOYER:1:5000000000" --fund-address "$BOOKER:1:3000000000" \
    --fund-address "$FOLDER:1:500000000" --fund-address "$RETURNER:1:100000000" ) \
    >"$WORK/fixture.out" 2>"$WORK/fixture.err" &
FIXTURE_PID=$!
trap 'kill "$FIXTURE_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 120); do grep -q providerUrl "$WORK/fixture.out" 2>/dev/null && break; sleep 1; done
grep -q providerUrl "$WORK/fixture.out" || fail "the fixture did not report its settings"
URL=$(jq -r .providerUrl "$WORK/fixture.out"); TIME_DIR=$(jq -r .networkTimeDirectory "$WORK/fixture.out"); SOCKET=$(jq -r .privateProbeSocket "$WORK/fixture.out")
for _ in $(seq 1 120); do [[ "$(grep -c '^devnet: funded' "$WORK/fixture.err" 2>/dev/null || true)" == 5 ]] && break; sleep 1; done
[[ "$(grep -c '^devnet: funded' "$WORK/fixture.err")" == 5 ]] || fail "the fixture did not fund the five wallets"
( source "$NODE_ENV"; $ENACT_PV11 "$SOCKET" ) >"$WORK/enact-pv11.log" 2>&1 || fail "the protocol transition to 11 failed"
for waited in $(seq 1 300); do
    curl -s "$URL/tip" >/dev/null || true
    [[ "$(jq -r .protocolMajor "$TIME_DIR/time-manifest.json" 2>/dev/null)" == 11 ]] && break
    sleep 1
done
[[ "$(jq -r .protocolMajor "$TIME_DIR/time-manifest.json")" == 11 ]] || fail "the facade's network time did not reach protocol 11"
log "binding: argv: $0 $*; ckeri $CKERI sha256 $(sha256sum "$CKERI" | cut -c1-64); this script sha256 $(sha256sum "${BASH_SOURCE[0]}" | cut -c1-64), source revision $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown) with $(git -C "$HERE" status --short 2>/dev/null | wc -l) changed files"
log "local fixture at protocol version 11 (preprod's, epoch 327 snapshot); facade $URL"

outputs_of() { # how many outputs a wallet holds, from the facade
    curl -s -X POST "$URL/address_utxos" -H 'content-type: application/json' -d "{\"_addresses\":[\"$1\"]}" | jq 'length'
}
for pair in "deployer:$DEPLOYER" "booker:$BOOKER" "folder:$FOLDER" "returner:$RETURNER"; do
    [[ "$(outputs_of "${pair#*:}")" == 1 ]] || fail "the ${pair%%:*} wallet does not hold exactly one output"
done
log "ok: the deployer, booker, folder and returner each hold exactly one output"

common=(--network-magic $MAGIC --blueprint "$BLUEPRINT" --timeout-seconds 300)
provider=(--koios-url "$URL" --network-time "$TIME_DIR")
terms=(--registration-cost 1000000 --minimum-tip 500000 --process-time 90000 --booking-width 5000 --deposit 1000000000 --freeze-bond 5000000 --premium 2000000 --minimum-ada 2000000 --termination-carrier 1500000)
cd "$WORK"

attempt() { # attempt <label> <outfile> <command...>: record the command's outcome
    local label="$1" out="$2" status=0; shift 2
    "$@" >"$WORK/$out.out" 2>"$WORK/$out.err" || status=$?
    local first
    first=$(grep -v "not for mainnet" "$WORK/$out.err" | grep -m1 -E "^ckeri: " | cut -c1-300 || true)
    log "$label: exit $status ${first:+| $first}"
    ATTEMPT_STATUS=$status
    if [[ "$MODE" == assert && $status != 0 ]]; then fail "$label exited $status"; fi
}

# a registry deployed by the funder, with three bookings made by the funder: the requests the single-output wallets act on
"$CKERI" registry deploy "${common[@]}" "${provider[@]}" --funding-address "$FUNDER" --vault "$WORK/funder.vault" \
    --release-identity-out "$WORK/identity.json" --reference-record-out "$WORK/records.json" "${terms[@]}" >"$WORK/setup-deploy.out" 2>"$WORK/setup-deploy.err" || fail "the setup deploy (setup-deploy.err)"
book() { "$CKERI" registry register "${common[@]}" "${provider[@]}" --funding-address "$1" --vault "$WORK/$2.vault" \
    --release-identity "$WORK/identity.json" --reference-record "$WORK/records.json" --kli-export "$FIXTURES/$3" ; }
REQ_NODE=$(book "$FUNDER" funder kli-export-single.cesr 2>"$WORK/setup-book-1.err" | sed -n 's/^booking-output: //p')
REQ_NAMED=$(book "$FUNDER" funder kli-export-2-of-5.cesr 2>"$WORK/setup-book-2.err" | sed -n 's/^booking-output: //p')
REQ_RETURN=$(book "$FUNDER" funder kli-export-single.cesr 2>"$WORK/setup-book-3.err" | sed -n 's/^booking-output: //p')
[[ -n "$REQ_NODE" && -n "$REQ_NAMED" && -n "$REQ_RETURN" ]] || fail "the setup bookings (setup-book-*.err)"
log "setup: registry deployed and three requests booked by a multi-output wallet"

# deploy, from the deployer's single output (a registry of its own)
attempt "deploy from one output" one-deploy "$CKERI" registry deploy "${common[@]}" "${provider[@]}" --funding-address "$DEPLOYER" --vault "$WORK/deployer.vault" \
    --release-identity-out "$WORK/deployer-identity.json" --reference-record-out "$WORK/deployer-records.json" "${terms[@]}"

# register, from the booker's single output, into the setup registry (the deposit is held in the booking)
attempt "register from one output" one-register book "$BOOKER" booker kli-export-2-of-5-rotation.cesr

# fold: supplied state on the node socket, then the named path on the facade
printf '{"schema_version":1,"supplied_by":"the empty registry","active":[],"terminal":[]}\n' >"$WORK/snapshot-empty.json"
attempt "fold (supplied state, node socket) from one output" one-fold-node "$CKERI" registry fold "${common[@]}" --node-socket "$SOCKET" \
    --funding-address "$FOLDER" --vault "$WORK/folder.vault" --release-identity "$WORK/identity.json" --reference-record "$WORK/records.json" \
    --request "$REQ_NODE" --snapshot "$WORK/snapshot-empty.json"
attempt "fold (named, public history, facade) from one output" one-fold-named "$CKERI" registry fold "${common[@]}" "${provider[@]}" \
    --funding-address "$FOLDER" --vault "$WORK/folder.vault" --release-identity "$WORK/identity.json" --reference-record "$WORK/records.json" \
    --pending "$REQ_NAMED"

# return, from the returner's single output, after the request's deadline (the process time is ninety seconds)
sleep 100
attempt "return from one output" one-return "$CKERI" registry return "${common[@]}" "${provider[@]}" --funding-address "$RETURNER" --vault "$WORK/returner.vault" \
    --release-identity "$WORK/identity.json" --reference-record "$WORK/records.json" --request "$REQ_RETURN"
log "done (mode $MODE)"
