import CardanoKeri.ApplicationVectors

/-! The pending-input read through the concrete checkpoint datum codec. The
epoch and native sequence differ so exchanging the fields changes the result. -/
open CardanoKeri CardanoKeri.Application CardanoKeri.Application.Vectors
open CardanoKeri.ConsumerIdentity.Bytes (aidOfCesr)
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (aidE)

def main (_ : List String) : IO UInt32 := do
  let aid := aidOfCesr aidE
  let position : Checkpoint.KeyState := ⟨2, 7⟩
  let raw := CheckpointDatum.raw (checkpointData aidE (.terminationPending position))
  let input := { convicted (datum := raw) with reference := ⟨105, 3⟩ }
  unless accepted i env rp cp release (terminationBooking (input := input)) do
    throw (IO.userError "fixture termination booking refused")
  let expected : PendingSpend := ⟨input.reference, aid, position⟩
  unless readPendingSpend i rp scenarioConfiguration registry aid input = some expected do
    IO.println "pending-receipt-changed"
    return 1
  IO.println "PASS termination booking reads the spent reference, identifier, epoch and native sequence"
  return 0
