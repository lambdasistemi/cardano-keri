import CardanoKeri.CheckpointCommitmentGoals
import CardanoKeri.CheckpointSystemFixtures
import CardanoKeri.CheckpointDatumVectors

/-! Vectors of the commitment a conviction reveals (#534).

Conviction rows run the local conviction step on one live output with a
commitment and a payee at a slot: accepted only when the commitment names this
output's key state, the evidence shown there and this payee, and the slot lies in
its window. The output's other facts (its marks, pool, birth slot and refund
address) do not enter: a top-up, a freeze or a poison after the opening keeps the
commitment, and a rotation voids it. Controls change one fact of the accepted row
at a time. System rows run the certificate interpreter over a registered and twice
rotated checkpoint: a conviction needs an open commitment naming its AID and its
deployment, burns it, and a commitment is revealed inside its window or swept
after it; the same journey in another deployment refuses the first deployment's
commitment. Checks run the actual Lean functions; they are evidence over the
listed inputs, not a proof over all inputs. -/
namespace CardanoKeri.Checkpoint.CommitmentVectors
open Lean (Json toJson)
open CardanoKeri.CheckpointDatum.Vectors (natJson rows leaves mutateAt)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (field str)

def params : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }

/-- The two fixture selectors encode a rival whose forward fields conflict
with the spent tip, or one whose forward fields agree with it. The JSON
selector names are retained for existing vector readers. -/
inductive Shown where
  | duplicity (epoch sn : Nat)
  | sameEvent (epoch sn : Nat)
  deriving DecidableEq, Repr

def Shown.evidence : Shown → Evidence
  | .duplicity e sn => (CardanoKeri.CheckpointConviction.Fixtures.comparison 11 e sn).rival
  | .sameEvent e sn => (CardanoKeri.CheckpointConviction.Fixtures.comparison 11 e sn true).rival

def Shown.json : Shown → Json
  | .duplicity e sn => Json.mkObj [("duplicity", toJson [e, sn])]
  | .sameEvent e sn => Json.mkObj [("sameEvent", toJson [e, sn])]

/-- The spend reads the selected tip and rival. The separate predecessor and
event lookups serve the KERI reader. -/
def envFor (rivalIsAccepted : Bool) : Env := {
  rotationTo := fun _ _ _ => false, depositAuthorized := fun _ => false, quorum := fun _ => false,
  attestationMinted := fun _ => true,
  presentedSpend := fun e sn => some ⟨⟨105, 0⟩, CardanoKeri.CheckpointConviction.Fixtures.comparison 11 e sn rivalIsAccepted⟩,
  convictionContext := fun e sn => some (CardanoKeri.Duplicity.fixture e sn).1,
  convictionRival := fun e sn => some (if rivalIsAccepted then (CardanoKeri.Duplicity.fixture e sn).1.accepted
    else (CardanoKeri.Duplicity.fixture e sn).2) }

/-- The output as it stood when the commitment was opened: sequence 1, epoch 1,
refund address 42, pool 4. -/
def output : Live := ⟨1, 1, false, false, 3, 42, 4, false⟩

structure Case where
  id : String
  note : String
  output : Live
  rivalIsAccepted : Bool
  committedKeyState : Hash
  shown : Shown
  committedPayee : Addr
  openedAt : Slot
  eligibleAfter : Slot
  expiresAt : Slot
  payee : Addr
  now : Slot

def Case.commitment (c : Case) : Commitment := {
  aid := 11, deployment := SystemFixtures.deployment, keyState := c.committedKeyState,
  evidence := c.shown.evidence, payee := c.committedPayee,
  openedAt := c.openedAt, eligibleAfter := c.eligibleAfter, expiresAt := c.expiresAt, marker := 1 }

def honest (id note : String) (now : Slot) : Case :=
  ⟨id, note, output, false, output.hash, .duplicity 1 1, 8, 5, 6, 20, 8, now⟩

def cases : List Case := [
  honest "accepted-first-eligible-slot" "the first slot after the opening slot: accepted" 6,
  honest "accepted-last-slot" "the commitment's last slot: accepted" 20,
  honest "refused-opening-slot" "the slot the opening transaction's validity range ends at: refused" 5,
  honest "refused-expired" "one slot after the commitment's last slot: refused" 21,
  { honest "refused-other-payee" "the conviction pays 9, the commitment names 8: refused" 6 with payee := 9 },
  { honest "accepted-output-topped-up" "the output was topped up after the opening: accepted" 6 with
      output := { output with pool := 5, toppedUp := true } },
  { honest "accepted-output-frozen" "the output was frozen after the opening: accepted" 6 with
      output := { output with frozen := true } },
  { honest "accepted-output-poisoned" "the output was poisoned after the opening: accepted" 6 with
      output := { output with poisoned := true } },
  { honest "refused-output-rotated" "the output was rotated after the opening: refused" 6 with
      output := { output with sn := 2, epoch := 2, pool := 3 } },
  { honest "refused-other-key-state" "the commitment names key state (2, 2), the output carries (1, 1): refused" 6 with
      committedKeyState := ⟨2, 2⟩ },
  { honest "refused-other-evidence" "the commitment names the evidence of another key state: refused" 6 with
      shown := .duplicity 2 2 },
  { honest "refused-no-duplicity" "the committed rival and spent tip agree on their forward fields: refused" 6 with
      rivalIsAccepted := true, shown := .sameEvent 1 1 }]

def liveJson (l : Live) : Json :=
  Json.mkObj [("sn", natJson l.sn), ("epoch", natJson l.epoch), ("poisoned", toJson l.poisoned),
    ("frozen", toJson l.frozen), ("bornAt", natJson l.bornAt), ("refundTo", natJson l.refundTo),
    ("pool", natJson l.pool), ("toppedUp", toJson l.toppedUp)]

def paymentJson : Option Payment → Json
  | none => Json.null
  | some q => Json.mkObj [("addr", natJson q.addr), ("dreg", natJson q.dreg), ("b", natJson q.b),
      ("pool", natJson q.pool)]

def outcomeJson : Option (Flow × State) → Json
  | none => Json.mkObj [("accepted", toJson false)]
  | some (f, s) => Json.mkObj [("accepted", toJson true),
      ("convictor", paymentJson f.convictor), ("refund", paymentJson f.refund),
      ("pending", match s with
        | .terminationPending h => toJson [h.epoch, h.sn]
        | _ => Json.null)]

def Case.run (c : Case) : Option (Flow × State) :=
  stepFn params (envFor c.rivalIsAccepted) (.convict c.payee c.commitment) c.now (.present c.output)

def Case.row (c : Case) : Json :=
  Json.mkObj [
    ("id", toJson c.id), ("note", toJson c.note),
    ("output", liveJson c.output),
    ("shown", (if c.rivalIsAccepted then Shown.sameEvent c.output.epoch c.output.sn
      else Shown.duplicity c.output.epoch c.output.sn).json),
    ("commitment", Json.mkObj [
      ("aid", natJson c.commitment.aid), ("deployment", natJson c.commitment.deployment),
      ("keyState", toJson [c.committedKeyState.epoch, c.committedKeyState.sn]),
      ("evidence", c.shown.json),
      ("payee", natJson c.committedPayee), ("openedAt", natJson c.openedAt),
      ("eligibleAfter", natJson c.eligibleAfter), ("expiresAt", natJson c.expiresAt)]),
    ("payee", natJson c.payee), ("now", natJson c.now),
    ("outcome", outcomeJson c.run)]

/-! ## System rows: the commitment program beside the checkpoint -/

open SystemWire SystemFixtures in
/-- Run named commands from a machine and record each outcome and the open markers after it. -/
def runCells (start : Machine) (commands : List (String × Command)) : List Json :=
  (commands.foldl (fun (cells, machine) (name, command) =>
    match execute machine SystemFixtures.p (evidenceFor SystemFixtures.byIdentifier) command with
    | .error why => (cells ++ [Json.mkObj [("name", toJson name), ("outcome", toJson why)]], machine)
    | .ok (next, _, _) =>
      let state := next.certified.state
      (cells ++ [Json.mkObj [("name", toJson name), ("outcome", toJson "accepted"),
        ("open", toJson ([1, 2].filter fun m => (state.commitments m).isSome)),
        ("checkpoint", match state.states 11 with
          | .present _ => toJson "live" | .terminationPending _ => toJson "pending"
          | .absent => toJson "absent" | .convicted => toJson "convicted")]], next))
    ([], start)).1

open SystemWire SystemFixtures in
/-- The journey's checkpoint in deployment `d`: registered and rotated once, and
the same rotated a second time. -/
def rotatedIn (d : Deployment) : Except String (Machine × Machine) := do
  let registered ← advance (Machine.init d) (← registrationCommand)
  let rotated ← advance registered rotatedCommand
  pure (rotated, ← advance rotated rotatedAgainCommand)

open SystemWire SystemFixtures in
def systemRows : Except String (List Json) := do
  let (rotatedOnce, rotatedAgain) ← rotatedIn deployment
  let (_, elsewhere) ← rotatedIn otherDeployment
  let earlier : Commitment := { earlierCommitment with marker := 1 }
  let later : Commitment := { commitment with marker := 2 }
  let other : Commitment := { commitment with aid := 12, marker := 2 }
  let foreign := foreignCommitment
  let stranger : Commitment := { commitment with payee := 9, marker := 2 }
  pure [
    Json.mkObj [("id", toJson "conviction-consumes-an-open-commitment"),
      ("note", toJson "a conviction needs the commitment open and naming this AID, and burns it"),
      ("cells", toJson (runCells rotatedAgain [
        ("convict-unopened", convictedCommand),
        ("open", openCommand), ("reopen-same-marker", openCommand),
        ("open-for-another-aid", .openCommitment other),
        ("convict-revealing-the-other-aid-commitment", .local 11 5 (.convict 7 other)),
        ("convict", convictedCommand),
        ("reveal-after-conviction", .reveal 1 6)]))],
    Json.mkObj [("id", toJson "commitment-window"),
      ("note", toJson "a commitment is revealed inside its window and swept only after it"),
      ("cells", toJson (runCells rotatedAgain [
        ("open", openCommand), ("open-stranger-commitment", .openCommitment stranger),
        ("reveal-in-opening-slot", .reveal 1 4), ("reveal-first-eligible-slot", .reveal 1 5),
        ("sweep-on-last-slot", .sweep 2 20), ("sweep-after-last-slot", .sweep 2 21),
        ("convict-after-reveal", convictedCommand)]))],
    Json.mkObj [("id", toJson "commitment-survives-a-top-up"),
      ("note", toJson "a top-up after the opening leaves the commitment open and the conviction accepted"),
      ("cells", toJson (runCells rotatedAgain [
        ("open", openCommand), ("top-up", .local 11 5 (.topUp 1)),
        ("second-top-up", .local 11 5 (.topUp 1)),
        ("convict", convictedCommand)]))],
    Json.mkObj [("id", toJson "commitment-convicts-before-a-rotation"),
      ("note", toJson "with no rotation in between, the commitment opened at key state (1, 1) convicts"),
      ("cells", toJson (runCells rotatedOnce [
        ("open-before-the-rotation", .openCommitment earlier),
        ("convict-revealing-the-earlier-commitment", .local 11 4 (.convict 7 earlier))]))],
    Json.mkObj [("id", toJson "commitment-voided-by-a-rotation"),
      ("note", toJson ("a rotation after the opening leaves the commitment open and entitling nothing; " ++
        "a commitment naming the new key state convicts")),
      ("cells", toJson (runCells rotatedOnce [
        ("open-before-the-rotation", .openCommitment earlier), ("rotate", rotatedAgainCommand),
        ("convict-revealing-the-earlier-commitment", .local 11 5 (.convict 7 earlier)),
        ("open-for-the-new-key-state", .openCommitment later),
        ("convict-revealing-the-later-commitment", .local 11 5 (.convict 7 later))]))],
    Json.mkObj [("id", toJson "conviction-needs-this-deployment"),
      ("note", toJson "a commitment naming another deployment is refused here although it is open and names this AID"),
      ("cells", toJson (runCells rotatedAgain [
        ("open-for-another-deployment", .openCommitment foreign),
        ("convict-revealing-the-other-deployment-commitment", .local 11 5 (.convict 7 foreign)),
        ("open", openCommand), ("convict", convictedCommand)]))],
    Json.mkObj [("id", toJson "refused-at-another-deployment"),
      ("note", toJson ("the same journey in another deployment: same identifier, same key state, the same " ++
        "commitment open; the conviction is refused, and the commitment naming that deployment convicts")),
      ("cells", toJson (runCells elsewhere [
        ("open", openCommand), ("convict", convictedCommand),
        ("open-for-this-deployment", .openCommitment foreign),
        ("convict-revealing-this-deployment-commitment", .local 11 5 (.convict 7 foreign))]))]]

/-! ## The table -/

def table : Except String Json := do
  pure (Json.mkObj [
    ("description", toJson ("Vectors of the commitment a conviction reveals: the local conviction step " ++
      "with a commitment, a payee and a slot; and the system steps that open, reveal, sweep and burn " ++
      "commitments beside a checkpoint.")),
    ("model", toJson "lean/CardanoKeri/Checkpoint.lean (Commitment.entitles, Step.convict, Sys.revealOpen, LocalEvent, OpenEvent, RevealEvent, SweepEvent)"),
    ("rules", Json.mkObj [
      ("conviction", toJson "the spent-tip comparison must accept the rival at the live epoch and sequence. The commitment must name that position, the evidence read for its identifier and this payee, with eligibleAfter <= now <= expiresAt"),
      ("system", toJson "a conviction's commitment is open under its marker and names this AID and this deployment; the conviction burns it; a commitment opens with eligibleAfter = openedAt + 1 <= expiresAt; a reveal needs eligibleAfter <= now <= expiresAt; a sweep needs expiresAt < now")]),
    ("params", Json.mkObj [("D", natJson params.D), ("B", natJson params.B), ("P", natJson params.P)]),
    ("deployments", Json.mkObj [("this", natJson SystemFixtures.deployment), ("other", natJson SystemFixtures.otherDeployment)]),
    ("conviction", Json.arr (cases.map Case.row).toArray),
    ("system", Json.arr (← systemRows).toArray)])

/-! ## Checking a committed table -/

def verifyConviction (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some c := cases.find? (·.id == id) | throw s!"{id}: no such conviction case"
  unless row == c.row do throw s!"{id}: differs from the Lean's row"

def verifySystem (lean : List Json) (row : Json) : Except String Unit := do
  let id ← str row ["id"]
  let some expected := lean.find? (fun r => (r.getObjValAs? String "id").toOption == some id)
    | throw s!"{id}: no such system case"
  unless row == expected do throw s!"{id}: differs from the Lean's row"

/-- Every leaf of every committed row except the free-text `id` and `note`,
changed in turn, must fail its row's verification. -/
def fieldControls (rs : Array Json) (verify : Json → Except String Unit) : Except String Nat := do
  let mut count := 0
  for row in rs do
    for path in leaves row [] do
      if path == ["id"] || path == ["note"] then continue
      match verify (mutateAt row path) with
      | .ok () => throw s!"changing {path} of a row still verifies"
      | .error _ => count := count + 1
  pure count

/-- The accepted row changed in one entitling fact at a time: each is refused. -/
def discriminatingControls : Except String Nat := do
  let some base := cases.head? | throw "no conviction case"
  unless base.run.isSome do throw "the honest conviction is refused"
  let changed : List (String × Case) := [
    ("payee", { base with payee := base.payee + 1 }),
    ("key state named", { base with committedKeyState := ⟨base.committedKeyState.epoch, base.committedKeyState.sn + 1⟩ }),
    ("key state carried", { base with output := { base.output with sn := base.output.sn + 1, epoch := base.output.epoch + 1 } }),
    ("evidence", { base with shown := .duplicity 2 2 }),
    ("before-eligible", { base with now := base.eligibleAfter - 1 }),
    ("after-expiry", { base with now := base.expiresAt + 1 }),
    ("no-duplicity", { base with rivalIsAccepted := true, shown := .sameEvent 1 1 })]
  for (name, c) in changed do
    if c.run.isSome then throw s!"changing the {name} of the honest conviction still convicts"
  pure changed.length

/-- The accepted row changed in one fact of the output other than its key state at
a time: each is still accepted and pays the same convictor. -/
def indifferentControls : Except String Nat := do
  let some base := cases.head? | throw "no conviction case"
  let some (paid, _) := base.run | throw "the honest conviction is refused"
  let changed : List (String × Live) := [
    ("pool", { base.output with pool := base.output.pool + 1 }),
    ("top-up mark", { base.output with toppedUp := !base.output.toppedUp }),
    ("freeze mark", { base.output with frozen := !base.output.frozen }),
    ("poison mark", { base.output with poisoned := !base.output.poisoned }),
    ("birth slot", { base.output with bornAt := base.output.bornAt + 1 }),
    ("refund address", { base.output with refundTo := base.output.refundTo + 1 })]
  for (name, output) in changed do
    match ({ base with output } : Case).run with
    | none => throw s!"changing the {name} of the convicted output refuses the conviction"
    | some (flow, _) =>
      unless flow.convictor == paid.convictor do
        throw s!"changing the {name} of the convicted output changes the convictor's payment"
  pure changed.length

def checkTable (j : Json) : Except String (Nat × Nat × Nat × Nat × Nat) := do
  let conviction ← rows j "conviction"
  let system ← rows j "system"
  let lean ← systemRows
  unless conviction.size == cases.length do throw "conviction count differs from the Lean cases"
  unless system.size == lean.length do throw "system count differs from the Lean cases"
  for row in conviction do verifyConviction row
  for row in system do verifySystem lean row
  let fields := (← fieldControls conviction verifyConviction) + (← fieldControls system (verifySystem lean))
  pure (conviction.size, system.size, fields, ← discriminatingControls, ← indifferentControls)

end CardanoKeri.Checkpoint.CommitmentVectors
