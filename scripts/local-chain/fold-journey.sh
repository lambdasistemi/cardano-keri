#!/usr/bin/env bash
# Rehearsal of the fold on a local chain, through public Singular's unchanged local-chain fixture.
#
# The fixture is Singular's own `devnet` executable: a node and the Koios-shaped facade that follows
# its blocks and serves the routes the installed commands read, `asset_txs` (the public history of a
# token) included. The fixture starts at protocol version 10 and preprod runs 11 (a read-only
# snapshot of its protocol parameters, epoch 327), so this script moves the local fixture to 11 with a test-side
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
#   ENACT_PV11=<command>                 optional: enacts protocol version 11 on a node socket given as its argument (default: enact-pv11.sh next to this file)
#   INSPECT=<command>                    optional: prints a transaction from its CBOR hex (default: inspect-tx.sh next to this file)
#   NODE_ENV=<file>                      shell file that puts cardano-node on PATH and sets E2E_GENESIS_DIR, then enters its directory
#   BLUEPRINT=<plutus.json>              the release's blueprint
#   WORK=<empty directory>               where the fixture, the wallets, the files and the log go
#   PASSPHRASE=<text>                    the development passphrase of the two throwaway vaults
set -euo pipefail

for name in CKERI SINGULAR DEVNET NODE_ENV BLUEPRINT WORK PASSPHRASE; do
    [[ -n "${!name:-}" ]] || { echo "local-chain-fold-journey: $name is not set" >&2; exit 2; }
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/../../offchain/deployment-test/fixtures"
ENACT_PV11="${ENACT_PV11:-$HERE/enact-pv11.sh}"
INSPECT="${INSPECT:-$HERE/inspect-tx.sh}"
MUTATE="${MUTATE:-$HERE/mutate-tx.sh}"
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
log "binding: argv: $0 $*"
log "binding: ckeri $CKERI sha256 $(sha256sum "$CKERI" | cut -c1-64)"
log "binding: this script $HERE/$(basename "${BASH_SOURCE[0]}") sha256 $(sha256sum "${BASH_SOURCE[0]}" | cut -c1-64); source revision $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown) with $(git -C "$HERE" status --short 2>/dev/null | wc -l) changed files in the tree"
log "binding: blueprint $BLUEPRINT sha256 $(sha256sum "$BLUEPRINT" | cut -c1-64); singular $(sha256sum "$SINGULAR" | cut -c1-64); devnet $(sha256sum "$DEVNET" | cut -c1-64)"
source "$HERE/bind-helpers.sh"; bind_helpers
if [[ -n "${CANDIDATE_BINDING:-}" ]]; then log "binding: candidate record $CANDIDATE_BINDING"; sed 's/^/binding:   /' "$CANDIDATE_BINDING" | while IFS= read -r line; do log "$line"; done; fi

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
    local epoch
    epoch=$(curl -s "$URL/tip" | jq -r '.[0].epoch_no' 2>/dev/null || true)
    curl -s "$URL/epoch_params?_epoch_no=$epoch" >"$WORK/txinfo/epoch_params.json" || true
    local id
    for id in $(grep -hoE '[0-9a-f]{64}' "$WORK"/deploy.out "$WORK"/register-*.out "$WORK"/deploy-2.out "$WORK"/fold-1.out "$WORK"/fold-2.out "$WORK"/return.out 2>/dev/null | sort -u); do
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
if [[ "${CANDIDATE_KIND:-complete}" == before-donation ]]; then
    # the build before the treasury donation can be expressed: Singular's batch is built and its script evaluation refuses it
    [[ $fold2_status == 1 ]] || fail "the build before the donation was expected to refuse the named fold, and exited $fold2_status"
    grep -q "BuildFailed.*EvalFailure" "$WORK/fold-2.err" || fail "the refusal is not a script evaluation failure (fold-2.err)"
    grep -q "nothing was submitted; nothing was spent" "$WORK/fold-2.err" || fail "the refused fold does not say it spent nothing"
    FOLD2=""
    log "ok: before the donation: the named fold is refused at script evaluation, nothing submitted (fold-2.err)"
else
[[ $fold2_status == 0 ]] || { cat "$WORK/fold-2.err" >&2; fail "the named fold on the facade exited $fold2_status (see fold-2.err)"; }
FOLD2=$(sed -n 's/^fold-transaction: //p' "$WORK/fold-2.out")
[[ -n "$FOLD2" ]] || fail "the named fold reported no transaction"
grep -q "^folded: $REQUEST_B registration" "$WORK/fold-2.out" || fail "the named fold did not report folding $REQUEST_B"
log "ok: second fold $FOLD2, named, on the facade, no state file"
fi

# ---- 4. read back ---------------------------------------------------------------------------------
if [[ -n "$FOLD2" ]]; then
for _ in $(seq 1 30); do history | grep -q "$FOLD2" && break; sleep 1; done
[[ "$(history | tr '\n' ' ')" == "$GENESIS $FOLD1 $FOLD2 " ]] || fail "the history after the second fold is not genesis, first fold, second fold: $(history | tr '\n' ' ')"
log "ok: the public history is the genesis and both folds, in order"
INFO=$(curl -s -X POST "$URL/tx_info" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$FOLD2\"],\"_inputs\":true,\"_assets\":true}")
APP_POLICY=$(jq -r .release.application_policy "$WORK/release-identity.json")
REQ_B_TX=${REQUEST_B%%#*}
echo "$INFO" >"$WORK/fold-2.tx_info.json"
jq -e --arg tx "$REQ_B_TX" '.[0].inputs | any(.tx_hash==$tx)' "$WORK/fold-2.tx_info.json" >/dev/null || fail "the second fold did not spend its booking"
# the facade's account does not carry what a transaction mints or donates: read it from the transaction's own bytes
mkdir -p "$WORK/txinfo"
curl -s -X POST "$URL/tx_cbor" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$FOLD2\"]}" | jq -r '.[0].cbor' >"$WORK/fold-2.hex"
( source "$NODE_ENV"; $INSPECT "$WORK/fold-2.hex" ) >"$WORK/fold-2.inspect" 2>"$WORK/fold-2.inspect.err" || fail "the second fold could not be decoded (fold-2.inspect.err)"
grep -q "(\"$APP_POLICY\",\"[0-9a-f]*\",-1)" "$WORK/fold-2.inspect" || fail "the second fold did not burn an approval"
[[ "$(grep -o "(\"$APP_POLICY\"" "$WORK/fold-2.inspect" | wc -l)" == 1 ]] || fail "the second fold mints or burns more than one application asset"
grep -q "(\"$STATE_POLICY\",\"[0-9a-f]*\",1)" "$WORK/fold-2.inspect" || fail "the second fold did not mint the key's active token"
grep -q "^treasury-donation 1000000$" "$WORK/fold-2.inspect" || fail "the second fold did not pay the treasury the registration cost"
grep -q "^collateral-inputs 1$" "$WORK/fold-2.inspect" || fail "the second fold has no single collateral input"
log "ok: the second fold spent its booking, burned its approval once, minted its key's token and paid the treasury the registration cost"
fi

# ---- the exclusion control ----------------------------------------------------------------------------
# A transaction the node refuses, that touches the registry's state token, must not appear in its public history.
# The mutant is the second fold with its validity end moved by one slot: another body, so another identifier, under
# the signature of the first; it spends inputs the second fold already spent. Submitted to the node through the
# facade's own submission route, it is refused, and the history is as it was.
HISTORY_BEFORE=$(history | tr '\n' ' ')
MUTATED=$FOLD2
if [[ -z "$MUTATED" ]]; then MUTATED=$FOLD1; curl -s -X POST "$URL/tx_cbor" -H 'content-type: application/json' -d "{\"_tx_hashes\":[\"$FOLD1\"]}" | jq -r '.[0].cbor' >"$WORK/fold-1.hex"; fi
MUTANT=$( ( source "$NODE_ENV"; $MUTATE "$WORK/$([[ $MUTATED == "$FOLD2" ]] && echo fold-2 || echo fold-1).hex" "$WORK/mutant.hex" ) 2>"$WORK/mutant.err" | grep -oE '[0-9a-f]{64}' | tail -1 ) || fail "the refused transaction could not be made (mutant.err)"
[[ "$MUTANT" =~ ^[0-9a-f]{64}$ && "$MUTANT" != "$MUTATED" ]] || fail "the refused transaction has no identifier of its own: $MUTANT"
printf '%s' "$(cat "$WORK/mutant.hex")" | xxd -r -p >"$WORK/mutant.cbor"
refusal=$(curl -s -o "$WORK/mutant.response" -w '%{http_code}' -X POST "$URL/submittx" -H 'content-type: application/cbor' --data-binary @"$WORK/mutant.cbor" || true)
[[ "$refusal" =~ ^[45] ]] || fail "the node did not refuse the transaction (HTTP $refusal): $(cat "$WORK/mutant.response")"
log "ok: the node refused the mutant $MUTANT (HTTP $refusal)"
sleep 5
[[ "$(history | tr '\n' ' ')" == "$HISTORY_BEFORE" ]] || fail "the history changed after the refused submission: $(history | tr '\n' ' ')"
history | grep -q "$MUTANT" && fail "the refused transaction is in the public history"
log "ok: exclusion control: a transaction the node refused is not in the public history"

# ---- the closed window, and the return --------------------------------------------------------------
# A request whose deadline has passed is out of time: the named fold refuses it from the provider's tip alone,
# before anything is signed, and the return, which is for exactly that case, pays the refund. A registry of its own
# holds the request, so that no key of the first registry stands in the way of the window being what refuses it.
"$CKERI" registry deploy "${common[@]}" "${provider[@]}" --funding-address "$BOOKER" --vault "$WORK/booker.vault" \
    --release-identity-out "$WORK/release-identity-2.json" --reference-record-out "$WORK/reference-outputs-2.json" \
    --registration-cost 1000000 --minimum-tip 500000 --process-time 90000 --booking-width 5000 \
    --deposit 1000000000 --freeze-bond 5000000 --premium 2000000 --minimum-ada 2000000 --termination-carrier 1500000 \
    >"$WORK/deploy-2.out" 2>"$WORK/deploy-2.err" || fail "the second registry's deploy (deploy-2.err)"
"$CKERI" registry register "${common[@]}" "${provider[@]}" --funding-address "$BOOKER" --vault "$WORK/booker.vault" \
    --release-identity "$WORK/release-identity-2.json" --reference-record "$WORK/reference-outputs-2.json" \
    --kli-export "$FIXTURES/kli-export-single.cesr" >"$WORK/register-closed.out" 2>"$WORK/register-closed.err" || fail "the booking of the request that will be out of time (register-closed.err)"
REQUEST_C=$(sed -n 's/^booking-output: //p' "$WORK/register-closed.out")
[[ -n "$REQUEST_C" ]] || fail "register reported no booking output for the request to be returned"
log "ok: booked $REQUEST_C in a second registry; its deadline is ninety seconds on"
sleep 110
set +e
"$CKERI" registry fold "${common[@]}" "${provider[@]}" --funding-address "$FOLDER" --vault "$WORK/folder.vault" \
    --release-identity "$WORK/release-identity-2.json" --reference-record "$WORK/reference-outputs-2.json" \
    --pending "$REQUEST_C" >"$WORK/fold-closed.out" 2>"$WORK/fold-closed.err"
closed_status=$?
set -e
[[ $closed_status == 1 ]] || fail "the named fold of a request past its deadline exited $closed_status, not 1"
grep -q "ProcessingWindowClosed" "$WORK/fold-closed.err" || fail "the refusal does not name the closed window (fold-closed.err)"
grep -q "nothing was submitted; nothing was spent" "$WORK/fold-closed.err" || fail "the refused fold does not say it spent nothing"
log "ok: closed window: the named fold of a request past its deadline is refused (ProcessingWindowClosed), nothing submitted"
"$CKERI" registry return "${common[@]}" "${provider[@]}" --funding-address "$FOLDER" --vault "$WORK/folder.vault" \
    --release-identity "$WORK/release-identity-2.json" --reference-record "$WORK/reference-outputs-2.json" \
    --request "$REQUEST_C" >"$WORK/return.out" 2>"$WORK/return.err" || fail "the return of the closed request (return.err)"
RETURN=$(sed -n 's/^return-transaction: //p' "$WORK/return.out")
[[ -n "$RETURN" ]] || fail "the return reported no transaction"
log "ok: the request past its deadline is returned: $RETURN, fee $(sed -n 's/^return-fee: //p' "$WORK/return.out")"
log "journey complete (${CANDIDATE_KIND:-complete}): fold 1 $FOLD1, fold 2 ${FOLD2:-refused}, refused mutant $MUTANT, return $RETURN"
