# S0-RELAND TICKET BRIEF — commissioned, NOT PLACED (host HOLD) — r2 per CORRECTION-050

Authority: A-027 sha256
`093add18d5464d23a191552005125dfde6406f6ce8aaa055c912db5c07adb3dd`
(verify, read in full). Small standalone lane; first link of the
watcher-first chain.

- Seat at placement: fresh Opus 5 `[1m]` high ticket owner, window
  `cardano-keri-ms11-tS0-reland`, runtime `/tmp/ms-keri-11/s0-reland`.
  The ticket owner is a PURE ORCHESTRATOR: it authors briefs, gates, and
  verifications only — it never authors, stages, or commits repository
  changes, regardless of size.
- Objective: reland accepted S0 head
  `137edef07917d493914e73e69b72839b2c833b50` onto read-back main
  (re-read at branch time) as ONE small change with EXACT content/tree
  equivalence evidence (per-path blob identity vs the accepted head; any
  divergence stops and hands up). NO witness-mode content. S0 design is
  not reopened.
- Topology (mandatory, no alternative): fresh Codex `gpt-5.6-sol` high
  commit owner performs every repository write (the ticket owner builds
  that pane, NOTE-040 routing, START barrier); after the owner parks, a
  distinct fresh Opus 5 `[1m]` high auditor (scope proportionate to the
  reland); merge only on audit PASS + green CI + guard read-back.
- Gate (ticket-owner-authored, frozen, desk-verified BEFORE any product
  write): six A-026 controls where their artifact exists — receipt
  prints+verifies candidate head/tree (CI-S2W-C); dirty-tree/index
  refusal before any proof leg (CI-S2W-D); equivalence-evidence kill
  (a doctored blob hash must fail right-cause); free prefix AFTER the
  commit exists + any realizing leg on the same clean SHA/tree, both
  receipts.
- Realization law: classify every command by its actual realization
  boundary; cold/uncertain legs wait on the machine's fresh release
  (HOST-BUILD-HOLD; exact bar 66,571,993,088 B; acquire-time predicates;
  per-leg fail-before-command inside the wrapper path; bytes journaled
  at acquire AND release).
- Law: worker-protocol journaling via status-event; OPUS-CAPACITY per
  the A-014 precedent; grok/AGY/Qwen no seats; no AI attribution; hash
  every durable artifact; /tmp ages.
