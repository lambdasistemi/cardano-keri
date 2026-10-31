# Resume — M1.2 milestone owner

**Current as of 2026-08-28T12:15Z.** Supersedes the 2026-08-24 handover entirely.
Read `ledger.md` (snapshot) before anything else; `ledger-history-to-2026-08-27.md`
is archaeology, consult it only for a cited ruling.

## Identity

- Desk: session `keri-m12`, window `m12-desk`, runtime `/tmp/keri/m12/`.
- Launch: `claude --dangerously-skip-permissions --model 'claude-opus-5[1m]'`
- Load chain: `orchestrator-contract` → `milestone-orchestrator` → `worker-protocol`.
- Parent: the operator directly in this lane. The project-owner seat exists in
  `0-projects` but is under the omnia pausa; escalations went to the operator.
- Home repo `/code/cardano-keri`; worktree `/code/cardano-keri-300-projection-fidelity`;
  ledger branch `milestones`, depth 1, fresh root per write.

## Your exact next action

**RELEASED** for this session by `RELEASE-2026-08-28T1104Z-keri-m12.md`. The pause
stays in force for reactivegas, treasury-ms1, 0-projects and session 0.

1. **Rule on DESIGN NOTE 002.** It arrived 2026-08-28 at `/code/enforcementeconomics.md`,
   is preserved here as `design/DESIGN-NOTE-002-enforcement-economics.md`
   (sha256 `d52923f6ab3f343c7413c12768dd127d60fa2dc1bfe5d2357fc4a36c793d676a`), and is
   addressed to this seat to **accept, amend or discard**. It does not contradict #300's
   accepted requirements — desk-verified section by section — it extends them. Landing it
   in the repository needs an issue, which `RELEASE-015` holds.
2. **F-2 is the finding to act on first.** #271's commit-reveal entitlement is absent from
   the `m12` escrow and from DN-001 §8's S2 scope list. A closed exposure has silently
   reopened. It is registered; it needs an owner.
3. Put the **PR #306 merge decision** to the operator with the burn-down argument attached.
4. Do **not** re-arm the stale PROOF-COMPLETE polling terminal (process group 4027515 was
   SIGTERMed 2026-08-27). Named in the release order.
5. The 4 `[OPEN]` items in DN-001 stay open. Still an operator question, restated 2026-08-28.

## Standing rulings you inherit

- **A-001 (this desk, 2026-08-27):** the design record's authoritative path is
  `docs/design/record-cursor-projection-fidelity.md`. The ticket text was corrected; the
  file does not move. `DESIGN-NOTE-` was never a repository convention.
- **Merge, closing #300, amending `0cfc9c28…`, `main` contact, and the R1 lane remain
  withheld.** A release scoped to one act does not widen to the next.
- **Never abbreviate a hash a child may need to reproduce.** Inherited, and re-earned:
  this desk queried gist revisions with 8-character SHAs, got HTTP 422, and its pipeline
  read the error as a zero count — it nearly reported the opposite of the truth.
- **Do not send Escape after Enter into a codex pane.** It CANCELS submission. Two notes
  sat unsent while one was reported delivered. Send text, press Enter, verify `Working`.
- **Verify a render, never assume it.** The state publisher's own check returned RED on a
  fetch failure; the page was verified by hand instead.

## The trap this desk walked into and disarmed

The ledger sweep force-pushes a fresh root commit. #300's accepted spec cited the
mandates by branch commit `3653813e1c3f7631c7e8ffb971fd2b194ac1eaf1`, and the four
content hashes were in no committed file — so **the desk's own routine housekeeping would
have orphaned the authority chain of an audited deliverable** referenced by an open PR.
Fixed 2026-08-28 by tagging the commit BEFORE sweeping:
`refs/tags/ms11/mandates/a-019` (tag object `a21c9338528444d7831d55d5043360c3979a6b3a`).
**Any future sweep must check that a cited commit is tagged before it pushes.**

## Live seats

- **%103** — this desk.
- **%104** — ticket owner #300, Codex `gpt-5.6-sol` high, worktree
  `/code/cardano-keri-300-projection-fidelity`, branch
  `docs/300-projection-fidelity-requirements`, runtime `/tmp/keri/m12/t300/`.
  `COMPLETE` and `PARKED`; its work is accepted and pushed. **Your only immediate child.**
- **%105** — commit owner (Pi/GLM), released by its ticket owner, idle. **Not yours.**

## External input in flight

An external reviewer's design feedback arrived 2026-08-27 via the operator. It asks for
first-seen and liveness that mirror KERI, and doubts the pen construction on a
theft-or-interop dilemma. The desk's reading: the pen is the answer to the first half,
and the dilemma lands on a limit the pen's own text concedes. DN-002 §6 now answers the
same question in the opposite direction without citing the pen. **Registered as
`enforced: NONE`; it is a product ruling, not this desk's.**
