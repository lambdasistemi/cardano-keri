# MANDATE SKELETON — R2: sufficient event leaf + key-state snapshot (STAGED)

Authority: A-019 sha256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf` §3,
under A-018 FINAL `1c9788a6…` §5. OPEN-free; new semantic choices return
upward before write.

- Predecessor: R1 accepted AND merged; R2 bases on that result.
- Scope: the value at the R1 key becomes the versioned `EventLeafV1` exactly
  as A-019 §3 (aid/sequence/prior/said/event_type + `KeyStateSnapshotV1` +
  optional `DelegationAnchorV1` + settlement_slot-as-evidence). Normative
  details bind verbatim: closed event-type sum (no catch-all demoting
  dip/drt); canonical qualified CESR bytes + list order preserved; exact
  threshold sum (ordered weighted clauses of reduced rationals); explicit
  `NonTransferable`/`Abandoned` next-authority; validator-derived effective
  witness set (cuts then adds) with `bt` threshold; KERI-ordered
  configuration_traits (EO/DND/RB/NRB computable); last_establishment
  inherited across ixn, replaced by establishment events; delegated events
  carry the verified anchor incl. `seal_index`; settlement_slot never a
  tie-breaker. Receipts are immutable event-bound attestations — never a
  submitter `receipt_count`; grade derives from VERIFIED receipt identities
  vs the snapshot's witness set/threshold.
- Gate duties: cursor-consumes-only-authenticated-leaves proof with
  event-byte rereads DISABLED; kill removal/substitution of every §3 field;
  schema serialization versioned + golden-vector frozen before write.
- Seats/guards: identical to R1 skeleton (Codex owner, fresh Opus auditor,
  62.00 GiB one-lane cold bar, both tokens, hooks binding, one slice at a
  time).
