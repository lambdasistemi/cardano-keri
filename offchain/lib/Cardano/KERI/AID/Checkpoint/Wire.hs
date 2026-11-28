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
    releaseSpendRedeemerData,
    bookingAttestationBurnData,
    bookingAttestationClaimData,
    bookingAttestationIssueData,
    bookingAttestationName,
    registerObserverRedeemerData,
    registrationEvidenceData,
    asPlcData,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (blake2b_256, canonicalCbor)
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

{- | The booking attestation policy's Issue redeemer: the policy of the
application whose requests are attested, and the evidence of every request the
transaction books, each with the index of its output among the transaction's
outputs. The indices are distinct and are exactly the outputs the application's
mint books.
-}
bookingAttestationIssueData ::
    ByteString -> [(Integer, RegistrationEvidence)] -> Data
bookingAttestationIssueData applicationPolicy requests =
    Constr
        0
        [ B applicationPolicy
        , List
            [ Constr 0 [I index, registrationEvidenceData evidence]
            | (index, evidence) <- requests
            ]
        ]

-- | The booking attestation policy's Burn redeemer: nothing is minted.
bookingAttestationBurnData :: Data
bookingAttestationBurnData = Constr 1 []

{- | The claim of a booking: the action, the application policy, the zero-based
output index of the request, the exact initial datum it commits and the deposit
it commits.
-}
bookingAttestationClaimData ::
    ByteString -> Integer -> Data -> Integer -> Data
bookingAttestationClaimData applicationPolicy index initialDatum deposit =
    Constr
        0
        [ B "cardano-keri/book-registration/v1"
        , B applicationPolicy
        , I index
        , initialDatum
        , I deposit
        ]

{- | The name of the attestation of a booking: the BLAKE2b-256 of the serialised
claim.
-}
bookingAttestationName ::
    ByteString -> Integer -> Data -> Integer -> ByteString
bookingAttestationName applicationPolicy index initialDatum deposit =
    blake2b_256
        ( canonicalCbor
            ( BuiltinData
                ( bookingAttestationClaimData
                    applicationPolicy
                    index
                    initialDatum
                    deposit
                )
            )
        )

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

{- | The Freeze arm is spend constructor three, appended after the retired migration index so
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

{- | The Release spend: the pending output of a convicted checkpoint is spent in
the transaction that books its termination. Constructor five, after TopUp, so
nothing renumbers; it carries no field.
-}
releaseSpendRedeemerData :: Data
releaseSpendRedeemerData = Constr 5 []

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

-- | The Aiken @AdvanceEvidence@ record: @Constr 0@ of 5 fields.
advanceEvidenceData :: AdvanceEvidence -> Data
advanceEvidenceData AdvanceEvidence{..} =
    Constr
        0
        [ B aeEventBytes
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

-- | The Aiken @RegistrationEvidence@ record: @Constr 0@ of 3 fields.
registrationEvidenceData :: RegistrationEvidence -> Data
registrationEvidenceData RegistrationEvidence{..} =
    Constr
        0
        [ B reEventBytes
        , signatureListData reCtrlSigs
        , signatureListData reWitReceipts
        ]

-- | Aiken tuples are Data lists, not record-shaped constructors.
signatureListData :: [(Int, ByteString)] -> Data
signatureListData =
    List . map (\(index, signature) -> List [I (fromIntegral index), B signature])

asPlcData :: (ToData a) => a -> Data
asPlcData value = let BuiltinData dat = toBuiltinData value in dat
