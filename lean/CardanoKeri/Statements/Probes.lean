import CardanoKeri.Statements.Credential
import CardanoKeri.Statements.Delegation

/-!
# Executable probes: the invariant review's scenarios, retained

Runtime checks over the production definitions only — no goal file is
imported, no `sorry` is behind any of them. Each `#guard` evaluates a
concrete trace from `Sys.init` through successful steps and asserts the
permitted or refused outcome. They were the counterexamples of the
2026-09-10 invariant review, adapted to the repaired interfaces, with
their controls. The evidence predicates are permissive abstractions for
probing (`signed`/`receipted` keyed by epoch and event); they are never
production authentication.

Naming: `C` credential scenarios, `D` delegation, `O` registry inception.
-/

namespace CardanoKeri.Probes

open CardanoKeri.History

namespace C

open CardanoKeri.Credential

def p : Params := ⟨1⟩
/-- Issuer 20 references the root credential but is not its issuee (30). -/
def unlinkedLeaf : Body := ⟨20, 1, 20, 99, some 2001⟩
/-- Issuer 30 is the root credential's issuee: the vLEI shape. -/
def linkedLeaf : Body := ⟨30, 1, 30, 99, some 2001⟩
def rootBody : Body := ⟨10, 2, 10, 30, none⟩
def hashTel (t : TelEvent) : Nat :=
  (match t.kind with | .vcp => 100000 | .iss => 200000 | .rev => 300000) + t.i * 100 + t.ri * 10 + t.s
def vcp (i : Nat) : TelEvent := ⟨.vcp, i, i, 0⟩
def iss (i said : Nat) : TelEvent := ⟨.iss, said, i, 0⟩
def kel (i said : Nat) : KelEvent := ⟨1, false, [(vcp i).sealOf hashTel, (iss i said).sealOf hashTel]⟩
def env : CEnv :=
  { signed := fun ep ev =>
      (ep == 100 && ev == kel 10 2001) || (ep == 200 && ev == kel 20 1001) || (ep == 300 && ev == kel 30 1002)
    receipted := fun ep ev =>
      (ep == 100 && ev == kel 10 2001) || (ep == 200 && ev == kel 20 1001) || (ep == 300 && ev == kel 30 1002)
    digest := hashTel
    saidOf := fun b =>
      if b = unlinkedLeaf then 1001 else if b = linkedLeaf then 1002 else if b = rootBody then 2001 else 0 }
def walk (i said idx : Nat) (t : TelEvent) (succ : Option Nat := none) : Walk :=
  ⟨t, ⟨kel i said, 0, succ, idx⟩⟩
def unlinkedHop (succ : Option Nat := none) : Hop := ⟨⟨unlinkedLeaf, 1001⟩, walk 20 1001 1 (iss 20 1001) succ, succ⟩
def linkedHop (succ : Option Nat := none) : Hop := ⟨⟨linkedLeaf, 1002⟩, walk 30 1002 1 (iss 30 1002) succ, succ⟩
def rootHop (succ : Option Nat := none) : Hop := ⟨⟨rootBody, 2001⟩, walk 10 2001 1 (iss 10 2001) succ, succ⟩
/-- The vLEI policy: the issuer below is the issuee above. -/
def vlei : Policy := ⟨10, [1, 2], [issuerIsIssuee], 2, 5⟩
/-- A policy with no link: the control that shows the link is what refuses. -/
def lax : Policy := ⟨10, [1, 2], [fun _ _ => true], 2, 5⟩
def onePol : Policy := ⟨10, [2], [], 1, 5⟩
def run (pol : Policy) (as : List Action) : Option Sys :=
  as.foldl (fun so a => so.bind fun s => stepFn p env pol s a) (some Sys.init)
def setup : List Action :=
  [.mirror (.register 10 100 1 none), .mirror (.register 20 200 1 none), .mirror (.register 30 300 1 none),
   .mirror (.open 10 (walk 10 2001 0 (vcp 10))), .mirror (.open 20 (walk 20 1001 0 (vcp 20))),
   .mirror (.open 30 (walk 30 1002 0 (vcp 30)))]
def advanced : List Action := setup ++
  [.mirror (.history 10 (.advance 2 1 none)), .mirror (.history 20 (.advance 2 1 none)),
   .mirror (.history 30 (.advance 2 1 none))]

-- Finding 1: cross-hop issuer authority. The unlinked chain is refused
-- under the vLEI link, admitted under a lax link (control), and the
-- linked chain is admitted under the vLEI link (control).
#guard (run vlei (advanced ++ [.admit 99 [unlinkedHop (some 2), rootHop (some 2)] 10])).isNone
#guard (run lax (advanced ++ [.admit 99 [unlinkedHop (some 2), rootHop (some 2)] 10])).isSome
#guard (run vlei (advanced ++ [.admit 99 [linkedHop (some 2), rootHop (some 2)] 10])).isSome
-- Existing discriminations still bite: missing receipts, wrong actor.
#guard ((run vlei setup).map fun s =>
  (admitChain p {env with receipted := fun _ _ => false} s.toSys vlei [linkedHop, rootHop]).isNone) == some true
#guard ((run vlei setup).map fun s =>
  (stepFn p env vlei s (.admit 98 [linkedHop, rootHop] 10)).isNone) == some true

-- Finding 2: the provisional-gate window, a stated residual. After the
-- issuer supersedes the sealing interaction the walk fails and eviction
-- is enabled on the evidence of the new leaf, but the gate is open until
-- the eviction lands. Eviction without evidence is refused (control).
def provisional := run onePol (setup ++ [.admit 30 [rootHop] 10])
def superseded := provisional.bind fun s => stepFn p env onePol s (.mirror (.history 10 (.advance 1 1 none)))
#guard (superseded.map fun s => (s.ckpt 10).bind fun c => sealWalk p env.toTelEnv c 10 (rootHop.walk)) == some none
#guard (superseded.map fun s => gate onePol s 30 10) == some true
#guard (superseded.map fun s => (stepFn p env onePol s (.evict 30 (some 1))).isSome) == some true
#guard (superseded.map fun s => (stepFn p env onePol s (.evict 30 none)).isSome) == some false
#guard ((superseded.bind fun s => stepFn p env onePol s (.evict 30 (some 1))).map fun s => gate onePol s 30 10) == some false

-- Finding 5: renewal after expiry. A final one-hop admission gates until
-- the bound, then can be renewed or expired by anyone; before the bound
-- neither is possible.
def finalOne := run onePol (setup ++ [.mirror (.history 10 (.advance 2 1 none)), .admit 30 [rootHop (some 2)] 10])
#guard (finalOne.map fun s => (gate onePol s 30 15, gate onePol s 30 16)) == some (true, false)
#guard (finalOne.map fun s => (stepFn p env onePol s (.admit 30 [rootHop (some 2)] 16)).isSome) == some true
#guard (finalOne.map fun s => (stepFn p env onePol s (.admit 30 [rootHop (some 2)] 15)).isSome) == some false
#guard (finalOne.map fun s => (stepFn p env onePol s (.expire 30 16)).isSome) == some true
#guard (finalOne.map fun s => (stepFn p env onePol s (.expire 30 15)).isSome) == some false
#guard (finalOne.map fun s => (stepFn p env onePol s (.evict 30 (some 2))).isSome) == some false
-- A renewed admission gates again.
#guard ((finalOne.bind fun s => stepFn p env onePol s (.admit 30 [rootHop (some 2)] 16)).map fun s =>
  gate onePol s 30 20) == some true

-- Event well-formedness: a `vcp` at TEL sequence 99, or naming another
-- registry, is refused; the well-formed one is accepted (control).
def badSeqVcp : TelEvent := ⟨.vcp, 50, 50, 99⟩
def badRegVcp : TelEvent := ⟨.vcp, 50, 51, 0⟩
def goodVcp : TelEvent := ⟨.vcp, 50, 50, 0⟩
def vcpWalk (t : TelEvent) : Walk := ⟨t, ⟨⟨1, false, [t.sealOf hashTel]⟩, 0, none, 0⟩⟩
def anyEnv : CEnv := { env with signed := fun _ _ => true, receipted := fun _ _ => true }
#guard ((run vlei setup).map fun s => (stepFn p anyEnv vlei s (.mirror (.open 10 (vcpWalk badSeqVcp)))).isSome) == some false
#guard ((run vlei setup).map fun s => (stepFn p anyEnv vlei s (.mirror (.open 10 (vcpWalk badRegVcp)))).isSome) == some false
#guard ((run vlei setup).map fun s => (stepFn p anyEnv vlei s (.mirror (.open 10 (vcpWalk goodVcp)))).isSome) == some true

end C

namespace O

open CardanoKeri.Credential

-- Finding 6: registry inception validity. A registry opened from a `vcp`
-- sealed provisionally at sequence 1 under leaf 0; the issuer then
-- advances to 1, superseding that interaction. An issuance on the new
-- branch under the surviving registry is refused until the same `vcp` is
-- re-anchored on the new branch; then it is admitted.
def p : Params := ⟨1⟩
def body : Body := ⟨10, 2, 50, 30, none⟩
def vcp : TelEvent := ⟨.vcp, 50, 50, 0⟩
def iss : TelEvent := ⟨.iss, 5001, 50, 0⟩
def vcpKel : KelEvent := ⟨1, false, [vcp.sealOf C.hashTel]⟩
def issKel : KelEvent := ⟨2, false, [iss.sealOf C.hashTel]⟩
def vcpKel2 : KelEvent := ⟨3, false, [vcp.sealOf C.hashTel]⟩
def env : CEnv :=
  { digest := C.hashTel
    saidOf := fun b => if b = body then 5001 else 0
    signed := fun ep ev => (ep == 100 && ev == vcpKel) || (ep == 101 && (ev == issKel || ev == vcpKel2))
    receipted := fun ep ev => (ep == 100 && ev == vcpKel) || (ep == 101 && (ev == issKel || ev == vcpKel2)) }
def vcpWalk : Walk := ⟨vcp, ⟨vcpKel, 0, none, 0⟩⟩
def reanchorWalk : Walk := ⟨vcp, ⟨vcpKel2, 1, none, 0⟩⟩
def hop (regProof : Option Nat) : Hop := ⟨⟨body, 5001⟩, ⟨iss, ⟨issKel, 1, none, 0⟩⟩, regProof⟩
def pol : Policy := ⟨10, [2], [], 1, 5⟩
def run (as : List Action) : Option Sys :=
  as.foldl (fun so a => so.bind fun s => stepFn p env pol s a) (some Sys.init)
def invalidated := run [.mirror (.register 10 100 1 none), .mirror (.open 10 vcpWalk),
  .mirror (.history 10 (.advance 1 1 none))]
#guard (invalidated.map fun s => (s.ckpt 10).bind fun c => sealWalk p env.toTelEnv c 50 vcpWalk) == some none
#guard (invalidated.map fun s => (stepFn p env pol s (.admit 30 [hop none] 10)).isSome) == some false
#guard (invalidated.map fun s => (stepFn p env pol s (.admit 30 [hop (some 1)] 10)).isSome) == some false
def reanchored := invalidated.bind fun s => stepFn p env pol s (.mirror (.reanchor reanchorWalk))
#guard reanchored.isSome
#guard (reanchored.map fun s => (stepFn p env pol s (.admit 30 [hop none] 10)).isSome) == some true

end O

namespace D

open CardanoKeri.Delegation

def p : Params := ⟨1⟩
def dip : ChildEvent := ⟨0, 1, 10⟩
def old : ChildEvent := ⟨1, 1, 11⟩
def replacement : ChildEvent := ⟨1, 1, 12⟩
def fresh : ChildEvent := ⟨1, 1, 13⟩
def digest (ev : ChildEvent) : Nat := ev.sn * 10000 + ev.toad * 100 + ev.nonce
def mkSeal (ev : ChildEvent) : Seal := ⟨20, ev.sn, digest ev⟩
def dipKel : KelEvent := ⟨1, false, [mkSeal dip]⟩
def oldKel : KelEvent := ⟨2, false, [mkSeal old]⟩
/-- The parent's rotation at sequence 2, superseding `oldKel` (rule A0),
carrying two seals of the replacement. -/
def rotKel : KelEvent := ⟨2, true, [mkSeal replacement, mkSeal replacement]⟩
/-- A parent interaction at sequence 2 after the rotation is impossible on
the accepted branch; the probe presents one to show A2 refuses it. -/
def ixnKel2 : KelEvent := ⟨2, false, [mkSeal fresh, mkSeal fresh]⟩
def freshKel : KelEvent := ⟨3, false, [mkSeal fresh]⟩
def env : DEnv :=
  { eventDigest := digest
    signed := fun ep ev => (ep == 100 && (ev == dipKel || ev == oldKel)) ||
      (ep == 101 && (ev == rotKel || ev == freshKel || ev == ixnKel2))
    receipted := fun ep ev => (ep == 100 && (ev == dipKel || ev == oldKel)) ||
      (ep == 101 && (ev == rotKel || ev == freshKel || ev == ixnKel2)) }
def run (as : List Action) : Option Sys :=
  as.foldl (fun so a => so.bind fun s => stepFn p env s a) (some Sys.init)
/-- Parent 10; child 20 incepted and rotated to 1 under approvals in the
parent's interactions at 1 and 2; then the parent rotates at 2. -/
def setup : List Action :=
  [.registerPlain 10 100 1,
   .mint 10 20 dip ⟨dipKel, 0, none, 0⟩, .registerDelegated 20 10 dip none,
   .mint 10 20 old ⟨oldKel, 0, none, 0⟩, .advanceDelegated 20 old none,
   .advancePlain 10 2 1]
#guard (run setup).isSome

-- Finding 4: B3. The replacement approved in the parent's rotation at the
-- same sequence and the same seal index supersedes the leaf installed
-- from the interaction; a later index does too; an interaction never
-- supersedes a rotation (A2).
def minted (idx : Nat) := run (setup ++ [.mint 10 20 replacement ⟨rotKel, 2, none, idx⟩])
#guard (minted 0).isSome
#guard ((minted 0).map fun s => (stepFn p env s (.supersedeDelegated 20 replacement none)).isSome) == some true
#guard ((minted 1).map fun s => (stepFn p env s (.supersedeDelegated 20 replacement none)).isSome) == some true
def afterRot := (minted 0).bind fun s => stepFn p env s (.supersedeDelegated 20 replacement none)
#guard (afterRot.bind fun s => stepFn p env s (.mint 10 20 fresh ⟨ixnKel2, 2, none, 1⟩)).isSome
#guard ((afterRot.bind fun s => stepFn p env s (.mint 10 20 fresh ⟨ixnKel2, 2, none, 1⟩)).map fun s =>
  (stepFn p env s (.supersedeDelegated 20 fresh none)).isSome) == some false

-- Finding 3: a stale provisional certificate installs nothing. The
-- certificate for `old` minted from the parent's interaction at 2 is
-- consumed only after the parent superseded that interaction: refused
-- under every proof. A fresh approval on the new branch is accepted.
def stale := run [.registerPlain 10 100 1,
  .mint 10 20 dip ⟨dipKel, 0, none, 0⟩, .registerDelegated 20 10 dip none,
  .mint 10 20 old ⟨oldKel, 0, none, 0⟩, .advancePlain 10 2 1]
#guard (stale.map fun s => (s.ckpt 10).bind fun pc => walkOn p env.toEnv pc (approvalSeal env 20 old) ⟨oldKel, 0, none, 0⟩) == some none
#guard (stale.map fun s => (stepFn p env s (.advanceDelegated 20 old none)).isSome) == some false
#guard (stale.map fun s => (stepFn p env s (.advanceDelegated 20 old (some 2))).isSome) == some false
#guard ((stale.bind fun s => stepFn p env s (.mint 10 20 fresh ⟨freshKel, 2, none, 0⟩)).map fun s =>
  (stepFn p env s (.advanceDelegated 20 fresh none)).isSome) == some true

-- Re-minting: a consumed approval minted again cannot re-install on the
-- live child (D16); after `leave`, the fresh-registration revival consumes
-- a new certificate of the inception — the documented abstraction.
def live := run [.registerPlain 10 100 1,
  .mint 10 20 dip ⟨dipKel, 0, none, 0⟩, .registerDelegated 20 10 dip none,
  .mint 10 20 old ⟨oldKel, 0, none, 0⟩, .advanceDelegated 20 old none,
  .mint 10 20 old ⟨oldKel, 0, none, 0⟩]
#guard live.isSome
#guard (live.map fun s => (stepFn p env s (.advanceDelegated 20 old none)).isSome) == some false
#guard (live.map fun s => (stepFn p env s (.supersedeDelegated 20 old none)).isSome) == some false
def revived := run [.registerPlain 10 100 1,
  .mint 10 20 dip ⟨dipKel, 0, none, 0⟩, .registerDelegated 20 10 dip none,
  .leave 20, .mint 10 20 dip ⟨dipKel, 0, none, 0⟩, .registerDelegated 20 10 dip none]
#guard revived.isSome

end D

end CardanoKeri.Probes
