{- |
Module      : Cardano.KERI.AID.Checkpoint.Wire
Description : PlutusData wire encoding for the Register observer

The production encoding boundary for #136. Keeping the registration encoder
in the library lets a cheap unit test pin the exact tuple/list nesting that a
live validator decodes.
-}
module Cardano.KERI.AID.Checkpoint.Wire (
    advanceSpendRedeemerData,
    advanceObserverRedeemerData,
    advanceEvidenceData,
    registerObserverRedeemerData,
    registrationEvidenceData,
    asPlcData,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Data.ByteString (ByteString)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

{- | The lifecycle observer's @ObserverEnvelope@ for @Register@: a claim
containing action zero, the checkpoint policy, and no input reference,
followed by the registration evidence.
-}
registerObserverRedeemerData ::
    ByteString -> RegistrationEvidence -> Data
registerObserverRedeemerData checkpointPolicy evidence =
    Constr
        0
        [ Constr 0 [I 0, B checkpointPolicy, Constr 1 []]
        , registrationEvidenceData evidence
        ]

{- | The small checkpoint validator keeps @Close@ at index zero and opens the
thin, evidence-free @Advance@ arm at index one.
-}
advanceSpendRedeemerData :: Data
advanceSpendRedeemerData = Constr 1 []

{- | The dedicated Advance observer envelope: action one, checkpoint policy,
the named spent output reference, and the unchanged rotation evidence.
-}
advanceObserverRedeemerData ::
    ByteString ->
    ByteString ->
    Integer ->
    AdvanceEvidence ->
    Data
advanceObserverRedeemerData checkpointPolicy spentTxId spentIndex evidence =
    Constr
        0
        [ Constr
            0
            [ I 1
            , B checkpointPolicy
            , Constr 0 [Constr 0 [B spentTxId, I spentIndex]]
            ]
        , advanceEvidenceData evidence
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

intListData :: (Integral a) => [a] -> Data
intListData = List . map (I . fromIntegral)

-- | Aiken tuples are Data lists, not record-shaped constructors.
signatureListData :: [(Int, ByteString)] -> Data
signatureListData =
    List . map (\(index, signature) -> List [I (fromIntegral index), B signature])

asPlcData :: (ToData a) => a -> Data
asPlcData value = let BuiltinData dat = toBuiltinData value in dat
