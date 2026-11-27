# MANDATE SKELETON — R3: whole-record cursor derivation (STAGED)

Authority: A-019 sha256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf` §§4+6,
under A-018 FINAL `1c9788a6…` §5. OPEN-free; new semantic choices return
upward before write.

- Predecessor: R2 accepted AND merged; R3 bases on that result.
- Scope: cursor output becomes the two-facts `CursorV1` exactly as A-019 §4 —
  monotone permanent `ever_duplicitous` (set on two distinct verified
  mutually-inconsistent event versions at one KERI location; never resets;
  may coexist with `Resolved(Recovered)`), separate `ResolutionV1`
  (`Resolved{tip…, Clean|Recovered}` | `Abstained{FirstSeenUnavailable,
  sequence, canonical-sorted candidate_saids}` | `NoValidTip{reason}`),
  evidence_grade, registration_slot, last_moved_slot. Derivation is over the
  COMPLETE authenticated event-and-attestation record — never the latest
  leaf, never a submitter-selected branch. Abandonment lives in
  `next_authority`, not overloaded onto duplicity. Settlement slot may be
  returned as evidence and cannot change `resolution`.
- Gate duties: the §6 attack case is mandatory — an attacker extending one
  branch beyond a poison/conflict event must NOT erase the permanent
  duplicity fact or the abstention/recovery result; plus arrival-order
  permutation invariance for content-derived rules.
- Seats/guards: identical to R1 skeleton.
