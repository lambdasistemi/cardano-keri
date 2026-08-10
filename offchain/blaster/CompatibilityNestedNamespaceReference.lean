import PlutusCore.ByteString

/-!
Reviewer-contributed AUD-4 seed from the closed mandate-v1 campaign.

The first name was fabricated by the old textual declaration indexer: Lean
appends a nested namespace declaration to the current namespace, while that
indexer reset the namespace stack.  The second name is the declaration Lean
actually creates at the pinned PlutusCoreBlaster revision.  The compatibility
oracle must reject the fabricated name and accept the real name in the same
environment, proving agreement with the elaborator in both directions.

This file is an audit input only.  It is not imported by the tracked bridge.
-/

#check PlutusCore.ByteStringInternal.appendByteString
#check PlutusCore.ByteString.PlutusCore.ByteStringInternal.appendByteString
