{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.AdvanceSpec
Description : #181 Slice 3 in-process Advance migration proof
-}
module Cardano.KERI.Deployment.AdvanceSpec (spec) where

import Cardano.Crypto.Hash (hashFromStringAsHex, hashToBytes)
import Cardano.KERI.Deployment.AdvanceTransaction (
    AdvanceConfig (..),
    AdvanceError (..),
    AdvanceObservationTimeout (..),
    AdvancePlan (..),
    AdvanceResult (..),
    awaitAdvance,
    runAdvanceTransaction,
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript, scriptHashText)
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionBuildError (..),
    TransactionRuntime (..),
    signWithPaymentKey,
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
    serialiseAccountAddress,
    serialiseAddr,
 )
import Cardano.Ledger.Alonzo.Plutus.Evaluate (
    TransactionScriptFailure (UnknownTxIn),
 )
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data qualified as LedgerData
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    addrTxOutL,
    datumTxOutL,
    referenceScriptTxOutL,
    valueTxOutL,
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
import Cardano.Ledger.Conway.TxCert (
    ConwayDelegCert (ConwayRegCert),
    ConwayTxCert (ConwayTxCertDeleg),
 )
import Cardano.Ledger.Core (
    Script,
    TxOut,
    mkBasicTx,
    mkBasicTxOut,
    ppKeyDepositL,
 )
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
    shouldSatisfy,
 )

spec :: Spec
spec = describe "in-process advance transaction" $ do
    it "freezes state spend/output, references, redeemers, collateral, signing, submission, tx-id, and settlement" $ do
        findExecutable "cardano-cli" >>= (`shouldBe` Nothing)
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runAdvanceTransaction
                (advanceConfig runtime)
                syntheticPlan
                fundingInputs
                activeInput
                True
        case result of
            Left err -> fail ("expected advance success, got " <> show err)
            Right AdvanceResult{resultObserverRegistrationTxId, resultAdvanceTxId} -> do
                resultObserverRegistrationTxId `shouldBe` Just resultAdvanceTxId
                signed <- readIORef signedRef
                case signed of
                    Nothing -> fail "trSign was never called"
                    Just tx -> do
                        let body = tx ^. bodyTxL
                            outputs = toList (body ^. outputsTxBodyL)
                            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
                            expectedCertificate =
                                ConwayTxCertDeleg $
                                    ConwayRegCert
                                        (ScriptHashObj observerScriptHash)
                                        (SJust $ testPParams ^. ppKeyDepositL)
                        body ^. inputsTxBodyL
                            `shouldBe` Set.fromList [stubTxIn 1, activeTxIn]
                        body ^. collateralInputsTxBodyL
                            `shouldBe` Set.singleton (stubTxIn 2)
                        body ^. referenceInputsTxBodyL
                            `shouldBe` Set.fromList [checkpointReference, observerReference]
                        toList (body ^. certsTxBodyL)
                            `shouldBe` [expectedCertificate]
                        case [output | output <- outputs, output ^. addrTxOutL == checkpointAddr] of
                            [stateOutput] -> do
                                stateOutput ^. valueTxOutL `shouldBe` checkpointValue
                                stateOutput ^. datumTxOutL
                                    `shouldSatisfy` (/= LedgerData.NoDatum)
                            other -> fail ("expected one successor state output, got " <> show (length other))
                        let LedgerData.Data successor =
                                case [output ^. datumTxOutL | output <- outputs, output ^. addrTxOutL == checkpointAddr] of
                                    [LedgerData.Datum binary] -> LedgerData.binaryDataToData binary
                                    _ -> error "successor datum missing"
                            withdrawalPurpose = ConwayRewarding (AsIx 0)
                            certificatePurpose = ConwayCertifying (AsIx 0)
                            spendPurpose =
                                ConwaySpending . AsIx . fromIntegral . fromJust $
                                    Set.lookupIndex activeTxIn (body ^. inputsTxBodyL)
                        successor `shouldBe` successorDatum
                        redeemerData spendPurpose redeemers `shouldBe` Just spendRedeemer
                        redeemerData withdrawalPurpose redeemers `shouldBe` Just observerRedeemer
                        redeemerData certificatePurpose redeemers
                            `shouldBe` Just (I 0)
                        let Withdrawals withdrawals =
                                body ^. withdrawalsTxBodyL
                        Map.lookup observerRewardAccount withdrawals
                            `shouldBe` Just (Coin 0)
                        body ^. feeTxBodyL `shouldSatisfy` (> Coin 0)
                        length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
                        transactionId tx `shouldBe` resultAdvanceTxId
                        transactionId tx `shouldSatisfy` (/= disagreeingId)
                order <- reverse <$> readIORef callsRef
                take 1 order `shouldBe` ["query"]
                order `shouldContain` ["evaluate"]
                drop (length order - 3) order
                    `shouldBe` ["sign", "submit", "observe"]

    it "fails closed on underfunding, evaluation rejection, and submission rejection" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        underfunded <-
            runAdvanceTransaction
                (advanceConfig baseRuntime)
                syntheticPlan
                [(stubTxIn 1, plainTxOut 1_000_000), (stubTxIn 2, plainTxOut 500_000)]
                activeInput
                False
        underfunded `shouldSatisfy` isFundingFailure
        let evaluationRuntime =
                baseRuntime
                    { trEvaluate = \_ ->
                        pure
                            ( Map.singleton
                                (ConwaySpending $ AsIx 0)
                                (Left $ UnknownTxIn $ stubTxIn 99)
                            )
                    }
        evaluation <-
            runAdvanceTransaction
                (advanceConfig evaluationRuntime)
                syntheticPlan
                fundingInputs
                activeInput
                False
        evaluation `shouldSatisfy` isEvaluationFailure
        let submissionRuntime =
                baseRuntime
                    { trSubmit = \_ -> pure (Rejected "advance submit rejected")
                    }
        submission <-
            runAdvanceTransaction
                (advanceConfig submissionRuntime)
                syntheticPlan
                fundingInputs
                activeInput
                False
        submission `shouldSatisfy` isSubmissionFailure

    it "reports timeout only after polling the advance settlement source" $ do
        pollsRef <- newIORef (0 :: Int)
        let query _ _ = modifyIORef' pollsRef (+ 1) >> pure []
        result <-
            awaitAdvance
                query
                1
                0
                syntheticPolicy
                syntheticAssetNameText
                "signed-advance-id"
                syntheticCheckpointAddress
        readIORef pollsRef >>= (`shouldSatisfy` (>= 1))
        result
            `shouldBe` Left
                ( AdvanceObservationTimeout
                    syntheticPolicy
                    syntheticAssetNameText
                    "signed-advance-id"
                    syntheticCheckpointAddress
                )

isFundingFailure :: Either AdvanceError AdvanceResult -> Bool
isFundingFailure (Left AdvanceFundingSelectionFailed{}) = True
isFundingFailure _ = False

isEvaluationFailure :: Either AdvanceError AdvanceResult -> Bool
isEvaluationFailure (Left (AdvanceBuildFailed TransactionBuildEvaluationRejected{})) = True
isEvaluationFailure _ = False

isSubmissionFailure :: Either AdvanceError AdvanceResult -> Bool
isSubmissionFailure (Left (AdvanceBuildFailed TransactionBuildSubmissionRejected{})) = True
isSubmissionFailure _ = False

advanceConfig :: TransactionRuntime IO -> AdvanceConfig
advanceConfig runtime =
    AdvanceConfig
        { advanceRuntime = runtime
        , advanceReferenceUtxos = referenceInputs
        , advanceFundingAddress = fundingAddr
        , advanceObserverRewardAccount = observerRewardAccount
        }

fundingInputs :: [(TxIn, TxOut ConwayEra)]
fundingInputs =
    [ (stubTxIn 1, plainTxOut 200_000_000)
    , (stubTxIn 2, plainTxOut 50_000_000)
    ]

activeInput :: (TxIn, TxOut ConwayEra)
activeInput = (activeTxIn, mkBasicTxOut checkpointAddr checkpointValue)

activeTxIn, checkpointReference, observerReference :: TxIn
activeTxIn = stubTxIn 20
checkpointReference = stubTxIn 21
observerReference = stubTxIn 22

referenceInputs :: [(TxIn, TxOut ConwayEra)]
referenceInputs =
    [ (checkpointReference, referenceTxOut checkpointScript)
    , (observerReference, referenceTxOut observerScript)
    ]

checkpointProgram, observerProgram :: SBS.ShortByteString
checkpointProgram = SBS.toShort "slice3-advance-checkpoint-script"
observerProgram = SBS.toShort "slice3-advance-observer-script"

checkpointScript, observerScript :: Script ConwayEra
checkpointScript = mkCageScript checkpointProgram
observerScript = mkCageScript observerProgram

checkpointScriptHash, observerScriptHash :: ScriptHash
checkpointScriptHash = computeScriptHash checkpointProgram
observerScriptHash = computeScriptHash observerProgram

syntheticPolicy, syntheticAssetNameText, syntheticCheckpointAddress :: Text
syntheticPolicy = scriptHashText checkpointScriptHash
syntheticAssetNameText = hexText (BS.replicate 32 0x31)
syntheticCheckpointAddress = renderAddr checkpointAddr

syntheticAssetName :: AssetName
syntheticAssetName = AssetName (SBS.toShort $ BS.replicate 32 0x31)

checkpointValue :: MaryValue
checkpointValue =
    MaryValue
        (Coin 7_000_000)
        ( MultiAsset $
            Map.singleton
                (PolicyID checkpointScriptHash)
                (Map.singleton syntheticAssetName 1)
        )

syntheticPlan :: AdvancePlan
syntheticPlan =
    AdvancePlan
        { planSpentReference = renderTxIn activeTxIn
        , planCheckpointReference = renderTxIn checkpointReference
        , planAdvanceReference = renderTxIn observerReference
        , planAdvanceRewardAddress =
            renderRewardAccount observerRewardAccount
        , planCheckpointPolicy = syntheticPolicy
        , planCheckpointAssetName = syntheticAssetNameText
        , planCheckpointAddress = syntheticCheckpointAddress
        , planStateOutput = "retired-cardano-cli-rendering"
        , planSpendRedeemer = plutusDataJson spendRedeemer
        , planObserverRedeemer = plutusDataJson observerRedeemer
        , planSuccessorDatum = plutusDataJson successorDatum
        }

spendRedeemer, observerRedeemer, successorDatum :: Data
spendRedeemer = Constr 1 [I 101]
observerRedeemer = Constr 2 [I 202]
successorDatum = Constr 3 [I 303]

fundingAddr, checkpointAddr :: Addr
fundingAddr = testAddr 1
checkpointAddr = Addr Testnet (ScriptHashObj checkpointScriptHash) StakeRefNull

observerRewardAccount :: AccountAddress
observerRewardAccount =
    AccountAddress Testnet (AccountId $ ScriptHashObj observerScriptHash)

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
renderTxId =
    TE.decodeUtf8
        . convertToBase Base16
        . hashToBytes
        . extractHash
        . unTxId

renderAddr :: Addr -> Text
renderAddr = renderBech32 "addr_test" . serialiseAddr

renderRewardAccount :: AccountAddress -> Text
renderRewardAccount = renderBech32 "stake_test" . serialiseAccountAddress

renderBech32 :: Text -> BS.ByteString -> Text
renderBech32 prefix bytes =
    Bech32.encodeLenient
        (either (error . show) id $ Bech32.humanReadablePartFromText prefix)
        (Bech32.dataPartFromBytes bytes)

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
