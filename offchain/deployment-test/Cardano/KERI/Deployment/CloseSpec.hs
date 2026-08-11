{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.CloseSpec
Description : #181 Slice 3 in-process Close migration proof
-}
module Cardano.KERI.Deployment.CloseSpec (spec) where

import Cardano.Crypto.Hash (
    hashFromStringAsHex,
    hashToBytes,
 )
import Cardano.KERI.Deployment.CloseTransaction (
    CloseConfig (..),
    CloseError (..),
    CloseObservationTimeout (..),
    ClosePlan (..),
    CloseResult (..),
    awaitClose,
    runCloseTransaction,
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
    shouldNotBe,
    shouldNotContain,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "in-process close transaction" $ do
    it "freezes burn, spend, exact refund, references, collateral, signing, submission, tx-id, and settlement" $ do
        findExecutable "cardano-cli" >>= (`shouldBe` Nothing)
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runCloseTransaction
                (closeConfig runtime)
                syntheticPlan
                fundingInputs
                activeInput
        case result of
            Left err -> fail ("expected close success, got " <> show err)
            Right CloseResult{closeResultTxId} -> do
                signed <- readIORef signedRef
                case signed of
                    Nothing -> fail "trSign was never called"
                    Just tx -> do
                        -- T240-S1-01: no-op unless CKERI_PARITY_ORACLE_DIR
                        -- is set; see Cardano.KERI.Deployment.ParityOracle.Capture.
                        captureShape "close" (renderTxId (transactionId tx)) tx
                        let body = tx ^. bodyTxL
                            outputs = toList (body ^. outputsTxBodyL)
                            MultiAsset minted = body ^. mintTxBodyL
                            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
                            spendPurpose =
                                ConwaySpending . AsIx . fromIntegral . fromJust $
                                    Set.lookupIndex activeTxIn (body ^. inputsTxBodyL)
                        body ^. inputsTxBodyL
                            `shouldBe` Set.fromList [stubTxIn 1, activeTxIn]
                        body ^. collateralInputsTxBodyL
                            `shouldBe` Set.singleton (stubTxIn 2)
                        body ^. referenceInputsTxBodyL
                            `shouldBe` Set.singleton checkpointReference
                        minted
                            `shouldBe` Map.singleton
                                (PolicyID checkpointScriptHash)
                                (Map.singleton syntheticAssetName (-1))
                        case [output | output <- outputs, output ^. addrTxOutL == refundAddr] of
                            [refund] -> do
                                refund ^. coinTxOutL `shouldBe` Coin 7_000_000
                                refund ^. datumTxOutL `shouldBe` LedgerData.NoDatum
                            other -> fail ("expected one exact refund output, got " <> show (length other))
                        redeemerData spendPurpose redeemers
                            `shouldBe` Just spendRedeemer
                        redeemerData (ConwayMinting $ AsIx 0) redeemers
                            `shouldBe` Just mintRedeemer
                        body ^. feeTxBodyL `shouldSatisfy` (> Coin 0)
                        length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
                        transactionId tx `shouldBe` closeResultTxId
                        transactionId tx `shouldSatisfy` (/= disagreeingId)
                order <- reverse <$> readIORef callsRef
                take 1 order `shouldBe` ["query"]
                order `shouldContain` ["evaluate"]
                drop (length order - 3) order
                    `shouldBe` ["sign", "submit", "observe"]

    it "fails closed on stale value, underfunding, evaluation rejection, and submission rejection" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        staleValue <-
            runCloseTransaction
                (closeConfig baseRuntime)
                syntheticPlan{closePlanRefundLovelace = 7_000_001}
                fundingInputs
                activeInput
        staleValue `shouldSatisfy` isPlanFailure
        underfunded <-
            runCloseTransaction
                (closeConfig baseRuntime)
                syntheticPlan
                [(stubTxIn 1, plainTxOut 1_000_000), (stubTxIn 2, plainTxOut 500_000)]
                activeInput
        underfunded `shouldSatisfy` isFundingFailure
        evaluation <-
            runCloseTransaction
                ( closeConfig
                    baseRuntime
                        { trEvaluate = \_ ->
                            pure
                                ( Map.singleton
                                    (ConwayMinting $ AsIx 0)
                                    (Left $ UnknownTxIn $ stubTxIn 99)
                                )
                        }
                )
                syntheticPlan
                fundingInputs
                activeInput
        evaluation `shouldSatisfy` isEvaluationFailure
        submission <-
            runCloseTransaction
                (closeConfig baseRuntime{trSubmit = \_ -> pure (Rejected "close submit rejected")})
                syntheticPlan
                fundingInputs
                activeInput
        submission `shouldSatisfy` isSubmissionFailure

    it "reports timeout only after polling the close settlement source" $ do
        pollsRef <- newIORef (0 :: Int)
        let query _ = modifyIORef' pollsRef (+ 1) >> pure False
        result <- awaitClose query 1 0 disagreeingId
        readIORef pollsRef >>= (`shouldSatisfy` (>= 1))
        result `shouldBe` Left (CloseObservationTimeout disagreeingId)

    boundedCollateralSpec

-- ---------------------------------------------------------------------------
-- #232 bounded phase-2 collateral loss

{- | The row 'selectFundingPair' reserves as collateral for close: the smallest
eligible entry in 'fundingInputs'.
-}
closeCollateralUtxo :: (TxIn, TxOut ConwayEra)
closeCollateralUtxo = (stubTxIn 2, plainTxOut 50_000_000)

boundedCollateralSpec :: Spec
boundedCollateralSpec = describe "#232 bounded collateral" $ do
    it "returns the remainder to the funding address, not close's change address" $ do
        -- Non-vacuity: close is one of the two verbs whose ordinary change
        -- address genuinely differs from its funding address, so this
        -- assertion cannot pass without the explicit return instruction.
        fundingAddr `shouldNotBe` changeAddr
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runCloseTransaction
                (closeConfig runtime)
                syntheticPlan
                fundingInputs
                activeInput
        case result of
            Left err -> fail ("expected close success, got " <> show err)
            Right _ -> do
                tx <-
                    readIORef signedRef
                        >>= maybe (fail "trSign was never called") pure
                shouldDeclareBoundedCollateral
                    testPParams
                    fundingAddr
                    closeCollateralUtxo
                    tx

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
            runCloseTransaction
                (closeConfig cappedRuntime)
                syntheticPlan
                fundingInputs
                activeInput
        case result of
            Left
                ( CloseBuildFailed
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

isFundingFailure :: Either CloseError CloseResult -> Bool
isFundingFailure (Left CloseFundingSelectionFailed{}) = True
isFundingFailure _ = False

isPlanFailure :: Either CloseError CloseResult -> Bool
isPlanFailure (Left ClosePlanRejected{}) = True
isPlanFailure _ = False

isEvaluationFailure :: Either CloseError CloseResult -> Bool
isEvaluationFailure (Left (CloseBuildFailed TransactionBuildEvaluationRejected{})) = True
isEvaluationFailure _ = False

isSubmissionFailure :: Either CloseError CloseResult -> Bool
isSubmissionFailure (Left (CloseBuildFailed TransactionBuildSubmissionRejected{})) = True
isSubmissionFailure _ = False

closeConfig :: TransactionRuntime IO -> CloseConfig
closeConfig runtime =
    CloseConfig
        { closeRuntime = runtime
        , closeReferenceUtxos = [(checkpointReference, referenceTxOut checkpointScript)]
        , closeFundingAddress = fundingAddr
        , closeChangeAddress = changeAddr
        }

fundingInputs :: [(TxIn, TxOut ConwayEra)]
fundingInputs =
    [ (stubTxIn 1, plainTxOut 200_000_000)
    , (stubTxIn 2, plainTxOut 50_000_000)
    ]

activeInput :: (TxIn, TxOut ConwayEra)
activeInput =
    ( activeTxIn
    , mkBasicTxOut
        checkpointAddr
        ( MaryValue
            (Coin 7_000_000)
            ( MultiAsset $
                Map.singleton
                    (PolicyID checkpointScriptHash)
                    (Map.singleton syntheticAssetName 1)
            )
        )
    )

activeTxIn, checkpointReference :: TxIn
activeTxIn = stubTxIn 20
checkpointReference = stubTxIn 21

checkpointProgram :: SBS.ShortByteString
checkpointProgram = SBS.toShort "slice3-close-checkpoint-script"

checkpointScript :: Script ConwayEra
checkpointScript = mkCageScript checkpointProgram

checkpointScriptHash :: ScriptHash
checkpointScriptHash = computeScriptHash checkpointProgram

syntheticAssetName :: AssetName
syntheticAssetName = AssetName (SBS.toShort $ BS.replicate 32 0x41)

syntheticPlan :: ClosePlan
syntheticPlan =
    ClosePlan
        { closePlanSpentReference = renderTxIn activeTxIn
        , closePlanCheckpointReference = renderTxIn checkpointReference
        , closePlanPolicy = scriptHashText checkpointScriptHash
        , closePlanAssetName = hexText (BS.replicate 32 0x41)
        , closePlanRefundAddress = renderAddr refundAddr
        , closePlanRefundLovelace = 7_000_000
        , closePlanRefundOutput = "retired-cardano-cli-rendering"
        , closePlanSpendRedeemer = plutusDataJson spendRedeemer
        , closePlanMintRedeemer = plutusDataJson mintRedeemer
        }

spendRedeemer, mintRedeemer :: Data
spendRedeemer = Constr 1 [I 111]
mintRedeemer = Constr 2 [I 222]

fundingAddr, changeAddr, refundAddr, checkpointAddr :: Addr
fundingAddr = testAddr 1
changeAddr = testAddr 2
refundAddr = testAddr 3
checkpointAddr = Addr Testnet (ScriptHashObj checkpointScriptHash) StakeRefNull

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
