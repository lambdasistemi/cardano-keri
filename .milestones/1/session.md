# Identity core session

Milestone owner: tmux session cardano-keri-M1, window 1 cardano-keri-ms1-identity-core, pane %240 since 2026-10-30. Seat: Claude Opus 5.5 (no Codex seats, operator 2026-10-30). Canonical checkout /code/cardano-keri stays on main. Runtime /home/paolino/.orch-runtime/cardano-keri/m1. Resume the owner by reading resume/ms.md.

    claude --dangerously-skip-permissions --model claude-opus-5-5 --effort high

Staffing (operator 2026-10-30): Lean tickets have one Claude Opus 5.5 high writer. Aiken tickets have a ticket owner (Opus 5.5 high) who launches a commit owner (Sonnet 5.5 high) and a persistent auditor (Opus 5.5 high). Each seat has its own /code/cardano-keri-<issue>-<slug> worktree and TMPDIR=/code/.lanes-tmp/keri-m1/<seat-id>. The owner reviews before push and performs merges.

    env TMPDIR=/code/.lanes-tmp/keri-m1/<seat-id> claude --dangerously-skip-permissions --model claude-opus-5-5 --effort high


