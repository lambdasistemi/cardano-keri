#!/usr/bin/env bash
# usage: fee-account.sh <rehearsal work directory>
# For each transaction the rehearsal's commands made, accounts for its fee from the chain's own records: the bytes of the
# transaction (less the one byte of the validity flag the fee does not price), its declared execution units, and the
# scripts its inputs and reference inputs resolve to (their bytes, from the facade's account of each transaction), at the
# protocol parameters of the epoch the rehearsal ended in. The recomputed fee must equal the fee paid.
# Needs the hex of each transaction and the inspector's output next to it (the rehearsal keeps both); run inside nix develop.
set -euo pipefail
W="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
a=$(jq -r '.[0].min_fee_a' "$W/txinfo/epoch_params.json"); b=$(jq -r '.[0].min_fee_b' "$W/txinfo/epoch_params.json")
pm=$(jq -r '.[0].price_mem' "$W/txinfo/epoch_params.json"); ps=$(jq -r '.[0].price_step' "$W/txinfo/epoch_params.json")
rs=$(jq -r '.[0].min_fee_ref_script_cost_per_byte' "$W/txinfo/epoch_params.json")
# the transactions the commands reported, in order, and their bytes as the facade holds them
list="$W/all.list"; : >"$list"
add() { [[ -n "$2" ]] && echo "$1 $2" >>"$list" || true; }
for f in deploy deploy-2; do
    while read -r step id; do add "$f-$step" "$id"; done < <(sed -n 's/^\(publish-[a-z-]*\|create-registry\): \([0-9a-f]\{64\}\) fee=.*/\1 \2/p' "$W/$f.out")
done
add premint-single "$(sed -n 's/^premint-transaction: //p' "$W/register-single.out" 2>/dev/null)"
add premint-multi "$(sed -n 's/^premint-transaction: //p' "$W/register-multi.out" 2>/dev/null)"
add premint-closed "$(sed -n 's/^premint-transaction: //p' "$W/register-closed.out" 2>/dev/null)"
add register-single "$(sed -n 's/^booking-transaction: //p' "$W/register-single.out" 2>/dev/null)"
add register-multi "$(sed -n 's/^booking-transaction: //p' "$W/register-multi.out" 2>/dev/null)"
add register-closed "$(sed -n 's/^booking-transaction: //p' "$W/register-closed.out" 2>/dev/null)"
add fold-1 "$(sed -n 's/^fold-transaction: //p' "$W/fold-1.out" 2>/dev/null)"
add fold-2 "$(sed -n 's/^fold-transaction: //p' "$W/fold-2.out" 2>/dev/null)"
add return "$(sed -n 's/^return-transaction: //p' "$W/return.out" 2>/dev/null)"
while read -r name id; do jq -r '.[0].cbor' "$W/txinfo/$id.cbor.json" >"$W/$name.hex"; done <"$list"
printf '%-30s %6s %9s %9s %8s %9s %7s %10s %6s %12s %14s\n' transaction size fee linear exec refbytes reffee recomputed delta payer-change other-outputs
while read -r name id; do
    [[ -n "$id" && -s "$W/$name.hex" ]] || continue
    out=$("$here/inspect-tx.sh" "$W/$name.hex" 2>/dev/null)
    size=$(sed -n 's/^size //p' <<<"$out"); fee=$(sed -n 's/^fee //p' <<<"$out")
    read -r mem steps < <(sed -n 's/^total-ex-units (\([0-9]*\),\([0-9]*\))/\1 \2/p' <<<"$out")
    info="$W/txinfo/$id.json"
    # the scripts the transaction resolves: those of its reference inputs and of its spent inputs, once per input
    # the payer's change is the last output when it goes back to the key address that paid (the builders put it last); every other
    # output, the registry's own and the payer's published outputs included, is an ordinary output
    read -r change others < <(jq -r '.[0] as $t | ([$t.inputs[] | .payment_addr.bech32 | select(startswith("addr_test1v"))] | first) as $payer | ($t.outputs | length) as $n | ($t.outputs | map(.value | tonumber)) as $v | (if $t.outputs[$n - 1].payment_addr.bech32 == $payer then $v[$n - 1] else 0 end) as $c | "\($c) \(($v | add) - $c)"' "$info")
    refbytes=$(jq '[(.[0].reference_inputs[]?, .[0].inputs[]?) | .reference_script | select(. != null) | (.bytes | length) / 2] | add // 0' "$info")
    awk -v size="$size" -v fee="$fee" -v mem="${mem:-0}" -v steps="${steps:-0}" -v a="$a" -v b="$b" -v pm="$pm" -v ps="$ps" -v rs="$rs" -v rb="$refbytes" -v name="$name" -v change="$change" -v others="$others" 'BEGIN {
        lin = a * (size - 1) + b
        e = mem * pm + steps * ps; ex = int(e); if (ex < e) ex++
        # the reference-script fee: each stride of 25600 bytes priced 1.2 times the one before
        left = rb; price = rs; rf = 0
        while (left > 0) { chunk = (left > 25600) ? 25600 : left; rf += chunk * price; left -= chunk; price *= 1.2 }
        rf = int(rf)
        printf "%-30s %6d %9d %9d %8d %9d %7d %10d %6d %12d %14d\n", name, size, fee, lin, ex, rb, rf, lin + ex + rf, fee - (lin + ex + rf), change, others }'
done < "$W/all.list"
