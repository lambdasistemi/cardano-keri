# Data model: #300 — projection-fidelity requirements record

Artifact ceiling: 160 lines / 11,000 bytes.

No data type is implemented by #300. Each row states the exact minimum a
future slice must make true and how it is validated, normatively sourced
from its A-019 mandate; nothing here is a schema realization.

DM-300-R1 — EventKeyV1
statement:    the V1 MPF key is exactly the A-019 domain-separated
              `blake2b_256(canonical_plutus_data(Constr 0 [B "cardano-keri/event-key/v1", B i, I s, prior-constr, B d]))`
              over verified `i`, `s`, `p`, and `d`; the redeemer supplies
              only the sibling proof — no trusted key, location, or
              ordering; the legacy `HistoricalProof.key/.location` and
              `prior_snapshot_digest` shapes carry no authority.
validation:   golden vectors for both prior constructors and every supported
              CESR code (a new code requires a new accepted vector; unknown
              or non-canonical fails closed); kills for every named field,
              domain-string, tag/order, and submitter-key mutant; positive
              proof that two valid rival SAIDs at one location coexist.

DM-300-R2 — EventLeafV1 / KeyStateSnapshotV1
statement:    event identity (aid/sequence/prior/said); closed event-type
              sum with no catch-all demoting dip/drt; canonical qualified
              CESR bytes with list order preserved; versioned
              `KeyStateSnapshotV1` carrying current keys, explicit
              next-authority states (`NonTransferable`/`Abandoned`), the
              validator-derived effective witness set (cuts then adds) with
              `bt` threshold, the exact threshold sum as ordered weighted
              clauses of reduced rationals, KERI-ordered
              configuration_traits (EO/DND/RB/NRB computable), and
              last_establishment inherited across ixn and replaced by
              establishment events; optional `DelegationAnchorV1` with the
              verified anchor including `seal_index` on delegated events;
              settlement slot stored as evidence only; grade derived from
              verified receipt identities against the snapshot witness set
              and threshold — never a submitter `receipt_count`.
validation:   cursor-consumes-only-authenticated-leaves proof with
              event-byte rereads disabled; kill removal or substitution of
              every mandate §3 field; versioned schema serialization with
              golden vectors frozen before write.

DM-300-R3 — CursorV1
statement:    two facts — monotone permanent `ever_duplicitous` (set on two
              distinct verified mutually-inconsistent event versions at one
              KERI location; never resets; may coexist with
              `Resolved(Recovered)`) plus separate `ResolutionV1`
              (`Resolved{tip, Clean|Recovered}`,
              `Abstained(FirstSeenUnavailable, sequence, canonical-sorted
              candidate_saids)`, `NoValidTip{reason}`), together with
              evidence grade, registration slot, and last-moved slot.
derivation:   consumes the complete authenticated event-and-attestation
              record — never the latest leaf, never a submitter-selected
              branch; abandonment lives in `next_authority`, not overloaded
              onto duplicity; settlement slot is evidence only.
validation:   the A-019 §6 case where an attacker extending one branch
              beyond a poison/conflict event must not erase the permanent
              duplicity fact or the abstention/recovery result; arrival-order
              permutation invariance for every content-derived rule.

DM-300-R4 — parity/abstention outcome
statement:    otherwise-equal means equally admissible after every
              content-derived KERI verification and
              superseding/reconciliation rule has run. The total four-step
              decision procedure: (1) invalid evidence is rejected, never
              abstained; (2) apply all arrival-order-invariant rules (prior
              chaining, thresholds, content/anchor-derived recovery); (3) if
              the pinned keripy result changes solely under first-seen order
              permutation of the same evidence set, abstain with
              `Abstained(FirstSeenUnavailable, ...)`; (4) otherwise match
              keripy exactly.
oracle:       pin the exact keripy commit and container digest; run both
              arrival orders and all relevant permutations for larger
              minimal sets; an invariant result requires equality; an
              order-dependent result without authenticated first-seen
              evidence requires abstention; every unsupported or invalid
              class — parser rejection, unsupported types, missing
              signatures or anchors, implementation gaps — gets a distinct
              total outcome, with no broad observation-dependent bucket
              hiding any of them. Includes symmetric rival interactions,
              non-superseding rival rotations, and first-seen-dependent
              delegated recovery; excludes content-resolved
              rotation-over-interaction and authenticated delegation
              ordering actually present.
negative_control: a resolve-by-Cardano-slot mutant must make the abstention
              check RED.
