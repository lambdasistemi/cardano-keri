import CardanoKeri.CheckpointCertificate
import CardanoKeri.CheckpointTraceWire
import CardanoKeri.RegistryTraceWire

/-! Finite system-certificate interchange. A trace starts from Sys.init; callers
supply commands, not a forged Sys or proof. The origin environment table is
retained from its registration command for serialization, while execution uses
the actual origin's stored function. Unlisted AIDs have the initial defaults. -/
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
      (booking : Singular.TerminationBooking)
  | complete (aid : Nat) (certificate : FoldCertificate)
  deriving ToJson, FromJson

structure Machine where
  certified : CertifiedSys
  contexts : List (AID × CardanoKeri.Registry.TraceWire.EnvTable)

def Machine.init : Machine := ⟨CertifiedSys.init, []⟩

def execute (machine : Machine) (p : Params) (env : Env) (command : Command) :
    Except String (Machine × Option Flow × Option CardanoKeri.Registry.Flow) := do
  let current := machine.certified
  let result ← match command with
    | .register aid now refund pool context certificate booking index =>
        registerCertificate current p env aid now refund pool context.parameters
          context.environment.toEnv context.configuration certificate booking index
    | .local aid now action => localCertificate current p env aid now action
    | .book aid booker fee history booking => bookCertificate current p env aid booker fee history booking
    | .complete aid certificate => completeCertificate current p env aid certificate
  let contexts := match command with
    | .register aid _ _ _ context _ _ _ => machine.contexts ++ [(aid, context.environment)]
    | _ => machine.contexts
  pure (⟨result.next, contexts⟩, result.checkpointFlow, result.registryFlow)

def originJson (environment : CardanoKeri.Registry.TraceWire.EnvTable) (origin : Origin) : Json :=
  Json.mkObj [
    ("parameters", toJson origin.parameters), ("environment", toJson environment),
    ("configuration", toJson origin.configuration), ("registered", toJson origin.registered),
    ("token", toJson origin.token), ("registrationRef", toJson origin.registrationRef),
    ("carrierRef", toJson origin.carrierRef)]

def stateJson (machine : Machine) : Json :=
  let s := machine.certified.state
  Json.mkObj [("aids", Json.arr (machine.contexts.map fun (aid, environment) => Json.mkObj [
    ("aid", toJson aid), ("leaf", toJson (s.leaves aid)), ("state", toJson (s.states aid)),
    ("origin", match s.origins aid with | none => Json.null | some origin => originJson environment origin),
    ("pending", match s.pending aid with
      | none => Json.null
      | some association => Json.mkObj [
        ("origin", originJson environment association.origin), ("keyState", toJson association.keyState),
        ("reference", toJson association.reference), ("entry", toJson association.entry),
        ("booked", toJson association.booked)])]).toArray)]

def cell (name : String) (p : Params) (table : EnvTable) (machine : Machine)
    (command : Command) : Json × Machine :=
  let (result, next) := match execute machine p table.toEnv command with
    | .error why => (Json.mkObj [("error", toJson why)], machine)
    | .ok (next, flow, registryFlow) =>
      (Json.mkObj [("ok", Json.mkObj [("state", stateJson next),
        ("checkpointFlow", toJson flow), ("registryFlow", toJson registryFlow)])], next)
  (CardanoKeri.Registry.TraceWire.exactJson (Json.mkObj [
    ("name", toJson name), ("params", toJson p), ("env", toJson table),
    ("input", stateJson machine), ("command", toJson command), ("result", result)]), next)

end CardanoKeri.Checkpoint.SystemWire
