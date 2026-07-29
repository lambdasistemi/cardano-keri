# Frozen endpoint-board datum schema

This file is the follower contract published with the endpoint-board policy
and marker address. Its field order and constructor indices are immutable for
the M1 board policy.

## Release identity

- Blueprint entry: `endpoint_board.endpoint_board.mint`
- Production compiler: Aiken `v1.1.21` via the flake-owned blueprint
- Policy ID: `54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c`
- Preprod marker address:
  `addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4`

## `BoardDatumV1`

Canonical Plutus Data:

```text
Constr 0
  [ B witness_key
  , B endpoint_record
  , B endpoint_signature
  , B owner_key_hash
  ]
```

| Position | Field | Wire constraint | Meaning |
|---:|---|---|---|
| 0 | `witness_key` | exactly 32 bytes | Raw Ed25519 key decoded from the witness's non-transferable KERI `B...` identifier; exactly the marker asset name. |
| 1 | `endpoint_record` | non-empty bytes | Exact serialized KERI `/loc/scheme` `rpy` event bytes, without its CESR attachment. |
| 2 | `endpoint_signature` | exactly 64 bytes | Raw Ed25519 signature decoded from the record's CESR attachment; verifies over `endpoint_record` under `witness_key`. |
| 3 | `owner_key_hash` | exactly 28 bytes | Cardano payment verification-key hash that must appear in `extra_signatories` on update and retire. Readers parse and width-check it but never use it to select witnesses. |

The marker policy authenticates the byte-level signature and the
asset-name/key binding. Readers additionally parse the KERI event and fail
closed unless it is a self-consistent `/loc/scheme` record whose `eid`
decodes to `witness_key`, whose SAID is valid, and whose URL/scheme fields are
valid.

## Currency and duplicates

Current means exactly the unspent marker outputs at the marker address. There
is no TTL, wall clock, or slot expiry in the schema or follower filter. A
spent predecessor is stale. Every valid unspent duplicate is surfaced with
its distinct output reference.

## Lifecycle redeemer

```text
Update = Constr 0 []
Retire refund_address = Constr 1 [<Address Data>]
```

Update requires the recorded owner, preserves the exact marker and deposit,
and replaces the datum with another valid `BoardDatumV1` for the same
`witness_key`. Retire requires the recorded owner, burns exactly one matching
marker, and pays the complete board deposit to `refund_address`.

The minting-policy redeemer is likewise frozen:

```text
Post = Constr 0 []
Burn = Constr 1 []
```
