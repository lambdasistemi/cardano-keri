import Lean
import CardanoKeri.Statements

open Lean Elab Command

-- Compiled declarations, including axioms of the explicitly numbered goals.
run_cmd do
  let env ← getEnv
  let mut constructors : List (String × Json) := []
  for name in [``CardanoKeri.History.HAction, ``CardanoKeri.Mirror.Action,
               ``CardanoKeri.Credential.Action, ``CardanoKeri.Delegation.Action] do
    match env.find? name with
    | some (.inductInfo info) =>
        constructors := constructors ++ [(name.toString, toJson (info.ctors.map Name.toString))]
    | _ => throwError "missing compiled inductive {name}"
  let mut statements : List (String × Json) := []
  for (name, info) in env.constants.toList do
    if let .thmInfo _ := info then
      let n := name.toString
      let numbered := ["CardanoKeri.History.H", "CardanoKeri.History.S",
        "CardanoKeri.Mirror.M", "CardanoKeri.Credential.C", "CardanoKeri.Delegation.D"].any
        fun stem => stem.isPrefixOf n &&
          ((n.drop stem.length).toString.toList.head?.map Char.isDigit).getD false
      if numbered then
        let axioms ← collectAxioms name
        statements := (n, toJson (axioms.toList.map Name.toString)) :: statements
  logInfo (Json.mkObj [("constructors", Json.mkObj constructors),
    ("statements", Json.mkObj statements)]).compress
