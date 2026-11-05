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
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    enforcementEvidenceData,
    enforcementProofData,
    freezeEvidenceData,
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
    topUpSpendRedeemerData,
    registerObserverRedeemerData,
    registrationEvidenceData,
    asPlcData,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Deposit (BondOption, bondOptionData)
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence)
import Cardano.KERI.AID.Checkpoint.Entitlement (EnforcementProofV1 (..))
import Cardano.KERI.AID.Checkpoint.Freeze (FreezeEvidence (..))
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

{- | The checkpoint validator's @Advance@ arm is constructor index zero. It
names the output that receives the premium when the pool covers it, then
carries the bond option: keep the bond state, or deposit the bond.
-}
advanceSpendRedeemerData :: Integer -> BondOption -> Data
advanceSpendRedeemerData payeeOutputIndex bond =
    Constr 0 [I payeeOutputIndex, bondOptionData bond]

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

{- | The Freeze arm is spend constructor three, appended after MigrateOut so
nothing renumbers; it names the output that receives the freeze bond.
-}
freezeSpendRedeemerData :: Integer -> Data
freezeSpendRedeemerData hunterOutputIndex =
    Constr 3 [I hunterOutputIndex]

{- | The TopUp arm is spend constructor four, appended after Freeze so nothing
renumbers; it carries the amount added to the pool, in lovelace.
-}
topUpSpendRedeemerData :: Integer -> Data
topUpSpendRedeemerData amount =
    Constr 4 [I amount]

{- | The Freeze observer envelope: action two, checkpoint policy, the named
spent output reference, and the freeze evidence.
-}
freezeObserverRedeemerData ::
    ByteString ->
    ByteString ->
    Integer ->
    FreezeEvidence ->
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
        , freezeEvidenceData evidence
        ]

{- | The Aiken freeze evidence record: the rotated keys, their sequence
number and the rotation evidence.
-}
freezeEvidenceData :: FreezeEvidence -> Data
freezeEvidenceData FreezeEvidence{..} =
    Constr
        0
        [ asPlcData feRotatedKeys
        , I feRotatedSn
        , advanceEvidenceData feRotation
        ]

{- | Conviction is spend constructor one; evidence remains in the isolated
observer envelope.
-}
convictSpendRedeemerData :: ByteString -> Integer -> Data
convictSpendRedeemerData convictorPkh convictorOutputIndex =
    Constr 1 [B convictorPkh, I convictorOutputIndex]

-- | The witnessed-conflict observer envelope uses isolated action four.
convictObserverRedeemerData ::
    ByteString ->
    ByteString ->
    Integer ->
    EnforcementProofV1 ->
    Data
convictObserverRedeemerData checkpointPolicy spentTxId spentIndex proof =
    Constr
        0
        [ Constr
            0
            [ I 4
            , B checkpointPolicy
            , Constr 0 [Constr 0 [B spentTxId, I spentIndex]]
            ]
        , enforcementProofData proof
        ]

{- | The Aiken @EnforcementProofV1@ record: @Constr 0@ of the complete actual
evidence, the payee this enforcement authorizes, and the reveal that names the
reservation earning it.  Field order is wire surface (#254 S254-E).
-}
enforcementProofData :: EnforcementProofV1 -> Data
enforcementProofData EnforcementProofV1{..} =
    Constr
        0
        [ enforcementEvidenceData epEvidence
        , B epPayeePkh
        , asPlcData epReveal
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

{- | The Aiken @EnforcementEvidence@ record: @Constr 0@ of 19 fields.

The field order itself lives with the type, in
"Cardano.KERI.AID.Checkpoint.Enforcement", because #254 S254-E made these
exact bytes the preimage of the canonical enforcement evidence digest.  A
second copy here would be a second thing to keep in step.
-}
enforcementEvidenceData :: EnforcementEvidence -> Data
enforcementEvidenceData = asPlcData

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
