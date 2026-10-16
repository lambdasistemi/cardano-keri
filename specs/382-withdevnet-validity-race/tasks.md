# Issue 382 tasks

Artifact ceiling: 2,000 bytes / 60 lines.

## S382-P1 — contract and gate

- [x] **T382-01** Freeze the compact requirements, invariant, module, data,
  function, scope, and numerical timing policy on the baselined lane base.
- [x] **T382-02** Freeze and falsify the ignored runtime gate with a real
  `OutsideValidityIntervalUTxO` control. (`S382-P2-v1` `805b1eed…`;
  one-slot control `2ed13baf…`; 6 examples / 2 intended expiry failures in
  `gate-red-live.log` `7234623c…`.)

## S382-P2 — harness repair

- [ ] **T382-03** Commit a deterministic live RED proof that delays one
  submission by 25 slots and observes actual validity expiry.
- [ ] **T382-04** Implement exact expiry classification, one fresh rebuild,
  and timing-specific diagnostics.
- [ ] **T382-05** Prove non-expiry/domain rejection is terminal with no retry,
  and preserve every pre-existing live smoke example.

## S382-P3 — independent acceptance

- [ ] **T382-06** Obtain fresh alternate-family provenance, semantic/failure-
  mode, and mutation/control inspection of the exact candidate.

## S382-P4 — delivery

- [ ] **T382-07** Accept the audited tree, create the final commit, run local
  gates, push the exact SHA, wait for green remote CI, pass finalization audit,
  and mark the draft PR ready without merging.
