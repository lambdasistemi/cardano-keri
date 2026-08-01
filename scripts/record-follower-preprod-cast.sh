#!/usr/bin/env bash
set -euo pipefail

# Tour script for the runnable KERI follower (#188) against live preprod.
# Drives the exact production entrypoint over a FIFO so genuine interleaved
# catch-up progress and verb output land in the recording as it happens;
# never fabricates or retypes output. Intended to run once undecorated (a
# dry run) and once wrapped in `asciinema rec -c` for the tracked cast.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

store_path="${CKERI_TOUR_STORE:?set CKERI_TOUR_STORE to a fresh, non-existent store directory under /code}"
socket="${CKERI_TOUR_SOCKET:-/code/cardano-preprod/ipc/node.socket}"
funding_address="${CKERI_TOUR_FUNDING_ADDRESS:-addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d}"
checkpoint_aid="${CKERI_TOUR_CHECKPOINT_AID:-EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi}"
catchup_wait="${CKERI_TOUR_CATCHUP_WAIT:-20}"
read_pause="${CKERI_TOUR_READ_PAUSE:-4}"

if [[ -e "$store_path" ]]; then
    printf 'record-follower-preprod-cast: store already exists, refusing to reuse: %s\n' \
        "$store_path" >&2
    exit 1
fi

reset=$'\033[0m'
cyan=$'\033[1;36m'
dim=$'\033[0;90m'
green=$'\033[1;32m'
yellow=$'\033[1;33m'

header() { printf '%b%s%b\n\n' "$cyan" "$1" "$reset"; }
comment() { printf '%b# %s%b\n' "$dim" "$1" "$reset"; }
typed() { printf '%b$ %s%b\n' "$green" "$1" "$reset"; }
key() { printf '%b%s%b\n' "$yellow" "$1" "$reset"; }
clear_frame() { printf '\033[H\033[2J\033[3J'; }

fifo="$store_path.fifo"
follower_pid=""

cleanup() {
    if [[ -n "$follower_pid" ]] && kill -0 "$follower_pid" 2>/dev/null; then
        wait "$follower_pid" 2>/dev/null || true
    fi
    exec 3>&- 2>/dev/null || true
    rm -f "$fifo"
}
trap cleanup EXIT

clear_frame
header "The runnable KERI follower -- live preprod"
comment "Cold-starts a fresh local store at the committed M1 start point,"
comment "catches up to the live preprod tip, then serves an interactive"
comment "local-store query prompt over the running process."
sleep "$read_pause"

mkdir -p "$(dirname "$store_path")"
rm -f "$fifo"
mkfifo "$fifo"

cmd=(nix run ./offchain#ckeri-follower --
    --node-socket "$socket"
    --network-magic 1
    --byron-epoch-slots 21600
    --security-param-k 2160
    --start-slot 129566111
    --start-block-hash 52457d38ab799de201f67936cec9bbc86948adcc2a2685bf80b5690eb1377887
    --store-path "$store_path"
    --manifest-path deploy/preprod/m1-manifest.json
    --funding-address "$funding_address")

typed "${cmd[*]}"
sleep 1

exec 3<>"$fifo"
"${cmd[@]}" <&3 &
follower_pid=$!

# Haskeline does not echo FIFO-fed input, and its async progress reporter
# (Shell.hs progressLoop, every 2s via externalPrint) keeps redrawing the
# "ckeri> " prompt on its own, so genuine progress output always lands
# between that redraw and our fd-3 write -- the original prompt is never
# adjacent to what we send. Render the faithful interactive display line
# ourselves immediately before writing the same command to fd 3: this is
# input-echo rendering necessitated by the async redraw, not a second prompt
# stacked after an existing one, and it never renders or alters a follower
# result.
send() {
    printf 'ckeri> %s\n' "$1"
    printf '%s\n' "$1" >&3
}

comment "waiting for the follower to catch up to the live preprod tip..."
sleep "$catchup_wait"

comment "status: one fresh local-store read"
send "status"
sleep "$read_pause"

comment "list: every live checkpoint right now"
send "list"
sleep "$read_pause"

comment "checkpoint: the one live AID this deployment has advanced"
send "checkpoint $checkpoint_aid"
sleep "$read_pause"

comment "payer: the configured funding address' live UTxOs"
send "payer $funding_address"
sleep "$read_pause"

comment "status again: a repeated fresh read in the same running process"
send "status"
sleep "$read_pause"

comment "quit: clean shutdown"
send "quit"

wait "$follower_pid"
follower_pid=""
key "done."
