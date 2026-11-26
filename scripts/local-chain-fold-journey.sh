#!/usr/bin/env bash
# Rehearsal of the fold on a local chain, through public Singular's unchanged local-chain fixture.
#
# The fixture is Singular's own `devnet` executable: a node and the Koios-shaped facade that follows
# its blocks and serves the routes the installed commands read, `asset_txs` (the public history of a
# token) included. The fixture starts at protocol version 10 and preprod runs 11 (the trial team's
# read-only snapshot, epoch 327), so this script moves the local fixture to 11 with a test-side
# governance helper before any command runs. Nothing here touches a public network: local chain only,
# throwaway wallets whose passphrase is a development one.
#
# What it shows, in order, each step asserted:
#   1. deploy a registry and book two identities (installed `ckeri registry deploy|register`, on the facade);
#   2. fold the first by the supplied-state path on the node socket: that transaction is submitted
#      to the node directly, not through the facade, and must appear in the facade's history route;
#   3. fold the second with `ckeri registry fold --pending`, on the facade, with no state file: the
#      registry's state is rebuilt from the public history, which includes step 2's transaction;
#   4. read back the chain: the registry's state token history, both bookings spent, both approvals burned,
#      both holdings delivered, the treasury paid.
#
# usage (all of these are required; the paths are the caller's):
#   CKERI=<ckeri binary>                 the command under test
#   SINGULAR=<singular binary>           public Singular's command line, for the wallet vaults only
#   DEVNET=<singular devnet binary>      public Singular's local-chain fixture
#   ENACT_PV11=<command>                 enacts protocol version 11 on a node socket given as its argument
#   NODE_ENV=<file>                      shell file that puts cardano-node on PATH and sets E2E_GENESIS_DIR, then enters its directory
#   BLUEPRINT=<plutus.json>              the release's blueprint
#   WORK=<empty directory>               where the fixture, the wallets, the files and the log go
#   PASSPHRASE=<text>                    the development passphrase of the two throwaway vaults
set -euo pipefail

for name in CKERI SINGULAR DEVNET ENACT_PV11 NODE_ENV BLUEPRINT WORK PASSPHRASE; do
    [[ -n "${!name:-}" ]] || { echo "local-chain-fold-journey: $name is not set" >&2; exit 2; }
done
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/offchain/deployment-test/fixtures"
mkdir -p "$WORK"
log() { printf '%s\n' "$*" | tee -a "$WORK/journey.log"; }
fail() { log "FAIL: $*"; exit 1; }
expect() { # expect <description> <command...>
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then log "ok: $what"; else fail "$what"; fi
}
export SINGULAR_PASSPHRASE="$PASSPHRASE"
MAGIC=42

# ---- the wallets: a booker and a distinct folder -------------------------------------------------
"$SINGULAR" wallet create --vault "$WORK/booker.vault" --network-magic $MAGIC >/dev/null
"$SINGULAR" wallet create --vault "$WORK/folder.vault" --network-magic $MAGIC >/dev/null
BOOKER=$("$SINGULAR" wallet address --vault "$WORK/booker.vault" --network-magic $MAGIC | tail -1)
FOLDER=$("$SINGULAR" wallet address --vault "$WORK/folder.vault" --network-magic $MAGIC | tail -1)
log "booker $BOOKER"; log "folder $FOLDER"

# ---- the fixture ---------------------------------------------------------------------------------
# shellcheck disable=SC1090
( source "$NODE_ENV"; TMPDIR="$WORK" exec "$DEVNET" --evidence-dir "$WORK/evidence" \
    --fund-address "$BOOKER:6:5000000000" --fund-address "$FOLDER:4:500000000" ) \
    >"$WORK/fixture.out" 2>"$WORK/fixture.err" &
FIXTURE_PID=$!
# what the chain holds of every transaction the commands made is kept for comparison between builds, whatever the run came to
keep_chain() {
    [[ -n "${URL:-}" ]] || return 0
    mkdir -p "$WORK/txinfo"
    curl -s "$URL/epoch_params" >"$WORK/txinfo/epoch_params.json" || true
    local id
    for id in $(grep -hoE '[0-9a-f]{64}' "$WORK"/deploy.out "$WORK"/register-*.out "$WORK"/fold-1.out "$WORK"/fold-2.out 2>/dev/null | sort -u); do
        curl -s -X POST "$URL/tx_info" -H 'content-type: application/json' \
            -d "{\"_tx_hashes\":[\"$id\"],\"_inputs\":true,\"_assets\":true,\"_scripts\":true}" >"$WORK/txinfo/$id.json" || true
        curl -s -X POST "$URL/tx_cbor" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$id\"]}" >"$WORK/txinfo/$id.cbor.json" || true
    done
}
trap 'keep_chain; kill "$FIXTURE_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 120); do
    [[ -s "$WORK/fixture.out" ]] && grep -q providerUrl "$WORK/fixture.out" && break
    sleep 1
done
grep -q providerUrl "$WORK/fixture.out" || fail "the fixture did not report its settings"
URL=$(jq -r .providerUrl "$WORK/fixture.out")
TIME_DIR=$(jq -r .networkTimeDirectory "$WORK/fixture.out")
SOCKET=$(jq -r .privateProbeSocket "$WORK/fixture.out")
log "facade $URL; network time $TIME_DIR; node socket $SOCKET"

# the fixture funds the two wallets from the genesis outputs before the protocol transition spends the rest of them
for _ in $(seq 1 120); do
    [[ "$(grep -c "^devnet: funded" "$WORK/fixture.err" 2>/dev/null || true)" == 2 ]] && break
    sleep 1
done
[[ "$(grep -c "^devnet: funded" "$WORK/fixture.err")" == 2 ]] || fail "the fixture did not fund the two wallets"
( source "$NODE_ENV"; $ENACT_PV11 "$SOCKET" ) >"$WORK/enact-pv11.log" 2>&1 || fail "the protocol transition to 11 failed (see enact-pv11.log)"
for waited in $(seq 1 300); do
    # the facade republishes its network time when it is read: a read of the tip is the harmless one
    curl -s "$URL/tip" >/dev/null || true
    [[ "$(jq -r .protocolMajor "$TIME_DIR/time-manifest.json" 2>/dev/null)" == 11 ]] && break
    (( waited % 30 )) || log "waiting for the facade's network time to report protocol 11 ($(jq -r .protocolMajor "$TIME_DIR/time-manifest.json" 2>/dev/null || echo none) after ${waited}s)"
    sleep 1
done
[[ "$(jq -r .protocolMajor "$TIME_DIR/time-manifest.json")" == 11 ]] || fail "the facade's network time did not reach protocol 11"
log "ok: the local fixture is at protocol version 11, as preprod is (epoch 327 snapshot)"

common=(--network-magic $MAGIC --blueprint "$BLUEPRINT" --timeout-seconds 300)
provider=(--koios-url "$URL" --network-time "$TIME_DIR")

# ---- 1. deploy and book ---------------------------------------------------------------------------
cd "$WORK"
"$CKERI" registry deploy "${common[@]}" "${provider[@]}" --funding-address "$BOOKER" --vault "$WORK/booker.vault" \
    --release-identity-out "$WORK/release-identity.json" --reference-record-out "$WORK/reference-outputs.json" \
    --registration-cost 1000000 --minimum-tip 500000 --process-time 90000 --booking-width 5000 \
    --deposit 1000000000 --freeze-bond 5000000 --premium 2000000 --minimum-ada 2000000 --termination-carrier 1500000 \
    >"$WORK/deploy.out" 2>"$WORK/deploy.err" || fail "registry deploy (see deploy.err)"
GENESIS=$(sed -n 's/^create-registry: \([0-9a-f]\{64\}\).*/\1/p' "$WORK/deploy.out")
[[ -n "$GENESIS" ]] || fail "deploy reported no create-registry transaction"
log "ok: registry deployed, genesis $GENESIS"
book() { # book <name> <export> -> prints the booking output
    "$CKERI" registry register "${common[@]}" "${provider[@]}" --funding-address "$BOOKER" --vault "$WORK/booker.vault" \
        --release-identity "$WORK/release-identity.json" --reference-record "$WORK/reference-outputs.json" \
        --kli-export "$FIXTURES/$2" >"$WORK/register-$1.out" 2>"$WORK/register-$1.err" || fail "registry register $1 (see register-$1.err)"
    sed -n 's/^booking-output: //p' "$WORK/register-$1.out"
}
REQUEST_A=$(book single kli-export-single.cesr)
REQUEST_B=$(book multi kli-export-2-of-5.cesr)
[[ -n "$REQUEST_A" && -n "$REQUEST_B" ]] || fail "register reported no booking output"
log "ok: booked $REQUEST_A and $REQUEST_B"

STATE_POLICY=$(jq -r .release.state_policy "$WORK/release-identity.json")
STATE_NAME=$(curl -s -X POST "$URL/tx_info" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$GENESIS\"],\"_assets\":true}" \
    | jq -r --arg p "$STATE_POLICY" '.[0].outputs[].asset_list[]? | select(.policy_id==$p) | .asset_name' | head -1)
[[ -n "$STATE_NAME" ]] || fail "the genesis holds no state token"
history() { curl -s "$URL/asset_txs?_asset_policy=$STATE_POLICY&_asset_name=$STATE_NAME&_after_block_height=0" | jq -r '.[].tx_hash'; }
[[ "$(history | tr '\n' ' ')" == "$GENESIS " ]] || fail "the history of the state token is not the genesis alone: $(history | tr '\n' ' ')"
log "ok: the public history of the state token is the genesis"

# ---- 2. the first fold: supplied state, on the node socket -----------------------------------------
printf '{"schema_version":1,"supplied_by":"the empty registry","active":[],"terminal":[]}\n' >"$WORK/snapshot-empty.json"
"$CKERI" registry fold "${common[@]}" --node-socket "$SOCKET" --funding-address "$FOLDER" --vault "$WORK/folder.vault" \
    --release-identity "$WORK/release-identity.json" --reference-record "$WORK/reference-outputs.json" \
    --request "$REQUEST_A" --snapshot "$WORK/snapshot-empty.json" >"$WORK/fold-1.out" 2>"$WORK/fold-1.err" || fail "the first fold on the node socket (see fold-1.err)"
FOLD1=$(sed -n 's/^fold-transaction: //p' "$WORK/fold-1.out")
[[ -n "$FOLD1" ]] || fail "the first fold reported no transaction"
log "ok: first fold $FOLD1, submitted to the node directly"
for _ in $(seq 1 30); do history | grep -q "$FOLD1" && break; sleep 1; done
[[ "$(history | tr '\n' ' ')" == "$GENESIS $FOLD1 " ]] || fail "the facade's history does not hold the fold submitted to the node directly: $(history | tr '\n' ' ')"
log "ok: inclusion control: a transaction submitted to the node, not through the facade, is in the public history"

# ---- 3. the second fold: no state file, on the facade -----------------------------------------------
set +e
"$CKERI" registry fold "${common[@]}" "${provider[@]}" --funding-address "$FOLDER" --vault "$WORK/folder.vault" \
    --release-identity "$WORK/release-identity.json" --reference-record "$WORK/reference-outputs.json" \
    --pending "$REQUEST_B" >"$WORK/fold-2.out" 2>"$WORK/fold-2.err"
fold2_status=$?
set -e
[[ $fold2_status == 0 ]] || { cat "$WORK/fold-2.err" >&2; fail "the named fold on the facade exited $fold2_status (see fold-2.err)"; }
FOLD2=$(sed -n 's/^fold-transaction: //p' "$WORK/fold-2.out")
[[ -n "$FOLD2" ]] || fail "the named fold reported no transaction"
grep -q "^folded: $REQUEST_B registration" "$WORK/fold-2.out" || fail "the named fold did not report folding $REQUEST_B"
log "ok: second fold $FOLD2, named, on the facade, no state file"

# ---- 4. read back ---------------------------------------------------------------------------------
for _ in $(seq 1 30); do history | grep -q "$FOLD2" && break; sleep 1; done
[[ "$(history | tr '\n' ' ')" == "$GENESIS $FOLD1 $FOLD2 " ]] || fail "the history after the second fold is not genesis, first fold, second fold: $(history | tr '\n' ' ')"
log "ok: the public history is the genesis and both folds, in order"
INFO=$(curl -s -X POST "$URL/tx_info" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$FOLD2\"],\"_inputs\":true,\"_assets\":true}")
APP_POLICY=$(jq -r .release.application_policy "$WORK/release-identity.json")
REQ_B_TX=${REQUEST_B%%#*}
echo "$INFO" >"$WORK/fold-2.tx_info.json"
jq -e --arg tx "$REQ_B_TX" '.[0].inputs | any(.tx_hash==$tx)' "$WORK/fold-2.tx_info.json" >/dev/null || fail "the second fold did not spend its booking"
jq -e --arg p "$APP_POLICY" '[.[0].assets_minted[]? | select(.policy_id==$p and .quantity=="-1")] | length == 1' "$WORK/fold-2.tx_info.json" >/dev/null || fail "the second fold did not burn its approval once"
log "ok: the second fold spent its booking and burned its approval"
log "journey complete: fold 1 $FOLD1, fold 2 $FOLD2"
