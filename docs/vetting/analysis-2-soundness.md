# Analysis 2 — Cryptographic Soundness & Permissionless Attack Surface

Cold, adversarial vet of the canonical permissionless model. Primary lens:
cryptographic soundness and permissionless attack surface. Vetted against the
normative docs listed in the brief; background primers were not vetted.

Verification performed locally: the `veridian-bridge.md` CESR F-prefix test
vector reproduces exactly (blake2b-256 digest and 44-char qb64 both match). The
example in `blake2b256-requirement.md` does **not** (see D9).

---

## Confident defects

### D1 — Rotation redeemer omits binding between the signed `rot_msg` and the redeemer's `new_next`/`trie_key`/`seq_to`
**Severity:** High
**Location:** `identity-ops.md#rotation` vs `veridian-bridge.md#rotation-transaction`

**Flawed claim.** The "why the preimage check alone is not authorization" box asserts the signature "binds the new commitment the owner actually chose."

**Problem.** `rot_msg` contains `trie_key`, `reveal_key`, `new_next`, `seq_to`, but the on-chain check list never asserts `rot_msg.trie_key == redeemer.trie_key`, `rot_msg.new_next == redeemer.new_next`, or `rot_msg.seq_to == leaf.seq + 1`. Checks re-derive `seq_to` and check the preimage but do not tie the *signed* `new_next` to the `new_next` written into the resulting leaf (a separate redeemer field in `veridian-bridge.md`).

**Concrete failure.** If an implementer wires `resulting_leaf.next_digest = redeemer.new_next` while verifying the signature over a `rot_msg` whose `new_next` is not asserted equal to `redeemer.new_next`, an observer (reveal_key is public in the KEL) can submit their own `new_next` and capture the identity at seq+2. The danger box claims this is closed; the check list does not close it.

**Resolution.** Reconstruct `rot_msg` on-chain from the redeemer fields and the spent leaf, verify the signature over that reconstruction, and state the equality checks explicitly. Do not accept `new_next` as an independent redeemer field the signature does not cover.

### D2 — Emergency freeze spends the pre-rotation next key's secrecy and is replayable → next-key exposure + attacker-usable denial primitive
**Severity:** High
**Location:** `identity-ops.md#emergency-freeze`; `trust-model.md`

**Flawed claim.** "possession of the next key is what authorizes the freeze"; freeze "dissolves automatically once the on-chain rotation lands."

**Problem 1 (next-key exposure).** The freeze is signed with `reveal_key` (the pre-committed next key) and submitted while `cur_key` is compromised and an attacker is watching. The pre-rotation guarantee rests on the next key staying unused/secret until rotation; the freeze forces its use in the most hostile window, before rotation retires it (which the doc admits may be delayed by main-registry contention).

**Problem 2 (replay/liveness).** `freeze_msg = {domain, network_id, freeze_policy_id, freeze_thread_token, trie_key, seq}` — no freeze root, no nonce, no validity window. The marker is "active while `marker.seq == key_state.seq`." Any observer of one `freeze_msg` signature for `(trie_key, seq)` can re-submit it and keep the identity frozen at seq N; the owner's only escape is rotation on the congested main registry. A single ever-signed freeze becomes an attacker denial primitive.

**Resolution.** Bind `freeze_msg` to a freeze-registry counter/root so it is single-use; use a distinct authorization that does not consume the rotation's next key; reject a marker for a `(trie_key, seq)` already spent.

### D3 — Oracle can censor a rotation/freeze to keep a stolen key alive; freeze coverage is cage-optional, not enforced
**Severity:** High
**Location:** `overview.md#residual-oracle-trust`; `trust-model.md`; `veridian-bridge.md#synchronization-lag`

**Flawed claim.** "The oracle provides liveness; it cannot forge." "cages require `status == Active` plus freeze-registry absence."

**Problem.** Freeze security depends on *every* cage checking the freeze root, but the docs repeatedly hedge "cages that do not check the freeze registry," describing freeze-checking as cage-configured, not enforced. An oracle can deploy a freeze-blind cage, and — since the oracle is necessary for every value-write — an oracle colluding with a `cur_key` thief can keep co-signing the thief's writes and decline the owner's. "Cannot forge" holds; "keep a stolen key economically live" is fully available. Identity-plane permissionlessness does not rescue the value plane.

**Resolution.** Make freeze-registry consultation a mandatory spec-level invariant for any cage authorizing against the identity registry. State the oracle+thief collusion scenario and require an oracle-exit design, not a footnote.

### D4 — Value-write `auth_msg` is not bound to the freeze root; a stale freeze-absence proof re-authorizes a frozen key
**Severity:** High
**Location:** `value-auth.md#option-a`; `overview.md`

**Flawed claim.** `auth_msg` "binds … both MPFS roots … with replay protection"; cages check "no active `FreezeMarker`."

**Problem.** `auth_msg` binds `identity_root`, `value_input_root`, `value_output_root`, `key_seq`, cage id/token — but **not** the freeze root. The freeze-absence proof is checked against a freeze root the script reads separately, and the model tolerates snapshots/root windows. An attacker/oracle can present a freeze-absence proof against a freeze root taken *before* the owner's freeze landed, re-authorizing the stolen key. The doc's window discussion covers only the identity root, never freeze-registry freshness. This defeats the D2/D3 emergency channel.

**Resolution.** Add `freeze_root` (or a freeze counter) to `auth_msg`, require the absence proof be verified against exactly that root, and require it be the current freeze root (no window).

### D5 — Super-watcher burn is unsound without Blake3, and the challenge-period mitigation has no stated completeness or liveness — an innocent controller can be burned
**Severity:** High
**Location:** `super-watcher.md#without-blake3-the-trust-problem`, `#burn-transaction`

**Flawed claim.** "Option 1 (challenge period) is the most trust-minimized"; the fork-forfeit bond "makes convergence the rational choice."

**Problem.** The doc concedes checks 2–4 (parse CESR, compare keys, verify event signature + witness receipts) cannot run on-chain without Blake3, "so the script trusts the extraction — which a malicious watcher could forge against an innocent identity." The challenge-period fix is under-specified: (1) no completeness — what signed object refutes a forged proof? An honest controller who did not fork has no counter-proof of a negative, and any refutation still cannot be CESR-parsed on-chain; (2) liveness — a fixed N-block window means an offline/partitioned/censored controller loses the deposit to a forged proof; (3) economics — high deposits (encouraged for "strong guarantees") make innocents lucrative targets. Yet the docs present the bond as a load-bearing convergence guarantee.

**Resolution.** Do not present the burn/bond as a security guarantee in normative docs until Blake3/CESR exists. Fully specify the challenge tx and prove completeness + state liveness assumptions, or drop the burn in the pre-Blake3 model.

### D6 — Duplicity freeze check is both too narrow (misses real forks) and too weak (griefing → permanent tombstone from cross-protocol signature reuse)
**Severity:** Medium
**Location:** `identity-ops.md#duplicity-freeze`

**Flawed claim.** Both events verified with `leaf.key_state.cur_pubkey`; submission permissionless because "no invalid freeze can pass."

**Problem 1 (too narrow).** A real KEL fork can sign the two conflicting events under *different* keys (much of the point of a fork), or one event may be a rotation revealing a new key. Requiring both under the current on-chain `cur_pubkey` catches only a strict subset.

**Problem 2 (griefing).** Events are raw `ByteArray` with no domain tag and no KERI-structure/genuine-conflict check — only `event_1 != event_2` and both verify. Any two distinct messages ever signed under `cur_pubkey` (e.g. a rotation message and a value-write `auth_msg`) satisfy the check and permanently, irrecoverably tombstone the identity and burn the deposit. Cross-protocol signature reuse becomes a total-loss attack — the exact thing domain separation exists to prevent.

**Resolution.** Require both events be well-formed KERI events at the same seq that genuinely conflict. On-chain CESR parsing being out of scope, gate duplicity-freeze behind the same challenge machinery as the burn, or require a domain-separated `cardano-keri` duplicity attestation instead of raw signatures over arbitrary bytes. "No invalid freeze can pass" is false as written.

### D7 — Ed25519 non-canonical-S malleability is never addressed; breaks any replay/equality check keyed on signature bytes
**Severity:** Medium
**Location:** all signature-verifying flows — `identity-ops.md`, `value-auth.md`, `super-watcher.md`, `spo-delegation.md`

**Problem.** Standard Ed25519 verify (and the Plutus builtin) does not enforce low-S; a valid signature can be mauled into a second distinct valid signature over the same message. No doc mentions canonical-S. This voids: the D6 `event_1 != event_2` check, any "signature already appeared" replay reasoning (D2), and off-chain dedup keyed on signature bytes.

**Resolution.** State a canonical-S / non-malleability requirement for every verified signature; key replay-protection and equality on the signed message + explicit counter, never on signature bytes.

### D8 — Option A `auth_msg` counter has no specified on-chain store; root window + rollback enables cross-block replay
**Severity:** Medium
**Location:** `value-auth.md#window-root-selection`; `operational.md#block-ordering-coupling`

**Flawed claim.** Replay protection from the `auth_msg` counter + validity window; an old root "remains valid as long as still in the window."

**Problem.** The docs never specify where the counter lives or how a cage rejects a reused counter — Option B gets UTxO-uniqueness replay protection for free, but Option A's counter has no on-chain register. The accepted-root window means one `auth_msg` can be valid across multiple blocks; across a short Praos rollback (acknowledged in `operational.md`) the write + auth can be replayed. The "counter + validity window" is decorative without an on-chain monotonic store.

**Resolution.** Specify the on-chain per-`trie_key`/per-cage counter store and its check; enforce `valid_from/valid_until` against the tx validity interval; bind the auth to the specific cage input UTxO, not just its root.

### D9 — `blake2b256-requirement.md` worked example is internally inconsistent (43-char qb64, wrong content)
**Severity:** Low
**Location:** `blake2b256-requirement.md#cesr-f-prefix` (lines 24–26)

**Verified locally.** Raw bytes `f4a778…d5e6f7` with CESR pad semantics (`'F' + base64url('\x00'||digest)[1:]`) give `FPSneOh8s9bpyatua1misOHnyNLxo7XH2eDxorPE1eb3` (44 chars). The doc shows `F9Kd46Hy026-mm5rm5orzh7x4tLxowtc2exeD7Gim3M` (43 chars) — a plain `base64url(digest)`, exactly the mistake `veridian-bridge.md` warns against, and it contradicts the same page's "44 characters" statement. (The `veridian-bridge.md` vector is correct — verified.)

**Resolution.** Regenerate with the correct snippet or delete and reference the one correct vector.

### D10 — `trie_key` pre-image CBOR shape is under-specified; front-run-proof/uniqueness argument depends on byte-identical on-chain re-encoding
**Severity:** Low
**Location:** `aid-model.md#trie_key-derivation`, `#cbor-determinism`

**Problem.** The uniqueness and "front-running collapses to key theft" arguments require the Aiken script to re-encode `cbor({cur_pubkey, next_digest})` byte-identically to the registrant. Canonical CBOR is mandated but the concrete map shape (integer vs text keys, map header, field order) is not pinned to the builtin's output. A one-byte mismatch either breaks legitimate inceptions or means the absence proof is against the wrong key. Underspecification of a value that gates uniqueness and front-run resistance is itself a soundness finding.

**Resolution.** Pin the exact CBOR structure as a normative test vector matching the Aiken builtin byte-for-byte.

---

## Questions / uncertainties

### Q1 — Mandatory k-of-n KeyState invalidates the singleton pre-rotation/derivation proofs; the multisig case is never analyzed
**Location:** `aid-model.md` note; `business-cases/index.md#the-factored-core`; all business cases.

Every security argument (pre-rotation, "reveal binds commitment," rotation signature) is written for a single key, yet list-shaped k-of-n is mandatory from v1 and frozen into `trie_key`. Unanswered: does `next_digest` commit to the next *set* / threshold / Merkle root? Does rotation need k signatures? Is partial rotation representable? Can a current-key quorum rotate, and how is that squared with "theft of the current quorum cannot rotate" vs organizational recovery? The most load-bearing property is stated only for the degenerate case the docs admit is not real.

### Q2 — On-chain feasibility of the "bounded"/"O(1)" verification is asserted, never budgeted
**Location:** `amaru-integration.md`; `defi-gate.md`; `regulated-defi.md#4`; `business-cases/index.md`.

The DeFi case shows admission-cache is "arithmetically" mandatory (batch ACDCs exceed 16 KB), but no exec-unit/script-size budget is given for the admission tx that runs the full 4-hop chain verify (4 ACDCs + KEL/TEL MPF proofs + Ed25519 + CESR decode) in Plutus V3, nor for the per-action path (identity inclusion + freeze absence + Ed25519 + up to 3 TEL proofs + counter). Whether even the "cheap" path fits Plutus V3 mem/CPU with multiple MPF proofs is unestablished.

### Q3 — Seq-0 binding mitigation is off-chain and unenforceable, but downstream claims assume the SDK obeyed it
**Location:** `aid-model.md#seq-0-binding-gap`; `veridian-bridge.md#digest-agility-requirement`; `vlei.md` gap table ("ships M1").

The docs admit at seq 0 the binding is unverifiable unless the SDK mandates blake2b-256 digest agility and "the on-chain script cannot verify it." Every downstream claim (super-watcher divergence, binding protocol, admission) assumes the SDK complied. Is there any on-chain marker that an inception used the mandated encoding? Apparently not — `next_digest` is opaque. A hostile/buggy SDK yields silent, whole-pre-rotation-life unverifiability.

### Q4 — `cesr_aid` squatting dismissed as "metadata," but admission flows may key on it
**Location:** `aid-model.md#inception-security`; `trust-model.md#cesr-aid`; business cases.

`cesr_aid → trie_key` is one-to-many; only KEL-recomputation is authoritative. But admission resolves a vLEI AID to a `trie_key`, and the index is called a "convenience." If any admission tool trusts the index instead of running the full binding-verification protocol, a squatter asserting the victim's `cesr_aid` gets admitted. The docs say "MUST recompute" in one place and "convenience" in others — is the full KEL replay a hard requirement at admission or advisory?

### Q5 — "Wait N blocks for root stability" contradicts freeze urgency
**Location:** `operational.md#block-ordering-coupling` vs `veridian-bridge.md#synchronization-lag`.

Operational advises value-writes wait N blocks for identity-root stability; the emergency freeze needs stolen-key authority revoked fast against an advancing freeze root. Consumers waiting for identity-root stability read a root that may predate the freeze, widening the compromise window. The two mitigations pull opposite directions and are never reconciled.

---

## Overclaims

1. **"The oracle … cannot forge."** True for forgery, but the oracle can censor and — via freeze-optional cages + collusion with a `cur_key` thief (D3) — keep a stolen key economically live. Security-tokens.md itself flags this contradicts the headline.
2. **"Fork = forfeit … makes convergence the rational choice."** The bond is unenforceable without Blake3/CESR (conceded), and the challenge-period substitute lacks completeness/liveness (D5). A guarantee presented; an open problem deferred to M5.
3. **"No invalid freeze can pass" / duplicity proof "self-authenticating."** The check accepts two differing byte-strings under one key with no KERI-structure/conflict check; cross-protocol signature reuse permanently tombstones an innocent identity (D6).
4. **"Front-running collapses to key theft."** Holds only if on-chain CBOR re-encoding is byte-identical (D10, underspecified) and for the singleton case; k-of-n derivation unspecified (Q1).
5. **"Immediately verifiable after inception" / seq-0 "ships M1."** Conditional on an off-chain SDK mandate the chain cannot verify; a violating SDK yields silent unverifiability (Q3).
6. **"Replay protection" for Option A value-writes.** The counter has no specified on-chain store/check, and the root window admits cross-block/rollback replay (D8) — asserted, not constructed.
7. **"Instant revocation" framing of the freeze.** Neither instant (contention, sync lag) nor complete (freeze-optional cages, stale-root evasion D4).
8. **Pre-rotation "a thief who obtains `cur_pubkey` cannot advance `seq`."** True in isolation, but the freeze path forces the owner to spend the next key's secrecy in the hostile window (D2), and the property is unanalyzed for the mandatory k-of-n case (Q1).
