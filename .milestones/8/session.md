# tmux session `keri-ms8-blaster` — milestone 8 resurrection manual

Snapshot updated 2026-08-02T19:07Z. Milestone 8 is active in its dedicated session `keri-ms8-blaster`. The reclaim hold is released, the operator dissolved #192's M1 dependency, and the M8-owned root-gate migration is a separate non-blocking work item. This remains a separate desk from Cardano-KERI M1 and must never reuse or retarget M1 pane `%5169`.

## milestone singleton — `cardano-keri-ms8-blaster`

- Session/window/pane on the founding host: `keri-ms8-blaster:1.1`, window `@3589`, pane `%5225`.
- Role: `milestone-orchestrator`; one pane only.
- Exact CLI launch: `codex-raw --dangerously-bypass-approvals-and-sandbox -C /home/paolino -c model=gpt-5.6-sol -c model_reasoning_effort=xhigh`
- CWD: `/home/paolino` (the desk writes no repository implementation).
- Runtime: `/tmp/ms-keri-8`.
- Resume: read `.milestones/8/resume/ms.md` from the `milestones` branch, then `/tmp/ms-keri-8/brief.md` and `/tmp/ms-keri-8/STATUS.md` when the host runtime survives.
- Required skills: `orchestrator-contract`, `milestone-orchestrator`, `worker-protocol`, `tmux-orchestrator`, `invariants`, `verification`.
- Singleton drift: pane `%5287` is a preserved idle Claude/support pane in window `@3589`, not a milestone child or authority. Do not kill it without ownership confirmation; `%5225` remains the only milestone owner.

## Child windows

### Epic #189 — `cardano-keri-e189-t192-blaster-tractability`

- Epic owner: pane `%5236`, runtime `/tmp/ms-keri-8/e189`, `gpt-5.6-sol/xhigh`; stage `S1-GREEN-NAVIGATOR-REVIEW-ACTIVE`.
- Ticket #192 owner: pane `%5241`, runtime `/tmp/ms-keri-8/e189/t192`, worktree `/code/cardano-keri-issue-192`, branch `feat/192-uplc-tractability`, planning HEAD `eab9ac573256b161a8f5e5882d42a263851bd7b1`, open draft PR #215. Preserved PAIR: driver `%5279`, navigator `%5280`.
- Fresh baseline and planning pre-push gates passed. Corrected RED round 2 was approved; the real-Nix seeded negative failed as intended; exact restoration and the restored-positive pass are recorded. The complete 11-path GREEN handoff is frozen and under navigator review. Acceptance, implementation commit, and implementation push remain forbidden pending that verdict and ticket-owner verification.
- #193–#195 are filed but undispatched and dependency-blocked.
- M1 dependency: dissolved. `legacy-root-gate-migration` is M8-owned, separate, and non-blocking; #192 keeps root `gate.sh` and `.gitignore` forbidden.
- No loop, timer, scheduled prompt, monitor, poller, tail, or watchdog was re-armed; execution is foreground-owned by ticket #192 through the existing epic chain.
- Resume fragment: `.milestones/8/resume/e189.md`, aggregated byte-for-byte from the epic owner's `/tmp/ms-keri-8/e189/.orch/window-brief.md`. Authoritative pause handoff on the founding host: `/tmp/ms-keri-8/e189/handoffs/PAUSE.md`.

#190 remains queued behind #189's tractability/frozen-artifact contract. Each future epic owner must publish its own session/resume fragment; the milestone desk aggregates rather than ghost-writes it.
