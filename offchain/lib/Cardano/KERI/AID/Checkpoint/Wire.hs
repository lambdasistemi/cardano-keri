{- |
Module      : Cardano.KERI.AID.Checkpoint.Wire
Description : PlutusData wire encoding for the Register observer

The production encoding boundary for #136. Keeping the registration encoder
in the library lets a cheap unit test pin the exact tuple/list nesting that a
live validator decodes.
-}
module Cardano.KERI.AID.Checkpoint.Wire (
    closeBurnRedeemerData,
    advanceSpendRedeemerData,
    advanceObserverRedeemerData,
    responseAdvanceObserverRedeemerData,
    advanceEvidenceData,
    claimFreezeSpendRedeemerData,
    convictBurnRedeemerData,
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    freezeSpendRedeemerData,
    freezeObserverRedeemerData,
    enforcementEvidenceData,
    registerObserverRedeemerData,
    registrationEvidenceData,
    asPlcData,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Registration (RegistrationEvidence (..))
import Data.ByteString (ByteString)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

{- | CloseBurn is the second mint constructor and names the exact checkpoint
input whose singleton token must be burned.
-}
closeBurnRedeemerData :: ByteString -> Integer -> Data
closeBurnRedeemerData spentTxId spentIndex =
    Constr 1 [Constr 0 [B spentTxId, I spentIndex]]

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
advanceObserverRedeemerData = advanceObserverRedeemerDataWithAction 1

{- | The Armed response-Advance observer envelope uses action three so the
heavy observer can select the Armed datum wire without repeating role-address
derivation already enforced by the thin checkpoint arm.
-}
responseAdvanceObserverRedeemerData ::
    ByteString ->
    ByteString ->
    Integer ->
    AdvanceEvidence ->
    Data
responseAdvanceObserverRedeemerData = advanceObserverRedeemerDataWithAction 3

advanceObserverRedeemerDataWithAction ::
    Integer ->
    ByteString ->
    ByteString ->
    Integer ->
    AdvanceEvidence ->
    Data
advanceObserverRedeemerDataWithAction action checkpointPolicy spentTxId spentIndex evidence =
    Constr
        0
        [ Constr
            0
            [ I action
            , B checkpointPolicy
            , Constr 0 [Constr 0 [B spentTxId, I spentIndex]]
            ]
        , advanceEvidenceData evidence
        ]

{- | The small checkpoint keeps @Close@ at index zero and @Advance@ at index
one. Story #137 opens only the thin @Freeze { hunter_pkh }@ constructor at
index two; @ClaimFreeze@ remains absent and therefore fail-closed.
-}
freezeSpendRedeemerData :: ByteString -> Data
freezeSpendRedeemerData hunterPkh = Constr 2 [B hunterPkh]

{- | Story #138 opens only @ClaimFreeze { hunter_output_index }@ at
constructor index three. The index names the exact hunter payout output.
-}
claimFreezeSpendRedeemerData :: Integer -> Data
claimFreezeSpendRedeemerData hunterOutputIndex =
    Constr 3 [I hunterOutputIndex]

{- | Conviction burns the token under mint constructor two and names the exact
checkpoint input.
-}
convictBurnRedeemerData :: ByteString -> Integer -> Data
convictBurnRedeemerData spentTxId spentIndex =
    Constr 2 [Constr 0 [B spentTxId, I spentIndex]]

{- | Conviction is spend constructor four; evidence remains in the isolated
observer envelope.
-}
convictSpendRedeemerData :: ByteString -> Integer -> Integer -> Data
convictSpendRedeemerData convictorPkh convictorOutputIndex hunterOutputIndex =
    Constr
        4
        [ B convictorPkh
        , I convictorOutputIndex
        , I hunterOutputIndex
        ]

{- | The enforcement observer envelope for @Freeze@: stable action two, the
applied checkpoint policy, the named spent output reference, and the unchanged
enforcement evidence.
-}
freezeObserverRedeemerData ::
    ByteString ->
    ByteString ->
    Integer ->
    EnforcementEvidence ->
    Data
freezeObserverRedeemerData checkpointPolicy spentTxId spentIndex evidence =
    Constr
        0
        [ Constr
            0
            [ I 2
            , B checkpointPolicy
            , Constr 0 [Constr 0 [B spentTxId, I spentIndex]]
            ]
        , enforcementEvidenceData evidence
        ]

-- | The witnessed-conflict observer envelope uses isolated action four.
convictObserverRedeemerData ::
    ByteString ->
    ByteString ->
    Integer ->
    EnforcementEvidence ->
    Data
convictObserverRedeemerData checkpointPolicy spentTxId spentIndex evidence =
    Constr
        0
        [ Constr
            0
            [ I 4
            , B checkpointPolicy
            , Constr 0 [Constr 0 [B spentTxId, I spentIndex]]
            ]
        , enforcementEvidenceData evidence
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
