{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.EndpointBoardTransactionSpec
Description : #181 Slice 3 in-process endpoint-board migration proof
-}
module Cardano.KERI.Deployment.EndpointBoardTransactionSpec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Hash (
    hashFromBytes,
    hashFromStringAsHex,
    hashToBytes,
 )
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.Deployment.EndpointBoard (
    AuthorizedBoardDatum (..),
    BoardAuthorization (..),
    BoardEntry (..),
    BoardNonce (..),
    EndpointRecord (..),
    authorizedBoardDatumBytes,
    authorizedBoardDatumData,
    boardAuthorizationBytes,
    reconstructBoardAuthorization,
 )
import Cardano.KERI.Deployment.EndpointBoardTransaction (
    AuthorizedBoardPostPlan (..),
    AuthorizedBoardUpdatePlan (..),
    BoardAuthorizationError (..),
    BoardAuthorizationPayload (..),
    BoardConfig (..),
    BoardError (..),
    BoardObservationTimeout (..),
    BoardPostPlan (..),
    BoardResult (..),
    BoardRetirePlan (..),
    BoardUpdatePlan (..),
    ResolvedBoardTarget (..),
    attachBoardAuthorization,
    awaitBoard,
    mkAuthorizedBoardPostPlan,
    mkAuthorizedBoardUpdatePlan,
    mkBoardAuthorizationPayload,
    runAuthorizedBoardPostTransaction,
    runAuthorizedBoardUpdateTransaction,
    runBoardPostTransaction,
    runBoardRetireTransaction,
    runBoardUpdateTransaction,
 )
import Cardano.KERI.Deployment.ParityOracle.Capture (captureShape)
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript, scriptHashText)
import Cardano.KERI.Deployment.TransactionRuntime (
    CollateralSafetyError (..),
    TransactionBuildError (..),
    TransactionRuntime (..),
    signWithPaymentKey,
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (
    shouldDeclareBoundedCollateral,
    statedMaximumCollateralLovelace,
    testPParams,
    withFixedFee,
 )
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (
    TransactionScriptFailure (UnknownTxIn),
 )
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data qualified as LedgerData
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    reqSignerHashesTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
    referenceScriptTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (addrTxWitsL, rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (SJust),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (Script, TxOut, mkBasicTx, mkBasicTxOut)
import Cardano.Ledger.Credential (
    Credential (..),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash,
    extractHash,
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Keys (KeyRole (Guard, Payment))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..), unTxId)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Codec.Binary.Bech32 qualified as Bech32
import Data.Aeson (Value, object, (.=))
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (isLeft)
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data (Data (..))
import System.Directory (findExecutable)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldNotBe,
    shouldNotContain,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "in-process endpoint-board transactions" $ do
    it "post freezes ownership datum, marker mint, references, collateral, signing, tx-id, and settlement" $ do
        findExecutable "cardano-cli" >>= (`shouldBe` Nothing)
        (result, tx, order) <- capture $ \runtime ->
            runBoardPostTransaction
                (boardConfig runtime)
                postPlan
                fundingInputs
        BoardResult txId <- either (fail . show) pure result
        -- T240-S1-01: no-op unless CKERI_PARITY_ORACLE_DIR is set; see
        -- Cardano.KERI.Deployment.ParityOracle.Capture.
        captureShape "board-post" (renderTxId txId) tx
        let body = tx ^. bodyTxL
            outputs = toList (body ^. outputsTxBodyL)
            MultiAsset minted = body ^. mintTxBodyL
            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
        body ^. inputsTxBodyL `shouldBe` Set.singleton (stubTxIn 1)
        body ^. collateralInputsTxBodyL `shouldBe` Set.singleton (stubTxIn 2)
        body ^. referenceInputsTxBodyL `shouldBe` Set.singleton boardReference
        minted
            `shouldBe` Map.singleton
                (PolicyID boardScriptHash)
                (Map.singleton markerAssetName 1)
        case [output | output <- outputs, output ^. addrTxOutL == markerAddr] of
            [marker] -> do
                marker ^. coinTxOutL `shouldBe` Coin 2_000_000
                inlineDatum marker `shouldBe` postDatum
            other -> fail ("expected one marker output, got " <> show (length other))
        redeemerData (ConwayMinting $ AsIx 0) redeemers
            `shouldBe` Just mintRedeemer
        assertTerminal tx txId order

    it "update freezes owned spend, replacement datum, required signer, and no mint" $ do
        (result, tx, order) <- capture $ \runtime ->
            runBoardUpdateTransaction
                (boardConfig runtime)
                updatePlan
                fundingInputs
                boardInput
        BoardResult txId <- either (fail . show) pure result
        -- T240-S1-01: no-op unless CKERI_PARITY_ORACLE_DIR is set; see
        -- Cardano.KERI.Deployment.ParityOracle.Capture.
        captureShape "board-update" (renderTxId txId) tx
        let body = tx ^. bodyTxL
            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
            spendPurpose =
                ConwaySpending . AsIx . fromIntegral . fromJust $
                    Set.lookupIndex boardTxIn (body ^. inputsTxBodyL)
        body ^. inputsTxBodyL
            `shouldBe` Set.fromList [stubTxIn 1, boardTxIn]
        body ^. referenceInputsTxBodyL `shouldBe` Set.singleton boardReference
        body ^. mintTxBodyL `shouldBe` mempty
        body ^. reqSignerHashesTxBodyL `shouldBe` Set.singleton ownerKeyHash
        case [output | output <- toList (body ^. outputsTxBodyL), output ^. addrTxOutL == markerAddr] of
            [marker] -> inlineDatum marker `shouldBe` updateDatum
            other -> fail ("expected one replacement marker output, got " <> show (length other))
        redeemerData spendPurpose redeemers `shouldBe` Just spendRedeemer
        assertTerminal tx txId order

    it "retire freezes owned spend, marker burn, exact refund, required signer, and settlement" $ do
        (result, tx, order) <- capture $ \runtime ->
            runBoardRetireTransaction
                (boardConfig runtime)
                retirePlan
                fundingInputs
                boardInput
        BoardResult txId <- either (fail . show) pure result
        -- T240-S1-01: no-op unless CKERI_PARITY_ORACLE_DIR is set; see
        -- Cardano.KERI.Deployment.ParityOracle.Capture.
        captureShape "board-retire" (renderTxId txId) tx
        let body = tx ^. bodyTxL
            outputs = toList (body ^. outputsTxBodyL)
            MultiAsset minted = body ^. mintTxBodyL
            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
            spendPurpose =
                ConwaySpending . AsIx . fromIntegral . fromJust $
                    Set.lookupIndex boardTxIn (body ^. inputsTxBodyL)
        minted
            `shouldBe` Map.singleton
                (PolicyID boardScriptHash)
                (Map.singleton markerAssetName (-1))
        body ^. reqSignerHashesTxBodyL `shouldBe` Set.singleton ownerKeyHash
        case [output | output <- outputs, output ^. addrTxOutL == refundAddr] of
            [refund] -> do
                refund ^. coinTxOutL `shouldBe` Coin 2_000_000
                refund ^. datumTxOutL `shouldBe` LedgerData.NoDatum
            other -> fail ("expected one exact refund output, got " <> show (length other))
        redeemerData spendPurpose redeemers `shouldBe` Just retireSpendRedeemer
        redeemerData (ConwayMinting $ AsIx 0) redeemers
            `shouldBe` Just burnRedeemer
        assertTerminal tx txId order

    it "fails closed on stale value, underfunding, evaluation rejection, and submission rejection" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        staleValue <-
            runBoardUpdateTransaction
                (boardConfig baseRuntime)
                updatePlan{boardUpdateDepositLovelace = 2_000_001}
                fundingInputs
                boardInput
        staleValue `shouldSatisfy` isPlanFailure
        underfunded <-
            runBoardPostTransaction
                (boardConfig baseRuntime)
                postPlan
                [(stubTxIn 1, plainTxOut 1_000_000), (stubTxIn 2, plainTxOut 500_000)]
        underfunded `shouldSatisfy` isFundingFailure
        evaluation <-
            runBoardPostTransaction
                ( boardConfig
                    baseRuntime
                        { trEvaluate = \_ ->
                            pure
                                ( Map.singleton
                                    (ConwayMinting $ AsIx 0)
                                    (Left $ UnknownTxIn $ stubTxIn 99)
                                )
                        }
                )
                postPlan
                fundingInputs
        evaluation `shouldSatisfy` isEvaluationFailure
        submission <-
            runBoardPostTransaction
                (boardConfig baseRuntime{trSubmit = \_ -> pure (Rejected "board submit rejected")})
                postPlan
                fundingInputs
        submission `shouldSatisfy` isSubmissionFailure

    it "reports timeout only after polling the board settlement source" $ do
        pollsRef <- newIORef (0 :: Int)
        let query _ = modifyIORef' pollsRef (+ 1) >> pure False
        result <- awaitBoard query 1 0 disagreeingId
        readIORef pollsRef >>= (`shouldSatisfy` (>= 1))
        result `shouldBe` Left (BoardObservationTimeout disagreeingId)

    boundedCollateralSpec

    boardAuthorizationProducerSpec

    authorizedBoardPlannerSpec

-- ---------------------------------------------------------------------------
-- #232 bounded phase-2 collateral loss

{- | The row 'selectFundingPair' reserves as collateral for every board verb:
the smallest eligible entry in 'fundingInputs'.
-}
boardCollateralUtxo :: (TxIn, TxOut ConwayEra)
boardCollateralUtxo = (stubTxIn 2, plainTxOut 50_000_000)

boundedCollateralSpec :: Spec
boundedCollateralSpec = describe "#232 bounded collateral" $ do
    it "post, update, and retire all return the remainder to the funding address" $ do
        -- Non-vacuity: the board's ordinary change address genuinely differs
        -- from its funding address, so none of these three can pass without
        -- the explicit return instruction.
        fundingAddr `shouldNotBe` changeAddr
        (_, postTx, _) <- capture $ \runtime ->
            runBoardPostTransaction (boardConfig runtime) postPlan fundingInputs
        (_, updateTx, _) <- capture $ \runtime ->
            runBoardUpdateTransaction
                (boardConfig runtime)
                updatePlan
                fundingInputs
                boardInput
        (_, retireTx, _) <- capture $ \runtime ->
            runBoardRetireTransaction
                (boardConfig runtime)
                retirePlan
                fundingInputs
                boardInput
        mapM_
            ( shouldDeclareBoundedCollateral
                testPParams
                fundingAddr
                boardCollateralUtxo
            )
            [postTx, updateTx, retireTx]

    it "refuses a requirement above 5,000,000 lovelace before signing" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        let cappedRuntime =
                baseRuntime
                    { trQueryProtocolParams =
                        pure (withFixedFee (Coin 4_000_000) testPParams)
                    }
        result <-
            runBoardPostTransaction
                (boardConfig cappedRuntime)
                postPlan
                fundingInputs
        case result of
            Left
                ( BoardBuildFailed
                        ( TransactionBuildCollateralRejected
                                CollateralRequirementAboveMaximum
                                    { collateralRequiredLovelace
                                    , collateralMaximumLovelace
                                    }
                            )
                    ) -> do
                    collateralMaximumLovelace
                        `shouldBe` statedMaximumCollateralLovelace
                    collateralRequiredLovelace
                        `shouldSatisfy` (> statedMaximumCollateralLovelace)
            other ->
                fail ("expected a bounded-collateral rejection, got " <> show other)
        readIORef signedRef >>= (`shouldBe` Nothing)
        calls <- readIORef callsRef
        calls `shouldNotContain` ["sign"]
        calls `shouldNotContain` ["submit"]

assertTerminal :: ConwayTx -> TxId -> [String] -> IO ()
assertTerminal tx txId order = do
    tx ^. bodyTxL . feeTxBodyL `shouldSatisfy` (> Coin 0)
    length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
    transactionId tx `shouldBe` txId
    transactionId tx `shouldSatisfy` (/= disagreeingId)
    take 1 order `shouldBe` ["query"]
    order `shouldContain` ["evaluate"]
    drop (length order - 3) order `shouldBe` ["sign", "submit", "observe"]

isFundingFailure :: Either BoardError BoardResult -> Bool
isFundingFailure (Left BoardFundingSelectionFailed{}) = True
isFundingFailure _ = False

isPlanFailure :: Either BoardError BoardResult -> Bool
isPlanFailure (Left BoardPlanRejected{}) = True
isPlanFailure _ = False

isEvaluationFailure :: Either BoardError BoardResult -> Bool
isEvaluationFailure (Left (BoardBuildFailed TransactionBuildEvaluationRejected{})) = True
isEvaluationFailure _ = False

isSubmissionFailure :: Either BoardError BoardResult -> Bool
isSubmissionFailure (Left (BoardBuildFailed TransactionBuildSubmissionRejected{})) = True
isSubmissionFailure _ = False

capture ::
    (TransactionRuntime IO -> IO (Either BoardError BoardResult)) ->
    IO (Either BoardError BoardResult, ConwayTx, [String])
capture action = do
    callsRef <- newIORef []
    signedRef <- newIORef Nothing
    runtime <- standInRuntime callsRef signedRef
    result <- action runtime
    tx <- readIORef signedRef >>= maybe (fail "trSign was never called") pure
    order <- reverse <$> readIORef callsRef
    pure (result, tx, order)

boardConfig :: TransactionRuntime IO -> BoardConfig
boardConfig runtime =
    BoardConfig
        { boardRuntime = runtime
        , boardReferenceUtxos = [(boardReference, referenceTxOut boardScript)]
        , boardFundingAddress = fundingAddr
        , boardChangeAddress = changeAddr
        }

fundingInputs :: [(TxIn, TxOut ConwayEra)]
fundingInputs =
    [ (stubTxIn 1, plainTxOut 200_000_000)
    , (stubTxIn 2, plainTxOut 50_000_000)
    ]

boardInput :: (TxIn, TxOut ConwayEra)
boardInput =
    ( boardTxIn
    , mkBasicTxOut
        markerAddr
        ( MaryValue
            (Coin 2_000_000)
            ( MultiAsset $
                Map.singleton
                    (PolicyID boardScriptHash)
                    (Map.singleton markerAssetName 1)
            )
        )
    )

boardTxIn, boardReference :: TxIn
boardTxIn = stubTxIn 20
boardReference = stubTxIn 21

boardProgram :: SBS.ShortByteString
boardProgram = SBS.toShort "slice3-endpoint-board-script"

boardScript :: Script ConwayEra
boardScript = mkCageScript boardProgram

boardScriptHash :: ScriptHash
boardScriptHash = computeScriptHash boardProgram

markerAssetName :: AssetName
markerAssetName = AssetName (SBS.toShort $ BS.replicate 32 0x51)

postPlan :: BoardPostPlan
postPlan =
    BoardPostPlan
        { boardPostPolicy = scriptHashText boardScriptHash
        , boardPostAddress = renderAddr markerAddr
        , boardPostReference = renderTxIn boardReference
        , boardPostAssetName = hexText (BS.replicate 32 0x51)
        , boardPostDepositLovelace = 2_000_000
        , boardPostOutput = "retired-cardano-cli-rendering"
        , boardPostDatum = plutusDataJson postDatum
        , boardPostMintRedeemer = plutusDataJson mintRedeemer
        }

updatePlan :: BoardUpdatePlan
updatePlan =
    BoardUpdatePlan
        { boardUpdatePolicy = scriptHashText boardScriptHash
        , boardUpdateAddress = renderAddr markerAddr
        , boardUpdateReference = renderTxIn boardReference
        , boardUpdateSpentReference = renderTxIn boardTxIn
        , boardUpdateAssetName = hexText (BS.replicate 32 0x51)
        , boardUpdateDepositLovelace = 2_000_000
        , boardUpdateOwnerKeyHash = hexText ownerBytes
        , boardUpdateOutput = "retired-cardano-cli-rendering"
        , boardUpdateDatum = plutusDataJson updateDatum
        , boardUpdateSpendRedeemer = plutusDataJson spendRedeemer
        }

retirePlan :: BoardRetirePlan
retirePlan =
    BoardRetirePlan
        { boardRetirePolicy = scriptHashText boardScriptHash
        , boardRetireReference = renderTxIn boardReference
        , boardRetireSpentReference = renderTxIn boardTxIn
        , boardRetireAssetName = hexText (BS.replicate 32 0x51)
        , boardRetireOwnerKeyHash = hexText ownerBytes
        , boardRetireRefundAddress = renderAddr refundAddr
        , boardRetireRefundLovelace = 2_000_000
        , boardRetireRefundOutput = "retired-cardano-cli-rendering"
        , boardRetireSpendRedeemer = plutusDataJson retireSpendRedeemer
        , boardRetireMintRedeemer = plutusDataJson burnRedeemer
        }

postDatum, updateDatum, spendRedeemer, retireSpendRedeemer, mintRedeemer, burnRedeemer :: Data
postDatum = Constr 1 [I 101]
updateDatum = Constr 2 [I 202]
spendRedeemer = Constr 3 [I 303]
retireSpendRedeemer = Constr 4 [I 404]
mintRedeemer = Constr 5 [I 505]
burnRedeemer = Constr 6 [I 606]

ownerBytes :: BS.ByteString
ownerBytes = BS.replicate 28 0x44

ownerKeyHash :: KeyHash Guard
ownerKeyHash = KeyHash (fromJust $ hashFromBytes ownerBytes)

ownerPaymentKeyHash :: KeyHash Payment
ownerPaymentKeyHash = KeyHash (fromJust $ hashFromBytes ownerBytes)

fundingAddr, changeAddr, refundAddr, markerAddr :: Addr
fundingAddr = Addr Testnet (KeyHashObj ownerPaymentKeyHash) StakeRefNull
changeAddr = testAddr 2
refundAddr = testAddr 3
markerAddr = Addr Testnet (ScriptHashObj boardScriptHash) StakeRefNull

testAddr :: Int -> Addr
testAddr n =
    Addr
        Testnet
        (KeyHashObj $ KeyHash $ fromJust $ hashFromStringAsHex $ replicate 55 '0' <> show n)
        StakeRefNull

stubTxIn :: Int -> TxIn
stubTxIn n =
    TxIn
        (TxId $ unsafeMakeSafeHash $ fromJust $ hashFromStringAsHex hex)
        (TxIx 0)
  where
    hex = replicate 62 '0' <> hexByte n
    hexByte k =
        let digit i = "0123456789abcdef" !! i
         in [digit (k `div` 16 `mod` 16), digit (k `mod` 16)]

plainTxOut :: Integer -> TxOut ConwayEra
plainTxOut amount =
    mkBasicTxOut fundingAddr (MaryValue (Coin amount) $ MultiAsset mempty)

referenceTxOut :: Script ConwayEra -> TxOut ConwayEra
referenceTxOut script =
    plainTxOut 20_000_000 & referenceScriptTxOutL .~ SJust script

renderTxIn :: TxIn -> Text
renderTxIn (TxIn txId (TxIx index)) = renderTxId txId <> "#" <> T.pack (show index)

renderTxId :: TxId -> Text
renderTxId = TE.decodeUtf8 . convertToBase Base16 . hashToBytes . extractHash . unTxId

renderAddr :: Addr -> Text
renderAddr address =
    Bech32.encodeLenient
        (either (error . show) id $ Bech32.humanReadablePartFromText "addr_test")
        (Bech32.dataPartFromBytes $ serialiseAddr address)

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

recordCall :: IORef [String] -> String -> IO ()
recordCall ref tag = modifyIORef' ref (tag :)

standInRuntime :: IORef [String] -> IORef (Maybe ConwayTx) -> IO (TransactionRuntime IO)
standInRuntime callsRef signedRef =
    pure
        TransactionRuntime
            { trQueryProtocolParams = recordCall callsRef "query" >> pure testPParams
            , trEvaluate = \_ -> recordCall callsRef "evaluate" >> pure Map.empty
            , trSign = \tx -> do
                recordCall callsRef "sign"
                let result = signWithPaymentKey testEnvelope tx
                modifyIORef' signedRef (const $ either (const Nothing) Just result)
                pure result
            , trSubmit = \tx -> do
                readIORef signedRef >>= (`shouldBe` Just tx)
                recordCall callsRef "submit"
                pure (Submitted disagreeingId)
            , trObserve = \txId -> do
                signed <- readIORef signedRef
                fmap transactionId signed `shouldBe` Just txId
                recordCall callsRef "observe"
            }

testEnvelope :: Value
testEnvelope =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex"
            .= ("582083c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde" :: String)
        ]

disagreeingId :: TxId
disagreeingId = transactionId (mkBasicTx $ mkBasicTxBody & feeTxBodyL .~ Coin 999_999)

redeemerData ::
    ConwayPlutusPurpose AsIx ConwayEra ->
    Map.Map
        (ConwayPlutusPurpose AsIx ConwayEra)
        (LedgerData.Data ConwayEra, ExUnits) ->
    Maybe Data
redeemerData purpose redeemers =
    (\(LedgerData.Data datum, _) -> datum) <$> Map.lookup purpose redeemers

inlineDatum :: TxOut ConwayEra -> Data
inlineDatum txOut =
    case txOut ^. datumTxOutL of
        LedgerData.Datum binaryDatum ->
            let LedgerData.Data datum = LedgerData.binaryDataToData binaryDatum
             in datum
        other -> error ("expected inline datum, got " <> show other)

-- ---------------------------------------------------------------
-- #253 S253-1 producer boundary: payload out, signature in, no key
-- ---------------------------------------------------------------

{- | The witness's private key never appears in this module's production
counterpart. A producer emits bytes, an external signer returns 64 bytes,
and attachment refuses anything that does not verify.

The golden constants are the same independently derived vectors asserted
from Aiken and from 'Cardano.KERI.Deployment.EndpointBoardSpec'.
-}
boardAuthorizationProducerSpec :: Spec
boardAuthorizationProducerSpec =
    describe "board authorization producer" $ do
        it "emits exactly the frozen signable bytes" $ do
            payload <- expectPayload
            boardPayloadSignableBytes payload
                `shouldBe` frozenAuthorizationBytes

        it "shows the signer the typed fields those bytes encode" $ do
            payload <- expectPayload
            boardPayloadAuthorization payload
                `shouldBe` BoardAuthorization
                    { boardAuthDomain =
                        "cardano-keri/endpoint-board/authorization"
                    , boardAuthPolicyId = frozenPolicyBytes
                    , boardAuthWitnessKey = frozenWitnessKey
                    , boardAuthEndpointRecord = frozenRecord
                    , boardAuthOwnerKeyHash = frozenOwner
                    , boardAuthNonce = frozenNonce
                    }
            boardPayloadEndpointSignature payload
                `shouldBe` frozenEndpointSignature

        it "refuses malformed material before anything is signed" $ do
            let cases =
                    [ mkPayload "not hex" frozenRecordValue frozenOwner frozenNonce
                    , mkPayload
                        frozenPolicy
                        frozenRecordValue{endpointWitnessKey = BS.take 31 frozenWitnessKey}
                        frozenOwner
                        frozenNonce
                    , mkPayload
                        frozenPolicy
                        frozenRecordValue{endpointEventBytes = ""}
                        frozenOwner
                        frozenNonce
                    , mkPayload
                        frozenPolicy
                        frozenRecordValue{endpointSignature = BS.take 63 frozenEndpointSignature}
                        frozenOwner
                        frozenNonce
                    , mkPayload frozenPolicy frozenRecordValue (BS.replicate 27 0x33) frozenNonce
                    , mkPayload
                        frozenPolicy
                        frozenRecordValue
                        frozenOwner
                        (BoardNonce (BS.replicate 31 0x11) 0)
                    , mkPayload
                        frozenPolicy
                        frozenRecordValue
                        frozenOwner
                        (BoardNonce (BS.replicate 32 0x11) (-1))
                    ]
            cases `shouldSatisfy` all isLeft

        it "refuses a signature of the wrong width" $ do
            payload <- expectPayload
            attachBoardAuthorization
                payload
                (BS.take 63 frozenAuthorizationSignature)
                `shouldBe` Left
                    (BoardAuthorizationFieldWidth "authorization signature" 63)

        it "refuses a genuine signature by a foreign signer" $ do
            payload <- expectPayload
            attachBoardAuthorization payload frozenForeignSignature
                `shouldBe` Left BoardAuthorizationSignatureRejected

        it "attaches a verified signature as the frozen authorized datum" $ do
            payload <- expectPayload
            datum <-
                either
                    (fail . show)
                    pure
                    (attachBoardAuthorization payload frozenAuthorizationSignature)
            authorizedBoardDatumBytes datum
                `shouldBe` frozenAuthorizedDatumBytes
            authorizedSignature datum
                `shouldBe` frozenAuthorizationSignature

mkPayload ::
    Text ->
    EndpointRecord ->
    ByteString ->
    BoardNonce ->
    Either BoardAuthorizationError BoardAuthorizationPayload
mkPayload = mkBoardAuthorizationPayload

expectPayload :: IO BoardAuthorizationPayload
expectPayload =
    either
        (fail . show)
        pure
        (mkPayload frozenPolicy frozenRecordValue frozenOwner frozenNonce)

boardHex :: ByteString -> ByteString
boardHex encoded =
    case convertFromBase Base16 encoded of
        Right bytes -> bytes
        Left err ->
            error ("EndpointBoardTransactionSpec: bad vector hex: " <> err)

frozenPolicy :: Text
frozenPolicy = "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

frozenPolicyBytes :: ByteString
frozenPolicyBytes = boardHex (TE.encodeUtf8 frozenPolicy)

frozenWitnessKey :: ByteString
frozenWitnessKey =
    boardHex "d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729"

frozenOwner :: ByteString
frozenOwner = BS.replicate 28 0x33

frozenRecord :: ByteString
frozenRecord = "loc/scheme-vector-1"

frozenNonce :: BoardNonce
frozenNonce = BoardNonce (BS.replicate 32 0x11) 0

frozenRecordValue :: EndpointRecord
frozenRecordValue =
    EndpointRecord
        { endpointEventBytes = frozenRecord
        , endpointSignature = frozenEndpointSignature
        , endpointWitnessKey = frozenWitnessKey
        , endpointAid = "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
        , endpointScheme = "https"
        , endpointUrl = "https://witness-test.example/"
        }

frozenEndpointSignature :: ByteString
frozenEndpointSignature =
    boardHex
        "1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6\
        \989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

frozenAuthorizationBytes :: ByteString
frozenAuthorizationBytes =
    boardHex
        "d8799f582963617264616e6f2d6b6572692f656e64706f696e742d626f617264\
        \2f617574686f72697a6174696f6e581c54494f8a1b2930241b7b9fa010f61f2c\
        \f6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6d\
        \d4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f72\
        \2d31581c33333333333333333333333333333333333333333333333333333333\
        \d8799f5820111111111111111111111111111111111111111111111111111111\
        \111111111100ffff"

frozenAuthorizationSignature :: ByteString
frozenAuthorizationSignature =
    boardHex
        "61c8bf526ed993529bf86bfde5f962396a363c7f927e6f8953e606e98e77b021\
        \3b49fbbb0008f757fabfe00113c383c27377c51e310fc818091a0632abba8006"

frozenForeignSignature :: ByteString
frozenForeignSignature =
    boardHex
        "8eeaee81b6110a87c0737157c8ba317947b7aa1d4b23ec340ab679456f9f9716\
        \08488ead6d22d4dd1b0bf4a52081e1aa6913f0bba5e02c0c8718404ffd9b6b07"

frozenAuthorizedDatumBytes :: ByteString
frozenAuthorizedDatumBytes =
    boardHex
        "d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7af\
        \e125f54729536c6f632f736368656d652d766563746f722d3158401a809536db\
        \02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9eb\
        \bd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c333333\
        \33333333333333333333333333333333333333333333333333d8799f58201111\
        \11111111111111111111111111111111111111111111111111111111111100ff\
        \584061c8bf526ed993529bf86bfde5f962396a363c7f927e6f8953e606e98e77\
        \b0213b49fbbb0008f757fabfe00113c383c27377c51e310fc818091a0632abba\
        \8006ff"

-- ---------------------------------------------------------------
-- #253 S253-2 additive authorized-target planners
-- ---------------------------------------------------------------

{- | T253-S2-06. These planners are additive. The deployed-policy
'runBoardPostTransaction' and 'runBoardUpdateTransaction' proofs at the top of
this module are untouched and still pass, which is the compatibility half of
the task; what is new is here.

The property that matters: a Post must consume the exact output reference the
witness signed, and funding selection must not be able to substitute or drop
it. An Update's successor must carry the exact out-ref being spent, so one
authorization blesses one successor of one predecessor.
-}
authorizedBoardPlannerSpec :: Spec
authorizedBoardPlannerSpec = describe "authorized board planners" $ do
    it "names the exact signed nonce and the six-field datum" $ do
        plan <- expectPostPlan
        authorizedPostNonceReference plan `shouldBe` renderTxIn nonceTxIn
        authorizedPostPolicy plan `shouldBe` scriptHashText boardScriptHash
        authorizedPostAssetName plan `shouldBe` hexText authorizedWitness
        authorizedPostDepositLovelace plan `shouldBe` 2_000_000
        authorizedPostDatum plan
            `shouldBe` plutusDataJson
                (authorizedBoardDatumData authorizedPostDatumValue)

    it "refuses a post whose supplied input is not the signed nonce" $
        mkAuthorizedBoardPostPlan
            resolvedTarget
            (renderAddr fundingAddr)
            2_000_000
            (stubTxIn 31)
            authorizedPostDatumValue
            `shouldSatisfy` isLeft

    it "refuses a post whose owner address is not the signed owner" $
        mkAuthorizedBoardPostPlan
            resolvedTarget
            (renderAddr changeAddr)
            2_000_000
            nonceTxIn
            authorizedPostDatumValue
            `shouldSatisfy` isLeft

    it "refuses a post datum authorized under another policy" $
        -- A genuine, correctly shaped, correctly signed authorization — for a
        -- different applied board policy.
        mkAuthorizedBoardPostPlan
            resolvedTarget
            (renderAddr fundingAddr)
            2_000_000
            nonceTxIn
            (signedDatum foreignPolicyBytes (txInNonce nonceTxIn) ownerBytes)
            `shouldSatisfy` isLeft

    it "consumes the exact nonce input and emits the authorized datum" $ do
        plan <- expectPostPlan
        (result, tx, order) <- capture $ \runtime ->
            runAuthorizedBoardPostTransaction
                (boardConfig runtime)
                plan
                nonceInput
                fundingInputs
        BoardResult txId <- either (fail . show) pure result
        let body = tx ^. bodyTxL
            MultiAsset minted = body ^. mintTxBodyL
        body ^. inputsTxBodyL
            `shouldBe` Set.fromList [stubTxIn 1, nonceTxIn]
        minted
            `shouldBe` Map.singleton
                (PolicyID boardScriptHash)
                (Map.singleton authorizedAssetName 1)
        case [ output
             | output <- toList (body ^. outputsTxBodyL)
             , output ^. addrTxOutL == markerAddr
             ] of
            [marker] ->
                inlineDatum marker
                    `shouldBe` authorizedBoardDatumData authorizedPostDatumValue
            other ->
                fail ("expected one marker output, got " <> show (length other))
        assertTerminal tx txId order

    it "refuses to run when the supplied nonce input is not the plan's" $ do
        plan <- expectPostPlan
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runAuthorizedBoardPostTransaction
                (boardConfig runtime)
                plan
                (stubTxIn 31, plainTxOut 100_000_000)
                fundingInputs
        result `shouldSatisfy` isPlanFailure
        readIORef signedRef >>= (`shouldBe` Nothing)

    it "refuses to run when the nonce is also offered as funding" $ do
        -- Funding selection must not be able to reach the nonce output: if it
        -- could, the one output the witness authorized could be spent as
        -- change instead of as the record's nonce.
        plan <- expectPostPlan
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runAuthorizedBoardPostTransaction
                (boardConfig runtime)
                plan
                nonceInput
                (fundingInputs <> [nonceInput])
        result `shouldSatisfy` isPlanFailure
        readIORef signedRef >>= (`shouldBe` Nothing)

    it "derives the update nonce from the spent board record" $ do
        plan <- expectUpdatePlan
        authorizedUpdateSpentReference plan `shouldBe` renderTxIn boardTxIn
        authorizedUpdateOwnerKeyHash plan `shouldBe` hexText ownerBytes
        authorizedUpdateDatum plan
            `shouldBe` plutusDataJson
                (authorizedBoardDatumData authorizedSuccessorValue)

    it "refuses a pre-signed successor bound to another out-ref" $
        mkAuthorizedBoardUpdatePlan
            resolvedTarget
            (renderAddr fundingAddr)
            authorizedEntry
            -- genuinely signed, but for the Post nonce rather than the exact
            -- board out-ref being spent
            authorizedPostDatumValue
            `shouldSatisfy` isLeft

    it "spends the board record, requires the owner, and mints nothing" $ do
        plan <- expectUpdatePlan
        (result, tx, order) <- capture $ \runtime ->
            runAuthorizedBoardUpdateTransaction
                (boardConfig runtime)
                plan
                fundingInputs
                authorizedBoardInput
        BoardResult txId <- either (fail . show) pure result
        let body = tx ^. bodyTxL
        body ^. inputsTxBodyL `shouldBe` Set.fromList [stubTxIn 1, boardTxIn]
        body ^. mintTxBodyL `shouldBe` mempty
        body ^. reqSignerHashesTxBodyL `shouldBe` Set.singleton ownerKeyHash
        case [ output
             | output <- toList (body ^. outputsTxBodyL)
             , output ^. addrTxOutL == markerAddr
             ] of
            [marker] ->
                inlineDatum marker
                    `shouldBe` authorizedBoardDatumData authorizedSuccessorValue
            other ->
                fail ("expected one successor output, got " <> show (length other))
        assertTerminal tx txId order

expectPostPlan :: IO AuthorizedBoardPostPlan
expectPostPlan =
    either
        (fail . show)
        pure
        ( mkAuthorizedBoardPostPlan
            resolvedTarget
            (renderAddr fundingAddr)
            2_000_000
            nonceTxIn
            authorizedPostDatumValue
        )

expectUpdatePlan :: IO AuthorizedBoardUpdatePlan
expectUpdatePlan =
    either
        (fail . show)
        pure
        ( mkAuthorizedBoardUpdatePlan
            resolvedTarget
            (renderAddr fundingAddr)
            authorizedEntry
            authorizedSuccessorValue
        )

resolvedTarget :: ResolvedBoardTarget
resolvedTarget =
    ResolvedBoardTarget
        { resolvedTargetPolicyId = scriptHashText boardScriptHash
        , resolvedTargetAddress = renderAddr markerAddr
        , resolvedTargetReference = renderTxIn boardReference
        }

targetPolicyBytes, foreignPolicyBytes :: ByteString
targetPolicyBytes = boardHex (TE.encodeUtf8 $ scriptHashText boardScriptHash)
foreignPolicyBytes = BS.replicate 28 0x5a

nonceTxIn :: TxIn
nonceTxIn = stubTxIn 30

nonceInput :: (TxIn, TxOut ConwayEra)
nonceInput = (nonceTxIn, plainTxOut 100_000_000)

txInNonce :: TxIn -> BoardNonce
txInNonce (TxIn txid (TxIx index)) =
    BoardNonce
        (hashToBytes . extractHash $ unTxId txid)
        (fromIntegral index)

{- | A witness key whose secret this module holds, so it can produce genuine
authorizations over the synthetic target policy. The production module never
sees a private key; this is test material only.
-}
authorizedSignKey :: SignKeyDSIGN Ed25519DSIGN
authorizedSignKey =
    genKeyDSIGN . mkSeedFromBytes $
        boardHex
            "5323531f0000000000000000000000000000000000000000000000000000abcd"

authorizedWitness :: ByteString
authorizedWitness =
    rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN authorizedSignKey)

signAuthorized :: ByteString -> ByteString
signAuthorized message =
    rawSerialiseSigDSIGN (signDSIGN () message authorizedSignKey)

authorizedRecord :: ByteString
authorizedRecord = "loc/scheme-authorized-planner"

-- | A complete, genuinely signed authorized datum for the given binding.
signedDatum :: ByteString -> BoardNonce -> ByteString -> AuthorizedBoardDatum
signedDatum policyBytes nonce ownerHash =
    unsigned
        { authorizedSignature =
            signAuthorized . boardAuthorizationBytes $
                reconstructBoardAuthorization policyBytes unsigned
        }
  where
    unsigned =
        AuthorizedBoardDatum
            { authorizedWitnessKey = authorizedWitness
            , authorizedEndpointRecord = authorizedRecord
            , authorizedEndpointSignature = signAuthorized authorizedRecord
            , authorizedOwnerKeyHash = ownerHash
            , authorizedNonce = nonce
            , authorizedSignature = BS.replicate 64 0x00
            }

authorizedPostDatumValue, authorizedSuccessorValue :: AuthorizedBoardDatum
authorizedPostDatumValue =
    signedDatum targetPolicyBytes (txInNonce nonceTxIn) ownerBytes
authorizedSuccessorValue =
    signedDatum targetPolicyBytes (txInNonce boardTxIn) ownerBytes

authorizedAssetName :: AssetName
authorizedAssetName = AssetName (SBS.toShort authorizedWitness)

authorizedBoardInput :: (TxIn, TxOut ConwayEra)
authorizedBoardInput =
    ( boardTxIn
    , mkBasicTxOut
        markerAddr
        ( MaryValue
            (Coin 2_000_000)
            ( MultiAsset $
                Map.singleton
                    (PolicyID boardScriptHash)
                    (Map.singleton authorizedAssetName 1)
            )
        )
    )

authorizedEntry :: BoardEntry
authorizedEntry =
    BoardEntry
        { boardWitnessKey = authorizedWitness
        , boardAid = "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
        , boardScheme = "https"
        , boardUrl = "https://witness-test.example/"
        , boardTxId = txIdText boardTxIn
        , boardIndex = 0
        , boardLovelace = 2_000_000
        , boardOwnerKeyHash = ownerBytes
        }

txIdText :: TxIn -> Text
txIdText (TxIn txid _) = renderTxId txid
