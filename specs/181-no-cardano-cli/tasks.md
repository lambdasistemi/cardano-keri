# Tasks — #181 no `cardano-cli` in the transaction path

Boxes are stamped only by the ticket orchestrator after the frozen gate and
independent navigator review pass. Each implementation slice is a bisect-safe
commit with an exact `Tasks:` trailer.

## Slice 1 — coherent input/runtime seam

- [x] T181-S1-1 RED: plural payer addresses produce raw `(TxIn, TxOut)` values
      through exactly one store transaction; address permutation/duplication
      does not change the candidate set
- [x] T181-S1-2 RED: transaction-runtime call-order tests bind query,
      evaluation, balancing, signing, pure tx id, submission, and observation
      to one transaction evolution
- [x] T181-S1-3 RED: evaluation and submission rejection short-circuit later
      phases and retain actionable error details
- [x] T181-S1-4 GREEN: expose the minimal coherent payer read by reusing the
      existing transaction-level address scan without another private copy
- [x] T181-S1-5 GREEN: add indexer-neutral runtime/error types and pinned
      in-process protocol/evaluation/signing/id/submission helpers
- [x] T181-S1-6 Add `just transaction-path-check`, Cabal wiring, format/HLint,
      and a dependency-pin guard
- [x] T181-S1-7 Frozen slice gate and accumulated `./gate.sh` green; navigator
      verifies one commit with `Tasks: T181-S1-1,...,T181-S1-7`
- [x] T181-S1-8 Correction: the multi-address payer scan no longer collides with
      the `payerUtxosTx` that #219 merged into `main`, so the indexer library
      compiles again; `main`'s API is untouched and Slice 1's FR-2 proofs survive
      the rename

## Slice 2A — shared build/sign kernel

- [x] T181-S2A-1 RED: shared tests distinguish empty indexed input,
      insufficient value, and missing distinct collateral
- [x] T181-S2A-2 RED: evaluation, bad-key, submission, and restricted-`PATH`
      failures are distinct, actionable, and proven able to fail
- [x] T181-S2A-3 GREEN: add the operation-neutral build/balance/input/signing
      composition using the pinned transaction-tool APIs
- [x] T181-S2A-4 Focused matcher rejects zero selection and executes every
      named proof; frozen Slice 2A and accumulated gates are green
- [x] T181-S2A-5 Navigator verifies one commit with
      `Tasks: T181-S2A-1,...,T181-S2A-5`
- [x] T181-S2A-6 Correction: the `deployment-tests` component builds and runs
      from a clean checkout again, after Slice 2A gave it an import its own
      `other-modules` did not list; every added line forced by a named
      compiler or `cabal-fmt` error, with the preserved 2B/2C work untouched

## Slice 2B — deploy / Publisher migration

- [x] T181-S2B-1 RED: Publisher tests freeze reference output/script,
      fee/change, collateral, signing, tx-id, submission, and settlement
- [x] T181-S2B-2 RED: Publisher selection and exact-id observation failures
      remain distinct and timeout polling reaches its real deadline branch
- [x] T181-S2B-3 GREEN: migrate `Publisher` completely from subprocess query,
      build, sign, txid, and submit to the shared runtime; retire `CLI.hs`'s
      two `Publisher`-construction call sites (`runDeploy`, `runBoardDeploy`)
      to fail closed with an actionable error before funding/build/sign/
      submit, pending Slice 4 composition — ruled 2026-08-05 in answer to
      Q-001-red-oracle-kernel-conflicts: changing `Publisher`'s config shape
      mechanically breaks these two call sites regardless of Registration's
      own migration state, so their half of the fail-closed retirement moves
      here from Slice 2C. CLI flag parsing (`DeploySettings` etc.) is
      untouched; removing the flags themselves stays Slice 4's T181-S4-2.
- [x] T181-S2B-4 Prove the restricted-`PATH` suite can fail, reject zero
      selection, and pass restored production. (No standalone Publisher-only
      source-guard script — superseded by Slice 2C's combined
      `scripts/check-deploy-register-no-cli.sh`, already preserved in the
      worktree; ruled 2026-08-05 in the same gate v3 correction that fixed
      the post-#219-rebase `base=` drift.)
- [x] T181-S2B-5 One commit with `Tasks: T181-S2B-1,...,T181-S2B-5`,
      independently verified by a fresh commit auditor (not a navigator —
      this slice was redispatched mid-ticket from PAIR to the alternation
      contract: Claude ticket owner → Codex commit owner → fresh Claude
      auditor, per NOTE-006/007). Candidate `246c998ad1090f7612ccf3e6ed659d6955b549dd`,
      audit verdict PASS, 10/10 invariants, 0 blocking findings, report hash
      `89d16db2735bf2a8472d6c320183f4ebbbb29d10bf3ce53776112f211c074137`.

## Slice 2C — register migration and fail-closed old CLI

- [ ] T181-S2C-1 RED: Registration tests freeze datum, mint, reference inputs,
      lifecycle withdrawal, fee/change, collateral, signing, tx-id,
      submission, and settlement
- [ ] T181-S2C-2 RED: evaluation, bad-key, submission, and timeout failures
      retain exact actionable detail and exercise the real operation path
- [ ] T181-S2C-3 GREEN: migrate `Registration` completely from subprocess
      query, build, sign, txid, and submit to the shared runtime
- [ ] T181-S2C-4 Retire register `cardano-cli` fields and make the old
      register command fail closed before funding/build/sign/submit pending
      Slice 4. (Publisher's half — `runDeploy`/`runBoardDeploy` — already
      moved to T181-S2B-3; ruled 2026-08-05.)
- [ ] T181-S2C-5 Prove the combined source guard and restricted-`PATH` suite
      can fail, reject zero selection, and pass restored production
- [ ] T181-S2C-6 Navigator verifies one commit with
      `Tasks: T181-S2C-1,...,T181-S2C-6`

## Slice 3 — advance, close, and endpoint-board migration

- [ ] T181-S3-1 RED: advance/rotate tests freeze spending/reference inputs,
      checkpoint datum/redeemer, validity, collateral, signing, submission,
      tx-id, and settlement
- [ ] T181-S3-2 RED: close tests freeze burn/close semantics and board tests
      freeze post/update/retire ownership, datum, mint/burn, and settlement
- [ ] T181-S3-3 RED: all three operations demonstrate underfunded,
      evaluation/script, submission-rejection, and timeout signals fail closed
- [ ] T181-S3-4 GREEN: migrate `AdvanceTransaction` and `CloseTransaction` to
      the shared in-process runtime
- [ ] T181-S3-5 GREEN: migrate `EndpointBoardTransaction` post/update/retire to
      the shared in-process runtime
- [ ] T181-S3-6 Remove remaining transaction runner subprocess/configuration
      surface; source/closure guard fails on deliberate reintroduction and
      passes restored
- [ ] T181-S3-7 Focused and accumulated gates green; navigator verifies one
      commit with `Tasks: T181-S3-1,...,T181-S3-7`

## Slice 4 — #177 composition and live no-CLI journey

- [ ] T181-S4-1 Record the epic-owner-approved #177 integration base and wire
      the CLI library to one follower/runner plus one N2C provider/submitter
      without a deployment/indexer cycle
- [ ] T181-S4-2 Remove all transaction-command `cardano-cli` options and the
      packaged runtime dependency; executable help and closure guards pass
- [ ] T181-S4-3 Add a deterministic restricted-PATH helper whose positive
      control proves a reintroduced shellout fails
- [ ] T181-S4-4 Run the production deploy/register/advance-or-rotate/board/close
      journey on the real node with `cardano-cli` absent and observe every tx
- [ ] T181-S4-5 Run a deliberately underfunded production attempt and preserve
      its named non-zero error without submitting a transaction
- [ ] T181-S4-6 Regenerate exact UTC/network/node/tx-id/settlement transcripts
      mechanically and update operator docs
- [ ] T181-S4-7 Frozen live gate, `just ci`, and accumulated `./gate.sh` green;
      navigator verifies one commit with `Tasks: T181-S4-1,...,T181-S4-7`

## Orchestrator-owned completion

- [ ] T181-O-1 Independently verify each accepted commit against its frozen
      handoff/gate and stamp completed task boxes in metadata-only commits
- [ ] T181-O-2 Verify no transaction-path `cardano-cli` source, CLI option, or
      runtime closure remains and the negative control is genuinely red
- [ ] T181-O-3 Verify the live command, preserved raw evidence, and committed
      transcripts agree on node/network, UTC time, tx ids, and settlement
- [ ] T181-O-4 Push the accepted head, update the draft PR body with executed
      journey steps and #177/#183 boundaries, assign/label/link #181, and wait
      for current-head checks
- [ ] T181-O-5 Append `COMPLETE <PR> ready-for-review`, report exact final
      gates to epic owner, and never self-merge
