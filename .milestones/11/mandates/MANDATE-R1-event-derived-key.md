# MANDATE SKELETON — R1: event-derived MPF key (STAGED, NOT DISPATCHED)

Authority: A-019 sha256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf` §2,
under A-018 FINAL `1c9788a6…` §5. OPEN-free per A-019; any new semantic
choice returns to the project owner before product write.

- Predecessor: witness slice MERGED on main (audit-2 PASS + guard-merge of
  PR-302). R1 bases on that merged main; do not start against unmerged
  witness ancestry (A-019 §7).
- Scope: the V1 MPF key becomes exactly A-019 §2's domain-separated
  `blake2b_256(canonical_plutus_data(Constr 0 [B "cardano-keri/event-key/v1",
  B i, I s, prior-constr, B d]))` over verified `i/s/p/d`; redeemer supplies
  ONLY the sibling proof — no trusted key/location/ordering. The old
  `HistoricalProof.key/.location` and `prior_snapshot_digest` shapes carry no
  authority.
- Gate duties (fresh immutable gate, desk-verified before write): golden
  vectors both prior constructors + every supported CESR code (new code ⇒ new
  accepted vector; unknown/non-canonical fails closed); kills for mutations of
  `i`, numeric `s`, present/absent `p` tag, `p`, `d`, domain string,
  constructor order, submitter-chosen proof key; positive proof that two valid
  rival SAIDs at one location coexist.
- Seats: fresh Codex `gpt-5.6-sol` high owner; fresh distinct Opus 5 `[1m]`
  high auditor after park; fresh runtime/worktree/branch/gate; no reuse
  across requirements; grok/AGY/Qwen barred.
- Realization guard: cold-start bar 62.00 GiB one-lane
  (`66,571,993,088 B` via exact `df -B1 --output=avail /nix/store`);
  programme token then host token held through command+hooks; 50.00 GiB stop
  unchanged; realizing-hooks binding; uncertain warmth = cold.
- One slice at a time; R2 bases on R1's accepted/merged result.
