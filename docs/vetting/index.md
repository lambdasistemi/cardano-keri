# Vetting Summary

Two agents independently vetted the `docs/aid-ops.md` specification:

- **Codex gpt-5.5** — full report in `codex/ANALYSIS.md`
- **Claude Opus 4.8** — full report in `claude/ANALYSIS.md`
- **Discussion and convergence** — `discussion.md`

Both agents were given the specification cold, with no prior context about the design intent. Findings were compared and deduplicated. The table below reflects the merged result.

## Findings by severity

| Finding | Severity | Status |
|---|---|---|
| `vk_from_tx_signatories` hash-width mismatch (28 vs 32 bytes) | Critical | Closed by signer-model decision |
| Value-write `auth_msg` insufficient anti-replay | Critical | Closed by Option A/B decision |
| No inception self-auth (`cur_key` possession proof) | High | Open |
| MPF node domain separation missing | High | Open |
| Single-UTxO contention / recovery-rotation griefing | High | Open |
| Canonical CBOR not mandated | High | Open |
| Domain separation missing on all signed/hashed objects | High | Open |
| CIP-31 MEV reference-input coupling | Medium | Open |
| No revocation / unbounded trie growth | Medium | Open |
| [Ed25519](https://www.rfc-editor.org/rfc/rfc8032) canonical-S malleability | Low | Open |
| Settlement depth not specified | Medium | Open |

## Critical findings (closed)

### `vk_from_tx_signatories` hash-width mismatch

Both agents independently flagged this. The original spec derived the public key from `tx_signatories`, but Cardano transaction signatories are 28-byte `blake2b_224` key hashes — not public keys. The original `cur_digest` was defined as `blake2b_256(cur_key)` (32 bytes). These types can never match.

**Resolution:** the design decision (Option A vs Option B) closes this:
- Option A: carry `vk` in the redeemer; `cur_digest` remains 32-byte `blake2b_256`; do not use `tx_signatories` for key recovery.
- Option B: redefine `cur_digest` as `blake2b_224(PubKey)`; use `extra_signatories` for authorization; the 28-byte match works by design.

### Value-write `auth_msg` insufficient anti-replay

The original `auth_msg` lacked a binding to the value cage's current state, making it possible to replay a valid authorization against a different cage state. The fully-bound `auth_msg` specified in [Value Authorization](../architecture/value-auth.md) includes `value_input_root`, `value_output_root`, `op_hash`, `counter`, `valid_from`, and `valid_until`. Option B eliminates the replay problem through UTxO-model uniqueness.

## High-severity findings (open)

### No inception self-auth

The original spec did not require the registrant to prove possession of `cur_key` at inception. Without this, an observer who sees an `InceptionEvent` in the mempool can front-run the registration (copy the event, submit before the original sender). The `cur_key` signature at inception (signing over `InceptionEvent`) closes this. The current spec includes this requirement; it was not in the original.

### MPF node domain separation

Without distinct domain tags for leaf, branch, and empty [MPF](https://github.com/aiken-lang/merkle-patricia-forestry) nodes, a structural second-preimage attack is possible. An adversary could craft a trie with different structure that hashes to the same root, breaking absence and inclusion proof soundness. This must be addressed in the MPF implementation used by the registry.

### Single-UTxO contention / recovery-rotation griefing

See [Operational](../design/operational.md). One inception/rotation per block is a fundamental throughput constraint. Recovery-rotation griefing is blocked by the pre-rotation property (attacker needs `next_key`) but is still possible if both keys are compromised.

### Canonical CBOR not mandated

The spec does not require canonical CBOR encoding for `InceptionEvent`, `rot_msg`, or `auth_msg`. Non-canonical encodings open second-preimage attacks at the hash layer. Canonical CBOR must be enforced by the on-chain encoder and all off-chain tooling.

### Domain separation missing

The original spec did not specify domain tags for the signed/hashed objects. Added to the current spec as required fields in `rot_msg` and `auth_msg`. MPF node domain tags must be added to the MPF implementation.

## Convergence and disagreement

**Points of convergence:** both agents agreed on the hash-width mismatch (independently derived), the MPF domain separation requirement, the canonical CBOR requirement, the CIP-31 MEV risk, and the tombstone-does-not-revoke gap.

**One open disagreement:** Option A vs Option B for value-write authorization. Codex preferred Option A (separates AID key from Cardano wallet key, preserving key isolation). Claude preferred Option B (eliminates hash-width mismatch class of bugs, simpler script, ledger-proven replay protection). The recommendation in [Value Authorization](../architecture/value-auth.md) reflects Option B, but Option A is fully specified for teams with hardware isolation requirements.
