/-!
# The issuer's past: key-state history and the seal walk

STATEMENTS mode — an unproven specification. Every theorem about this model
lives in `HistoryGoals.lean` and ends in `sorry` on purpose; the statements
are the deliverable, the proofs are not. Nothing here is imported by the
compiled sole specification `CardanoKeri.Checkpoint`; it builds as the
separate library `CardanoKeriStatements`.

Abstract model of the two additions ruled on 2026-09-10 in
`docs/design/credential-verification.md` and
[#391](https://github.com/lambdasistemi/cardano-keri/issues/391):

* **The checkpoint remembers its past key states.** One leaf per accepted
  establishment event, keyed by its sequence number, holding the key state
  in force from that event and a back-pointer to the previous establishment
  event. The trie hashes its keys, so it answers exact lookups only; the
  back-pointer turns "the establishment at or below `k`" into two lookups
  and two comparisons. Registration inserts the inception leaf, every
  advance inserts the new leaf; the trie is insert-only, except that a
  delegated identity may have its latest leaf *replaced* by a
  parent-approved rotation at the same sequence number (KERI superseding
  rule B).
* **The seal walk.** Every use of an issuer's log reduces to one check: was
  this TEL event (or this child's event, for delegation) sealed by the
  issuer, under keys the issuer validly held, and seen by the issuer's
  witnesses. Branch binding is the witness receipt quorum at the historical
  `toad`, never a hash chain. An interaction event before a later rotation
  is **final**; one after the latest rotation is **provisional**, because a
  superseding rotation may still shunt it.

No cryptography. A key state is an epoch counter, as in `Checkpoint.lean`;
signatures and receipts are decidable predicates of an `Env`; the digest
the hash-proof token recomputes is a function `digest` of the `Env`, and
collision resistance is a hypothesis (`Function.Injective`) stated on the
theorems that need it rather than a fact of the model.

What this module does **not** model: the checkpoint lifecycle (bonds,
poison, freeze, close, revival — `Checkpoint.lean` owns it; here an
`advance` is what an accepted rotation does to the history, its evidence
having been checked by that machine); the MPF proofs themselves (the root
is the map it commits to and a proof is a lookup); the encoding of the
leaf; the byte offsets the proof builder supplies.
-/

namespace CardanoKeri.History

/-- KERI sequence numbers. -/
abbrev Seq := Nat

/-- Abstract key state of one establishment event: keys, threshold,
witnesses collapsed to a counter, as in the checkpoint machine. -/
abbrev Epoch := Nat

/-- AIDs. -/
abbrev AID := Nat

/-- Chain time. -/
abbrev Slot := Nat

/-- Digests: what the hash-proof token recomputes. -/
abbrev Digest := Nat

/-- SAIDs of credentials and TEL events. -/
abbrev Said := Nat

/-- Registry identifiers (the `ri` of an ACDC, the `i` of a `vcp`). -/
abbrev RegistryId := Nat

/-- Deployment parameters of the verifier family. -/
structure Params where
  /-- The toad floor: an issuer whose witness threshold is below it has no
  branch binding and is refused (the stated residual of #391). -/
  toadFloor : Nat

/-- One leaf of the establishment-history trie: the back-pointer to the
previous establishment event (`none` at inception), the key state in force
from this event, and its witness threshold. -/
structure Leaf where
  prev : Option Seq
  epoch : Epoch
  toad : Nat
  deriving DecidableEq, Repr

/-- The history root as the finite map it commits to. Exact lookups only. -/
abbrev History := Seq → Option Leaf

/-- An approval's position in the parent's log: event sequence, seal index. -/
abbrev Approval := Seq × Nat

/-- Strictly earlier in the parent's log, lexicographically (rule B2). -/
def Approval.before (a b : Approval) : Prop := a.1 < b.1 ∨ (a.1 = b.1 ∧ a.2 < b.2)

instance (a b : Approval) : Decidable (a.before b) := by unfold Approval.before; infer_instance

/-- What a checkpoint reference input yields to a verifier: the AID, the
sequence of the latest accepted establishment event, the current key
state, the history, the parent the identity was delegated by (`none`
for a non-delegated identity; from state, because a delegated rotation
carries no parent field of its own), and the position of the approval
that installed the latest leaf. -/
structure Checkpoint where
  aid : AID
  latest : Seq
  cur : Epoch
  hist : History
  parent : Option AID
  /-- Where in the parent's log the approval that installed the latest leaf
  sits: the parent's event sequence and the seal's position (`none` for a
  non-delegated identity). KERI rule B2 orders competing delegated rotations
  by this position, so superseding compares it. -/
  approval : Option Approval

/-- Well-formedness of a history: what registration and advances produce.
The inception leaf sits at 0 with no back-pointer; every other leaf points
to an existing earlier leaf with nothing in between; every leaf is at or
below `latest`, which exists and holds the current key state. -/
structure WF (c : Checkpoint) : Prop where
  inception : ∃ l, c.hist 0 = some l ∧ l.prev = none
  prev_none_at_zero : ∀ sn l, c.hist sn = some l → l.prev = none → sn = 0
  prev_exists : ∀ sn l e, c.hist sn = some l → l.prev = some e → e < sn ∧ ∃ l', c.hist e = some l'
  contiguous : ∀ sn l e, c.hist sn = some l → l.prev = some e → ∀ m, e < m → m < sn → c.hist m = none
  bounded : ∀ sn l, c.hist sn = some l → sn ≤ c.latest
  latest_current : ∃ l, c.hist c.latest = some l ∧ l.epoch = c.cur
  epoch_monotone : ∀ sn sn' l l', c.hist sn = some l → c.hist sn' = some l' → sn < sn' → l.epoch < l'.epoch

/-- The history a registration creates: the inception leaf alone. -/
def inception (aid : AID) (epoch : Epoch) (toad : Nat) (parent : Option AID) (appr : Option Approval) :
    Checkpoint :=
  { aid := aid, latest := 0, cur := epoch,
    hist := fun sn => if sn = 0 then some ⟨none, epoch, toad⟩ else none,
    parent := parent, approval := appr }

/-- What the history does on an accepted advance to `sn'` (whose evidence
the checkpoint machine has already checked): insert the new leaf pointing
back at the previous latest, and record the approval that installed it
(`none` for a non-delegated identity). Refused unless `sn'` is strictly
later. -/
def advance (c : Checkpoint) (sn' : Seq) (toad' : Nat) (appr : Option Approval) : Option Checkpoint :=
  let epoch' := c.cur + 1
  if c.latest < sn' then
    some { c with latest := sn', cur := epoch', approval := appr,
                  hist := fun sn => if sn = sn' then some ⟨some c.latest, epoch', toad'⟩ else c.hist sn }
  else none

/-- KERI superseding rule B: a delegated identity's latest leaf is replaced
by a parent-approved rotation at the same sequence number whose approval
sits **strictly later** in the parent's log than the one that installed the
leaf (rule B2: the position decides). The back-pointer is kept; the key
state and the recorded approval change. Refused for a non-delegated
identity (rule A1: insert-only), at any other sequence, and for an
approval that is not later. The approval's authenticity is the delegation
module's business. -/
def supersede (c : Checkpoint) (sn' : Seq) (toad' : Nat) (appr : Approval) : Option Checkpoint :=
  let epoch' := c.cur + 1
  match c.parent, c.hist c.latest, c.approval with
  | some _, some l, some a =>
      if sn' = c.latest ∧ a.before appr then
        some { c with cur := epoch', approval := some appr,
                      hist := fun sn => if sn = sn' then some ⟨l.prev, epoch', toad'⟩ else c.hist sn }
      else none
  | _, _, _ => none

/-- The two things that happen to a history after registration. -/
inductive HAction where
  | advance (sn' : Seq) (toad' : Nat) (appr : Option Approval)
  | supersede (sn' : Seq) (toad' : Nat) (appr : Approval)
  deriving Repr

/-- The executable history step. -/
def hstep (c : Checkpoint) : HAction → Option Checkpoint
  | .advance sn' t a => advance c sn' t a
  | .supersede sn' t a => supersede c sn' t a

/-- Histories reachable from a registration by history steps alone. -/
inductive HReach : Checkpoint → Prop
  | init (aid : AID) (epoch : Epoch) (toad : Nat) (parent : Option AID) (appr : Option Approval) :
      HReach (inception aid epoch toad parent appr)
  | step {c c' : Checkpoint} {a : HAction} (h : HReach c) (hs : hstep c a = some c') : HReach c'

/-! ## Coverage: which key state governs the event at `k` -/

/-- A verdict of the walk: final when a later establishment event closes
the range, provisional when the covering leaf is the latest one and a
superseding rotation may still shunt the event. -/
inductive Verdict where
  | final
  | provisional
  deriving DecidableEq, Repr

/-- The range proof the redeemer supplies for "leaf `e` governs sequence
`k`": the successor leaf `e'` whose back-pointer is `e` with `e ≤ k < e'`,
or nothing when `e` is the latest leaf and `e ≤ k`, which is provisional.
The trie cannot answer the range question itself; this is the two-lookup
encoding of #391. -/
def cover (c : Checkpoint) (e k : Seq) (succ : Option Seq) : Option Verdict :=
  match c.hist e with
  | none => none
  | some _ =>
    match succ with
    | some e' =>
      match c.hist e' with
      | some l' => if l'.prev = some e ∧ e ≤ k ∧ k < e' then some .final else none
      | none => none
    | none => if e = c.latest ∧ e ≤ k then some .provisional else none

/-- The property the range proof is meant to establish: `e` is the greatest
establishment sequence at or below `k`. -/
def Governs (c : Checkpoint) (e k : Seq) : Prop :=
  (∃ l, c.hist e = some l) ∧ e ≤ k ∧ ∀ m, e < m → m ≤ k → c.hist m = none

/-! ## The seal walk -/

/-- An event seal as keripy builds it, `SealEvent(i, s, d)`: for a TEL
event, `i` is the TEL identifier, `s` the TEL sequence, `d` the SAID of the
TEL event; for a delegation approval, `i` is the child AID, `s` the child's
sequence and `d` the SAID of the child's event. -/
structure Seal where
  i : Nat
  s : Nat
  d : Digest
  deriving DecidableEq, Repr

/-- The issuer's KEL event that carries the seal, as the verifier sees it:
its sequence, whether it is an establishment event (an establishment-only
registry seals in a `rot`, whose keys are its own leaf) and its seal list,
by position — the position matters (KERI rule B2). The bytes themselves
are what `signed` and `receipted` are evaluated over. -/
structure KelEvent where
  sn : Seq
  establishment : Bool
  seals : List Seal
  deriving DecidableEq, Repr

/-- The evidence the walk verifies, abstracted at the cryptographic
boundary. -/
structure Env where
  /-- `signed ep ev`: the indexed controller signatures over the raw event
  bytes meet the threshold of key state `ep`. -/
  signed : Epoch → KelEvent → Bool
  /-- `receipted ep ev`: `toad` receipts from the witnesses of key state
  `ep` over the same bytes. First-seen witnessing is the branch binding. -/
  receipted : Epoch → KelEvent → Bool

/-- The seal-walk redeemer, minus the sealed thing: the sealing event, the
covering leaf claimed, its range proof, and the seal's position. -/
structure WalkCore where
  kel : KelEvent
  e : Seq
  succ : Option Seq
  idx : Nat
  deriving Repr

/-- The seal walk on a given seal (the design's "shared proof"): the seal
sits at the named position of the sealing event; the claimed leaf exists,
meets the toad floor, and its keys signed and its witnesses receipted the
event; and the leaf governs the event's sequence — as the event itself when
the event is an establishment event, by the range proof otherwise. -/
def walkOn (p : Params) (env : Env) (c : Checkpoint) (sl : Seal) (w : WalkCore) : Option Verdict :=
  if w.kel.seals[w.idx]? ≠ some sl then none else
  match c.hist w.e with
  | none => none
  | some l =>
    if l.toad < p.toadFloor then none else
    if env.signed l.epoch w.kel = false ∨ env.receipted l.epoch w.kel = false then none else
    if w.kel.establishment then
      (if w.e = w.kel.sn then cover c w.e w.kel.sn w.succ else none)
    else cover c w.e w.kel.sn w.succ

/-! ## TEL events and their walk -/

/-- The three TEL events the design consumes. -/
inductive TelKind where
  | vcp
  | iss
  | rev
  deriving DecidableEq, Repr

/-- A TEL event as the verifier slices it: kind, identifier (`i`: the
credential SAID for `iss`/`rev`, the registry id for `vcp`), registry
(`ri`), TEL sequence (`s`: 0 for `vcp` and `iss`, 1 for `rev`). -/
structure TelEvent where
  kind : TelKind
  i : Nat
  ri : RegistryId
  s : Nat
  deriving DecidableEq, Repr

/-- The seal a TEL event must have in the sealing KEL event. -/
def TelEvent.sealOf (digest : TelEvent → Digest) (t : TelEvent) : Seal :=
  ⟨t.i, t.s, digest t⟩

/-- The TEL side of the environment: the SAID the hash-proof token recomputes. -/
structure TelEnv extends Env where
  digest : TelEvent → Digest

/-- A full TEL seal walk: the TEL event and its walk core. -/
structure Walk where
  tel : TelEvent
  core : WalkCore
  deriving Repr

/-- The seal walk of a TEL event against an issuer's checkpoint, for the
registry `rid`: the event names the registry, and its seal walks. -/
def sealWalk (p : Params) (env : TelEnv) (c : Checkpoint) (rid : RegistryId) (w : Walk) : Option Verdict :=
  if w.tel.ri ≠ rid then none else
  walkOn p env.toEnv c (w.tel.sealOf env.digest) w.core

end CardanoKeri.History
