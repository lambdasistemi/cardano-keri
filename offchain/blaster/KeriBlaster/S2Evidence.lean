import PlutusCore.UPLC

/-
Real production programs are deeply nested terms, and elaborating them into
Lean declarations exceeds the default elaborator recursion limit. Observed:
with the default limit the three largest programs
(`checkpoint.checkpoint.spend`, and both `observer_advance` validators) each
failed with "maximum recursion depth has been reached" *after* decoding
successfully, while the five smaller ones elaborated. Raising the limit is a
Lean elaboration setting on this module; it does not modify, patch, or
override the pinned dependency, and it weakens no assertion.
-/
set_option maxRecDepth 100000

/-!
# S2 production program registry and computed evidence contract

This module binds the tracked Lean proof surface to the exact production UPLC
programs. Each program is imported at elaboration time from a file that only
the flake can produce.

The paths below are resolved against this module's build directory, which
contains nothing but this source file unless the flake places the generated
artifacts beside it. `nix-generated/` is never tracked in Git; it is
materialised solely from the SHA-bound `offchain#plutus-blueprint` artifact.
If that generation is missing, incomplete, or renamed, this module fails to
elaborate and the flake-owned `blaster` runner cannot build.

Everything asserted about a program is *computed from the imported value*.
The builtin inventory is obtained by mechanically traversing the decoded term
of each of the eight `registry` entries; the residual and unsupported
classifications are derived from that traversal and from the pinned
`expectedArgs`/`evaluateBuiltinFunction` definitions. No hand-maintained
builtin list, literal inventory row, or literal evaluation result can satisfy
these definitions, and `matchesDecodedInventoryRow` exists so that a literal
row can be rejected mechanically.
-/

#import_uplc checkpointSpend PlutusV3 single_cbor_hex "nix-generated/checkpoint.checkpoint.spend.hex"
#import_uplc hashProofMint PlutusV3 single_cbor_hex "nix-generated/hash_proof.hash_proof.mint.hex"
#import_uplc observerLifecycleWithdraw PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_lifecycle.withdraw.hex"
#import_uplc observerLifecyclePublish PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_lifecycle.publish.hex"
#import_uplc observerAdvanceWithdraw PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_advance.withdraw.hex"
#import_uplc observerAdvancePublish PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_advance.publish.hex"
#import_uplc observerEnforcementWithdraw PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_enforcement.withdraw.hex"
#import_uplc observerEnforcementPublish PlutusV3 single_cbor_hex "nix-generated/checkpoint_observer.observer_enforcement.publish.hex"

namespace KeriBlaster.S2

open PlutusCore.Default (BuiltinSemanticsVariant)
open PlutusCore.UPLC.PlutusScript (PlutusScript)
open PlutusCore.UPLC.Term (Term BuiltinFun Program)
open PlutusCore.UPLC.Builtins (ExpectedBuiltinArgs expectedArgs)
open PlutusCore.UPLC.CekValue (CekValue)
open PlutusCore.UPLC.BuiltinFunctions.Evaluate (evaluateBuiltinFunction)

/-- One production program, named by its exact blueprint validator title.

The title is the selection key used to extract the program from the
blueprint; it is not evidence about the program. Everything asserted *about*
the program is derived from `program`.
-/
structure ProductionProgram where
  /-- exact `validators[].title` in the production blueprint -/
  title : String
  /-- the imported program, decoded from the generated artifact -/
  program : PlutusScript

/-- The complete production surface, in blueprint manifest order.

Each entry pairs a title with the value produced by the corresponding
`#import_uplc` directive above, so an entry cannot exist without its exact
generated artifact.
-/
def registry : List ProductionProgram :=
  [ { title := "checkpoint.checkpoint.spend"
    , program := checkpointSpend }
  , { title := "hash_proof.hash_proof.mint"
    , program := hashProofMint }
  , { title := "checkpoint_observer.observer_lifecycle.withdraw"
    , program := observerLifecycleWithdraw }
  , { title := "checkpoint_observer.observer_lifecycle.publish"
    , program := observerLifecyclePublish }
  , { title := "checkpoint_observer.observer_advance.withdraw"
    , program := observerAdvanceWithdraw }
  , { title := "checkpoint_observer.observer_advance.publish"
    , program := observerAdvancePublish }
  , { title := "checkpoint_observer.observer_enforcement.withdraw"
    , program := observerEnforcementWithdraw }
  , { title := "checkpoint_observer.observer_enforcement.publish"
    , program := observerEnforcementPublish }
  ]

/-- The registry covers the whole production surface.

This fails to elaborate if an entry is dropped while its import survives,
which an import-removal control alone would not catch.
-/
theorem registry_covers_eight_programs : registry.length = 8 := by rfl

/-! ## Mechanical decoded-term traversal

These definitions are the only permitted source of builtin inventory
evidence. They walk the decoded term of an imported program; nothing here can
be satisfied by a literal.
-/

/-- Every builtin occurrence in a decoded term, in traversal order. -/
partial def termBuiltins : Term → List BuiltinFun
  | .Var _ => []
  | .Const _ => []
  | .Builtin found => [found]
  | .Lam _ body => termBuiltins body
  | .Apply function argument => termBuiltins function ++ termBuiltins argument
  | .Delay body => termBuiltins body
  | .Force body => termBuiltins body
  | .Constr _ fields =>
      fields.foldl (fun found field => found ++ termBuiltins field) []
  | .Case scrutinee branches =>
      branches.foldl
        (fun found branch => found ++ termBuiltins branch)
        (termBuiltins scrutinee)
  | .Error => []

/-- First-occurrence-preserving deduplication. -/
def nubBuiltins (builtins : List BuiltinFun) : List BuiltinFun :=
  builtins.foldl
    (fun seen found => if seen.contains found then seen else seen ++ [found])
    []

/-- The body of a decoded program. -/
def programBody : Program → Term
  | .Program _ body => body

/-- Every distinct builtin syntactically present in one imported program. -/
def decodedBuiltins (entry : ProductionProgram) : List BuiltinFun :=
  nubBuiltins (termBuiltins (programBody entry.program.script))

/-- How many times a builtin occurs in one imported program.

Occurrence counts are syntactic. They are reported as such and never as
reachability evidence.
-/
def builtinOccurrences (wanted : BuiltinFun) (entry : ProductionProgram) :
    Nat :=
  (termBuiltins (programBody entry.program.script)).foldl
    (fun count found => if found == wanted then count + 1 else count)
    0

/-- The decoded builtin inventory of the whole registry, per title. -/
def decodedInventory : List (String × List BuiltinFun) :=
  registry.map (fun entry => (entry.title, decodedBuiltins entry))

/-- Every distinct builtin decoded anywhere in the eight programs. -/
def decodedBuiltinsAcrossRegistry : List BuiltinFun :=
  nubBuiltins (decodedInventory.foldl (fun found row => found ++ row.2) [])

/-! ## Reachability, residual, and unsupported classification

A builtin that is decoded is not thereby reached. Reachability is an
observation of the pinned CEK on an exact production invocation, supplied to
these definitions as `reached`/`dispatches`. The classifications below are
computed from that observation together with the decoded traversal and the
pinned evaluator; none of them may be emitted as a literal.
-/

/-- Decoded but never reached by the pinned CEK on the exercised invocations.

`residual = decoded - reached`.
-/
def residualBuiltins (reached : List BuiltinFun) : List BuiltinFun :=
  decodedBuiltinsAcrossRegistry.filter (fun found => !(reached.contains found))

/-- One builtin actually dispatched by the pinned CEK, with the argument
values it was dispatched on. -/
structure LiveDispatch where
  /-- the dispatched builtin -/
  builtin : BuiltinFun
  /-- the argument values the pinned CEK supplied at dispatch -/
  arguments : List CekValue

/-- The arity the pinned `expectedArgs` demands for a builtin.

`XorByteString` has no `expectedArgs` case in the pinned dependency and
therefore falls through to `One ArgV`. This function reports that pinned
fact; it does not assume the builtin is supported.
-/
def expectedArgsArity : ExpectedBuiltinArgs → Nat
  | .One _ => 1
  | .More _ rest => 1 + expectedArgsArity rest

/-- The pinned expected arity of a builtin, computed from `expectedArgs`. -/
def pinnedExpectedArity (builtin : BuiltinFun) : Nat :=
  expectedArgsArity (expectedArgs builtin)

/-- Whether the pinned evaluator produces a result for this exact dispatch. -/
def pinnedEvaluatorProduces (variant : BuiltinSemanticsVariant)
    (dispatch : LiveDispatch) : Bool :=
  (evaluateBuiltinFunction variant dispatch.builtin dispatch.arguments).isSome

/-- Reached, but the pinned evaluator returns no result for the exact
arguments the CEK dispatched on.

A non-empty result is an unsupported reached builtin. It is never a pass: it
requires preserved evidence, an upstream-defect record, and a park.
-/
def unsupportedDispatches (variant : BuiltinSemanticsVariant)
    (dispatches : List LiveDispatch) : List LiveDispatch :=
  dispatches.filter (fun dispatch => !(pinnedEvaluatorProduces variant dispatch))

/-! ## Anti-literalisation obligations

Emitted evidence must equal the computed value. These predicates are the
mechanical rejection path for a fabricated or stale row.
-/

/-- An emitted inventory row is acceptable only when it equals the row
computed from the imported program of that exact title. -/
def matchesDecodedInventoryRow (emittedTitle : String)
    (emittedBuiltins : List BuiltinFun) : Bool :=
  match decodedInventory.find? (fun row => row.1 == emittedTitle) with
  | some row => row.2 == emittedBuiltins
  | none => false

/-- An emitted whole-registry inventory is acceptable only when it equals the
computed inventory, title by title and builtin by builtin. -/
def matchesDecodedInventory (emitted : List (String × List BuiltinFun)) :
    Bool :=
  emitted == decodedInventory

/-- The number of programs the audit row may claim, computed from the
registry rather than written down. -/
def auditProgramCount : Nat := registry.length

end KeriBlaster.S2
