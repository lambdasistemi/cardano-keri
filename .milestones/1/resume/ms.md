# Resume the identity core milestone

Read /home/paolino/.orch-runtime/cardano-keri/m1/brief.md in full, then the local handoffs/ledger.md and the tail of STATUS.md. Two operator rulings of 2026-10-30 amend that brief: no Codex seats (desk and writers are Claude Opus 5.5 high; Aiken tickets get an Opus ticket owner, a Sonnet commit owner and an Opus auditor), and no owner exit: a checkpoint is alive until convicted. Do not copy the private brief into a public artifact.

State at 2026-10-31 06:00 UTC: resumed after the operator's pause. PRs 487, 488, 490, 491, 492, 494, 496, 499, 500, 501, 503 merged. One lane runs: datum-v2-onchain (#339, Aiken team). The ticket owner requests review with REVIEW-REQUESTED; the desk grants an exact SHA to push, then merges after green.

On resume: journal START, re-arm wait-channels over the desk root (it covers both lanes), and read both lanes' journal tails.
