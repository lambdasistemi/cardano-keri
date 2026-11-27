import CardanoKeri.ApplicationVectors
import CardanoKeri.ApplicationPrefixGoals

open CardanoKeri CardanoKeri.Application CardanoKeri.Application.Vectors Duplicity
open SingularApplicationHeld
open CardanoKeri.ConsumerIdentity.Bytes (aidOfCesr)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (aidB aidE)

/- The example bytes and partial decoder stand for a decoded signed event.
The companion Python check independently constructs, serializes and signs
the corresponding keripy events. -/
private def identifier (code : String) : String :=
  if code == "E" then aidE else code ++ (aidB.drop 1).toString

private def body (code : String) (next : List Nat := []) : Content :=
  let aid := aidOfCesr (identifier code)
  ⟨aid, 0, .inception, 0, [aid], .count 1, next, .count next.length, [], [], 0, []⟩

private def evidence (b : Content) (ws : List Nat := []) : InceptionPrefix.Evidence :=
  ⟨⟨b, true, b.keys.map (fun key => ⟨key, b, true⟩), ws.map (fun w => ⟨w, b, true⟩)⟩, ws⟩

private def payload (c : String) (keys : InceptionPrefix.KeyState) : Nat :=
  -- A fixture encoder for the normalized datum projection; keep each shape distinct.
  (Lean.toJson (c, keys.keys, keys.threshold, keys.nextKeys, keys.nextThreshold, keys.witnesses, keys.toad)).compress.toUTF8.data.toList.foldl
    (fun n b => 256 * n + b.toNat) 1

private def book (code : String) (e : InceptionPrefix.Evidence)
    (digest : Option Nat := none) (bytes : List (Option (List UInt8)) := [some [1]])
    (keyState := e.keyState) (hasEvidence := true) : Bool := Id.run do
  let aid := aidOfCesr (identifier code)
  let raw := payload code keyState
  let data := {requestData 15 with key := aid, initialDatum := raw}
  let interp := {i with
    decode := fun n => if n == 9001 then some (.registration data) else none
    decodeCheckpoint := fun n => if n == raw then some ⟨aid, (initialFacts).datumFacts⟩ else none }
  let reads : InceptionPrefix.Reads := {
    decodeEvidence := fun bs => if bs == [1] then some e else none
    prefixCode := fun id => if id == aid then some code else none
    deriveIdentifier := fun bs => if bs == [1] then digest else none
    datumKeys := fun n => if n == raw then some keyState else none }
  let approval := registrationAsset interp.hash interp.code release data
  let tx := booking 9001 18
  let output := { request 9001 18 with assets := [(approval, 1)] }
  return accepted interp {inception := fun _ => hasEvidence, opening := reads} rp cp release
    {tx with outputs := [output], assets.mint := [(approval, 1)], signedInceptions := bytes}

private def regular (code : String) (b : Content) :=
  book code (evidence b) (some (aidOfCesr (identifier code)))

private def witnessed (code : String) :=
  evidence {body code with witnessThreshold := 1} [17]

private def prefixCases : List (String × Bool) := [
  ("B empty", regular "B" (body "B")), ("D empty", regular "D" (body "D")),
  ("B next", regular "B" (body "B" [22])), ("D next", regular "D" (body "D" [22])),
  ("B witness", book "B" (witnessed "B")), ("D witness", book "D" (witnessed "D")),
  ("B seal", regular "B" {body "B" with extension := [7]}), ("D seal", regular "D" {body "D" with extension := [7]}),
  ("D weighted one", regular "D" {body "D" with threshold := .weighted [[.key ⟨1,1⟩]]}),
  ("E digest", regular "E" (body "E")),
  ("D missing next", regular "D" {body "D" with nextThreshold := .count 1}),
  ("D oversized next", regular "D" {body "D" [22] with nextThreshold := .count 2}),
  ("B missing next", regular "B" {body "B" with nextThreshold := .count 1}),
  ("E zero signing", regular "E" {body "E" with threshold := .count 0}),
  ("D zero next with digest", regular "D" {body "D" [22] with nextThreshold := .count 0})]

private def future (next : List Nat) (clauses : List (List Weight)) :=
  regular "D" {body "D" next with nextThreshold := .weighted clauses}

private def futureCases : List (String × Bool) :=
  let half := Weight.key ⟨1, 2⟩
  let third := Weight.key ⟨1, 3⟩
  let one := Weight.key ⟨1, 1⟩
  [("D next below one", future [21,22] [[third, third]]),
   ("D next unreduced", future [21,22] [[.key ⟨2,4⟩, .key ⟨2,4⟩]]),
   ("D next partial coverage", future [21,22,23] [[one], [one]]),
   ("D weighted next without commitments", future [] [[one]]),
   ("D next exact one", future [21,22] [[half, half]]),
   ("D next second clause below one", future [21,22] [[one], [third]]),
   ("D next inner below one", future [21,22,23] [[one, .group ⟨1,2⟩ [⟨1,3⟩, ⟨1,3⟩]]]),
   ("D next nested exact one", future [21,22,23] [[half, .group ⟨1,2⟩ [⟨1,2⟩, ⟨1,2⟩]]]),
   ("D next no clauses", future [] [])]

private def refusals : List Bool :=
  let e := evidence (body "D")
  [regular "D" {body "D" with keys := [12]}, regular "D" {body "D" with keys := [12,13]},
   book "E" (evidence (body "E")) (some 12), book "E" (evidence (body "E")),
   book "D" {e with signed.signatures := []}, book "D" {(witnessed "D") with signed.receipts := []},
   book "D" e (bytes := [none, some [1]]), book "D" e (bytes := [some [2]]),
   book "D" e (keyState := {e.keyState with nextKeys := [50]}), book "D" e (hasEvidence := false),
   regular "X" (body "X"), regular "D" {body "D" with kind := .delegatedInception},
   regular "D" {body "D" [22] with nextThreshold := .weighted [[.key ⟨3,2⟩]]}]

def main : IO Unit := do
  if refusals.any id then throw (IO.userError "An inconsistent booking was admitted")
  IO.println (Lean.toJson (prefixCases ++ futureCases)).compress
