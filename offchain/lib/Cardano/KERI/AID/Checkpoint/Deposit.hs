{- |
Module      : Cardano.KERI.AID.Checkpoint.Deposit
Description : The deposit option of Advance (#345, Lean @Step.rotateDepositPaid@ and @Step.rotateDepositUnpaid@)

The controller's witnessed rotation may restore the freeze bond: the successor
is unfrozen and holds the bond again, and the new keys of the rotation signed an
intent that names this rotation, this output and this amount. The intent
('DepositIntent') and how its signatures are counted are the Lean's
@CardanoKeri.CheckpointDeposit@.

The verdict ('depositVerdict') is the Haskell mirror of the checkpoint spend arm
and the rotation observer for a deposit Advance: a deposit is taken exactly when
the validators take it.
-}
module Cardano.KERI.AID.Checkpoint.Deposit (
    -- * The bond option of Advance
    BondOption (..),
    bondOptionData,

    -- * The deposit intent
    DepositIntent (..),
    depositDomain,
    depositIntentData,
    depositIntentPreimage,
    DepositFacts (..),
    requiredIntent,
    depositSigned,

    -- * The deposit verdict
    DepositParams (..),
    DepositInput (..),
    DepositRefusal (..),
    depositVerdict,
) where

import Cardano.KERI.AID.CESR (aidDigest)
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence,
    AdvancePredicateError,
    advancePredicate,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    Verkey,
    keyStateView,
 )
import Cardano.KERI.AID.Checkpoint.Freeze (freezeSpentView)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold, evaluate)
import Cardano.KERI.AID.Checkpoint.Value (heldValue, withValue)
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import Data.IntSet qualified as IntSet
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins (serialiseData)
import PlutusTx.Builtins.Internal (BuiltinByteString (..), BuiltinData (..))

-- | The bond option of an Advance: keep the bond state, or deposit the bond.
data BondOption
    = -- | @BondOp.Keep@, constructor zero.
      Keep
    | {- | @BondOp.Deposit { signatures }@, constructor one: signatures as
      positions in the successor's current keys and signature bytes.
      -}
      Deposit ![(Int, ByteString)]
    deriving stock (Show, Eq)

-- | The Plutus Data of a bond option.
bondOptionData :: BondOption -> Data
bondOptionData = \case
    Keep -> Constr 0 []
    Deposit signatures ->
        Constr
            1
            [ List
                [ List [I (fromIntegral position), B signature]
                | (position, signature) <- signatures
                ]
            ]

-- | The deposit intent the new keys sign (Lean @DepositIntent@).
data DepositIntent = DepositIntent
    { diDomain :: !ByteString
    , diNetworkId :: !Integer
    , diCheckpointPolicy :: !ByteString
    , diSpentTxId :: !ByteString
    , diSpentIndex :: !Integer
    , diAid :: !ByteString
    , diNewSn :: !Integer
    , diNewEpoch :: !Integer
    , diDeposit :: !Integer
    }
    deriving stock (Show, Eq)

-- | The frozen domain tag, @cardano-keri/checkpoint/deposit/v1@.
depositDomain :: ByteString
depositDomain = BC.pack "cardano-keri/checkpoint/deposit/v1"

-- | The intent as Plutus Data, constructor zero with eight fields.
depositIntentData :: DepositIntent -> Data
depositIntentData DepositIntent{..} =
    Constr
        0
        [ B diDomain
        , I diNetworkId
        , B diCheckpointPolicy
        , Constr 0 [B diSpentTxId, I diSpentIndex]
        , B diAid
        , I diNewSn
        , I diNewEpoch
        , I diDeposit
        ]

-- | The signed bytes: the canonical CBOR of the intent's Plutus Data.
depositIntentPreimage :: DepositIntent -> ByteString
depositIntentPreimage intent =
    let BuiltinByteString bytes =
            serialiseData (BuiltinData (depositIntentData intent))
     in bytes

{- | What the validator observes beside the datum: the applied network, the
checkpoint policy and the spent output.
-}
data DepositFacts = DepositFacts
    { dfNetworkId :: !Integer
    , dfPolicy :: !ByteString
    , dfTxId :: !ByteString
    , dfOutputIndex :: !Integer
    }
    deriving stock (Show, Eq)

{- | The intent the validator requires: the freeze bond @B@, the observed
facts, the spent datum and the rotation's sequence number. 'Nothing' for a
datum that is not live.
-}
requiredIntent ::
    Integer -> DepositFacts -> CheckpointDatumV2 -> Integer -> Maybe DepositIntent
requiredIntent bond DepositFacts{..} spent newSn = case spent of
    Live{lvAid, lvEpoch, lvFrozen} ->
        Just
            DepositIntent
                { diDomain = depositDomain
                , diNetworkId = dfNetworkId
                , diCheckpointPolicy = dfPolicy
                , diSpentTxId = dfTxId
                , diSpentIndex = dfOutputIndex
                , diAid = lvAid
                , diNewSn = newSn
                , diNewEpoch = lvEpoch + 1
                , diDeposit = if lvFrozen then bond else 0
                }
    TerminationPending{} -> Nothing

{- | The keys at the threshold signed the message: the distinct verified
positions satisfy the threshold.
-}
depositSigned ::
    [Verkey] -> Threshold -> [(Int, ByteString)] -> ByteString -> Bool
depositSigned keys threshold signatures message =
    evaluate threshold (length keys) positions
  where
    positions =
        IntSet.fromList
            [ position
            | (position, signature) <- signatures
            , Just key <- [keyAt position]
            , verifyEd25519 key message signature
            ]
    keyAt position
        | position < 0 = Nothing
        | otherwise = case drop position keys of
            (key : _) -> Just key
            [] -> Nothing

-- | The deployment amounts, in lovelace, and the applied network.
data DepositParams = DepositParams
    { dpNetworkId :: !Integer
    , dpMinAda :: !Integer
    , dpDeposit :: !Integer
    , dpBond :: !Integer
    , dpPremium :: !Integer
    }
    deriving stock (Show, Eq)

-- | A deposit Advance as the validators see it.
data DepositInput = DepositInput
    { dnPolicy :: !ByteString
    , dnSpentTxId :: !ByteString
    , dnSpentIndex :: !Integer
    , dnSpentDatum :: !CheckpointDatumV2
    , dnSpentLovelace :: !Integer
    , dnSuccessorDatum :: !CheckpointDatumV2
    , dnSuccessorLovelace :: !Integer
    , dnPayeeLovelace :: !(Maybe Integer)
    -- ^ the premium payee output, when there is one
    , dnMinted :: !Bool
    -- ^ the transaction mints or burns under the checkpoint policy
    , dnSignatures :: ![(Int, ByteString)]
    , dnRotation :: !AdvanceEvidence
    }
    deriving stock (Show, Eq)

-- | Why a deposit is refused.
data DepositRefusal
    = DepositNotLive
    | DepositBelowFloor
    | DepositSuccessorFrameChanged
    | DepositSuccessorPoisoned
    | DepositSuccessorStillFrozen
    | DepositSuccessorValueMismatch
    | DepositPremiumUnpaid
    | DepositMinted
    | DepositAidNotCanonical
    | DepositNotAuthorized
    | DepositRotationRefused !AdvancePredicateError
    deriving stock (Show, Eq)

-- | The Haskell verdict of a deposit Advance: the validators' premises.
depositVerdict :: DepositParams -> DepositInput -> Either DepositRefusal ()
depositVerdict DepositParams{..} DepositInput{..} = do
    (aid, born, refund) <- case dnSpentDatum of
        Live{lvAid, lvBornAt, lvRefundTo} -> Right (lvAid, lvBornAt, lvRefundTo)
        TerminationPending{} -> Left DepositNotLive
    pool <-
        maybe
            (Left DepositBelowFloor)
            Right
            (withValue dpMinAda dpDeposit dpBond dnSpentDatum dnSpentLovelace)
    (sn', epoch', keys') <- case dnSuccessorDatum of
        Live{lvPoisoned = True} -> Left DepositSuccessorPoisoned
        Live{lvAid, lvSn, lvEpoch, lvBornAt, lvRefundTo, lvKeys}
            | lvAid == aid && lvBornAt == born && lvRefundTo == refund ->
                Right (lvSn, lvEpoch, lvKeys)
        _ -> Left DepositSuccessorFrameChanged
    when dnMinted $ Left DepositMinted
    case dnSuccessorDatum of
        Live{lvFrozen = True} -> Left DepositSuccessorStillFrozen
        _ -> Right ()
    -- The intent is the one the Lean requires for this spent state and
    -- output; the sequence number and the epoch are the successor's, which the
    -- rotation evidence then binds to the spent state.
    intent <-
        maybe
            (Left DepositNotLive)
            Right
            ( requiredIntent
                dpBond
                DepositFacts
                    { dfNetworkId = dpNetworkId
                    , dfPolicy = dnPolicy
                    , dfTxId = dnSpentTxId
                    , dfOutputIndex = dnSpentIndex
                    }
                dnSpentDatum
                sn'
            )
    unless
        ( depositSigned
            (kmCurKeys keys')
            (kmCurThreshold keys')
            dnSignatures
            (depositIntentPreimage intent{diNewEpoch = epoch'})
        )
        $ Left DepositNotAuthorized
    let covers = dpPremium <= pool
        poolAfter = if covers then pool - dpPremium else pool
    unless (dnSuccessorLovelace == heldValue dpMinAda dpDeposit dpBond dnSuccessorDatum poolAfter) $
        Left DepositSuccessorValueMismatch
    when (covers && maybe True (< dpPremium) dnPayeeLovelace) $
        Left DepositPremiumUnpaid
    rawAid <- maybe (Left DepositAidNotCanonical) Right (aidDigest aid)
    spent <-
        maybe
            (Left DepositAidNotCanonical)
            Right
            (freezeSpentView dnPolicy dnSpentTxId dnSpentIndex dnSpentDatum)
    first DepositRotationRefused $
        advancePredicate spent (keyStateView rawAid sn' epoch' keys') dnRotation
