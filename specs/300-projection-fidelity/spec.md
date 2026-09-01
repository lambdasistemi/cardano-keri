# #300 — projection-fidelity requirements record

Authority: the four A-019 V1 mandate skeletons at commit
`3653813e1c3f7631c7e8ffb971fd2b194ac1eaf1` under `.milestones/11/mandates/`,
each sha256-pinned in the ticket gate manifest. The captured design record
`docs/design/record-cursor-projection-fidelity.md` is evidence, not authority:
its 4 `[OPEN]` tags stay open and nothing here settles them. Where a mandate
is more specific than issue #300, the mandate binds.

No implementation is authorized by #300. Each section below states one future
implementation slice as an ordered, separately gated OWNER deliverable; the
slices are defined, not built, and no design-note OPEN item is worded as a
ruling.

Artifact ceiling: 180 lines / 12,000 bytes.

## R300-1 — Event-derived MPF key

Authority: `MANDATE-R1-event-derived-key.md`, normative under A-019 §2, under
A-018 FINAL §5. OPEN-free per A-019: any new semantic choice returns to the
project owner before product write.

Requirement: the V1 MPF key becomes exactly the A-019 domain-separated
`blake2b_256(canonical_plutus_data(Constr 0 [B "cardano-keri/event-key/v1", B i, I s, prior-constr, B d]))`
computed over verified `i`, `s`, `p`, and `d`. The redeemer supplies only the sibling proof — no trusted key, location, or ordering. The legacy
`HistoricalProof.key/.location` and `prior_snapshot_digest` shapes carry no
authority.

Future gate must prove: golden vectors for both prior constructors and every
supported CESR code (a new code requires a new accepted vector; unknown or
non-canonical input fails closed); kills for every mutation of `i`, numeric
`s`, present/absent `p` tag, `p`, `d`, the domain string, constructor order,
and a submitter-chosen proof key; and a positive proof that two valid rival SAIDs at one location coexist — the record stays append-only and
multi-branch, so duplicity remains a shape in the data, never a verdict the
chain issues.

Future slice: OWNER, independently gated, after the witness slice is merged.
It bases on that merged main, never on unmerged witness ancestry.
OPEN dependency: the captured record tags the derived-key direction
`[OPEN, and S2 must decide it explicitly.]` and the object's own name as
provisional `[OPEN]`. A-019 §2 now binds the V1 key construction for this
spec; the provisional `record` naming and the exact key-design provenance
beyond the A-019 minimum remain decision debt at the project owner.

## R300-2 — Sufficient event leaf and key-state snapshot

Authority: `MANDATE-R2-event-leaf-snapshot.md`, normative under A-019 §3.
OPEN-free per A-019.

Requirement: the value stored at the R300-1 key becomes the versioned
`EventLeafV1`: event identity (aid/sequence/prior/said), a closed event-type
sum with no catch-all demoting dip/drt events, a `KeyStateSnapshotV1`, an
optional `DelegationAnchorV1`, and settlement_slot stored as evidence. The
snapshot carries, normatively: current keys; explicit next-authority states
(`NonTransferable`/`Abandoned`); the validator-derived effective witness set
(cuts then adds) with `bt` threshold; the exact threshold sum as ordered
weighted clauses of reduced rationals; canonical qualified CESR bytes with
list order preserved; KERI-ordered configuration_traits (EO/DND/RB/NRB
computable); last_establishment inherited across ixn and replaced by
establishment events; delegated events carry the verified anchor including
`seal_index`. Receipts are immutable event-bound attestations, never a
submitter `receipt_count`; grade derives from verified receipt identities
against the snapshot's witness set and threshold. The settlement slot is evidence and never a tie-breaker. Without next-key digests a claimed
successor cannot be checked; without the witness set receipts cannot be
graded — the cursor must become computable from the tree alone.

Future gate must prove: the cursor consumes only authenticated leaves with
event-byte rereads disabled; removal or substitution of every §3 field is
killed; the schema serialization is versioned with golden vectors frozen
before write.

Future slice: OWNER, independently gated, after R300-1 is accepted and merged.
OPEN dependency: the captured record keeps `[OPEN: exact schema.]` for the
snapshot beyond the A-019 §3 minimum that binds here, and keeps the
receipt-grade consumer policy `[OPEN]` — how consumers weigh grade informs
and never gates on-chain.

## R300-3 — Whole-record cursor derivation

Authority: `MANDATE-R3-whole-record-cursor.md`, normative under A-019 §§4+6.
OPEN-free per A-019.

Requirement: the cursor output becomes the two-facts `CursorV1`: a monotone,
permanent `ever_duplicitous` (set on two distinct verified
mutually-inconsistent event versions at one KERI location; never resets; may
coexist with `Resolved(Recovered)`), and a separate `ResolutionV1` —
`Resolved{tip, Clean|Recovered}`, `Abstained(FirstSeenUnavailable, sequence,
canonical-sorted candidate_saids)`, or `NoValidTip{reason}` — plus
evidence_grade, registration_slot, and last_moved_slot. Derivation consumes
the complete authenticated event-and-attestation record — never the latest
leaf, never a submitter-selected branch. Abandonment lives in
`next_authority` and is not overloaded onto duplicity. Settlement slot may be
returned as evidence and the settlement slot cannot change `resolution`.

Future gate must prove the A-019 §6 attack case: an attacker extending one branch beyond a poison/conflict event must not erase the permanent duplicity
fact or the abstention/recovery result; plus arrival-order permutation invariance for every content-derived rule.

Future slice: OWNER, independently gated, after R300-2 is accepted and merged.
OPEN dependency: the captured record keeps consumer acceptance of
ever-duplicitous versus recovered state `[OPEN, but the reframe removes the
false binary.]` — the `accepted_states` consumer policy is decision debt —
and keeps the predecessor-closed succession policy `[OPEN]`. Neither is
settled here.

## R300-4 — Pinned keripy parity and proven abstention

Authority: `MANDATE-R4-keripy-parity-abstention.md`, normative under A-019.

Otherwise-equal means equally admissible AFTER every content-derived rule has run.
The decision procedure is total: invalid evidence is rejected, never abstained;
apply all arrival-order-invariant rules; when the pinned keripy result changes solely under first-seen order permutation, abstain; otherwise match keripy exactly.

The oracle must pin the exact keripy commit and container digest and run both arrival orders and all relevant permutations.
Expected contested outcome: `Abstained(FirstSeenUnavailable, ...)`.
A resolve-by-Cardano-slot mutant MUST make the abstention check RED, and every unsupported or invalid class has a distinct total outcome.

Future slice: OWNER, independently gated, after R300-3 is accepted and merged.
OPEN dependency: none; observation-local first-seen remains deliberately unavailable.
