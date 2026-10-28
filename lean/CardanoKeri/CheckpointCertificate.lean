import CardanoKeri.CheckpointSystemEvidence

/-! A finite certificate interpreter for the existing Checkpoint system events.
The successful result carries its actual SysStep proof. Registry extensions
execute in the stored origin context. No new transition or receipt premise is
introduced into Checkpoint; this is an executable producer of its witnesses. -/
namespace CardanoKeri.Checkpoint

structure FoldCertificate where
  history : List CardanoKeri.Registry.Action
  unspent : Singular.EconomicUtxo
  transaction : Singular.EconomicTransaction

structure ReplayedFold (p : CardanoKeri.Registry.Params) (env : CardanoKeri.Registry.Env)
    (cfg : Singular.Config) (start : CardanoKeri.Registry.Sys) where
  receipt : CardanoKeri.Registry.FoldReceipt p env cfg
  history : CardanoKeri.Registry.History p env start receipt.before

def replayFold (rp : CardanoKeri.Registry.Params) (re : CardanoKeri.Registry.Env)
    (cfg : Singular.Config) (start : CardanoKeri.Registry.Sys)
    (reachable : CardanoKeri.Registry.Reach rp re cfg start) (certificate : FoldCertificate) :
    Except String (ReplayedFold rp re cfg start) :=
  match run : CardanoKeri.Registry.replay rp re start certificate.history with
  | .error why => .error why
  | .ok before =>
    match folded : CardanoKeri.Registry.fold rp re before before.gen before.config.applicationPolicy
        certificate.unspent certificate.transaction with
    | .error why => .error why
    | .ok (flow, after) =>
      let history := CardanoKeri.Registry.replay_history rp re certificate.history run
      .ok {
        receipt := {
          before, after, unspent := certificate.unspent,
          transaction := certificate.transaction, flow,
          reachable := history.reachable reachable, executed := folded }
        history }

structure CertificateResult (current : CertifiedSys) (p : Params) (env : Env) where
  next : CertifiedSys
  event : SysStep p env current.state next.state
  checkpointFlow : Option Flow := none
  registryFlow : Option CardanoKeri.Registry.Flow := none

def completeCertificate (current : CertifiedSys) (p : Params) (env : Env)
    (aid : AID) (certificate : FoldCertificate) : Except String (CertificateResult current p env) := do
  match stored : current.state.pending aid with
  | none => throw "checkpoint-association-missing"
  | some association =>
    let folded ← replayFold association.origin.parameters association.origin.environment
      association.origin.configuration association.booked (current.pending aid association stored) certificate
    if checked : receiptFieldsB current.state aid association folded.receipt = true then
      let matching := (receiptFieldsB_iff current.state aid association folded.receipt stored
        (current.bound aid association stored) folded.history).mp checked
      let event : SysStep p env current.state (current.state.finish aid) :=
        .complete ⟨aid, association, folded.receipt, matching, rfl⟩
      pure {
        next := current.advance event, event,
        registryFlow := some folded.receipt.flow }
    else throw "checkpoint-receipt-mismatch"

def bookCertificate (current : CertifiedSys) (p : Params) (env : Env)
    (aid booker fee : Nat) (history : List CardanoKeri.Registry.Action)
    (booking : Singular.TerminationBooking) : Except String (CertificateResult current p env) := do
  match state : current.state.states aid with
  | .terminationPending key =>
    match stored : current.state.origins aid with
    | none => throw "checkpoint-origin-missing"
    | some origin =>
      if empty : current.state.pending aid = none then
        match run : CardanoKeri.Registry.replay origin.parameters origin.environment origin.registered history with
        | .error why => throw why
        | .ok before =>
          match executed : CardanoKeri.Registry.bookTermination origin.parameters before aid booker fee booking with
          | .error why => throw why
          | .ok (flow, booked) =>
            match found : CardanoKeri.Registry.pendingAt booked booking.request.reference with
            | none => throw "checkpoint-booking-entry-missing"
            | some entry =>
              if fields : entry.booking = booking ∧ entry.payload.aid = aid ∧ entry.payload.token = origin.token then
                let association : PendingAssociation := {
                  origin, keyState := key, reference := booking.request.reference, entry, booked }
                let event : SysStep p env current.state (current.state.associate aid association) :=
                  .book ⟨aid, key, origin, before, booked, booker, fee, booking, flow, entry,
                    state, stored, empty, CardanoKeri.Registry.replay_history _ _ _ run,
                    executed, found, fields.1, fields.2.1, fields.2.2, rfl⟩
                pure { next := current.advance event, event, registryFlow := some flow }
              else throw "checkpoint-booking-binding"
      else throw "checkpoint-already-associated"
  | _ => throw "checkpoint-not-pending"

def isRegistration : Action → Bool
  | .register _ _ => true
  | _ => false

def reopenAllowed (s : Sys) (aid : AID) : Action → Bool
  | .reopen _ _ _ => decide (s.leaves aid = .active)
  | _ => true

def localCertificate (current : CertifiedSys) (p : Params) (env : Env)
    (aid : AID) (now : Slot) (action : Action) : Except String (CertificateResult current p env) := do
  if localAction : isRegistration action = false then
    if active : reopenAllowed current.state aid action = true then
      match executed : stepFn p env action now (current.state.states aid) with
      | none => throw "checkpoint-local-refused"
      | some (flow, state) =>
        have nonregister : ∀ refund pool, action ≠ .register refund pool := by
          intro refund pool equal
          subst action
          contradiction
        have reopen : (∃ sn refund pool, action = .reopen sn refund pool) →
            current.state.leaves aid = .active := by
          rintro ⟨sn, refund, pool, rfl⟩
          simpa [reopenAllowed] using active
        let event : SysStep p env current.state (current.state.set aid state) :=
          .local ⟨aid, action, now, flow, state, nonregister,
            (T7_step_iff_stepFn p env).mpr executed,
            reopen, rfl⟩
        pure { next := current.advance event, event, checkpointFlow := some flow }
    else throw "checkpoint-reopen-leaf"
  else throw "checkpoint-registration-receipt-required"

def registerCertificate (current : CertifiedSys) (p : Params) (env : Env)
    (aid : AID) (now : Slot) (refund pool : Nat)
    (rp : CardanoKeri.Registry.Params) (re : CardanoKeri.Registry.Env) (cfg : Singular.Config)
    (certificate : FoldCertificate) (booking : Singular.RegistrationBooking) (index : Nat) :
    Except String (CertificateResult current p env) := do
  if absent : current.state.leaves aid = .absent then
    if unbound : current.state.origins aid = none then
      match executed : stepFn p env (.register refund pool) now (current.state.states aid) with
      | none => throw "checkpoint-local-refused"
      | some (flow, state) =>
        let folded ← replayFold rp re cfg (CardanoKeri.Registry.Sys.init cfg) .init certificate
        let receipt := folded.receipt
        match alias : CardanoKeri.Registry.bindingAt receipt.after aid with
        | none => throw "checkpoint-registration-alias-missing"
        | some token =>
          match outputFound : receipt.transaction.outputs[index]? with
          | none => throw "checkpoint-registration-output-missing"
            | some output =>
            letI : BEq Singular.FoldMember := instBEqOfDecidableEq
            if fields : Singular.FoldMember.registration booking ∈
                Singular.foldMembers receipt.before.toWorld receipt.transaction ∧
                booking.request.key = aid ∧
                output.singularTags = [receipt.before.config.singularTag aid] ∧
                output.output.address = some booking.request.destination ∧
                output.output.datumValue = booking.request.datum ∧
                output.output.lovelace = booking.request.carrierAda then
              let origin : Origin := {
                parameters := rp, environment := re, configuration := cfg,
                registered := receipt.after, token, registrationRef := booking.request.reference,
                carrierRef := ⟨receipt.transaction.identity, index⟩ }
              have delivered : DeliveredOrigin receipt booking aid origin := by
                exact ⟨fields.1, fields.2.1, rfl, rfl, rfl, rfl, rfl, alias,
                  index, output, outputFound, rfl, fields.2.2.1, fields.2.2.2.1,
                  fields.2.2.2.2.1, fields.2.2.2.2.2⟩
              let event : SysStep p env current.state (current.state.installOrigin aid state origin) :=
                .register ⟨aid, now, refund, pool, flow, state, rp, re, cfg, receipt, booking, origin,
                  absent, unbound, (T7_step_iff_stepFn p env).mpr executed, delivered, rfl⟩
              pure {
                next := current.advance event, event, checkpointFlow := some flow,
                registryFlow := some receipt.flow }
            else throw "checkpoint-registration-delivery-mismatch"
    else throw "checkpoint-origin-already-bound"
  else throw "checkpoint-registration-leaf"

end CardanoKeri.Checkpoint
