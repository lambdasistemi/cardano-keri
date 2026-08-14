# Tasks: slice S162-1

One commit owner executes this ordered slice. The ticket owner owns planning,
gate, PR, CI acceptance, and final merge handoff. The owner never edits this
task list, tracked planning, or the ignored gate.

## Preconditions owned by ticket owner

- P01: the foreign realization census is clear and recorded.
- P02: exactly one corrected baseline `just ci` passed from the repository root.
- P03: this tracked mandate is committed and its hash is the owner pre-slice base.
- P04: draft PR exists; ignored `./gate.sh` has substituted hashes, passed its
  buildless self-test, survived a seeded path/vacuity falsification, and is
  frozen by SHA256.
- P05: ticket owner launches exactly the specified Grok 4.6 xhigh pane; no
  other Grok seat or auditor exists.

## RED

- T001: declare compact reliance on existing chain-query, endpoint-board, KEL,
  readiness, live deployment, and devnet boundaries.
- T002: add labeled `#162 relayer` parser/settings tests including invalid
  bounds and selection-vacuity protection.
- T003: add immediate-next KEL tests with positives and seeded forged AID,
  sequence, commitment, signature, receipt, SAID, and trailing-data failures.
- T004: add discovery/final-snapshot/race/log tests with seeded board downgrade,
  changed predecessor/endpoint, equal-sequence conflict, and forged-before-
  construction negatives.
- T005: add the genuine-devnet test shape and loopback witness boundary so the
  production command initially fails the required journey.
- T006: run permitted focused RED commands after host preflight, record expected
  failures, and commit tests only as `test(relayer): specify unattended advances`.

## GREEN

- T007: add CLI instruction/settings and shared follower query-handle/readiness
  interfaces without changing readiness semantics.
- T008: implement atomic discovery and final submission query programs plus
  fail-closed board-first/static-fallback selection.
- T009: implement bounded keripy-compatible witness intake and immediate-next
  rotation verification preserving native signatures.
- T010: promote/reuse in-process advance and settlement, implement exact race
  reconciliation and stable secret-free logs.
- T011: complete the real devnet restart/race/auth journey and wire it through
  existing Nix checks so `just ci` cannot omit it.
- T012: add `docs/user/run-a-relayer.md` and MkDocs navigation with command,
  prerequisites, 620-second conditional bound, discovery/fallback, restart,
  race, logs, and failure behavior.
- T013: run focused GREEN commands after individual host preflights; commit
  logical production/doc changes with conventional subjects.

## Proof and handoff

- T014: run the frozen ignored gate exactly, capture its evidence directory,
  and append `PROOF-COMPLETE` with HEAD, gate hash, commands, invariant outcomes,
  file/line totals, and no-push declaration.
- T015: park. Tier-2 CI is the only audit. The ticket owner reviews evidence,
  runs/accepts remote CI, requests repairs if needed, and authorizes the owner
  to create a final fixup commit only if required.
- T016: owner appends `COMPLETE`; ticket owner remains responsible for push/PR
  reconciliation and acceptance.

## Slice resource fence

At most 20 changed tracked files and 3,200 changed lines. No new dependency
outside existing Cabal/Nix inputs without challenge. Scratch data belongs under
`/code/tmp/e156`, never the repository. Any owned-path or resource overrun is a
STOP and question to the ticket owner.
