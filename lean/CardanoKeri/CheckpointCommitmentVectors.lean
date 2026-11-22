import CardanoKeri.CheckpointCommitmentGoals
import CardanoKeri.CheckpointSystemFixtures
import CardanoKeri.CheckpointDatumVectors

/-! Vectors of the commitment a conviction reveals (#534).

Conviction rows run the local conviction step on one live output with a
commitment and a payee at a slot: accepted only when the commitment names this
output, the evidence shown at its key state and this payee, and the slot lies in
its window. Controls change one fact of the accepted row at a time and must be
refused. System rows run the certificate interpreter over a registered and twice
rotated checkpoint: a conviction needs an open commitment naming its AID, burns
it, and a commitment is revealed inside its window or swept after it. Checks run
the actual Lean functions; they are evidence over the listed inputs, not a proof
over all inputs. -/
namespace CardanoKeri.Checkpoint.CommitmentVectors
open Lean (Json toJson)
open CardanoKeri.CheckpointDatum.Vectors (natJson rows leaves mutateAt)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (field str)

def params : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }

/-- Which evidence a fixture selector names: the concrete duplicity fixture at a key
state, or the same context with the accepted event as its own rival (no duplicity). -/
inductive Shown where
  | duplicity (epoch sn : Nat)
  | sameEvent (epoch sn : Nat)
  deriving DecidableEq, Repr

def Shown.evidence : Shown → Evidence
  | .duplicity e sn => CardanoKeri.Duplicity.fixture e sn
  | .sameEvent e sn => ((CardanoKeri.Duplicity.fixture e sn).1, (CardanoKeri.Duplicity.fixture e sn).1.accepted)

def Shown.json : Shown → Json
  | .duplicity e sn => Json.mkObj [("duplicity", toJson [e, sn])]
  | .sameEvent e sn => Json.mkObj [("sameEvent", toJson [e, sn])]

/-- The environment shows the duplicity fixture at every key state, or (`sameEvent`)
a rival equal to the accepted event, which proves nothing. -/
def envFor (rivalIsAccepted : Bool) : Env := {
  rotationTo := fun _ _ _ => false, depositAuthorized := fun _ => false, quorum := fun _ => false,
  convictionContext := fun e sn => some (CardanoKeri.Duplicity.fixture e sn).1,
  convictionRival := fun e sn => some (if rivalIsAccepted then (CardanoKeri.Duplicity.fixture e sn).1.accepted
    else (CardanoKeri.Duplicity.fixture e sn).2) }

/-- The convicted output: sequence 1, epoch 1, refund address 42, pool 4. -/
def output : Live := ⟨1, 1, false, false, 3, 42, 4, false⟩

structure Case where
  id : String
  note : String
  output : Live
  rivalIsAccepted : Bool
  committedOutput : Live
  shown : Shown
  committedPayee : Addr
  openedAt : Slot
  eligibleAfter : Slot
  expiresAt : Slot
  payee : Addr
  now : Slot

def Case.commitment (c : Case) : Commitment := {
  aid := 11, deployment := SystemFixtures.deployment, keyState := c.committedOutput.hash,
  evidence := c.shown.evidence, payee := c.committedPayee,
  openedAt := c.openedAt, eligibleAfter := c.eligibleAfter, expiresAt := c.expiresAt, marker := 1 }

def honest (id note : String) (now : Slot) : Case :=
  ⟨id, note, output, false, output, .duplicity 1 1, 8, 5, 6, 20, 8, now⟩

def cases : List Case := [
  honest "accepted-first-eligible-slot" "the first slot after the opening slot: accepted" 6,
  honest "accepted-last-slot" "the commitment's last slot: accepted" 20,
  honest "refused-opening-slot" "the slot the opening transaction's validity range ends at: refused" 5,
  honest "refused-expired" "one slot after the commitment's last slot: refused" 21,
  { honest "refused-other-payee" "the conviction pays 9, the commitment names 8: refused" 6 with payee := 9 },
  { honest "refused-output-topped-up" "the output was topped up after the opening: refused" 6 with
      output := { output with pool := 5, toppedUp := true } },
  { honest "refused-output-rotated" "the output was rotated after the opening: refused" 6 with
      output := { output with sn := 2, epoch := 2, pool := 3 } },
  { honest "refused-other-evidence" "the commitment names the evidence of another key state: refused" 6 with
      shown := .duplicity 2 2 },
  { honest "refused-no-duplicity" "the evidence shown and committed proves no duplicity: refused" 6 with
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
      ("output", liveJson c.committedOutput), ("evidence", c.shown.json),
      ("payee", natJson c.committedPayee), ("openedAt", natJson c.openedAt),
      ("eligibleAfter", natJson c.eligibleAfter), ("expiresAt", natJson c.expiresAt)]),
    ("payee", natJson c.payee), ("now", natJson c.now),
    ("outcome", outcomeJson c.run)]

/-! ## System rows: the commitment program beside the checkpoint -/

open SystemWire SystemFixtures in
/-- Run named commands from a machine and record each outcome and the open markers after it. -/
def runCells (start : Machine) (commands : List (String × Command)) : List Json :=
  (commands.foldl (fun (cells, machine) (name, command) =>
    match execute machine SystemFixtures.p SystemFixtures.evidence.toEnv command with
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
def systemRows : Except String (List Json) := do
  let registered ← advance (Machine.init deployment) (← registrationCommand)
  let rotated ← advance registered rotatedCommand
  let rotatedAgain ← advance rotated rotatedAgainCommand
  let other : Commitment := { commitment with aid := 12, marker := 2 }
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
        ("convict-after-reveal", convictedCommand)]))]]

/-! ## The table -/

def table : Except String Json := do
  pure (Json.mkObj [
    ("description", toJson ("Vectors of the commitment a conviction reveals: the local conviction step " ++
      "with a commitment, a payee and a slot; and the system steps that open, reveal, sweep and burn " ++
      "commitments beside a checkpoint.")),
    ("model", toJson "lean/CardanoKeri/Checkpoint.lean (Commitment.entitles, Step.convict, LocalEvent, OpenEvent, RevealEvent, SweepEvent)"),
    ("rules", Json.mkObj [
      ("conviction", toJson "accepted iff duplicity at the output's key state and the commitment names this output, the evidence shown there and this payee, and eligibleAfter <= now <= expiresAt"),
      ("system", toJson "a conviction's commitment is open under its marker and names this AID; the conviction burns it; a reveal needs eligibleAfter <= now <= expiresAt; a sweep needs expiresAt < now")]),
    ("params", Json.mkObj [("D", natJson params.D), ("B", natJson params.B), ("P", natJson params.P)]),
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
    ("output", { base with output := { base.output with pool := base.output.pool + 1 } }),
    ("evidence", { base with shown := .duplicity 2 2 }),
    ("before-eligible", { base with now := base.eligibleAfter - 1 }),
    ("after-expiry", { base with now := base.expiresAt + 1 }),
    ("no-duplicity", { base with rivalIsAccepted := true, shown := .sameEvent 1 1 })]
  for (name, c) in changed do
    if c.run.isSome then throw s!"changing the {name} of the honest conviction still convicts"
  pure changed.length

def checkTable (j : Json) : Except String (Nat × Nat × Nat × Nat) := do
  let conviction ← rows j "conviction"
  let system ← rows j "system"
  let lean ← systemRows
  unless conviction.size == cases.length do throw "conviction count differs from the Lean cases"
  unless system.size == lean.length do throw "system count differs from the Lean cases"
  for row in conviction do verifyConviction row
  for row in system do verifySystem lean row
  let fields := (← fieldControls conviction verifyConviction) + (← fieldControls system (verifySystem lean))
  pure (conviction.size, system.size, fields, ← discriminatingControls)

end CardanoKeri.Checkpoint.CommitmentVectors
