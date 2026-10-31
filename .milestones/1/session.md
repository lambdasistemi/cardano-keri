# Identity core session

Milestone owner: tmux session cardano-keri-M1, window 1 cardano-keri-ms1-identity-core, pane %240 since 2026-10-30. Seat: Claude Opus 5.5 (no Codex seats, operator 2026-10-30). Canonical checkout /code/cardano-keri stays on main. Runtime /home/paolino/.orch-runtime/cardano-keri/m1. Resume the owner by reading resume/ms.md.

    claude --dangerously-skip-permissions --model claude-opus-5-5 --effort high

Staffing (operator 2026-10-30): Lean tickets have one Claude Opus 5.5 high writer. Aiken tickets have a ticket owner (Opus 5.5 high) who launches a commit owner (Sonnet 5.5 high) and a persistent auditor (Opus 5.5 high). Each seat has its own /code/cardano-keri-<issue>-<slug> worktree and TMPDIR=/code/.lanes-tmp/keri-m1/<seat-id>. The owner reviews before push and performs merges.

    env TMPDIR=/code/.lanes-tmp/keri-m1/<seat-id> claude --dangerously-skip-permissions --model claude-opus-5-5 --effort high


## Window cardano-keri-ms1-t339-datum-v2-onchain

Ticket owner for #339 (Aiken team: ticket owner Opus 5.5 high, commit owner Sonnet 5.5 high, auditor Opus 5.5 high). Runtime /home/paolino/.orch-runtime/cardano-keri/m1/datum-v2-onchain (children under it), base 0eab1e1. Pane %309 at dispatch. To resume: relaunch the Opus line in /code/cardano-keri with TMPDIR=/code/.lanes-tmp/keri-m1/datum-v2-onchain, then paste "Read /home/paolino/.orch-runtime/cardano-keri/m1/datum-v2-onchain/brief.md and STATUS.md; continue from your last event and resurrect your children from your resume record; journal START."
