{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.EndpointBoardTransactionSpec
Description : #181 Slice 3 in-process endpoint-board migration proof
-}
module Cardano.KERI.Deployment.EndpointBoardTransactionSpec (spec) where

import Cardano.Crypto.Hash (
    hashFromBytes,
    hashFromStringAsHex,
    hashToBytes,
 )
import Cardano.KERI.Deployment.EndpointBoardTransaction (
    BoardConfig (..),
    BoardError (..),
    BoardObservationTimeout (..),
    BoardPostPlan (..),
    BoardResult (..),
    BoardRetirePlan (..),
    BoardUpdatePlan (..),
    awaitBoard,
    runBoardPostTransaction,
    runBoardRetireTransaction,
    runBoardUpdateTransaction,
 )
import Cardano.KERI.Deployment.ParityOracle.Capture (captureShape)
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript, scriptHashText)
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionBuildError (..),
    TransactionRuntime (..),
    signWithPaymentKey,
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
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
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
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
