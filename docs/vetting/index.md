# Vetting Summary

Two agents independently vetted the `docs/aid-ops.md` specification (now archived as [`aid-ops-historical.md`](aid-ops-historical.md)):

- **Codex gpt-5.5** — full report in [`analysis-codex.md`](analysis-codex.md)
- **Claude Opus 4.8** — full report in [`analysis-claude.md`](analysis-claude.md)
- **Cross-agent discussion** — [`codex-to-claude.md`](codex-to-claude.md) and [`claude-to-codex.md`](claude-to-codex.md)

Both agents were given the specification cold, with no prior context about the design intent. Findings were compared and deduplicated. The table below reflects the merged result.

## Findings by severity

| Finding | Severity | Status |
|---|---|---|
| `vk_from_tx_signatories` hash-width mismatch (28 vs 32 bytes) | Critical | Closed by signer-model decision |
| Value-write `auth_msg` insufficient anti-replay | Critical | Closed by Option A/B decision |
| No inception self-auth (`cur_key` possession proof) | High | Resolved — spec now requires `Ed25519(cur_pubkey, inc_msg)` |
| MPF node domain separation missing | High | Resolved — domain tags specified in `aid-model.md` |
| Single-UTxO contention / recovery-rotation griefing | High | Open — mitigated by deposit + freeze registry |
| Canonical CBOR not mandated | High | Resolved — canonical CBOR required by `aid-model.md` |
| Domain separation missing on all signed/hashed objects | High | Resolved — domain tags specified in `aid-model.md` |
| CIP-31 MEV reference-input coupling | Medium | Open |
| No revocation / unbounded trie growth | Medium | Open |
| [Ed25519](https://www.rfc-editor.org/rfc/rfc8032) canonical-S malleability | Low | Open |
| Settlement depth not specified | Medium | Open |

## Still-open implementation requirements

| Requirement | Notes |
|---|---|
| Canonical next-key encoding | `canonical_next_pubkey_bytes` now defined in `veridian-bridge.md` with test vector; SDK must implement exactly |
| Deposit model | Resolved: Option A (`deposit : Lovelace` in `KeyState`); see `super-watcher.md` |
| Freeze marker unification | Resolved: canonical 4-field `FreezeMarker` defined in `identity-ops.md` |
| `cesr_aid` derivation code | Open: currently stored as raw 32 bytes; future versions should store full CESR qualified prefix |
| Convergence enforcement trustlessness | Open: burn mechanism is a proposal; not fully trustless without Blake3 on-chain |
| CIP-31 MEV coupling | Open |
| Ed25519 canonical-S malleability | Open |
| Settlement depth policy | Open |

## Critical findings (closed)

### `vk_from_tx_signatories` hash-width mismatch

Both agents independently flagged this. The original spec derived the public key from `tx_signatories`, but Cardano transaction signatories are 28-byte `blake2b_224` key hashes — not public keys. The original `cur_digest` was defined as `blake2b_256(cur_key)` (32 bytes). These types can never match.

**Resolution:** the design decision (Option A vs Option B) closes this:
- Option A: carry `vk` in the redeemer; `cur_digest` remains 32-byte `blake2b_256`; do not use `tx_signatories` for key recovery.
- Option B: redefine `cur_digest` as `blake2b_224(PubKey)`; use `extra_signatories` for authorization; the 28-byte match works by design.

### Value-write `auth_msg` insufficient anti-replay

The original `auth_msg` lacked a binding to the value cage's current state, making it possible to replay a valid authorization against a different cage state. The fully-bound `auth_msg` specified in [Value Authorization](../architecture/value-auth.md) includes `value_input_root`, `value_output_root`, `op_hash`, `counter`, `valid_from`, and `valid_until`. Option B eliminates the replay problem through UTxO-model uniqueness.

## High-severity findings (now resolved)

### Inception self-auth

The original spec did not require the registrant to prove possession of `cur_key` at inception. Without this, an observer who sees an `InceptionEvent` in the mempool can front-run the registration. **Resolution:** the current spec requires `Ed25519(cur_pubkey, inc_msg)` at inception. See [Identity Operations — Inception](../architecture/identity-ops.md#inception).

### Canonical CBOR

The spec did not require canonical CBOR encoding for `InceptionEvent`, `rot_msg`, or `auth_msg`. **Resolution:** canonical CBOR is now mandated for all hashed and signed objects. See [AID Model — CBOR determinism](../design/aid-model.md#cbor-determinism).

### Domain separation

The original spec did not specify domain tags for the signed/hashed objects. **Resolution:** domain tags are now required fields in all messages. See [AID Model — Domain separation](../design/aid-model.md#domain-separation).

## Convergence and disagreement

**Points of convergence:** both agents agreed on the hash-width mismatch (independently derived), the MPF domain separation requirement, the canonical CBOR requirement, the CIP-31 MEV risk, and the tombstone-does-not-revoke gap.

**One open disagreement:** Option A vs Option B for value-write authorization. Codex preferred Option A (separates AID key from Cardano wallet key, preserving key isolation). Claude preferred Option B (eliminates hash-width mismatch class of bugs, simpler script, ledger-proven replay protection). The recommendation in [Value Authorization](../architecture/value-auth.md) reflects Option B, but Option A is fully specified for teams with hardware isolation requirements.
