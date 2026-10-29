import CardanoKeri.CheckpointGoals
import CardanoKeri.Samaritan
import CardanoKeri.Statements.MirrorGoals

/-! PRIVATE PRE-MEETING RESEARCH. No accepted protocol changes.
All time and money units below are illustrative integer ticks/units. -/
namespace Freshness
open CardanoKeri

abbrev Time := Nat
abbrev Agent := Nat

/-- Events belong to one chosen AID/history. This type does not authenticate or
separate mixed-AID/fork inputs. Publication and availability are distinct;
none can mean hidden/unavailable. -/
structure Event where
  sequence : Checkpoint.Seq
  publishedAt : Option Time
  evidenceAt : Option Time
  deriving Repr

def observable (e : Event) (now : Time) : Bool :=
  match e.publishedAt, e.evidenceAt with
  | some p, some v => p ≤ now && v ≤ now
  | _, _ => false

inductive Frontier where
  | unknown
  | unsupported (claimedSequence : Checkpoint.Seq)
  | observed (sequence : Checkpoint.Seq) (sampledAt : Time)
  deriving Repr, DecidableEq

/-- Data-to-frontier reduction over a supplied finite observation list.
Only published and evidence-available events at now contribute. The list's
completeness/authenticity and evidenceAt values remain research inputs. -/
def frontierFrom (events : List Event) (now : Time) : Frontier :=
  match events.filter (fun event => observable event now) with
  | [] => .unknown
  | first :: rest =>
      .observed (rest.foldl (fun highest event => max highest event.sequence) first.sequence) now

inductive Lag where
  | noProjection
  | unknown
  | unsupported
  | aheadOfObservation (chain observed : Checkpoint.Seq)
  | behindBy (events : Nat)
  deriving Repr, DecidableEq

/-- Relative to a supported observation, never a claim to know hidden events. -/
def sequenceLag (s : Checkpoint.State) (frontier : Frontier) : Lag :=
  match s.sn?, frontier with
  | none, _ => .noProjection
  | _, .unknown => .unknown
  | _, .unsupported _ => .unsupported
  | some c, .observed o _ =>
      if c ≤ o then .behindBy (o - c) else .aheadOfObservation c o

/-- Invalid chronology and unpublished events are not zero delay. -/
def projectionDelay (e : Event) (included : Time) : Option Nat :=
  match e.publishedAt with
  | some p => if p ≤ included then some (included - p) else none
  | none => none

/-- Imported consumer rule: no off-chain freshness assertion is added. -/
def eligible := Checkpoint.consumableStateB

inductive Role where
  | sponsor | controller | monitor | submitter | consumer
  deriving Repr, DecidableEq

/-- Several roles and addresses may be controlled by one agent. -/
structure Control where
  roleOwner : Role → Agent
  addressOwner : Checkpoint.Addr → Agent

/-- Research choices are not Checkpoint.Action constructors. -/
inductive Choice where
  | monitor | submit | wait | withhold | stop | manufactureValidWork
  deriving Repr, DecidableEq

structure Costs where
  monitoring : Nat := 0
  success : Nat := 0
  failure : Nat := 0
  racing : Nat := 0
  lockedCapital : Nat := 0
  manufacture : Nat := 0
  deriving Repr

def Costs.total (c : Costs) : Int :=
  c.monitoring + c.success + c.failure + c.racing + c.lockedCapital + c.manufacture

/-- Principal is a balance-sheet transfer; terminalPrincipal is recoverable
value at the horizon (face-value valuation is a research assumption). -/
structure Account where
  revenue : Nat := 0
  principalReturned : Nat := 0
  principalCommitted : Nat := 0
  terminalPrincipal : Nat := 0
  sponsorFunding : Nat := 0
  costs : Costs := {}
  deriving Repr

def utility (a : Account) : Int :=
  (a.revenue : Int) + a.principalReturned + a.terminalPrincipal -
    a.principalCommitted - a.sponsorFunding - a.costs.total

structure Execution (p : Checkpoint.Params) (env : Checkpoint.Env) where
  before : Checkpoint.State
  action : Checkpoint.Action
  atTime : Time
  flow : Checkpoint.Flow
  after : Checkpoint.State
  lawful : Checkpoint.Step p env action atTime before flow after

/-- An adapter to the actual law, not a copied transition. -/
def executionOf {p : Checkpoint.Params} {env : Checkpoint.Env}
    (s : Checkpoint.State) (a : Checkpoint.Action) (t : Time) (f : Checkpoint.Flow) (s' : Checkpoint.State)
    (h : Checkpoint.stepFn p env a t s = some (f, s')) : Execution p env :=
  ⟨s, a, t, f, s', (Checkpoint.T7_step_iff_stepFn p env).mpr h⟩

def isRotation : Checkpoint.Action → Bool
  | .rotate .. => true
  | _ => false

/-- Only pool premiums on rotations count as freshness revenue here.
Refund, bond and conviction categories are deliberately not conflated. -/
def rotationRevenue (control : Control) (agent : Agent)
    (action : Checkpoint.Action) (flow : Checkpoint.Flow) : Nat :=
  if isRotation action then
    match flow.hunter with
    | some q => if control.addressOwner q.addr = agent then q.pool else 0
    | none => 0
  else 0

def isKeepRotation : Checkpoint.Action → Bool
  | .rotate _ .keep _ none => true
  | _ => false

/-- Only keep rotations with no refund change: their Flow has no capital input.
Costs remain externally attributed; this is not a full lifecycle account. -/
def submissionAccount {p : Checkpoint.Params} {env : Checkpoint.Env}
    (control : Control) (agent : Agent) (e : Execution p env)
    (_keep : isKeepRotation e.action = true) (costs : Costs) : Account :=
  { revenue := rotationRevenue control agent e.action e.flow, costs := costs }

/-- A finite deterministic normal-form study with exogenous payoffs. The
schedule/payoff table and feasible sets are model choices, not protocol law. -/
structure Game where
  agents : List Agent
  feasible : Agent → List Choice
  payoff : (Agent → Choice) → Agent → Int

/-- An illustrative feasible submission menu, conditional on the supplied evidence
oracle, publication/availability at now, and a lawful exact-event rotation.
It does not infer real signing ability from a natural-number role/address. -/
def submissionMenu (p : Checkpoint.Params) (env : Checkpoint.Env) (event : Event) (now : Time)
    (s : Checkpoint.State) (payee : Checkpoint.Addr) : List Choice :=
  if observable event now &&
      (Checkpoint.stepFn p env (.rotate event.sequence .keep payee none) now s).isSome
  then [.submit, .wait, .stop] else [.monitor, .wait, .stop, .withhold]

abbrev Strategy := Agent → Frontier → Choice
abbrev Profile := Agent → Choice

def deviate (profile : Profile) (agent : Agent) (choice : Choice) : Profile :=
  fun a => if a = agent then choice else profile a

def BestResponse (g : Game) (profile : Profile) (agent : Agent) : Prop :=
  profile agent ∈ g.feasible agent ∧
  ∀ choice ∈ g.feasible agent,
    g.payoff (deviate profile agent choice) agent ≤ g.payoff profile agent

def bestResponseB (g : Game) (profile : Profile) (agent : Agent) : Bool :=
  (g.feasible agent).contains (profile agent) &&
  (g.feasible agent).all (fun choice =>
    g.payoff (deviate profile agent choice) agent ≤ g.payoff profile agent)

/-- Duplicates are removed so one controlling agent is counted once. -/
def coalitionUtility (members : List Agent) (payoffs : Agent → Int) : Int :=
  ((members.eraseDups).map payoffs).sum

def CoalitionDeviation (members : List Agent) (before after : Profile) : Prop :=
  ∀ a, a ∉ members → before a = after a

structure Timing where
  published : Time
  observed : Time
  submitted : Time
  included : Time
  deriving Repr

def ordered (t : Timing) : Prop :=
  t.published ≤ t.observed ∧ t.observed ≤ t.submitted ∧ t.submitted ≤ t.included

/-- A lawful inclusion of this exact sequence. Availability, observation,
submission and inclusion clocks are extra assumptions, not Step guarantees. -/
structure ProjectedEvent (p : Checkpoint.Params) (env : Checkpoint.Env) (event : Event) where
  timing : Timing
  execution : Execution p env
  publication : event.publishedAt = some timing.published
  available : observable event timing.observed = true
  chronology : ordered timing
  inclusion : execution.atTime = timing.included
  target : ∃ op payee refund,
    execution.action = .rotate event.sequence op payee refund

/-- Restricted lawful trace: only rotations and external pool top-ups.
Initial funding is start.poolHeld. This is not a full lifecycle theorem. -/
inductive FundingTrace (p : Checkpoint.Params) (env : Checkpoint.Env) :
    Time → Checkpoint.State → List Checkpoint.Flow → Checkpoint.State → Prop
  | nil (t : Time) (s : Checkpoint.State) : FundingTrace p env t s [] s
  | rotate {t t' : Time} {s s' s'' : Checkpoint.State} {f : Checkpoint.Flow} {rest : List Checkpoint.Flow}
      {sn : Checkpoint.Seq} {op : Checkpoint.BondOp} {payee : Checkpoint.Addr} {refund : Option Checkpoint.Addr}
      (time : t ≤ t') (step : Checkpoint.Step p env (.rotate sn op payee refund) t' s f s')
      (tail : FundingTrace p env t' s' rest s'') :
      FundingTrace p env t s (f :: rest) s''
  | topUp {t t' : Time} {s s' s'' : Checkpoint.State} {f : Checkpoint.Flow} {rest : List Checkpoint.Flow}
      {amount : Nat} (time : t ≤ t') (step : Checkpoint.Step p env (.topUp amount) t' s f s')
      (tail : FundingTrace p env t' s' rest s'') :
      FundingTrace p env t s (f :: rest) s''

def premiums (flows : List Checkpoint.Flow) : Nat :=
  (flows.map (fun f => Checkpoint.Payment?.pool f.hunter)).sum

def funding (flows : List Checkpoint.Flow) : Nat := (flows.map (·.poolIn)).sum

def paidCount (flows : List Checkpoint.Flow) : Nat :=
  (flows.filter (fun f => 0 < Checkpoint.Payment?.pool f.hunter)).length

/-- Mirror coverage uses the actual revocation seal-walk and actual revoked set.
This universal predicate is not executable discovery of all possible walks. -/
def RevocationCovered (s : Mirror.Sys) (rid : History.RegistryId) (said : History.Said) : Prop :=
  ∃ r, s.reg rid = some r ∧ r.revoked said = true

def MirrorComplete (p : History.Params) (env : History.TelEnv) (s : Mirror.Sys) : Prop :=
  ∀ rid r c (w : History.Walk), s.reg rid = some r → s.ckpt r.issuer = some c →
    w.tel.kind = .rev → w.tel.ri = rid →
    (History.sealWalk p env c rid w).isSome = true → RevocationCovered s rid w.tel.i

/-- Finite supplied walks can be checked; this is not completeness of the list. -/
def coveredB (s : Mirror.Sys) (rid : History.RegistryId) (said : History.Said) : Bool :=
  match s.reg rid with
  | some r => r.revoked said
  | none => false

end Freshness
