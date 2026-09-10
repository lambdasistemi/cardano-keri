import Lean
import CardanoKeri.Statements.Credential
import CardanoKeri.Statements.Delegation

-- Specification fixtures only. All transitions and queries run the pinned source.
open Lean CardanoKeri

deriving instance ToJson for History.Verdict
deriving instance ToJson for History.Leaf
deriving instance ToJson for History.Seal
deriving instance ToJson for History.KelEvent
deriving instance ToJson for History.WalkCore
deriving instance ToJson for History.TelKind
deriving instance ToJson for History.TelEvent
deriving instance ToJson for History.Walk
deriving instance ToJson for History.HAction
deriving instance ToJson for Mirror.Action
deriving instance ToJson for Credential.Body
deriving instance ToJson for Credential.Acdc
deriving instance ToJson for Credential.Hop
deriving instance ToJson for Credential.Policy
deriving instance ToJson for Credential.Dep
deriving instance ToJson for Credential.Admission
deriving instance ToJson for Credential.Action
deriving instance ToJson for Delegation.ChildEvent
deriving instance ToJson for Delegation.Cert
deriving instance ToJson for Delegation.Action

namespace StatementVectors

structure Oracle where
  signed : Bool := true
  receipted : Bool := true
  signatureEpoch : Option Nat := none
  deriving ToJson

def Oracle.env (o : Oracle) : Credential.CEnv :=
  { signed := fun ep _ => o.signed && o.signatureEpoch.all (· == ep)
    receipted := fun _ _ => o.receipted
    digest := fun t => t.i + 10000
    saidOf := fun b => b.registry + 1000 }

def Oracle.denv (o : Oracle) : Delegation.DEnv :=
  { toEnv := o.env.toTelEnv.toEnv, eventDigest := fun ev => ev.nonce + 20000 }

def oracle : Oracle := {}
def params : History.Params := ⟨2⟩
def aids := List.range 10
def sequences := List.range 41
def registries := [10, 20, 30]
def saids := [1010, 1020, 1030]
def obj := Json.mkObj

def hjson (c : History.Checkpoint) : Json := obj [
  ("aid", toJson c.aid), ("latest", toJson c.latest), ("cur", toJson c.cur),
  ("parent", toJson c.parent), ("hist", toJson (sequences.filterMap fun sn =>
    (c.hist sn).map fun l => obj [("sn", toJson sn), ("leaf", toJson l)]))]

def ckjson (cs : Nat → Option History.Checkpoint) : Json := toJson (aids.filterMap fun aid =>
  (cs aid).map fun c => obj [("aid", toJson aid), ("checkpoint", hjson c)])

def mfields (s : Mirror.Sys) : List (String × Json) := [
  ("ckpt", ckjson s.ckpt), ("reg", toJson (registries.filterMap fun rid =>
    (s.reg rid).map fun r => obj [("rid", toJson rid), ("registry", obj [
      ("issuer", toJson r.issuer), ("rid", toJson r.rid), ("revoked", toJson (saids.filter r.revoked))])]))]

def mjson (s : Mirror.Sys) : Json := obj (mfields s)
def cjson (s : Credential.Sys) : Json := obj (mfields s.toSys ++ [
  ("cage", toJson (aids.filterMap fun key => (s.cage key).map fun ad =>
    obj [("key", toJson key), ("admission", toJson ad)]))])

def djson (s : Delegation.Sys) : Json := obj [
  ("ckpt", ckjson s.ckpt), ("certs", toJson s.certs),
  ("known", toJson (aids.filterMap fun aid => (s.known aid).map fun par =>
    obj [("aid", toJson aid), ("value", match par with
      | none => obj [("kind", toJson "plain")]
      | some p => obj [("kind", toJson "delegated"), ("parent", toJson p)])]))]

def opt {α} (f : α → Json) : Option α → Json
  | none => Json.null
  | some a => f a

def row (name family : String) (o : Oracle) (state action result : Json)
    (policy : Option Credential.Policy := none) : Json := obj [
  ("name", toJson name), ("family", toJson family), ("oracle", toJson o),
  ("call", obj ([("state", state), ("action", action)] ++
    policy.toList.map fun p => ("policy", toJson p))), ("result", result)]

def hr (name : String) (c : History.Checkpoint) (a : History.HAction) : Json :=
  row name "history" oracle (hjson c) (toJson a) (opt hjson (History.hstep c a))
def mr (name : String) (s : Mirror.Sys) (a : Mirror.Action) (o : Oracle := oracle) : Json :=
  row name "mirror" o (mjson s) (toJson a) (opt mjson (Mirror.stepFn params o.env.toTelEnv s a))
def cr (name : String) (s : Credential.Sys) (p : Credential.Policy) (a : Credential.Action) : Json :=
  row name "credential" oracle (cjson s) (toJson a) (opt cjson (Credential.stepFn params oracle.env p s a)) (some p)
def dr (name : String) (s : Delegation.Sys) (a : Delegation.Action) (o : Oracle := oracle) : Json :=
  row name "delegation" o (djson s) (toJson a) (opt djson (Delegation.stepFn params o.denv s a))
def query (name : String) (state : Json) (op : String) (args : List (String × Json)) (result : Json)
    (o : Oracle := oracle) (pol : Option Credential.Policy := none) : Json :=
  row name "query" o state (obj (("action", toJson op) :: args)) result pol

def walk (t : History.TelEvent) (provisional := false) : History.Walk :=
  { tel := t, core := {
    kel := ⟨if provisional then 25 else 15, false, [⟨99, 0, 0⟩, t.sealOf oracle.env.digest]⟩
    e := if provisional then 20 else 10
    succ := if provisional then none else some 20
    idx := 1 } }

def approval (child : Nat) (ev : Delegation.ChildEvent) : History.WalkCore :=
  { kel := ⟨15, false, [⟨99, 0, 0⟩, Delegation.approvalSeal oracle.denv child ev]⟩
    e := 10, succ := some 20, idx := 1 }

def need {α} (name : String) : Option α → Except String α
  | some x => .ok x
  | none => .error ("fixture setup refused: " ++ name)

def examples : Except String Json := do
  let c10 ← need "history ten" (History.advance (History.inception 1 0 2 none) 10 2)
  let c ← need "history twenty" (History.advance c10 20 2)
  let dc := { c with parent := some 0 }
  let m0 : Mirror.Sys := {
    ckpt := fun a =>
      if a = 1 then some c
      else if a = 2 then some { c with aid := 2 }
      else none
    reg := fun _ => none }
  let vcp := walk ⟨.vcp, 10, 10, 0⟩
  let m1 ← need "open first" (Mirror.stepFn params oracle.env.toTelEnv m0 (Mirror.Action.open 1 vcp))
  let m ← need "open second" (Mirror.stepFn params oracle.env.toTelEnv m1 (Mirror.Action.open 2 (walk ⟨.vcp, 20, 20, 0⟩)))
  let h1 : Credential.Hop := ⟨⟨⟨1, 7, 10, 7, some 1020⟩, 1010⟩, walk ⟨.iss, 1010, 10, 0⟩⟩
  let h2 : Credential.Hop := ⟨⟨⟨2, 8, 20, 1, none⟩, 1020⟩, walk ⟨.iss, 1020, 20, 0⟩⟩
  let hops := [h1, h2]
  let pol : Credential.Policy := ⟨2, [7, 8], 2, 5⟩
  let cs : Credential.Sys := { toSys := m, cage := fun _ => none }
  let ad ← need "final admission" (Credential.stepFn params oracle.env pol cs (.admit 7 hops 100))
  let hp := { h1 with walk := walk h1.walk.tel true }
  let ap ← need "provisional admission" (Credential.stepFn params oracle.env pol cs (.admit 7 [hp, h2] 100))
  let moved ← need "superseding insertion" (Mirror.stepFn params oracle.env.toTelEnv m (.history 1 (.advance 23 2)))
  let am := { ap with toSys := moved }
  let rev := walk ⟨.rev, 1020, 20, 1⟩
  let revoked ← need "revocation" (Mirror.stepFn params oracle.env.toTelEnv m (.push rev))
  let ds : Delegation.Sys := {
    ckpt := fun a => if a = 1 then some c else none
    certs := []
    known := fun a => if a = 1 then some none else none }
  let ev0 : Delegation.ChildEvent := ⟨0, 2, 1⟩
  let ev10 : Delegation.ChildEvent := ⟨10, 2, 2⟩
  let evSame : Delegation.ChildEvent := ⟨10, 2, 3⟩
  let mint0 := Delegation.Action.mint 1 3 ev0 (approval 3 ev0)
  let minted ← need "mint inception approval" (Delegation.stepFn params oracle.denv ds mint0)
  let child ← need "delegated registration" (Delegation.stepFn params oracle.denv minted (.registerDelegated 3 1 ev0))
  let minted10 ← need "mint rotation approval" (Delegation.stepFn params oracle.denv child (.mint 1 3 ev10 (approval 3 ev10)))
  let advanced ← need "delegated advance" (Delegation.stepFn params oracle.denv minted10 (.advanceDelegated 3 ev10))
  let mintedSame ← need "mint same sequence" (Delegation.stepFn params oracle.denv advanced (.mint 1 3 evSame (approval 3 evSame)))
  let parentLeft ← need "parent leaves" (Delegation.stepFn params oracle.denv child (.leave 1))
  let noReceipt : Oracle := { receipted := false }
  let currentOnly : Oracle := { signatureEpoch := some 2 }
  let cases := [
    hr "history-later" c (.advance 30 2), hr "history-not-later" c (.advance 20 2),
    hr "history-delegated-replacement" dc (.supersede 20 3), hr "history-plain-replacement-refused" c (.supersede 20 3),
    mr "mirror-register" m0 (.register 3 0 2 none), mr "mirror-register-existing" m0 (.register 1 0 2 none),
    mr "mirror-history" m (.history 1 (.advance 30 2)), mr "mirror-history-missing" m (.history 9 (.advance 30 2)),
    mr "mirror-open" m0 (Mirror.Action.open 1 vcp), mr "mirror-open-duplicate" m (Mirror.Action.open 1 vcp),
    mr "mirror-open-missing-receipts" m0 (Mirror.Action.open 1 vcp) noReceipt,
    mr "mirror-push" m (.push rev), mr "mirror-push-duplicate" revoked (.push rev),
    mr "mirror-push-iss-refused" m (.push h2.walk),
    cr "credential-mirror" ad pol (.mirror (.push rev)),
    cr "credential-mirror-refused" { ad with toSys := revoked } pol (.mirror (.push rev)),
    cr "credential-admit-final" cs pol (.admit 7 hops 100),
    cr "credential-admit-provisional" cs pol (.admit 7 [hp, h2] 100),
    cr "credential-admit-duplicate" ad pol (.admit 7 hops 100),
    cr "credential-admit-empty" cs pol (.admit 7 [] 100),
    cr "credential-revoked-parent" { cs with toSys := revoked } pol (.admit 7 hops 100),
    cr "credential-wrong-said" cs pol (.admit 7 [{ h1 with acdc := { h1.acdc with said := 1011 } }, h2] 100),
    cr "credential-wrong-edge" cs pol (.admit 7 [{ h1 with acdc := { h1.acdc with body := { h1.acdc.body with edge := none } } }, h2] 100),
    cr "credential-wrong-root" cs { pol with root := 9 } (.admit 7 hops 100),
    cr "credential-depth-refused" cs { pol with maxDepth := 1 } (.admit 7 hops 100),
    cr "credential-schema-count-refused" cs { pol with schemas := [7] } (.admit 7 hops 100),
    cr "credential-evict-moved" am pol (.evict 7), cr "credential-evict-final-refused" ad pol (.evict 7),
    cr "credential-evict-missing" cs pol (.evict 7),
    dr "delegation-mint" ds mint0, dr "delegation-mint-duplicate" minted mint0,
    dr "delegation-mint-wrong-index" ds (.mint 1 3 ev0 { (approval 3 ev0) with idx := 0 }),
    dr "delegation-register-plain" ds (.registerPlain 4 0 2), dr "delegation-register-plain-existing" ds (.registerPlain 1 0 2),
    dr "delegation-register-child" minted (.registerDelegated 3 1 ev0),
    dr "delegation-register-without-certificate" ds (.registerDelegated 3 1 ev0),
    dr "delegation-register-nonzero-sequence" minted (.registerDelegated 3 1 ev10),
    dr "delegation-advance-plain" ds (.advancePlain 1 30 2), dr "delegation-advance-plain-on-child" child (.advancePlain 3 10 2),
    dr "delegation-advance-child" minted10 (.advanceDelegated 3 ev10),
    dr "delegation-advance-without-certificate" child (.advanceDelegated 3 ev10),
    dr "delegation-supersede-child" mintedSame (.supersedeDelegated 3 evSame),
    dr "delegation-supersede-wrong-sequence" minted10 (.supersedeDelegated 3 ev10),
    dr "delegation-leave" child (.leave 1), dr "delegation-leave-missing" child (.leave 9),
    dr "delegation-mint-after-parent-left" parentLeft mint0,
    dr "delegation-remint-consumed-name" child mint0,
    query "cover-final" (hjson c) "history.cover" [("e", toJson (10 : Nat)), ("k", toJson (15 : Nat)), ("succ", toJson (some (20 : Nat)))] (opt toJson (History.cover c 10 15 (some 20))),
    query "cover-provisional" (hjson c) "history.cover" [("e", toJson (20 : Nat)), ("k", toJson (25 : Nat)), ("succ", Json.null)] (opt toJson (History.cover c 20 25 none)),
    query "cover-successor-boundary-refused" (hjson c) "history.cover" [("e", toJson (10 : Nat)), ("k", toJson (20 : Nat)), ("succ", toJson (some (20 : Nat)))] (opt toJson (History.cover c 10 20 (some 20))),
    query "walk-on-final" (hjson c) "history.walkOn" [("seal", toJson (vcp.tel.sealOf oracle.env.digest)), ("w", toJson vcp.core)] (opt toJson (History.walkOn params oracle.env.toTelEnv.toEnv c (vcp.tel.sealOf oracle.env.digest) vcp.core)),
    query "walk-on-current-keys-refused" (hjson c) "history.walkOn" [("seal", toJson (vcp.tel.sealOf oracle.env.digest)), ("w", toJson vcp.core)] (opt toJson (History.walkOn params currentOnly.env.toTelEnv.toEnv c (vcp.tel.sealOf oracle.env.digest) vcp.core)) currentOnly,
    query "seal-walk-final" (hjson c) "history.sealWalk" [("rid", toJson (10 : Nat)), ("w", toJson vcp)] (opt toJson (History.sealWalk params oracle.env.toTelEnv c 10 vcp)),
    query "seal-walk-registry-mismatch" (hjson c) "history.sealWalk" [("rid", toJson (20 : Nat)), ("w", toJson vcp)] (opt toJson (History.sealWalk params oracle.env.toTelEnv c 20 vcp)),
    query "mirror-miss-unopened" (mjson m0) "mirror.miss" [("rid", toJson (10 : Nat)), ("said", toJson (1010 : Nat))] (toJson (Mirror.miss m0 10 1010)),
    query "mirror-miss-present" (mjson m) "mirror.miss" [("rid", toJson (10 : Nat)), ("said", toJson (1010 : Nat))] (toJson (Mirror.miss m 10 1010)),
    query "chain-admission" (mjson m) "credential.admitChain" [("hops", toJson hops)] (opt toJson (Credential.admitChain params oracle.env m pol hops)) oracle (some pol),
    query "chain-admission-refused" (mjson revoked) "credential.admitChain" [("hops", toJson hops)] (opt toJson (Credential.admitChain params oracle.env revoked pol hops)) oracle (some pol),
    query "gate-inclusive-deadline" (cjson ad) "credential.gate" [("key", toJson (7 : Nat)), ("now", toJson (105 : Nat))] (toJson (Credential.gate pol ad 7 105)) oracle (some pol),
    query "gate-after-deadline" (cjson ad) "credential.gate" [("key", toJson (7 : Nat)), ("now", toJson (106 : Nat))] (toJson (Credential.gate pol ad 7 106)) oracle (some pol),
    query "gate-revoked-parent" (cjson { ad with toSys := revoked }) "credential.gate" [("key", toJson (7 : Nat)), ("now", toJson (100 : Nat))] (toJson (Credential.gate pol { ad with toSys := revoked } 7 100)) oracle (some pol),
    query "gate-before-eviction" (cjson am) "credential.gate" [("key", toJson (7 : Nat)), ("now", toJson (100 : Nat))] (toJson (Credential.gate pol am 7 100)) oracle (some pol),
    query "ancestry-direct-parent-absent" (djson parentLeft) "delegation.ancestorWithin" [("depth", toJson (1 : Nat)), ("child", toJson (3 : Nat)), ("root", toJson (1 : Nat))] (toJson (Delegation.ancestorWithin parentLeft 1 3 1)),
    query "ancestry-zero-depth" (djson child) "delegation.ancestorWithin" [("depth", toJson (0 : Nat)), ("child", toJson (3 : Nat)), ("root", toJson (1 : Nat))] (toJson (Delegation.ancestorWithin child 0 3 1)),
    query "issuer-walk" (djson ds) "delegation.issuerWalk" [("aid", toJson (1 : Nat)), ("rid", toJson (10 : Nat)), ("w", toJson vcp)] (opt toJson (Delegation.issuerWalk params oracle.env.toTelEnv ds 1 10 vcp)),
    query "issuer-walk-missing" (djson parentLeft) "delegation.issuerWalk" [("aid", toJson (1 : Nat)), ("rid", toJson (10 : Nat)), ("w", toJson vcp)] (opt toJson (Delegation.issuerWalk params oracle.env.toTelEnv parentLeft 1 10 vcp))]
  pure (obj [("profile", toJson "statements-model-v1"),
    ("source", toJson "4906cfaed34e43405b04d3cc8746bd6388fc8452"),
    ("params", obj [("toadFloor", toJson params.toadFloor)]),
    ("domain", obj [("aids", toJson aids), ("sequences", toJson sequences),
      ("registries", toJson registries), ("saids", toJson saids)]), ("cases", toJson cases)])

#eval match examples with
  | .ok j => IO.println j.compress
  | .error e => throw (IO.userError e)

end StatementVectors
