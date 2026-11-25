import CardanoKeri.CheckpointDatum
import CardanoKeri.CheckpointLifecycleExamples

/-! Size study for an inline writer opening. These Plutus Data terms are
measurement fixtures. Selecting a production wire layout and measuring a
validator transaction are separate tasks. Each small identity in the fixtures
is represented by a distinct 32-byte value, the AID by 44 bytes and the refund
address by 28. The variable extension contains the bytes of example seals. -/
open CardanoKeri Checkpoint CheckpointDatum

namespace WriterSizeStudy

private def identifier (width n : Nat) : Data := .bytes (List.replicate (width - 1) 0 ++ [n])
private def identities (xs : List Nat) : Data := .list (xs.map (identifier 32))
private def fraction (w : Duplicity.Fraction) : Data := .list [.int w.numerator, .int w.denominator]
private def weight : Duplicity.Weight → Data
  | .key w => .constr 0 [fraction w]
  | .group w members => .constr 1 [fraction w, .list (members.map fraction)]
private def threshold : Duplicity.Threshold → Data
  | .count n => .constr 0 [.int n]
  | .weighted cs => .constr 1 [.list (cs.map fun c => .list (c.map weight))]
private def kind : Duplicity.EventKind → Nat
  | .inception => 0 | .rotation => 1 | .interaction => 2
  | .delegatedInception => 3 | .delegatedRotation => 4
private def opening (e : Duplicity.Content) : Data :=
  .list [identifier 44 e.aid, .int e.sn, .int (kind e.kind), identifier 32 e.priorDigest,
    identities e.keys, threshold e.threshold, identities e.nextKeys, threshold e.nextThreshold,
    identities e.cuts, identities e.adds, .int e.witnessThreshold, .bytes e.extension]
private def prior : Option Duplicity.Predecessor → Data
  | none => .constr 0 []
  | some p => .constr 1 [identifier 44 p.aid, .int p.sn, boolData p.delegated,
    identities p.nextKeys, threshold p.nextThreshold, identities p.witnesses]

-- Each field of the live state and writer needed at use is present. The pool
-- lives in the value. Current key fields shared with the opening occur once.
private def datum (l : Live) (d : WriterDatum) : Data :=
  .constr 0 [.int l.sn, .int l.epoch, boolData l.poisoned, boolData l.frozen,
    .int l.bornAt, identifier 28 l.refundTo, boolData l.toppedUp,
    opening d.writer, identities d.witnesses, prior d.previous]

private def sample (name : String) (live : Live) (d : WriterDatum) : Lean.Json :=
  Lean.Json.mkObj [("case", Lean.toJson name),
    ("liveBytes", Lean.toJson (cbor (datum live d)).length),
    ("writerOpeningBytes", Lean.toJson (cbor (opening d.writer)).length),
    ("previousBytes", Lean.toJson (cbor (prior d.previous)).length)]

def results : List Lean.Json :=
  let base := Examples.origin.inception.datum
  let one := base.advance (Duplicity.writerFixture 11 1 .rotation).event
  let two := one.advance (Duplicity.writerFixture 11 2 .rotation).event
  let grouped : Duplicity.Threshold := .weighted [[.group ⟨1,1⟩ [⟨1,1⟩]]]
  let groupedWriter := { one.writer with
    threshold := grouped, nextThreshold := grouped, extension := List.replicate 64 12 }
  let rich := { one with writer := groupedWriter }
  [sample "registration" Examples.live base, sample "first-rotation" Examples.rotatedLive one,
   sample "second-rotation" {Examples.rotatedLive with epoch := 2, sn := 2} two,
   sample "grouped-with-64-seal-bytes" Examples.rotatedLive rich]
end WriterSizeStudy

def main : IO Unit := IO.println (Lean.toJson WriterSizeStudy.results).compress
