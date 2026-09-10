import CardanoKeri.Statements.History

/-!
# Delegation: recursion becomes induction

STATEMENTS mode — an unproven specification; theorems in
`DelegationGoals.lean`.

Abstract model of how Cardano learns that a parent approved a child's key
event, per `docs/design/credential-verification.md` ("Delegation:
recursion becomes induction"),
[#292](https://github.com/lambdasistemi/cardano-keri/issues/292) and the
feasibility report under `specs/134-delegated-aids/` (§4.2, the
superseding rules):

* an approval is a seal in the parent's KEL naming the child, the child's
  sequence number and the SAID of the child's exact event; its **position**
  — the approving event's sequence, whether it is a rotation, and the seal
  index — decides precedence between competing delegated rotations (rules
  B1, B2, B3);
* anyone **mints a certificate** of one approval by the seal walk against
  the parent's checkpoint read as a reference input — the parent is never
  spent, so children never contend on it; the token's name is the exact
  `(parent, child, sn, said)`, the minting policy is the only
  authentication, and the certificate records the approval's position and
  the walk's **anchor** (covering leaf, key state, sealing sequence,
  verdict);
* the child's registration (`dip`) and every delegated rotation (`drt`)
  **consume** the matching certificate. A **provisional** certificate is
  consumed only if its anchor still stands on the parent's checkpoint,
  which the consumer reads as a reference input with a range proof (two
  lookups); a final certificate needs no parent read. A certificate whose
  approving event the parent has since superseded therefore installs
  nothing: it is a dead token;
* a delegated rotation at the latest sequence replaces the latest leaf
  (rule B) only with a strictly later approval; the same position never
  re-installs;
* a consumer asking "descended from the root I trust" walks parent fields
  across checkpoints, one reference input per generation, no signatures;
  the consumer bounds the depth;
* the parent an identity was delegated by is a fact of its inception, so
  it is fixed for ever and never changes on re-registration;
* delegation never touches the TEL: a delegated issuer's seal walks run
  against its own checkpoint (its leaf already embodies the approval).

**Explicit omissions**, stated as witnesses in the goals rather than
guarantees: an approval the parent later overturns leaves an
already-installed child leaf standing (D13); a bonded challenge for that
divergence is a later ruling. Rule C/C1 (precedence decided further up
the delegation chain) is not represented: such a rotation is refused,
fail closed. `leave` merges the parked and convicted states of the
checkpoint machine and permits re-registration; conviction terminality
and revival from the parked key state are that machine's guarantees
(`Checkpoint.T12`, `T8`), not this model's, and are not claimed here.
-/

namespace CardanoKeri.Delegation

open CardanoKeri.History

/-- A delegated establishment event of the child as the certificate policy
sees it: its sequence, its toad, and a nonce standing for everything else
in the bytes (so that two competing events at one sequence differ). Its
SAID is `DEnv.eventDigest`. -/
structure ChildEvent where
  sn : Seq
  toad : Nat
  nonce : Nat
  deriving DecidableEq, Repr

/-- The delegation side of the environment: the child's event SAID, which
the plain advance path never computes and the approval walk must. -/
structure DEnv extends Env where
  eventDigest : ChildEvent → Digest

/-- The seal a parent places to approve a child's event. -/
def approvalSeal (env : DEnv) (child : AID) (ev : ChildEvent) : Seal :=
  ⟨child, ev.sn, env.eventDigest ev⟩

/-- The certificate token: its name is `(parent, child, childSn, childSaid)`;
the rest records where in the parent's log the approval sits and what the
walk depended on. -/
structure Cert where
  parent : AID
  child : AID
  childSn : Seq
  childSaid : Digest
  approval : Approval
  anchor : Anchor
  deriving DecidableEq, Repr

/-- Same token name. -/
def Cert.named (c : Cert) (parent child : AID) (sn : Seq) (said : Digest) : Bool :=
  c.parent == parent && c.child == child && c.childSn == sn && c.childSaid == said

/-- The system: checkpoints, unconsumed certificates, and what is known of
each AID's delegation from its inception (`none`: never registered;
`some none`: non-delegated; `some (some par)`: delegated by `par`). -/
structure Sys where
  ckpt : AID → Option Checkpoint
  certs : List Cert
  known : AID → Option (Option AID)

def Sys.init : Sys := ⟨fun _ => none, [], fun _ => none⟩

def Sys.setCkpt (s : Sys) (aid : AID) (c : Option Checkpoint) : Sys :=
  { s with ckpt := fun a => if a = aid then c else s.ckpt a }

def Sys.setKnown (s : Sys) (aid : AID) (k : Option AID) : Sys :=
  { s with known := fun a => if a = aid then some k else s.known a }

/-- Consume the certificate of that name, if present. -/
def Sys.takeCert (s : Sys) (parent child : AID) (sn : Seq) (said : Digest) : Option (Cert × Sys) :=
  match s.certs.find? (fun c => c.named parent child sn said) with
  | none => none
  | some c => some (c, { s with certs := s.certs.eraseP (fun c => c.named parent child sn said) })

/-- A certificate may be consumed: a final one always; a provisional one
only while its anchor stands on the parent's checkpoint, shown by the
consumer's range proof. -/
def Sys.certStands (s : Sys) (cert : Cert) (proof : Option Seq) : Bool :=
  match cert.anchor.verdict with
  | .final => true
  | .provisional =>
    match s.ckpt cert.parent with
    | none => false
    | some pc => cert.anchor.stands pc proof

inductive Action where
  /-- Mint the certificate of the parent's approval of `ev`, by the seal
  walk `w` on the parent's checkpoint. -/
  | mint (parent child : AID) (ev : ChildEvent) (w : WalkCore)
  /-- A non-delegated registration. -/
  | registerPlain (aid : AID) (epoch : Epoch) (toad : Nat)
  /-- A delegated registration: the `dip` at sequence 0, consuming its
  certificate; `proof` shows a provisional certificate still stands. -/
  | registerDelegated (child parent : AID) (ev : ChildEvent) (proof : Option Seq)
  /-- A non-delegated advance, as the checkpoint machine lands it. -/
  | advancePlain (aid : AID) (sn' : Seq) (toad' : Nat)
  /-- A delegated rotation to a later sequence, consuming its certificate. -/
  | advanceDelegated (child : AID) (ev : ChildEvent) (proof : Option Seq)
  /-- A delegated rotation at the latest sequence (rule B), consuming its certificate. -/
  | supersedeDelegated (child : AID) (ev : ChildEvent) (proof : Option Seq)
  /-- The checkpoint leaves the chain: parked or convicted; no reference input. -/
  | leave (aid : AID)
  deriving Repr

def stepFn (p : Params) (env : DEnv) (s : Sys) : Action → Option Sys
  | .mint parent child ev w =>
      match s.ckpt parent with
      | none => none
      | some pc =>
        match walkOn p env.toEnv pc (approvalSeal env child ev) w with
        | none => none
        | some v =>
          if s.certs.any (fun c => c.named parent child ev.sn (env.eventDigest ev)) then none else
          (anchorOf pc w v).map fun a =>
            { s with certs := ⟨parent, child, ev.sn, env.eventDigest ev,
                                ⟨w.kel.sn, w.kel.establishment, w.idx⟩, a⟩ :: s.certs }
  | .registerPlain aid ep t =>
      match s.ckpt aid, s.known aid with
      | none, none => some ((s.setCkpt aid (some (inception aid ep t none none))).setKnown aid none)
      | none, some none => some (s.setCkpt aid (some (inception aid ep t none none)))
      | _, _ => none
  | .registerDelegated child parent ev proof =>
      match s.ckpt child with
      | some _ => none
      | none =>
        if ev.sn ≠ 0 then none else
        if s.known child ≠ none ∧ s.known child ≠ some (some parent) then none else
        match s.takeCert parent child 0 (env.eventDigest ev) with
        | none => none
        | some (cert, s') =>
            if s.certStands cert proof = false then none else
            some ((s'.setCkpt child (some (inception child 0 ev.toad (some parent) (some cert.approval)))).setKnown
              child (some parent))
  | .advancePlain aid sn' t =>
      match s.ckpt aid with
      | none => none
      | some c =>
        if c.parent ≠ none then none else
        (advance c sn' t none).map fun c' => s.setCkpt aid (some c')
  | .advanceDelegated child ev proof =>
      match s.ckpt child with
      | none => none
      | some c =>
        match c.parent with
        | none => none
        | some par =>
          match s.takeCert par child ev.sn (env.eventDigest ev) with
          | none => none
          | some (cert, s') =>
            if s.certStands cert proof = false then none else
            (advance c ev.sn ev.toad (some cert.approval)).map fun c' => s'.setCkpt child (some c')
  | .supersedeDelegated child ev proof =>
      match s.ckpt child with
      | none => none
      | some c =>
        match c.parent with
        | none => none
        | some par =>
          match s.takeCert par child ev.sn (env.eventDigest ev) with
          | none => none
          | some (cert, s') =>
            if s.certStands cert proof = false then none else
            (supersede c ev.sn ev.toad cert.approval).map fun c' => s'.setCkpt child (some c')
  | .leave aid =>
      match s.ckpt aid with
      | none => none
      | some _ => some (s.setCkpt aid none)

inductive ReachFrom (p : Params) (env : DEnv) : Sys → Sys → Prop
  | refl (s : Sys) : ReachFrom p env s s
  | step {s s' s'' : Sys} {a : Action} (hs : stepFn p env s a = some s') (h : ReachFrom p env s' s'') :
      ReachFrom p env s s''

def Reach (p : Params) (env : DEnv) (s : Sys) : Prop := ReachFrom p env Sys.init s

/-- The consumer's ancestry walk: parent fields across present checkpoints,
at most `n` generations, no signatures. Stops at an absent checkpoint. -/
def ancestorWithin (s : Sys) : Nat → AID → AID → Bool
  | 0, _, _ => false
  | n + 1, a, r =>
    match s.ckpt a with
    | none => false
    | some c =>
      match c.parent with
      | none => false
      | some par => par == r || ancestorWithin s n par r

/-- Descended from `r`, at some depth. -/
def Descends (s : Sys) (a r : AID) : Prop := ∃ n, ancestorWithin s n a r = true

/-- The parent fields alone: what the ancestry walk reads. -/
def Sys.parents (s : Sys) : AID → Option (Option AID) := fun a => (s.ckpt a).map (·.parent)

/-- A delegated issuer's TEL seal walk, at the system level: against its own
checkpoint and nothing else. -/
def issuerWalk (p : Params) (env : TelEnv) (s : Sys) (aid : AID) (rid : RegistryId) (w : Walk) : Option Verdict :=
  (s.ckpt aid).bind fun c => sealWalk p env c rid w

end CardanoKeri.Delegation
