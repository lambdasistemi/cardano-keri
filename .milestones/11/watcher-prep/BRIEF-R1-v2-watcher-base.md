# R1 BRIEF v2 — COMPLETE dispatch brief, watcher base (r2 per CORRECTION-050)

Authority: A-027 sha256
`093add18d5464d23a191552005125dfde6406f6ce8aaa055c912db5c07adb3dd`;
semantics A-019 §2 sha256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf`.
This brief is SELF-CONTAINED and SUPERSEDES
`mandates/BRIEF-R1-ready-to-dispatch.md` (4c2c8c1b…) IN FULL — nothing
carries from it. All witness-era base/gate/ancestry references
(`d68030fa…`, witness-merge predecessor) and the expired pre-reset Opus
timing clause are VOID. Commissioned, NOT PLACED (host HOLD); sequenced
strictly after the S0-reland merge.

# SEAT (at placement)

Fresh Opus 5 `[1m]` high ticket owner (pure orchestrator; never writes
the repository), window `cardano-keri-ms11-tR1-event-key`, runtime
`/tmp/ms-keri-11/r1-v2`. Fill at dispatch: `<BASE>` = the ONE exact
read-back main SHA/tree after the S0-reland merge — the sole candidate
ancestry; no other ancestor identity is bound.

# OBJECTIVE — R1: event-derived MPF key

Replace the redeemer-supplied MPF key with A-019 §2's domain-separated
derivation over verified `i/s/p/d`: exact Plutus encoding
`Constr 0 [B "cardano-keri/event-key/v1", B canonical-qualified-i,
I decoded-s, (Constr 0 [] | Constr 1 [B canonical-qualified-p]),
B canonical-qualified-d]` under blake2b_256; `s` is the INTEGER decoded
from canonical hex (never text length, never a redeemer integer); the
redeemer supplies ONLY the MPF sibling proof. The old
`HistoricalProof.key/.location` and `prior_snapshot_digest` shapes carry
no authority. SEED (read-only): candidate `6312a751…` (tree
`b1d41bb2…`) with its static-green evidence — reapply/reimplement;
rebase/cherry-pick identity is NOT acceptance; new candidate SHA/tree.

# ORDER OF WORK — gate first

Author immutable gate `r1-event-key-v2` binding `<BASE>` as sole
ancestor, then falsify, freeze, and BLOCK for milestone desk
verification BEFORE any product write. Gate duties:

1. Golden vectors: both prior constructors AND every supported CESR
   derivation code, expected keys derived by an independent instrument
   (not the code under test); unknown/non-canonical qualification fails
   closed; a new CESR code requires a new accepted vector.
2. Right-cause kills: mutations of `i`, numeric `s`, present/absent `p`
   tag, `p`, `d`, the domain string, constructor order, and a
   submitter-chosen proof key; plus the positive proof that two valid
   rival SAIDs at one location COEXIST.
3. Six-control hardening (A-026 §1 via A-027): receipts print AND verify
   candidate head/tree (CI-S2W-C); dirty worktree/index refusal before
   any proof leg (CI-S2W-D); any commit changing a measured-source byte
   carries the re-derived manifest digest, gate recomputes from the
   committed tree, narrowing the measured set is forbidden; executable
   versioned mandate-bundle recipe verified from the committed tree;
   declared flake-input discipline for repo-root artifacts (CI-S2W-E);
   free prefix runs AFTER the candidate commit exists, then the full
   realizing gate on the same exact clean SHA/tree — both receipts.
4. Dual CI-surface mirror: the packaged Build-Gate attr set snapshotted
   VERBATIM from ci.yml at freeze time; the dev-shell leg; any
   unmirrored job named as a residual.

# TOPOLOGY AND FLOW

Fresh Codex `gpt-5.6-sol` high commit owner (ticket owner builds the
pane; START barrier; RED-first slice; one candidate). After the owner
parks: a DISTINCT fresh Opus 5 `[1m]` high auditor (never the ticket
owner's process, never a reused context). Merge only after: full gate on
the exact committed candidate + audit PASS + all required CI terminal
green on the same SHA + then-current-main integration without unreviewed
drift + guard merge/read-back binding expected head+tree. R2 dispatches
only after R1 is accepted AND merged.

# LAW

Two-token interlock with the campaign bar AS A WRAPPER PARAMETER
(66,571,993,088 B at N=1 unless re-ruled), per-leg fail-before-command
INSIDE the wrapper invocation path, exact `df -B1 --output=avail
/nix/store` journaled at acquire AND release; cold/uncertain legs only
under a fresh machine capacity release; realizing-hooks binding
(resolve hook path mechanically before commits); OPUS-CAPACITY per the
A-014 precedent (surface's natural budget figure verbatim; /usage
barred); grok/AGY/Qwen no seats; no `[OPEN]` semantic choice — anything
outside A-019 §2's decisions returns upward before write; worker-protocol
journaling via status-event; Q-files; WIP notes; no AI attribution; hash
every durable artifact; /tmp ages.
