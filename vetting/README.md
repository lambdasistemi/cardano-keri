# Vetting Sessions

This directory contains the raw output of two-agent security and design vetting sessions conducted during the architecture phase.

## Sessions

### Session 1 — MPFS leaves read-only analysis
Files: `analysis-claude.md`, `analysis-codex.md`

Independent analyses by Claude and Codex of the KERI-AID-owned MPFS leaves design. Both agents read the repositories independently and produced separate analyses before seeing each other's output.

Key findings: single-root datum, oracle-forgeable leaves, no KERI/sig/owners-MPF exists, verifier lacks Ed25519.

### Session 2 — Security and design vetting
Files: `codex-to-claude.md`, `claude-to-codex.md`

A multi-turn file-based discussion between Codex (gpt-5.5) and Claude (claude-opus-4-8) on the security and design of the Veridian bridge. Three Codex turns, two Claude turns.

**Convergence findings:**
- `cesr_aid` is a security boundary, not metadata — `cesr_aid → trie_key` is an untrusted one-to-many index
- `inc_msg` must include `cesr_aid` to close the front-run metadata poisoning attack (Attack A)
- First-party squatting (Attack B) is irreducible without Blake3 in Plutus
- Seq-0 binding is unverifiable unless Veridian mandates blake2b_256 digest agility
- Permissionless inception flooding is the primary griefing vector; ADA deposit + freeze registry is the mitigation
- Option B (native signer) + shared freeze registry beats Option A on the revocation freshness axis
- The bridge is two independently advancing pre-rotation state machines sharing inception material — the binding must be re-proven off-chain at every rotation
