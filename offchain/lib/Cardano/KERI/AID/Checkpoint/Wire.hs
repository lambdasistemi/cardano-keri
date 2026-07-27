{- |
Module      : Cardano.KERI.AID.Checkpoint.Wire
Description : Off-chain PlutusData wire encoders for the checkpoint evidence families

The Haskell side of the off-chain\/on-chain encoding boundary: the
'Data' spellings the transaction builder hands to the checkpoint
lifecycle, advance and enforcement observers, which the Aiken
validators decode as @RegistrationEvidence@, @AdvanceEvidence@ and
@EnforcementEvidence@.

These encoders previously lived privately inside the devnet-only
@CheckpointTxBuilder@ e2e module, where no offline suite compiled
them and the only shape assertion compared an encoder's output
against that same encoder. They live here so the wire spelling is a
library seam an offline test can address directly (A-045).
-}
module Cardano.KERI.AID.Checkpoint.Wire (
    -- * Observer redeemer envelope
    registerObserverRedeemerData,

    -- * Evidence payloads
    registrationEvidenceData,
    advanceEvidenceData,
    enforcementEvidenceData,

    -- * Field encoders
    intListData,
    signatureListData,
    asPlcData,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Data.ByteString (ByteString)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

{- | The lifecycle observer's @ObserverEnvelope@ for the @Register@
claim: the claim triple (action, checkpoint policy bytes, own-ref)
followed by the registration evidence payload.

The checkpoint policy is taken as raw bytes rather than a ledger
@PolicyID@; the body only ever needed the policy's bytes, and the
narrower argument keeps this module free of a ledger dependency.
-}
registerObserverRedeemerData ::
    ByteString -> RegistrationEvidence -> Data
registerObserverRedeemerData checkpointPolicy evidence =
    Constr
        0
        [ Constr
            0
            [ I 0
            , B checkpointPolicy
            , Constr 1 []
            ]
        , registrationEvidenceData evidence
        ]

-- | The Aiken @RegistrationEvidence@ record: @Constr 0@ of 12 fields.
registrationEvidenceData :: RegistrationEvidence -> Data
registrationEvidenceData RegistrationEvidence{..} =
    Constr
        0
        [ B reEventBytes
        , I (fromIntegral reOffT)
        , I (fromIntegral reOffI)
        , I (fromIntegral reOffS)
        , intListData reOffK
        , I (fromIntegral reOffKt)
        , intListData reOffN
        , I (fromIntegral reOffNt)
        , intListData reOffB
        , I (fromIntegral reOffBt)
        , signatureListData reCtrlSigs
        , signatureListData reWitReceipts
        ]

-- | The Aiken @AdvanceEvidence@ record: @Constr 0@ of 15 fields.
advanceEvidenceData :: AdvanceEvidence -> Data
advanceEvidenceData AdvanceEvidence{..} =
    Constr
        0
        [ B aeEventBytes
        , I (fromIntegral aeOffT)
        , I (fromIntegral aeOffI)
        , I (fromIntegral aeOffS)
        , intListData aeOffK
        , I (fromIntegral aeOffKt)
        , intListData aeOffN
        , I (fromIntegral aeOffNt)
        , intListData aeOffBr
        , intListData aeOffBa
        , I (fromIntegral aeOffBt)
        , List (map B aeWitCut)
        , List (map B aeWitAdd)
        , signatureListData aeCtrlSigs
        , signatureListData aeWitReceipts
        ]

-- | The Aiken @EnforcementEvidence@ record: @Constr 0@ of 19 fields.
enforcementEvidenceData :: EnforcementEvidence -> Data
enforcementEvidenceData EnforcementEvidence{..} =
    Constr
        0
        [ B eneEventBytes
        , I (fromIntegral eneOffT)
        , I (fromIntegral eneOffI)
        , I (fromIntegral eneOffS)
        , I (fromIntegral eneOffD)
        , intListData eneOffK
        , I (fromIntegral eneOffKt)
        , intListData eneOffN
        , I (fromIntegral eneOffNt)
        , I (fromIntegral eneOffBt)
        , I eneNativeSn
        , B eneSaid
        , List (map B eneRevealedKeys)
        , List (map B eneNextKeys)
        , asPlcData eneCurThreshold
        , asPlcData eneNextThreshold
        , I eneToad
        , signatureListData eneCtrlSigs
        , signatureListData eneWitSigs
        ]

-- | A @List<Int>@ offset vector.
intListData :: (Integral a) => [a] -> Data
intListData = List . map (I . fromIntegral)

-- | A @List<(Int, ByteArray)>@ indexed-signature collection.
signatureListData :: [(Int, ByteString)] -> Data
signatureListData =
    List . map (\(index, signature) -> List [I (fromIntegral index), B signature])

-- | Reuse a type's own 'ToData' instance as a raw 'Data' spelling.
asPlcData :: (ToData a) => a -> Data
asPlcData value = let BuiltinData dat = toBuiltinData value in dat
