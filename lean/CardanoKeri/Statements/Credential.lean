import CardanoKeri.Statements.Mirror

/-!
# Credential admission: the ACDC chain and the cage

STATEMENTS mode — an unproven specification; theorems in
`CredentialGoals.lean`.

Abstract model of how a chain of ACDCs is admitted against the checkpoints
and mirrors of its issuers, per `docs/acdc-primer.md`,
`docs/design/credential-verification.md`, `docs/design/defi-gate.md` and
[#31](https://github.com/lambdasistemi/cardano-keri/issues/31) as amended
by #391 and #392. Per hop, from the leaf to a pinned root:

1. **integrity** — the SAID is the digest of the body (the hash-proof
   token recomputes it);
2. **chaining** — the hop's edge names the next hop's SAID, and the policy's
   **link** for that edge holds between the two bodies (for vLEI: the
   issuer of a credential is the issuee of the credential above it); the
   last hop has no edge and is issued by the pinned root; the schema of
   each hop is pinned by position; depth is bounded by the verifier;
3. **issued then** — the seal walk of the hop's `iss` against the issuer's
   checkpoint history, for the registry the credential names;
4. **unrevoked now** — the SAID is absent from that registry's mirror, and
   the registry's inception anchor still stands on the issuer's history
   (a presenter supplies the range proof; two lookups).

The chain's verdict is final when every hop is final, provisional when any
hop rests on its issuer's latest leaf. The **cage** caches an admission
under the actor's key — the leaf credential's issuee — with the anchor of
every hop, and anyone may **evict** an admission by presenting evidence
that a provisional anchor moved: the issuer replaced the covering leaf or
inserted a leaf at or below the sealing sequence. An admission **expires**
after the policy's freshness bound; an expired admission may be removed by
anyone and is the only kind a fresh admission may replace. The **gate** is
a lookup, the freshness bound and one absence per link; the actor's own
threshold is the checkpoint machine's `consumableState` and is outside this
module.

**Stated residual (open decision).** Between an issuer's superseding
rotation and the permissionless eviction, a *provisional* admission still
gates. The design authority (`credential-verification.md`: "the cage …
evicts a provisional admission") specifies cache-then-evict, so the gate
reads no checkpoint (C12) and the interval is bounded only by the
freshness bound and by whoever evicts. Closing the interval at the use
boundary would mean the gate reads the issuer checkpoint of every
provisional dependency as a reference input and runs `Anchor.stands`; that
is a design decision, recorded as open, not taken here (C20 is the
witness).

Not modelled: IPEX; the proof builder; attestation-token cuts (#397); the
actor's threshold check.
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

/-- One hop of the redeemer: the credential, the seal walk of its `iss`, and
the range proof that the registry's inception anchor still stands. -/
structure Hop where
  acdc : Acdc
  walk : Walk
  regProof : Option Seq
  deriving Repr

/-- The relationship a policy demands between a credential and the one its
edge names: `link child parent`. -/
abbrev Link := Body → Body → Bool

/-- The vLEI rule: a credential's issuer is the issuee of the credential
above it (a QVI credential accredits the QVI that issues below it). -/
def issuerIsIssuee : Link := fun child parent => child.issuer == parent.issuee

/-- The verifier's policy: the pinned root issuer, the schema per hop from
the leaf up, the link per edge, the depth bound, and the freshness bound of
an admission. -/
structure Policy where
  root : AID
  schemas : List Schema
  links : List Link
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
      if r.inception.stands c h.regProof = false then none else
      sealWalk p env.toTelEnv c a.body.registry h.walk
  | _, _ => none

/-- The chain, leaf first: each hop's edge names the next hop and the
policy's link for that edge holds; the last hop has no edge and is issued
by the root; schemas are pinned by position. -/
def chainFrom (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) :
    List Hop → List Schema → List Link → Option Verdict
  | [h], [sc], [] =>
      if h.acdc.body.schema = sc ∧ h.acdc.body.issuer = pol.root then hopVerdict p env s none h else none
  | h :: h₂ :: hs, sc :: scs, lk :: lks =>
      if h.acdc.body.schema = sc ∧ lk h.acdc.body h₂.acdc.body = true then
        (hopVerdict p env s (some h₂.acdc.said) h).bind fun v =>
          (chainFrom p env s pol (h₂ :: hs) scs lks).map v.meet
      else none
  | _, _, _ => none

/-- Admission of a chain under a policy: depth-bounded, then the chain. -/
def admitChain (p : Params) (env : CEnv) (s : Mirror.Sys) (pol : Policy) (hops : List Hop) : Option Verdict :=
  if hops.length ≤ pol.maxDepth then chainFrom p env s pol hops pol.schemas pol.links else none

/-- A dependency of an admission: the issuer and the anchor of one hop. -/
structure Dep where
  issuer : AID
  anchor : Anchor
  deriving DecidableEq, Repr

/-- The dependency a hop leaves, read off the issuer's checkpoint. -/
def Hop.dep (s : Mirror.Sys) (h : Hop) : Option Dep :=
  match s.ckpt h.acdc.body.issuer with
  | none => none
  | some c =>
    match cover c h.walk.core.e h.walk.core.kel.sn h.walk.core.succ with
    | none => none
    | some v => (anchorOf c h.walk.core v).map fun a => ⟨h.acdc.body.issuer, a⟩

/-- What the cage caches: the SAIDs and registries of the chain, the
verdict, the dependencies, and when. -/
structure Admission where
  saids : List Said
  registries : List RegistryId
  verdict : Verdict
  deps : List Dep
  admittedAt : Slot

/-- Past the freshness bound. -/
def Admission.expired (pol : Policy) (ad : Admission) (now : Slot) : Bool :=
  decide (ad.admittedAt + pol.notAfter < now)

/-- The credential system: the mirror system plus the cage, keyed by the
actor (the trie key of the defi gate). -/
structure Sys extends Mirror.Sys where
  cage : AID → Option Admission

def Sys.setCage (s : Sys) (key : AID) (ad : Option Admission) : Sys :=
  { s with cage := fun a => if a = key then ad else s.cage a }

/-- A dependency has moved, by the evidence `m` (H12: moved evidence
refutes every proof of standing). -/
def Dep.moved (s : Mirror.Sys) (d : Dep) (m : Option Seq) : Bool :=
  match s.ckpt d.issuer with
  | none => false
  | some c => d.anchor.moved c m

inductive Action where
  | mirror (a : Mirror.Action)
  /-- Admit a chain under `key`, now: the key is free or holds an expired admission. -/
  | admit (key : AID) (hops : List Hop) (now : Slot)
  /-- Evict `key`'s admission: permissionless, on evidence `m` that a dependency moved. -/
  | evict (key : AID) (m : Option Seq)
  /-- Remove `key`'s expired admission: permissionless. -/
  | expire (key : AID) (now : Slot)
  deriving Repr

def stepFn (p : Params) (env : CEnv) (pol : Policy) (s : Sys) : Action → Option Sys
  | .mirror a => (Mirror.stepFn p env.toTelEnv s.toSys a).map fun m => { s with toSys := m }
  | .admit key hops now =>
      -- The actor is bound to the credential: the leaf credential's issuee is
      -- the key the admission is cached under. The actor's own signatures
      -- (the checkpoint machine's threshold) cannot establish this.
      if hops.head?.map (·.acdc.body.issuee) ≠ some key then none else
      -- A live admission is never replaced; an expired one may be.
      if (s.cage key).any (fun ad => !ad.expired pol now) then none else
      match admitChain p env s.toSys pol hops, hops.mapM (Hop.dep s.toSys) with
      | some v, some deps =>
          some (s.setCage key (some ⟨hops.map (·.acdc.said), hops.map (·.acdc.body.registry), v, deps, now⟩))
      | _, _ => none
  | .evict key m =>
      match s.cage key with
      | some ad => if ad.deps.any (fun d => d.moved s.toSys m) then some (s.setCage key none) else none
      | none => none
  | .expire key now =>
      match s.cage key with
      | some ad => if ad.expired pol now then some (s.setCage key none) else none
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
