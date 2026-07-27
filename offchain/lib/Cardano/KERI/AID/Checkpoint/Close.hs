{- |
Module      : Cardano.KERI.AID.Checkpoint.Close
Description : #117 S1 controller-authorized Close message and predicate

Validator-free Close support.  The signed preimage is reconstructed from a
trusted deployment, the named spent outref, OLD, and the evidence's full refund
address.  Controller evidence is indexed into OLD's current key set; only
distinct positions with valid Ed25519 signatures are passed to the shared KERI
threshold evaluator.

'FullAddress' deliberately mirrors Aiken's @cardano/address.Address@ Plutus
Data representation, including inline and pointer stake credentials.  It is a
wire type only: the live validator supplies the ledger-native Aiken address.
-}
module Cardano.KERI.AID.Checkpoint.Close (
    -- * Full Aiken Address mirror
    AddressCredential (..),
    StakeCredential (..),
    FullAddress (..),

    -- * Close wire types
    closeDomain,
    CloseMessage (..),
    CloseEvidence (..),
    CloseContext (..),
    reconstructCloseMessage,
    closeEvidenceData,
    closeSpendRedeemerData,

    -- * Current-controller authorization
    ClosePredicateError (..),
    closePredicate,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    canonicalCbor,
    datumWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (evaluate)
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.IntSet qualified as IntSet
import Data.Text.Encoding qualified as TE
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (ToData (..))

-- ---------------------------------------------------------
-- Full Address Plutus Data mirror
-- ---------------------------------------------------------

-- | Aiken @Credential@: verification key is constructor 0, script is 1.
data AddressCredential
    = VerificationKeyCredential !ByteString
    | ScriptCredential !ByteString
    deriving stock (Show, Eq)

-- | Aiken @Referenced<Credential>@: inline is constructor 0, pointer is 1.
data StakeCredential
    = InlineStakeCredential !AddressCredential
    | PointerStakeCredential !Integer !Integer !Integer
    deriving stock (Show, Eq)

-- | Byte-identical Haskell mirror of Aiken @Address@ (constructor 0).
data FullAddress = FullAddress
    { faPaymentCredential :: !AddressCredential
    , faStakeCredential :: !(Maybe StakeCredential)
    }
    deriving stock (Show, Eq)

asData :: (ToData a) => a -> Data
asData value = let BuiltinData d = toBuiltinData value in d

instance ToData AddressCredential where
    toBuiltinData = \case
        VerificationKeyCredential hash -> BuiltinData (Constr 0 [B hash])
        ScriptCredential hash -> BuiltinData (Constr 1 [B hash])

instance ToData StakeCredential where
    toBuiltinData = \case
        InlineStakeCredential credential ->
            BuiltinData (Constr 0 [asData credential])
        PointerStakeCredential slot txIndex certIndex ->
            BuiltinData (Constr 1 [I slot, I txIndex, I certIndex])

instance ToData FullAddress where
    toBuiltinData FullAddress{..} =
        BuiltinData $
            Constr
                0
                [ asData faPaymentCredential
                , case faStakeCredential of
                    Just credential -> Constr 0 [asData credential]
                    Nothing -> Constr 1 []
                ]

-- ---------------------------------------------------------
-- Close message, context, and evidence
-- ---------------------------------------------------------

-- | @UTF8("cardano-keri/checkpoint/close/v1")@.
closeDomain :: ByteString
closeDomain = TE.encodeUtf8 "cardano-keri/checkpoint/close/v1"

-- | Frozen constructor-0 Close message with ten fields in protocol order.
data CloseMessage = CloseMessage
    { cmDomain :: !ByteString
    , cmNetworkId :: !Integer
    , cmCheckpointPolicyId :: !ByteString
    , cmAidAssetName :: !ByteString
    , cmCesrAid :: !ByteString
    , cmSpentTxid :: !ByteString
    , cmSpentIndex :: !Integer
    , cmPriorSeq :: !Integer
    , cmPriorNativeSn :: !Integer
    , cmRefundAddress :: !FullAddress
    }
    deriving stock (Show, Eq)

instance ToData CloseMessage where
    toBuiltinData CloseMessage{..} =
        BuiltinData $
            Constr
                0
                [ B cmDomain
                , I cmNetworkId
                , B cmCheckpointPolicyId
                , B cmAidAssetName
                , B cmCesrAid
                , B cmSpentTxid
                , I cmSpentIndex
                , I cmPriorSeq
                , I cmPriorNativeSn
                , asData cmRefundAddress
                ]

-- | The only prover-supplied Close fields.
data CloseEvidence = CloseEvidence
    { ceRefundAddress :: !FullAddress
    , ceCtrlSigs :: ![(Int, ByteString)]
    }
    deriving stock (Show, Eq)

-- | Trusted inputs used to reconstruct the signed Close preimage.
data CloseContext = CloseContext
    { ccNetworkId :: !Integer
    , ccCheckpointPolicyId :: !ByteString
    , ccSpentTxid :: !ByteString
    , ccSpentIndex :: !Integer
    , ccOld :: !CheckpointDatumV1
    }
    deriving stock (Show, Eq)

-- | Exact Aiken wire shape for @CloseEvidence@.
closeEvidenceData :: CloseEvidence -> Data
closeEvidenceData CloseEvidence{..} =
    Constr
        0
        [ asData ceRefundAddress
        , List
            [ List [I (fromIntegral index), B signature]
            | (index, signature) <- ceCtrlSigs
            ]
        ]

-- | Exact spending-redeemer wire shape for @SpendRedeemer.Close@.
closeSpendRedeemerData :: CloseEvidence -> Data
closeSpendRedeemerData evidence = Constr 0 [closeEvidenceData evidence]

-- | Reconstruct all message fields except the evidence's full refund address.
reconstructCloseMessage :: CloseContext -> CloseEvidence -> CloseMessage
reconstructCloseMessage CloseContext{..} CloseEvidence{..} =
    CloseMessage
        { cmDomain = closeDomain
        , cmNetworkId = ccNetworkId
        , cmCheckpointPolicyId = ccCheckpointPolicyId
        , cmAidAssetName = deriveAidAssetName (cdCesrAid ccOld)
        , cmCesrAid = cdCesrAid ccOld
        , cmSpentTxid = ccSpentTxid
        , cmSpentIndex = ccSpentIndex
        , cmPriorSeq = cdSeq ccOld
        , cmPriorNativeSn = cdNativeSn ccOld
        , cmRefundAddress = ceRefundAddress
        }

-- ---------------------------------------------------------
-- Current-controller predicate
-- ---------------------------------------------------------

data ClosePredicateError
    = -- | OLD failed the shared datum well-formedness predicate.
      CloseDatumInvalid
    | -- | Distinct verifying current-key indices did not satisfy the threshold.
      CloseControllerQuorumUnsatisfied
    deriving stock (Show, Eq)

-- | Verify Close authorization against OLD's current controller set.
closePredicate ::
    CloseContext -> CloseEvidence -> Either ClosePredicateError ()
closePredicate context@CloseContext{ccOld = old} evidence@CloseEvidence{..} = do
    case datumWellFormed old of
        Left _ -> Left CloseDatumInvalid
        Right () -> pure ()
    let preimage = canonicalCbor (reconstructCloseMessage context evidence)
        signed =
            IntSet.fromList
                [ index
                | (index, signature) <- ceCtrlSigs
                , Just key <- [cdCurKeys old `atMay` index]
                , verifyEd25519 key preimage signature
                ]
    unless
        (evaluate (cdCurThreshold old) (length (cdCurKeys old)) signed)
        (Left CloseControllerQuorumUnsatisfied)

atMay :: [a] -> Int -> Maybe a
atMay values index
    | index < 0 = Nothing
    | otherwise = case drop index values of
        value : _ -> Just value
        [] -> Nothing
