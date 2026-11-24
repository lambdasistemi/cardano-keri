import CardanoKeri.CheckpointCertificate
import CardanoKeri.ReaderStatus
import CardanoKeri.CheckpointTraceWire
import CardanoKeri.RegistryTraceWire

/-! Finite system-certificate interchange. A trace starts from Sys.init of one
deployment; callers
supply commands, not a forged Sys or proof. The origin environment table is
retained from its registration command for serialization, while execution uses
the actual origin's stored function. Unlisted AIDs have the initial defaults.
Each listed AID carries the status its lifecycle state warrants
(`ReaderStatus.lifecycleStatus`): what a reader answers on complete evidence
that realizes the system. -/
namespace CardanoKeri.Checkpoint.SystemWire
open Lean
open CardanoKeri.Checkpoint.TraceWire

deriving instance ToJson, FromJson for FoldCertificate
deriving instance ToJson for Leaf

structure RegistryContext where
  parameters : CardanoKeri.Registry.Params
  environment : CardanoKeri.Registry.TraceWire.EnvTable
  configuration : Singular.Config
  deriving ToJson, FromJson

inductive Command where
  | register (aid now refund pool : Nat) (context : RegistryContext)
      (certificate : FoldCertificate) (booking : Singular.RegistrationBooking) (index : Nat)
  | local (aid now : Nat) (action : Action)
  | book (aid booker fee : Nat) (history : List CardanoKeri.Registry.Action)
      (booking : CardanoKeri.Registry.TerminationBooking)
  | complete (aid : Nat) (certificate : FoldCertificate)
  | openCommitment (commitment : Commitment)
  | reveal (marker now : Nat)
  | sweep (marker now : Nat)
  deriving ToJson, FromJson

structure Machine where
  certified : CertifiedSys
  contexts : List (AID × CardanoKeri.Registry.TraceWire.EnvTable)
  -- The markers ever opened, for serialization of the open commitments by marker.
  commitments : List Marker := []

def Machine.init (d : Deployment) : Machine := ⟨CertifiedSys.init d, [], []⟩

def execute (machine : Machine) (p : Params) (env : SystemEnv) (command : Command) :
    Except String (Machine × Option Flow × Option CardanoKeri.Registry.Flow) := do
  let current := machine.certified
  let result ← match command with
    | .register aid now refund pool context certificate booking index =>
        registerCertificate current p env aid now refund pool context.parameters
          context.environment.toEnv context.configuration certificate booking index
    | .local aid now action => localCertificate current p env aid now action
    | .book aid booker fee history booking => bookCertificate current p env aid booker fee history booking
    | .complete aid certificate => completeCertificate current p env aid certificate
    | .openCommitment c => openCertificate current p env c
    | .reveal marker now => revealCertificate current p env marker now
    | .sweep marker now => sweepCertificate current p env marker now
  let contexts := match command with
    | .register aid _ _ _ context _ _ _ => machine.contexts ++ [(aid, context.environment)]
    | _ => machine.contexts
  let commitments := match command with
    | .openCommitment c => if machine.commitments.contains c.marker then machine.commitments
        else machine.commitments ++ [c.marker]
    | _ => machine.commitments
  pure (⟨result.next, contexts, commitments⟩, result.checkpointFlow, result.registryFlow)

def originJson (environment : CardanoKeri.Registry.TraceWire.EnvTable) (origin : Origin) : Json :=
  Json.mkObj [
    ("parameters", toJson origin.parameters), ("environment", toJson environment),
    ("configuration", toJson origin.configuration), ("registered", toJson origin.registered),
    ("token", toJson origin.token), ("registrationRef", toJson origin.registrationRef),
    ("carrierRef", toJson origin.carrierRef), ("inception", toJson origin.inception)]

def stateJson (machine : Machine) : Json :=
  let s := machine.certified.state
  Json.mkObj [("deployment", toJson s.deployment),
    ("commitments", Json.arr (((machine.commitments.mergeSort (· ≤ ·)).filterMap s.commitments).map toJson).toArray),
    ("aids", Json.arr (machine.contexts.map fun (aid, environment) => Json.mkObj [
    ("aid", toJson aid), ("leaf", toJson (s.leaves aid)), ("state", toJson (s.states aid)),
    ("status", toJson (CardanoKeri.ReaderStatus.lifecycleStatus (s.states aid)).word),
    ("origin", match s.origins aid with | none => Json.null | some origin => originJson environment origin),
    ("writer", toJson (s.writers aid)),
    ("pending", match s.pending aid with
      | none => Json.null
      | some association => Json.mkObj [
        ("origin", originJson environment association.origin), ("keyState", toJson association.keyState),
        ("reference", toJson association.reference), ("entry", toJson association.entry),
        ("booked", toJson association.booked)])]).toArray)]

/-- Each row supplies the evidence of one identifier. An unlisted identity has
no witnessed rotation, deposit signature, poison quorum or conviction pair. -/
abbrev EvidenceTable := List (AID × EnvTable)

def evidenceFor (table : EvidenceTable) (aid : AID) : Env :=
  ((table.lookup aid).getD ⟨[], [], [], [], {}⟩).toEnv aid

def cell (name : String) (p : Params) (table : EvidenceTable) (machine : Machine)
    (command : Command) : Json × Machine :=
  let (result, next) := match execute machine p (evidenceFor table) command with
    | .error why => (Json.mkObj [("error", toJson why)], machine)
    | .ok (next, flow, registryFlow) =>
      (Json.mkObj [("ok", Json.mkObj [("state", stateJson next),
        ("checkpointFlow", toJson flow), ("registryFlow", toJson registryFlow)])], next)
  (CardanoKeri.Registry.TraceWire.exactJson (Json.mkObj [
    ("name", toJson name), ("params", toJson p), ("env", toJson (table.map fun (aid, evidence) =>
      (aid, (toJson evidence).setObjVal! "writers" (toJson evidence.writers)))),
    ("input", stateJson machine), ("command", toJson command), ("result", result)]), next)

end CardanoKeri.Checkpoint.SystemWire
