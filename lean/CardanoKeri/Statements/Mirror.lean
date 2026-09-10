import CardanoKeri.Statements.History

/-!
# The revocation mirror: a per-registry set anyone may fill

STATEMENTS mode — an unproven specification; theorems in
`MirrorGoals.lean`.

Abstract model of the epic ruled on 2026-09-10 in
`docs/design/credential-verification.md` and
[#392](https://github.com/lambdasistemi/cardano-keri/issues/392):

* one UTxO per KERI registry, opened by the seal walk on the registry's
  `vcp` inception against the issuer's checkpoint; the datum holds the
  issuer AID, the registry id, the **anchor of the inception walk** and the
  root over revoked credential SAIDs;
* **issuances are never stored**: whoever presents a credential proves its
  `iss` (the credential module). Only revocations are stored, as a set;
* **push is permissionless**: a `rev` enters the set when its seal walk
  succeeds — the issuer's own cryptography is the permission, no owner
  gate, no current-key check. A duplicate push fails on the insert and is
  harmless; the set converges in any order;
* **the inception must stand for the registry to admit anything.** A
  registry opened from a provisionally sealed `vcp` whose sealing event the
  issuer later supersedes is not on the issuer's accepted branch; the
  credential module refuses every hop against it until the same `vcp` is
  **re-anchored** by a fresh walk (anyone, with the issuer's own seal).
  Revocations pushed meanwhile stay: over-revocation fails closed;
* **the gate** reads one absence per link of a chain; absence in the mirror
  is not absence in the KEL — freshness is push latency, stated and not
  enforced (#398).

The issuer side of the system is the history module's checkpoint, with its
two history steps lifted here so that superseding can be stated against
the mirror. No MPF: the root is the set it commits to and the absence
proof is the lookup. Who pays, min-ADA, the attestation-token layout of
#397 and blinded TEL state are not modelled.
-/

namespace CardanoKeri.Mirror

open CardanoKeri.History

/-- The registry UTxO's datum. -/
structure Registry where
  issuer : AID
  rid : RegistryId
  /-- The anchor of the `vcp` walk that opened (or last re-anchored) it. -/
  inception : Anchor
  /-- The revoked root, as the set it commits to. -/
  revoked : Said → Bool

/-- The system: issuer checkpoints and registries, both by identifier. -/
structure Sys where
  ckpt : AID → Option Checkpoint
  reg : RegistryId → Option Registry

/-- Nothing registered, nothing opened. -/
def Sys.init : Sys := ⟨fun _ => none, fun _ => none⟩

def Sys.setCkpt (s : Sys) (aid : AID) (c : Option Checkpoint) : Sys :=
  { s with ckpt := fun a => if a = aid then c else s.ckpt a }

def Sys.setReg (s : Sys) (rid : RegistryId) (r : Option Registry) : Sys :=
  { s with reg := fun x => if x = rid then r else s.reg x }

/-- Replace one issuer's current key state, leaving its history alone: the
counterfactual the "never mixed" statements quantify over. -/
def Sys.setCur (s : Sys) (aid : AID) (x : Epoch) : Sys :=
  { s with ckpt := fun a => if a = aid then (s.ckpt a).map (fun c => { c with cur := x }) else s.ckpt a }

/-- The actions: the issuer side (a registration and its history steps, as
the checkpoint machine lands them) and the mirror's three redeemers. -/
inductive Action where
  /-- An issuer's checkpoint appears with its inception state. -/
  | register (aid : AID) (epoch : Epoch) (toad : Nat) (parent : Option AID)
  /-- An accepted advance or superseding of an issuer's history. -/
  | history (aid : AID) (a : HAction)
  /-- Open the registry named by a sealed `vcp` of `issuer`. -/
  | open (issuer : AID) (w : Walk)
  /-- Push a sealed `rev` into its registry. -/
  | push (w : Walk)
  /-- Re-anchor an existing registry by a fresh walk of its `vcp`. -/
  | reanchor (w : Walk)
  deriving Repr

/-- Insert into the revoked set. -/
def Registry.insert (r : Registry) (said : Said) : Registry :=
  { r with revoked := fun x => if x = said then true else r.revoked x }

/-- The executable step: the sole transition semantics. -/
def stepFn (p : Params) (env : TelEnv) (s : Sys) : Action → Option Sys
  | .register aid ep t par =>
      match s.ckpt aid with
      | none => some (s.setCkpt aid (some (inception aid ep t par none)))
      | some _ => none
  | .history aid a =>
      match s.ckpt aid with
      | none => none
      | some c => (hstep c a).map fun c' => s.setCkpt aid (some c')
  | .open issuer w =>
      match s.reg w.tel.i, s.ckpt issuer with
      | none, some c =>
          if w.tel.kind = .vcp then
            match sealWalk p env c w.tel.i w with
            | none => none
            | some v =>
              (anchorOf c w.core v).map fun a =>
                s.setReg w.tel.i (some ⟨issuer, w.tel.i, a, fun _ => false⟩)
          else none
      | _, _ => none
  | .push w =>
      match s.reg w.tel.ri with
      | none => none
      | some r =>
        match s.ckpt r.issuer with
        | none => none
        | some c =>
          if w.tel.kind = .rev ∧ r.revoked w.tel.i = false ∧ (sealWalk p env c r.rid w).isSome then
            some (s.setReg r.rid (some (r.insert w.tel.i)))
          else none
  | .reanchor w =>
      match s.reg w.tel.i with
      | none => none
      | some r =>
        match s.ckpt r.issuer with
        | none => none
        | some c =>
          if w.tel.kind = .vcp then
            match sealWalk p env c r.rid w with
            | none => none
            | some v =>
              (anchorOf c w.core v).map fun a => s.setReg r.rid (some { r with inception := a })
          else none

/-- Reachability from one system to another by steps. -/
inductive ReachFrom (p : Params) (env : TelEnv) : Sys → Sys → Prop
  | refl (s : Sys) : ReachFrom p env s s
  | step {s s' s'' : Sys} {a : Action} (hs : stepFn p env s a = some s') (h : ReachFrom p env s' s'') :
      ReachFrom p env s s''

/-- Reachable from the empty system. -/
def Reach (p : Params) (env : TelEnv) (s : Sys) : Prop := ReachFrom p env Sys.init s

/-- The gate's absence check for one link: the registry exists and does not
hold the SAID. No registry, no absence — fail closed. -/
def miss (s : Sys) (rid : RegistryId) (said : Said) : Bool :=
  match s.reg rid with
  | some r => !r.revoked said
  | none => false

end CardanoKeri.Mirror
