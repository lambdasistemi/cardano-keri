# Surface B decoder lane — succession resume

Updated: 2026-08-18. This is the resurrection record for the retained ticket-owner lane. The
successor M1.2 milestone owner is in pane `%6656`. The immediate next action is **wait for the
project Q-007 ruling**; do not restart, edit, audit, build, or push while that ruling is absent.

## Lane identity

- Ticket owner: pane `%6715`, Codex `gpt-5.6-sol`, high effort.
- Ticket-owner replay command:
  `codex-raw --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri -c model_reasoning_effort=high`
- Tmux window: `keri-m12:2`, currently named `cardano-keri-ms11-tB-decoder-mainline`.
- Worktree: `/code/cardano-keri-ms11-b-decoder`.
- Branch: `ms11/b-decoder-land`, local only, currently 20 commits ahead of `origin/main`.
- Runtime root: `/tmp/ms-keri-11/b-decoder`.
- Durable lane status: `/tmp/ms-keri-11/b-decoder/STATUS.md`.
- No push, PR mutation, merge, release claim, or other remote mutation has occurred in this lane.

## Parked commit owner

- Worker: `repair-owner-1`, pane `%6720`, Grok `grok-4.6`.
- Replay command: `grok --always-approve -m grok-4.6` in the issue worktree above.
- Runtime: `/tmp/ms-keri-11/b-decoder/repair-owner-1`.
- State: `STATIC-READY`, parked write-idle. Do not wake it before the Q-007 ruling is delivered
  durably through the worker protocol.
- Rejected repair ancestry: `30cab0196b48ae1312ca0a19c252e9418b5f47fd`, tree
  `0dbdd118f13b15cd4a7f9e57cdd09c6b21ba102f` (`DO-NOT-LAND-AS-IS`).
- RED proof commit: `e1199aa0d757e3f60d46d308609410e5e8657b16`.
- Static-ready candidate: `f31c467ba9c9579864ab51c2dd36b931047ab1ac`, tree
  `54f17e58bbf61fbc7d2b269f15d40e6f325ae56b`.
- Candidate worktree and index were clean at succession capture.
- Candidate delta from `30cab019`: exactly six authorized paths, `+548/-112`.
- Receipt:
  `/tmp/ms-keri-11/b-decoder/repair-owner-1/handoffs/submission-2-receipt.md`, sha256
  `3861321c5ec97c1fbfc772a5daea4046ee0041f49df1e71af19e720757070701`.
- Handoff:
  `/tmp/ms-keri-11/b-decoder/repair-owner-1/handoffs/submission-2-handoff.md`, sha256
  `9821d60617e0917747107a1959522fe8a92ffc8474d6197f72893852a5df46ca`.

## Frozen proof and resource state

- Frozen gate: `/tmp/ms-keri-1/e274/t291-owner/gates/inv-bind-v1.sh`, sha256
  `7037228b898d5f93ad4ef365ac1cdfe0780f1bf6229f0f325cb2cf25171ac5b1`.
- Gate is byte-for-byte unchanged and has not been run against the static-ready candidate.
- Build budget: `builds_spent=0`, `builds_budget=1`; the single cold realization is unspent.
- Marker-aware realization wrapper:
  `/tmp/ms-keri-11/b-decoder/handoffs/run-with-build-tokens.sh`, sha256
  `140a699674789efee82c2b417ab5ed74a653f7d4108f1be416c0af9c7785cde3`.
- Submission-2 Claude Opus 5 `[1m]`, high-effort auditor has **not** been launched. It must audit
  the exact final repaired SHA/tree after the fence question is resolved, never `f31c467` as-is.

## Open blocker and authority boundary

- Ticket blocker: `Q-002-registration-test-outside-hard-fence` at
  `/tmp/ms-keri-11/b-decoder/questions/Q-002-registration-test-outside-hard-fence.md`, sha256
  `128546d47a828b976958a24e457a8bf334a801ee44b6b2857acf24aa74a0ab92`.
- Parent escalation: project question `Q-007`.
- Decision requested: extend A-002/A-006's hard proof allowlist by exactly
  `onchain/lib/cardano_keri/checkpoint/registration_tests.ak`.
- Static blocker: the generated vector correctly records `mis_dup_k` as
  `RegistrationInvalid(E4CurKeysMismatch)`, while the out-of-fence Aiken test pins the stale R4
  duplicate-key verdict. Its `parity` helper requires `recorded == pinned`; full CI reaches that row
  through `just ci` → `ci-onchain` → `check-onchain` → `aiken check`.
- Until the ruling: do not edit that file or any other out-of-fence path, including in a scratch
  copy; do not spend the build; do not launch the auditor; preserve candidate, receipts, and gate.

## F1 coverage claim — static and unaudited

The candidate claims fail-closed handling for every applicable protected list:

- `icp`: `k`, `n`, `b`;
- `dip`: `k`, `n`, `b`;
- `rot`: `k`, `n`, `br`, `ba`;
- `drt`: `k`, `n`, `br`, `ba`.

Malformed protected-list encodings and malformed elements must reject rather than become defaults,
and Aiken/Haskell accept-reject behavior must agree. This is a static-ready claim only. It has not
received the required fresh submission-2 falsification audit or compiled/gate evidence.

## Exact next action

1. **Wait for the Q-007 ruling. Do nothing else.**
2. If and only if the durable ruling grants the one-file extension, deliver it to the existing
   parked Grok owner through a worker-protocol answer/inbox pointer and require its acknowledgement.
   The owner then aligns only the stale `registration_tests.ak` pin/comment, creates a new local
   candidate SHA/tree, refreshes its receipt, and parks again.
3. Only after mechanically verifying that final clean SHA/tree and unchanged gate, create a fresh
   detached audit worktree and a new Claude Opus 5 `[1m]`, high-effort auditor pane for submission 2.
   That auditor owns the single marker-aware realization and deliberate F1/F2/F3 falsification.
4. Any submission-2 blocking finding ends this campaign; there is no implicit third attempt.
5. Even an audit pass does not authorize push: preserve the exact current-main delta and await every
   existing milestone acceptance and merge fence.
