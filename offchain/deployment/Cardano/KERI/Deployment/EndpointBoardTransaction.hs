{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.EndpointBoardTransaction
Description : Build and settle endpoint-board actions in process

The plans in this module are the off-chain mirror of the frozen board
validator. The shared transaction kernel builds, evaluates, signs, derives the
pure id, submits exactly the signed value, and observes settlement without an
external command or temporary transaction files.
-}
module Cardano.KERI.Deployment.EndpointBoardTransaction (
    BoardPostPlan (..),
    BoardUpdatePlan (..),
    BoardRetirePlan (..),
    BoardConfig (..),
    BoardCheckError (..),
    BoardError (..),
    BoardObservationTimeout (..),
    BoardResult (..),
    BoardAuthorizationPayload (..),
    BoardAuthorizationError (..),
    mkBoardAuthorizationPayload,
    attachBoardAuthorization,
    selectBoardEntry,
    mkBoardPostPlan,
    mkBoardUpdatePlan,
    mkBoardRetirePlan,
    runBoardPostTransaction,
    runBoardUpdateTransaction,
    runBoardRetireTransaction,
    awaitBoard,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    FullAddress (..),
 )
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.Close (decodeRefundAddress)
import Cardano.KERI.Deployment.EndpointBoard (
    BoardAuthorizationV2 (..),
    BoardDatumV2 (..),
    BoardEntry (..),
    BoardNonce (..),
    EndpointRecord (..),
    boardAuthorizationBytes,
    boardAuthorizationDomain,
    verifyBoardAuthorization,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    endpointBoardManifestSchema,
    frozenEndpointBoardAddress,
    frozenEndpointBoardPolicyId,
 )
import Cardano.KERI.Deployment.Manifest (
    NetworkInfo (..),
    Reference (..),
 )
import Cardano.KERI.Deployment.Registration (
    plutusDataFromJson,
    plutusDataJson,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    AggregateExUnitsError,
    CollateralContract (..),
    FundingPair (..),
    PayerSelectionError,
    TransactionBuildError,
    TransactionRuntime (..),
    checkAggregateExUnits,
    fundingSpends,
    runPlutusTransactionBuild,
    selectFundingPair,
 )
import Cardano.Ledger.Address (Addr (..), decodeAddr)
import Cardano.Ledger.Api.Tx.Out (referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (
    PParams,
    TxOut,
    hashScript,
    mkBasicTxOut,
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash (..),
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Keys (KeyRole (Guard))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Tx.Build (
    Check (..),
    InterpretIO (..),
    TxBuild,
    mint,
    output,
    payTo',
    reference,
    requireSignature,
    spend,
    spendScript,
    valid,
 )
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Data.Aeson (Value)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Lens.Micro ((^.))
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Text.Read (readMaybe)

data BoardPostPlan = BoardPostPlan
    { boardPostPolicy :: !Text
    , boardPostAddress :: !Text
    , boardPostReference :: !Text
    , boardPostAssetName :: !Text
    , boardPostDepositLovelace :: !Integer
    , boardPostOutput :: !Text
    , boardPostDatum :: !Value
    , boardPostMintRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data BoardUpdatePlan = BoardUpdatePlan
    { boardUpdatePolicy :: !Text
    , boardUpdateAddress :: !Text
    , boardUpdateReference :: !Text
    , boardUpdateSpentReference :: !Text
    , boardUpdateAssetName :: !Text
    , boardUpdateDepositLovelace :: !Integer
    , boardUpdateOwnerKeyHash :: !Text
    , boardUpdateOutput :: !Text
    , boardUpdateDatum :: !Value
    , boardUpdateSpendRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data BoardRetirePlan = BoardRetirePlan
    { boardRetirePolicy :: !Text
    , boardRetireReference :: !Text
    , boardRetireSpentReference :: !Text
    , boardRetireAssetName :: !Text
    , boardRetireOwnerKeyHash :: !Text
    , boardRetireRefundAddress :: !Text
    , boardRetireRefundLovelace :: !Integer
    , boardRetireRefundOutput :: !Text
    , boardRetireSpendRedeemer :: !Value
    , boardRetireMintRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data BoardConfig = BoardConfig
    { boardRuntime :: !(TransactionRuntime IO)
    , boardReferenceUtxos :: ![(TxIn, TxOut ConwayEra)]
    , boardFundingAddress :: !Addr
    , boardChangeAddress :: !Addr
    }

newtype BoardCheckError
    = BoardAggregateExUnitsExceeded AggregateExUnitsError
    deriving stock (Eq, Show)

data BoardError
    = BoardFundingSelectionFailed !PayerSelectionError
    | BoardPlanRejected !String
    | BoardBuildFailed !(TransactionBuildError BoardCheckError)
    deriving stock (Eq, Show)

newtype BoardObservationTimeout = BoardObservationTimeout TxId
    deriving stock (Eq, Show)

newtype BoardResult = BoardResult
    { boardResultTxId :: TxId
    }
    deriving stock (Eq, Show)

newtype RawData = RawData Data

instance ToData RawData where
    toBuiltinData (RawData datum) = BuiltinData datum

{- | Everything an external witness signer needs, and nothing it must not
have: the exact bytes to sign plus the typed fields those bytes mean.

The witness's private KERI key is deliberately absent from this module and
from every type it exposes. A producer builds a payload, hands the bytes to
whoever holds the key, and comes back with 64 bytes.
-}
data BoardAuthorizationPayload = BoardAuthorizationPayload
    { boardPayloadPolicyId :: !ByteString
    , boardPayloadAuthorization :: !BoardAuthorizationV2
    , boardPayloadSignableBytes :: !ByteString
    , boardPayloadEndpointSignature :: !ByteString
    }
    deriving stock (Show, Eq)

-- | Why a producer payload or witness signature is refused before planning.
data BoardAuthorizationError
    = -- | A protocol field has the wrong byte width.
      BoardAuthorizationFieldWidth !String !Int
    | -- | A counter that must be non-negative is not.
      BoardAuthorizationNegative !String !Integer
    | -- | The endpoint record is empty.
      BoardAuthorizationEmptyRecord
    | -- | The policy id is not hexadecimal.
      BoardAuthorizationPolicyMalformed !String
    | -- | The supplied signature does not verify over the payload bytes.
      BoardAuthorizationSignatureRejected
    deriving stock (Show, Eq)

{- | FUN-253-AUTH-PAYLOAD: the exact signable CBOR plus the typed fields it
encodes, so an external signer can confirm what it is about to sign.
-}
mkBoardAuthorizationPayload ::
    Text ->
    EndpointRecord ->
    ByteString ->
    Integer ->
    BoardNonce ->
    Either BoardAuthorizationError BoardAuthorizationPayload
mkBoardAuthorizationPayload policy record ownerKeyHash sequenceNumber nonce = do
    policyId <-
        first BoardAuthorizationPolicyMalformed $
            decodeHexSized "board policy id" 28 policy
    requireWidth "witness key" 32 (endpointWitnessKey record)
    requireWidth "endpoint signature" 64 (endpointSignature record)
    requireWidth "owner key hash" 28 ownerKeyHash
    requireWidth "nonce transaction id" 32 (boardNonceTxId nonce)
    when (BS.null $ endpointEventBytes record) $
        Left BoardAuthorizationEmptyRecord
    requireNonNegative "sequence" sequenceNumber
    requireNonNegative "nonce output index" (boardNonceOutputIndex nonce)
    let authorization =
            BoardAuthorizationV2
                { boardAuthDomain = boardAuthorizationDomain
                , boardAuthPolicyId = policyId
                , boardAuthWitnessKey = endpointWitnessKey record
                , boardAuthEndpointRecord = endpointEventBytes record
                , boardAuthOwnerKeyHash = ownerKeyHash
                , boardAuthSequence = sequenceNumber
                , boardAuthNonce = nonce
                }
    pure
        BoardAuthorizationPayload
            { boardPayloadPolicyId = policyId
            , boardPayloadAuthorization = authorization
            , boardPayloadSignableBytes =
                boardAuthorizationBytes authorization
            , boardPayloadEndpointSignature = endpointSignature record
            }
  where
    requireWidth label expected bytes =
        unless (BS.length bytes == expected) $
            Left (BoardAuthorizationFieldWidth label (BS.length bytes))
    requireNonNegative label value =
        when (value < 0) $
            Left (BoardAuthorizationNegative label value)

{- | FUN-253-ATTACH-AUTH: bind a witness signature to its payload.

The signature is verified here, before any plan exists, so an unusable datum
can never reach transaction construction.
-}
attachBoardAuthorization ::
    BoardAuthorizationPayload ->
    ByteString ->
    Either BoardAuthorizationError BoardDatumV2
attachBoardAuthorization payload signature = do
    unless (BS.length signature == 64) $
        Left
            ( BoardAuthorizationFieldWidth
                "authorization signature"
                (BS.length signature)
            )
    let authorization = boardPayloadAuthorization payload
        datum =
            BoardDatumV2
                { boardV2WitnessKey = boardAuthWitnessKey authorization
                , boardV2EndpointRecord =
                    boardAuthEndpointRecord authorization
                , boardV2EndpointSignature =
                    boardPayloadEndpointSignature payload
                , boardV2OwnerKeyHash = boardAuthOwnerKeyHash authorization
                , boardV2Sequence = boardAuthSequence authorization
                , boardV2Nonce = boardAuthNonce authorization
                , boardV2AuthorizationSignature = signature
                }
    unless (verifyBoardAuthorization (boardPayloadPolicyId payload) datum) $
        Left BoardAuthorizationSignatureRejected
    pure datum

-- | Resolve one current witness record without hiding ratified duplicates.
selectBoardEntry ::
    Maybe Text ->
    BS.ByteString ->
    [BoardEntry] ->
    Either String BoardEntry
selectBoardEntry selectedReference witnessKey entries =
    case selectedReference of
        Just selected ->
            case filter ((== selected) . boardEntryReference) matching of
                [entry] -> Right entry
                [] -> Left "the selected board output is not a current record for this witness"
                _ -> Left "the selected board output reference is ambiguous"
        Nothing ->
            case matching of
                [entry] -> Right entry
                [] -> Left "the witness has no current board record"
                _ -> Left "the witness has duplicate current board records; pass --board-out-ref TXID#INDEX to select one explicitly"
  where
    matching = filter ((== witnessKey) . boardWitnessKey) entries

mkBoardPostPlan ::
    EndpointBoardManifest ->
    Text ->
    Integer ->
    EndpointRecord ->
    Either String BoardPostPlan
mkBoardPostPlan manifest ownerAddress deposit record = do
    info <- validatedBoardInfo manifest
    when (deposit <= 0) $ Left "deposit-lovelace must be positive"
    owner <- paymentKeyHash ownerAddress
    let boardPostPolicy = endpointBoardPolicyId info
        boardPostAddress = endpointBoardAddress info
        boardPostReference = renderReference (endpointBoardReference info)
        boardPostAssetName = hexText (endpointWitnessKey record)
        boardPostDepositLovelace = deposit
        boardPostOutput = markerOutput boardPostAddress deposit boardPostPolicy boardPostAssetName
        boardPostDatum = endpointDatum owner record
        boardPostMintRedeemer = plutusDataJson (Constr 0 [])
    pure BoardPostPlan{..}

mkBoardUpdatePlan ::
    EndpointBoardManifest ->
    Text ->
    BoardEntry ->
    EndpointRecord ->
    Either String BoardUpdatePlan
mkBoardUpdatePlan manifest ownerAddress entry record = do
    info <- validatedBoardInfo manifest
    owner <- paymentKeyHash ownerAddress
    unless (owner == boardOwnerKeyHash entry) $
        Left "funding address payment key does not own the selected board record"
    unless (endpointWitnessKey record == boardWitnessKey entry) $
        Left "updated endpoint record belongs to a different witness"
    when (boardLovelace entry <= 0) $
        Left "selected board record has a non-positive deposit"
    let boardUpdatePolicy = endpointBoardPolicyId info
        boardUpdateAddress = endpointBoardAddress info
        boardUpdateReference = renderReference (endpointBoardReference info)
        boardUpdateSpentReference = boardEntryReference entry
        boardUpdateAssetName = hexText (boardWitnessKey entry)
        boardUpdateDepositLovelace = boardLovelace entry
        boardUpdateOwnerKeyHash = hexText owner
        boardUpdateOutput = markerOutput boardUpdateAddress boardUpdateDepositLovelace boardUpdatePolicy boardUpdateAssetName
        boardUpdateDatum = endpointDatum owner record
        boardUpdateSpendRedeemer = plutusDataJson (Constr 0 [])
    pure BoardUpdatePlan{..}

mkBoardRetirePlan ::
    EndpointBoardManifest ->
    Text ->
    Text ->
    BoardEntry ->
    Either String BoardRetirePlan
mkBoardRetirePlan manifest ownerAddress refundAddress entry = do
    info <- validatedBoardInfo manifest
    owner <- paymentKeyHash ownerAddress
    unless (owner == boardOwnerKeyHash entry) $
        Left "funding address payment key does not own the selected board record"
    refund <- decodeRefundAddress refundAddress
    when (boardLovelace entry <= 0) $
        Left "selected board record has a non-positive deposit"
    let boardRetirePolicy = endpointBoardPolicyId info
        boardRetireReference = renderReference (endpointBoardReference info)
        boardRetireSpentReference = boardEntryReference entry
        boardRetireAssetName = hexText (boardWitnessKey entry)
        boardRetireOwnerKeyHash = hexText owner
        boardRetireRefundAddress = refundAddress
        boardRetireRefundLovelace = boardLovelace entry
        boardRetireRefundOutput = refundAddress <> "+" <> T.pack (show boardRetireRefundLovelace)
        boardRetireSpendRedeemer = plutusDataJson (Constr 1 [asPlcData refund])
        boardRetireMintRedeemer = plutusDataJson (Constr 1 [])
    pure BoardRetirePlan{..}

runBoardPostTransaction ::
    BoardConfig ->
    BoardPostPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    IO (Either BoardError BoardResult)
runBoardPostTransaction config plan fundingInputs =
    case postInputs config plan fundingInputs of
        Left err -> pure (Left err)
        Right inputs@BoardPostInputs{postFunding = funding} ->
            runBoardBuild
                config
                funding
                []
                (postReferences inputs)
                (postProgram inputs)

runBoardUpdateTransaction ::
    BoardConfig ->
    BoardUpdatePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    IO (Either BoardError BoardResult)
runBoardUpdateTransaction config plan fundingInputs boardInput =
    case updateInputs config plan fundingInputs boardInput of
        Left err -> pure (Left err)
        Right inputs@BoardUpdateInputs{updateFunding = funding} ->
            runBoardBuild
                config
                funding
                [boardInput]
                (updateReferences inputs)
                (updateProgram inputs)

runBoardRetireTransaction ::
    BoardConfig ->
    BoardRetirePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    IO (Either BoardError BoardResult)
runBoardRetireTransaction config plan fundingInputs boardInput =
    case retireInputs config plan fundingInputs boardInput of
        Left err -> pure (Left err)
        Right inputs@BoardRetireInputs{retireFunding = funding} ->
            runBoardBuild
                config
                funding
                [boardInput]
                (retireReferences inputs)
                (retireProgram inputs)

runBoardBuild ::
    BoardConfig ->
    FundingPair ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    (PParams ConwayEra -> TxBuild BoardCtx BoardCheckError ()) ->
    IO (Either BoardError BoardResult)
runBoardBuild config funding extraInputs references program = do
    let runtime = boardRuntime config
    pparams <- trQueryProtocolParams runtime
    let frozenRuntime = runtime{trQueryProtocolParams = pure pparams}
    result <-
        runPlutusTransactionBuild
            frozenRuntime
            boardInterpret
            (fundingSpends funding <> extraInputs)
            references
            (boardChangeAddress config)
            -- The collateral remainder goes to the funding address, which the
            -- board deliberately keeps distinct from its ordinary change
            -- address (RQ-232-03).
            CollateralContract
                { collateralInput = fundingCollateral funding
                , collateralReturnAddress = boardFundingAddress config
                }
            (program pparams)
    pure (BoardResult <$> first BoardBuildFailed result)

data BoardPostInputs = BoardPostInputs
    { postFunding :: !FundingPair
    , postReferences :: ![(TxIn, TxOut ConwayEra)]
    , postAddress :: !Addr
    , postValue :: !MaryValue
    , postDatum :: !RawData
    , postPolicy :: !PolicyID
    , postAsset :: !AssetName
    , postMintData :: !RawData
    }

postInputs ::
    BoardConfig ->
    BoardPostPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    Either BoardError BoardPostInputs
postInputs config plan fundingInputs = do
    policyHash <- planScriptHash "board policy" (boardPostPolicy plan)
    postAsset <- planAssetName "board asset name" (boardPostAssetName plan)
    postAddress <- planAddress "board address" (boardPostAddress plan)
    when (boardPostDepositLovelace plan <= 0) $
        Left (BoardPlanRejected "board deposit must be positive")
    boardReference <- resolveReference policyHash (boardPostReference plan) (boardReferenceUtxos config)
    postDatum <- rawPlanData "board datum" (boardPostDatum plan)
    postMintData <- rawPlanData "board mint redeemer" (boardPostMintRedeemer plan)
    postFunding <-
        first BoardFundingSelectionFailed $
            selectFundingPair
                isPlainUtxo
                (Coin $ boardPostDepositLovelace plan + 5_000_000)
                fundingInputs
    let postPolicy = PolicyID policyHash
        postValue = singletonMarkerValue (boardPostDepositLovelace plan) postPolicy postAsset
        postReferences = [boardReference]
    pure BoardPostInputs{..}

data BoardUpdateInputs = BoardUpdateInputs
    { updateFunding :: !FundingPair
    , updateInput :: !(TxIn, TxOut ConwayEra)
    , updateReferences :: ![(TxIn, TxOut ConwayEra)]
    , updateAddress :: !Addr
    , updateValue :: !MaryValue
    , updateDatumData :: !RawData
    , updateSpendData :: !RawData
    , updateOwner :: !(KeyHash Guard)
    }

updateInputs ::
    BoardConfig ->
    BoardUpdatePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Either BoardError BoardUpdateInputs
updateInputs config plan fundingInputs boardInput = do
    spent <- planTxIn (boardUpdateSpentReference plan)
    unless (fst boardInput == spent) $
        Left (BoardPlanRejected "resolved board record disagrees with the update plan")
    policyHash <- planScriptHash "board policy" (boardUpdatePolicy plan)
    asset <- planAssetName "board asset name" (boardUpdateAssetName plan)
    requireMarkerValue
        (Coin $ boardUpdateDepositLovelace plan)
        (PolicyID policyHash)
        asset
        boardInput
    updateAddress <- planAddress "board address" (boardUpdateAddress plan)
    when (boardUpdateDepositLovelace plan <= 0) $
        Left (BoardPlanRejected "board deposit must be positive")
    boardReference <- resolveReference policyHash (boardUpdateReference plan) (boardReferenceUtxos config)
    updateDatumData <- rawPlanData "board datum" (boardUpdateDatum plan)
    updateSpendData <- rawPlanData "board update redeemer" (boardUpdateSpendRedeemer plan)
    updateOwner <- planOwnerKeyHash (boardUpdateOwnerKeyHash plan)
    updateFunding <- selectBoardFunding fundingInputs
    let updateInput = boardInput
        updateReferences = [boardReference]
        updateValue = singletonMarkerValue (boardUpdateDepositLovelace plan) (PolicyID policyHash) asset
    pure BoardUpdateInputs{..}

data BoardRetireInputs = BoardRetireInputs
    { retireFunding :: !FundingPair
    , retireInput :: !(TxIn, TxOut ConwayEra)
    , retireReferences :: ![(TxIn, TxOut ConwayEra)]
    , retireRefundAddr :: !Addr
    , retireRefundCoin :: !Integer
    , retirePolicy :: !PolicyID
    , retireAsset :: !AssetName
    , retireSpendData :: !RawData
    , retireMintData :: !RawData
    , retireOwner :: !(KeyHash Guard)
    }

retireInputs ::
    BoardConfig ->
    BoardRetirePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Either BoardError BoardRetireInputs
retireInputs config plan fundingInputs boardInput = do
    spent <- planTxIn (boardRetireSpentReference plan)
    unless (fst boardInput == spent) $
        Left (BoardPlanRejected "resolved board record disagrees with the retire plan")
    policyHash <- planScriptHash "board policy" (boardRetirePolicy plan)
    retireAsset <- planAssetName "board asset name" (boardRetireAssetName plan)
    requireMarkerValue
        (Coin $ boardRetireRefundLovelace plan)
        (PolicyID policyHash)
        retireAsset
        boardInput
    boardReference <- resolveReference policyHash (boardRetireReference plan) (boardReferenceUtxos config)
    retireRefundAddr <- planAddress "board refund address" (boardRetireRefundAddress plan)
    when (boardChangeAddress config == retireRefundAddr) $
        Left (BoardPlanRejected "change address must differ from the exact board retire refund target")
    when (boardRetireRefundLovelace plan <= 0) $
        Left (BoardPlanRejected "board refund must be positive")
    retireSpendData <- rawPlanData "board retire spend redeemer" (boardRetireSpendRedeemer plan)
    retireMintData <- rawPlanData "board retire mint redeemer" (boardRetireMintRedeemer plan)
    retireOwner <- planOwnerKeyHash (boardRetireOwnerKeyHash plan)
    retireFunding <- selectBoardFunding fundingInputs
    let retireInput = boardInput
        retireReferences = [boardReference]
        retireRefundCoin = boardRetireRefundLovelace plan
        retirePolicy = PolicyID policyHash
    pure BoardRetireInputs{..}

selectBoardFunding :: [(TxIn, TxOut ConwayEra)] -> Either BoardError FundingPair
selectBoardFunding =
    first BoardFundingSelectionFailed
        . selectFundingPair isPlainUtxo (Coin 5_000_000)

postProgram ::
    BoardPostInputs ->
    PParams ConwayEra ->
    TxBuild BoardCtx BoardCheckError ()
postProgram BoardPostInputs{postFunding = FundingPair{..}, ..} pparams = do
    mapM_ (spend . fst) (fundingSpend : fundingAdditionalSpends)
    _ <- payTo' postAddress postValue postDatum
    mint postPolicy (Map.singleton postAsset 1) postMintData
    mapM_ (reference . fst) postReferences
    valid (boardCheck pparams)

updateProgram ::
    BoardUpdateInputs ->
    PParams ConwayEra ->
    TxBuild BoardCtx BoardCheckError ()
updateProgram BoardUpdateInputs{updateFunding = FundingPair{..}, ..} pparams = do
    mapM_ (spend . fst) (fundingSpend : fundingAdditionalSpends)
    _ <- spendScript (fst updateInput) updateSpendData
    _ <- payTo' updateAddress updateValue updateDatumData
    mapM_ (reference . fst) updateReferences
    requireSignature updateOwner
    valid (boardCheck pparams)

retireProgram ::
    BoardRetireInputs ->
    PParams ConwayEra ->
    TxBuild BoardCtx BoardCheckError ()
retireProgram BoardRetireInputs{retireFunding = FundingPair{..}, ..} pparams = do
    mapM_ (spend . fst) (fundingSpend : fundingAdditionalSpends)
    _ <- spendScript (fst retireInput) retireSpendData
    _ <- output $ mkBasicTxOut retireRefundAddr (MaryValue (Coin retireRefundCoin) $ MultiAsset mempty)
    mint retirePolicy (Map.singleton retireAsset (-1)) retireMintData
    mapM_ (reference . fst) retireReferences
    requireSignature retireOwner
    valid (boardCheck pparams)

data BoardCtx a

boardInterpret :: InterpretIO BoardCtx
boardInterpret = InterpretIO (\case {})

boardCheck :: PParams ConwayEra -> ConwayTx -> Check BoardCheckError
boardCheck pparams tx =
    case checkAggregateExUnits pparams tx of
        Pass -> Pass
        LedgerFail failure -> LedgerFail failure
        CustomFail failure -> CustomFail (BoardAggregateExUnitsExceeded failure)

awaitBoard ::
    (TxId -> IO Bool) ->
    Int ->
    Int ->
    TxId ->
    IO (Either BoardObservationTimeout ())
awaitBoard settled pollMicros timeoutSeconds txId = do
    started <- getCurrentTime
    let loop = do
            result <- try (settled txId)
            case result of
                Right True -> pure (Right ())
                Right False -> retry started
                Left (_ :: SomeException) -> retry started
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt >= fromIntegral timeoutSeconds
                then pure (Left $ BoardObservationTimeout txId)
                else threadDelay pollMicros >> loop
    loop

resolveReference ::
    ScriptHash ->
    Text ->
    [(TxIn, TxOut ConwayEra)] ->
    Either BoardError (TxIn, TxOut ConwayEra)
resolveReference expected rendered rows = do
    txIn <- planTxIn rendered
    row@(_, txOut) <-
        maybe
            (Left $ BoardPlanRejected "board reference UTxO is unresolved")
            Right
            (find ((== txIn) . fst) rows)
    case txOut ^. referenceScriptTxOutL of
        SNothing -> Left (BoardPlanRejected "board reference UTxO has no script")
        SJust script
            | hashScript script == expected -> Right row
            | otherwise -> Left (BoardPlanRejected "board reference script disagrees with the plan")

requireMarkerValue ::
    Coin ->
    PolicyID ->
    AssetName ->
    (TxIn, TxOut ConwayEra) ->
    Either BoardError ()
requireMarkerValue expectedCoin policy assetName (_, txOut) =
    case txOut ^. valueTxOutL of
        MaryValue coin (MultiAsset assets)
            | coin == expectedCoin
                && assets == Map.singleton policy (Map.singleton assetName 1) ->
                Right ()
        _ ->
            Left $
                BoardPlanRejected
                    "board input value does not exactly match the singleton marker and deposit plan"

isPlainUtxo :: TxOut ConwayEra -> Bool
isPlainUtxo txOut =
    case (txOut ^. referenceScriptTxOutL, txOut ^. valueTxOutL) of
        (SNothing, MaryValue _ (MultiAsset assets)) -> Map.null assets
        _ -> False

singletonMarkerValue :: Integer -> PolicyID -> AssetName -> MaryValue
singletonMarkerValue lovelace policy asset =
    MaryValue
        (Coin lovelace)
        (MultiAsset $ Map.singleton policy $ Map.singleton asset 1)

rawPlanData :: String -> Value -> Either BoardError RawData
rawPlanData label =
    first (BoardPlanRejected . ((label <> ": ") <>))
        . fmap RawData
        . plutusDataFromJson

planScriptHash :: String -> Text -> Either BoardError ScriptHash
planScriptHash label encoded = do
    bytes <- first BoardPlanRejected (decodeHexSized label 28 encoded)
    maybe
        (Left $ BoardPlanRejected $ label <> " is not a ledger hash")
        (Right . ScriptHash)
        (hashFromBytes bytes)

planOwnerKeyHash :: Text -> Either BoardError (KeyHash Guard)
planOwnerKeyHash encoded = do
    bytes <- first BoardPlanRejected (decodeHexSized "board owner key hash" 28 encoded)
    maybe
        (Left $ BoardPlanRejected "board owner key hash is not a ledger hash")
        (Right . KeyHash)
        (hashFromBytes bytes)

planAssetName :: String -> Text -> Either BoardError AssetName
planAssetName label encoded = do
    bytes <- planHex label encoded
    if BS.length bytes <= 32
        then Right (AssetName $ SBS.toShort bytes)
        else Left (BoardPlanRejected $ label <> " exceeds 32 bytes")

planTxIn :: Text -> Either BoardError TxIn
planTxIn rendered =
    case T.splitOn "#" rendered of
        [encodedId, renderedIx] -> do
            rawId <- planHex "reference transaction id" encodedId
            unless (BS.length rawId == 32) $
                Left (BoardPlanRejected "reference transaction id is not 32 bytes")
            digest <-
                maybe
                    (Left $ BoardPlanRejected "reference transaction id is not a ledger hash")
                    Right
                    (hashFromBytes rawId)
            txIx <-
                maybe
                    (Left $ BoardPlanRejected "reference transaction index is invalid")
                    Right
                    (readMaybe $ T.unpack renderedIx)
            pure (TxIn (TxId $ unsafeMakeSafeHash digest) (TxIx txIx))
        _ -> Left (BoardPlanRejected "reference must have txid#index form")

planHex :: String -> Text -> Either BoardError ByteString
planHex label encoded =
    first
        (const $ BoardPlanRejected $ label <> " is not hexadecimal")
        (convertFromBase Base16 $ TE.encodeUtf8 encoded)

planAddress :: String -> Text -> Either BoardError Addr
planAddress label encoded = do
    (_, dataPart) <-
        first
            (BoardPlanRejected . ((label <> " is not Bech32: ") <>) . show)
            (Bech32.decodeLenient encoded)
    bytes <-
        maybe
            (Left $ BoardPlanRejected $ label <> " data is invalid")
            Right
            (Bech32.dataPartToBytes dataPart)
    address <-
        maybe
            (Left $ BoardPlanRejected $ label <> " is not a Shelley address")
            Right
            (decodeAddr bytes :: Maybe Addr)
    case address of
        Addr Testnet _ _ -> Right address
        Addr Mainnet _ _ -> Left (BoardPlanRejected $ label <> " belongs to mainnet")
        AddrBootstrap{} -> Left (BoardPlanRejected $ label <> " is a Byron address")

validatedBoardInfo :: EndpointBoardManifest -> Either String EndpointBoardInfo
validatedBoardInfo manifest = do
    unless
        (endpointBoardManifestSchemaVersion manifest == endpointBoardManifestSchema)
        (Left "endpoint-board manifest schema is not frozen V1")
    unless
        (endpointBoardManifestNetwork manifest == NetworkInfo "preprod" 1)
        (Left "endpoint-board manifest is not preprod network magic 1")
    let info = endpointBoardManifestInfo manifest
    unless
        ( endpointBoardPolicyId info == frozenEndpointBoardPolicyId
            && endpointBoardAddress info == frozenEndpointBoardAddress
        )
        (Left "endpoint-board manifest does not name the frozen policy and address")
    pure info

paymentKeyHash :: Text -> Either String BS.ByteString
paymentKeyHash address = do
    decoded <- decodeRefundAddress address
    case faPaymentCredential decoded of
        VerificationKeyCredential keyHash -> pure keyHash
        ScriptCredential _ -> Left "board ownership requires a Cardano payment verification key"

endpointDatum :: BS.ByteString -> EndpointRecord -> Value
endpointDatum owner record =
    plutusDataJson $
        Constr
            0
            [ B (endpointWitnessKey record)
            , B (endpointEventBytes record)
            , B (endpointSignature record)
            , B owner
            ]

markerOutput :: Text -> Integer -> Text -> Text -> Text
markerOutput address lovelace policy assetName =
    address
        <> "+"
        <> T.pack (show lovelace)
        <> " + 1 "
        <> policy
        <> "."
        <> assetName

renderReference :: Reference -> Text
renderReference scriptReference =
    referenceTxId scriptReference
        <> "#"
        <> T.pack (show $ referenceIndex scriptReference)

boardEntryReference :: BoardEntry -> Text
boardEntryReference entry =
    boardTxId entry <> "#" <> T.pack (show $ boardIndex entry)

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

decodeHexSized :: String -> Int -> Text -> Either String ByteString
decodeHexSized label expected encoded = do
    bytes <-
        either
            (const $ Left $ label <> " is not hexadecimal")
            Right
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == expected) $
        Left (label <> " has the wrong byte length")
    pure bytes
