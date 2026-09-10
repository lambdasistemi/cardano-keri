import CardanoKeri.Statements.Mirror

/-!
# Credential admission: the ACDC chain and the cage

STATEMENTS mode — an unproven specification; theorems in
`CredentialGoals.lean`, all `sorry`.

Abstract model of how a chain of ACDCs is admitted against the checkpoints
and mirrors of its issuers, per `docs/acdc-primer.md`,
`docs/design/credential-verification.md`, `docs/design/defi-gate.md` and
[#31](https://github.com/lambdasistemi/cardano-keri/issues/31) as amended
by #391 and #392. Four checks per hop, from the leaf to a pinned root:

1. **integrity** — the SAID is the digest of the body (the hash-proof
   token recomputes it);
2. **chaining** — the hop's edge names the next hop's SAID, and the last
   hop has no edge and is issued by the pinned root; the schema of each
   hop is pinned by position; depth is bounded by the verifier;
3. **issued then** — the seal walk of the hop's `iss` against the issuer's
   checkpoint history, for the registry the credential names;
4. **unrevoked now** — the SAID is absent from that registry's mirror.

The chain's verdict is final when every hop is final, provisional when any
hop rests on its issuer's latest leaf. The **cage** caches an admission
under the actor's key with the dependencies of every provisional hop, and
anyone may **evict** an admission once a dependency's issuer inserts a
leaf at or below the sealing sequence, or replaces the covering leaf. The
**gate** is a lookup, a freshness bound and one absence per link; the
actor's own threshold is the checkpoint machine's `consumableState` and
is outside this module.

Not modelled: the issuer/issuee relation between hops (schema-specific,
a policy hook); IPEX; the proof builder; attestation-token cuts (#397);
the actor's threshold check.
-/

namespace CardanoKeri.Credential

open CardanoKeri.History
open CardanoKeri.Mirror

/-- Schema SAIDs. -/
abbrev Schema := Nat

/-- What an ACDC's body carries that the verifier reads. -/
structure Body where
  issuer : AID
  schema : Schema
  registry : RegistryId
  issuee : AID
  /-- The edge to the parent credential, by SAID; `none` at the top. -/
  edge : Option Said
  deriving DecidableEq, Repr

/-- An ACDC: its body and its SAID. -/
structure Acdc where
  body : Body
  said : Said
  deriving DecidableEq, Repr

/-- The credential side of the environment: the SAID the hash-proof token
recomputes over the most-compact form. -/
structure CEnv extends TelEnv where
  saidOf : Body → Said

/-- One hop of the redeemer: the credential and the seal walk of its `iss`. -/
structure Hop where
  acdc : Acdc
  walk : Walk
  deriving Repr

/-- The verifier's policy: the pinned root issuer, the schema per hop from
the leaf up, the depth bound, and the freshness bound of an admission. -/
structure Policy where
  root : AID
  schemas : List Schema
  maxDepth : Nat
  notAfter : Nat

/-- The chain verdict is the meet: final only when every hop is final. -/
def _root_.CardanoKeri.History.Verdict.meet : Verdict → Verdict → Verdict
  | .final, .final => .final
  | _, _ => .provisional

/-- The four checks of one hop, given the SAID its edge must name. -/
def hopVerdict (p : Params) (env : CEnv) (s : Mirror.Sys) (parent : Option Said) (h : Hop) : Option Verdict :=
  let a := h.acdc
  if env.saidOf a.body ≠ a.said then none else
  if a.body.edge ≠ parent then none else
  if h.walk.tel.kind ≠ .iss ∨ h.walk.tel.i ≠ a.said then none else
  match s.ckpt a.body.issuer, s.reg a.body.registry with
  | some c, some r =>
      if r.issuer ≠ a.body.issuer then none else
      if r.revoked a.said then none else
      sealWalk p env.toTelEnv c a.body.registry h.walk
  | _, _ => none

/-- The chain, leaf first: each hop's edge names the next hop; the last hop
has no edge and is issued by the root; schemas are pinned by position. -/
def chainFrom (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) :
    List Hop → List Schema → Option Verdict
  | [h], [sc] =>
      if h.acdc.body.schema = sc ∧ h.acdc.body.issuer = pol.root then hopVerdict p env s none h else none
  | h :: h₂ :: hs, sc :: scs =>
      if h.acdc.body.schema = sc then
        (hopVerdict p env s (some h₂.acdc.said) h).bind fun v =>
          (chainFrom p env s pol (h₂ :: hs) scs).map v.meet
      else none
  | _, _ => none

/-- Admission of a chain under a policy: depth-bounded, then the chain. -/
def admitChain (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) (hops : List Hop) : Option Verdict :=
  if hops.length ≤ pol.maxDepth then chainFrom p env s pol hops pol.schemas else none

/-- A dependency of an admission: the issuer, the covering leaf and its key
state, and the sealing sequence, of one hop. -/
structure Dep where
  issuer : AID
  e : Seq
  epoch : Epoch
  k : Seq
  verdict : Verdict
  deriving DecidableEq, Repr

/-- The dependency a hop leaves, read off the issuer's checkpoint. -/
def Hop.dep (s : Mirror.Sys) (h : Hop) : Option Dep :=
  match s.ckpt h.acdc.body.issuer with
  | none => none
  | some c =>
    match c.hist h.walk.core.e, cover c h.walk.core.e h.walk.core.kel.sn h.walk.core.succ with
    | some l, some v => some ⟨h.acdc.body.issuer, h.walk.core.e, l.epoch, h.walk.core.kel.sn, v⟩
    | _, _ => none

/-- What the cage caches: the SAIDs and registries of the chain, the
verdict, the dependencies, and when. -/
structure Admission where
  saids : List Said
  registries : List RegistryId
  verdict : Verdict
  deps : List Dep
  admittedAt : Slot

/-- The credential system: the mirror system plus the cage, keyed by the
actor (the trie key of the defi gate). -/
structure Sys extends Mirror.Sys where
  cage : AID → Option Admission

def Sys.setCage (s : Sys) (key : AID) (ad : Option Admission) : Sys :=
  { s with cage := fun a => if a = key then ad else s.cage a }

/-- Is there a leaf strictly above `lo` and at or below `hi`? -/
def leafBetween (h : History) (lo : Nat) : Nat → Bool
  | 0 => false
  | n + 1 => (decide (lo < n + 1) && (h (n + 1)).isSome) || leafBetween h lo n

/-- A dependency has moved: the issuer replaced the covering leaf's key
state, or inserted a leaf at or below the sealing sequence, after it. Only
a provisional dependency can move (H5). -/
def Dep.moved (s : Mirror.Sys) (d : Dep) : Bool :=
  match s.ckpt d.issuer with
  | none => false
  | some c =>
    (match c.hist d.e with
     | some l => l.epoch != d.epoch
     | none => true) ||
    leafBetween c.hist d.e d.k

inductive Action where
  | mirror (a : Mirror.Action)
  /-- Admit a chain under `key`, now. -/
  | admit (key : AID) (hops : List Hop) (now : Slot)
  /-- Evict `key`'s admission: permissionless, on a moved dependency. -/
  | evict (key : AID)
  deriving Repr

def stepFn (p : Params) (env : CEnv) (pol : Policy) (s : Sys) : Action → Option Sys
  | .mirror a => (Mirror.stepFn p env.toTelEnv s.toSys a).map fun m => { s with toSys := m }
  | .admit key hops now =>
      match s.cage key, admitChain p env s.toSys pol hops, hops.mapM (Hop.dep s.toSys) with
      | none, some v, some deps =>
          some (s.setCage key (some ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩))
      | _, _, _ => none
  | .evict key =>
      match s.cage key with
      | some ad => if ad.deps.any (Dep.moved s.toSys) then some (s.setCage key none) else none
      | none => none

inductive ReachFrom (p : Params) (env : CEnv) (pol : Policy) : Sys → Sys → Prop
  | refl (s : Sys) : ReachFrom p env pol s s
  | step {s s' s'' : Sys} {a : Action} (hs : stepFn p env pol s a = some s') (h : ReachFrom p env pol s' s'') :
      ReachFrom p env pol s s''

def Sys.init : Sys := { toSys := Mirror.Sys.init, cage := fun _ => none }

def Reach (p : Params) (env : CEnv) (pol : Policy) (s : Sys) : Prop := ReachFrom p env pol Sys.init s

/-- The gate: a cached admission, within the freshness bound, and one
absence per link against the mirrors as they are now. The actor's own
threshold is checked by the checkpoint machine, not here. -/
def gate (pol : Policy) (s : Sys) (key : AID) (now : Slot) : Bool :=
  match s.cage key with
  | none => false
  | some ad =>
      decide (now ≤ ad.admittedAt + pol.notAfter) &&
      (ad.saids.zip ad.registries).all fun (said, rid) => miss s.toSys rid said

/-- Decidable mirror of the decidable verdict, for the simulator: is the
key gated in? -/
def Gated (pol : Policy) (s : Sys) (key : AID) (now : Slot) : Prop := gate pol s key now = true

end CardanoKeri.Credential
