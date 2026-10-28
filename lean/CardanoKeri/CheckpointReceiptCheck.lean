import CardanoKeri.Checkpoint
import CardanoKeri.RegistryReplay

/-! Executable fields of the stored-association receipt check. Origin identity
and extending history are separate obligations. The iff theorem explicitly
requires them; the field checker alone cannot certify a system completion. -/
namespace CardanoKeri.Checkpoint

def receiptFieldsB (s : Sys) (aid : AID) (association : PendingAssociation)
    (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters
      association.origin.environment association.origin.configuration) : Bool :=
  decide (s.states aid = .terminationPending association.keyState) &&
  decide (receipt.before.config = {
    association.origin.registered.config with root := receipt.before.config.root }) &&
  decide (CardanoKeri.Registry.pendingAt receipt.before association.reference = some association.entry) &&
  CardanoKeri.Registry.completesB receipt association.reference aid association.origin.token

/-- Given the stored pending association, its same stored origin and an actual
extending Registry history under that origin's context, when the field checker
accepts a context-indexed receipt, then and only then the whole ReceiptMatches
proposition holds. A foreign context is excluded by the receipt type, not by
this Boolean check. -/
theorem receiptFieldsB_iff (s : Sys) (aid : AID) (association : PendingAssociation)
    (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters
      association.origin.environment association.origin.configuration)
    (pending : s.pending aid = some association)
    (origin : s.origins aid = some association.origin)
    (history : CardanoKeri.Registry.History association.origin.parameters
      association.origin.environment association.booked receipt.before) :
    receiptFieldsB s aid association receipt = true ↔ ReceiptMatches s aid association receipt := by
  simp [receiptFieldsB, ReceiptMatches, pending, origin, history,
    CardanoKeri.Registry.completesB_iff, and_assoc]

end CardanoKeri.Checkpoint
