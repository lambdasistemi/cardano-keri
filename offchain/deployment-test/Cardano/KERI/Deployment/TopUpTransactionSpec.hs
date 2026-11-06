{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.TopUpTransactionSpec
Description : The transaction @ckeri top-up@ assembles, executed under a recording runtime

'runTopUpTransaction' is the runner @ckeri top-up@ calls. Under a stand-in
runtime that records the calls it receives, the spec asserts what it builds
from a plan: the spent checkpoint and the payer's inputs, the collateral, the
reference script, one successor at the checkpoint address holding exactly the
planned lovelace and the token with the marked datum, the TopUp redeemer
carrying the amount as the only script purpose (no observer, no withdrawal),
the change to the funding address, and the order signing, submission and
observation happen in. The plan's refusals before anything is signed are
covered too.
-}
module Cardano.KERI.Deployment.TopUpTransactionSpec (spec) where

import Cardano.Crypto.Hash (hashFromStringAsHex, hashToBytes)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.TopUp (markedLive)
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData, topUpSpendRedeemerData)
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript, scriptHashText)
import Cardano.KERI.Deployment.TopUp (
    TopUpConfig (..),
    TopUpError (..),
    TopUpPlan (..),
    runTopUpTransaction,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionRuntime (..),
    signWithPaymentKey,
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (
    Addr (..),
    Withdrawals (..),
    serialiseAddr,
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
import Cardano.Ledger.Core (Script, TxOut, mkBasicTxOut)
import Cardano.Ledger.Credential (
    Credential (..),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash, extractHash, unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
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
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldNotContain,
    shouldSatisfy,
 )

-- The lovelace of the checkpoint output the tests spend, and of a premium.
spentLovelace, amount :: Integer
spentLovelace = 1_010_000_000
amount = 2_000_000

spec :: Spec
spec = describe "ckeri top-up: the transaction the runner assembles" $ do
    it "spends the checkpoint with TopUp, pays one marked successor exactly the amount more, and signs, submits, observes in order" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runTopUpTransaction (config runtime) plan fundingInputs activeInput
        txId <- either (\err -> fail ("expected top-up success, got " <> show err)) pure result
        tx <- readIORef signedRef >>= maybe (fail "trSign was never called") pure
        let body = tx ^. bodyTxL
            outputs = toList (body ^. outputsTxBodyL)
            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
            spendPurpose =
                ConwaySpending . AsIx . fromIntegral . fromJust $
                    Set.lookupIndex activeTxIn (body ^. inputsTxBodyL)
        body ^. inputsTxBodyL `shouldBe` Set.fromList [stubTxIn 1, activeTxIn]
        body ^. collateralInputsTxBodyL `shouldBe` Set.singleton (stubTxIn 2)
        body ^. referenceInputsTxBodyL `shouldBe` Set.singleton checkpointReference
        toList (body ^. certsTxBodyL) `shouldBe` []
        let Withdrawals withdrawals = body ^. withdrawalsTxBodyL
        withdrawals `shouldBe` Map.empty
        -- the TopUp redeemer, carrying the amount, is the only script purpose
        Map.keys redeemers `shouldBe` [spendPurpose]
        redeemerData spendPurpose redeemers `shouldBe` Just (topUpSpendRedeemerData amount)
        -- one successor at the checkpoint address: the token, the planned lovelace, the marked datum
        case [o | o <- outputs, o ^. addrTxOutL == checkpointAddr] of
            [successor] -> do
                successor ^. valueTxOutL
                    `shouldBe` MaryValue
                        (Coin (spentLovelace + amount))
                        (let MaryValue _ assets = checkpointValue in assets)
                let LedgerData.Data datum = case successor ^. datumTxOutL of
                        LedgerData.Datum binary -> LedgerData.binaryDataToData binary
                        _ -> error "the successor carries no inline datum"
                datum `shouldBe` asPlcData (V2 markedFacts)
            other -> fail ("expected one successor at the checkpoint address, got " <> show (length other))
        -- the payer funds the difference and takes the change
        [o ^. addrTxOutL | o <- outputs, o ^. addrTxOutL /= checkpointAddr]
            `shouldSatisfy` all (== fundingAddr)
        length outputs `shouldSatisfy` (>= 2)
        body ^. feeTxBodyL `shouldSatisfy` (> Coin 0)
        length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
        transactionId tx `shouldBe` txId
        order <- reverse <$> readIORef callsRef
        take 1 order `shouldBe` ["query"]
        drop (length order - 3) order `shouldBe` ["sign", "submit", "observe"]

    it "refuses a plan whose spent output is not the output resolved from the chain, before anything is signed" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runTopUpTransaction
                (config runtime)
                plan{topUpPlanSpentReference = renderTxIn (stubTxIn 99)}
                fundingInputs
                activeInput
        result `shouldSatisfy` isPlanRejected
        readIORef signedRef >>= (`shouldBe` Nothing)
        calls <- readIORef callsRef
        calls `shouldNotContain` ["sign"]
        calls `shouldNotContain` ["submit"]

    it "refuses a plan whose reference script is not the planned checkpoint program" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runTopUpTransaction
                (config runtime){topUpReferenceUtxos = []}
                plan
                fundingInputs
                activeInput
        result `shouldSatisfy` isPlanRejected
        calls <- readIORef callsRef
        calls `shouldNotContain` ["sign"]

    it "fails closed on a payer that cannot fund the amount and the collateral" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runTopUpTransaction
                (config runtime)
                plan
                [(stubTxIn 1, plainTxOut 1_000_000), (stubTxIn 2, plainTxOut 500_000)]
                activeInput
        result `shouldSatisfy` isFundingFailure
        calls <- readIORef callsRef
        calls `shouldContain` []
        calls `shouldNotContain` ["sign"]

    it "fails closed on a submission the node rejects" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        result <-
            runTopUpTransaction
                (config runtime){topUpRuntime = runtime{trSubmit = \_ -> pure (Rejected "top-up rejected")}}
                plan
                fundingInputs
                activeInput
        result `shouldSatisfy` isBuildFailure

isPlanRejected, isFundingFailure, isBuildFailure :: Either TopUpError a -> Bool
isPlanRejected (Left TopUpPlanRejected{}) = True
isPlanRejected _ = False
isFundingFailure (Left TopUpFundingSelectionFailed{}) = True
isFundingFailure _ = False
isBuildFailure (Left TopUpBuildFailed{}) = True
isBuildFailure _ = False

config :: TransactionRuntime IO -> TopUpConfig
config runtime =
    TopUpConfig
        { topUpRuntime = runtime
        , topUpReferenceUtxos = [(checkpointReference, referenceTxOut checkpointScript)]
        , topUpFundingAddress = fundingAddr
        }

-- | The spent datum, one rotation old, the top-up mark clear.
spentFacts :: CheckpointDatumV2
spentFacts =
    Live
        { lvAid = BS.replicate 44 0x45
        , lvSn = 4
        , lvEpoch = 2
        , lvPoisoned = False
        , lvFrozen = False
        , lvBornAt = 1_700_000_000_000
        , lvRefundTo = BS.cons 0x61 (BS.replicate 28 0x53)
        , lvToppedUp = False
        , lvKeys =
            KeyMaterial
                { kmCurKeys = [BS.replicate 32 0x01]
                , kmCurThreshold = Unweighted 1
                , kmNextKeys = [BS.replicate 32 0x02]
                , kmNextThreshold = Unweighted 1
                , kmWitnesses = []
                , kmToad = 0
                }
        }

markedFacts :: CheckpointDatumV2
markedFacts = fromJust (markedLive spentFacts)

plan :: TopUpPlan
plan =
    TopUpPlan
        { topUpPlanSpentReference = renderTxIn activeTxIn
        , topUpPlanCheckpointReference = renderTxIn checkpointReference
        , topUpPlanCheckpointPolicy = scriptHashText checkpointScriptHash
        , topUpPlanCheckpointAssetName = hexText (BS.replicate 32 0x31)
        , topUpPlanCheckpointAddress = renderAddr checkpointAddr
        , topUpPlanSpendRedeemer = plutusDataJson (topUpSpendRedeemerData amount)
        , topUpPlanSuccessorDatum = plutusDataJson (asPlcData (V2 markedFacts))
        , topUpPlanSuccessorLovelace = spentLovelace + amount
        , topUpPlanAmount = amount
        }

checkpointProgram :: SBS.ShortByteString
checkpointProgram = SBS.toShort "top-up-checkpoint-script"

checkpointScript :: Script ConwayEra
checkpointScript = mkCageScript checkpointProgram

checkpointScriptHash :: ScriptHash
checkpointScriptHash = computeScriptHash checkpointProgram

checkpointValue :: MaryValue
checkpointValue =
    MaryValue
        (Coin spentLovelace)
        ( MultiAsset $
            Map.singleton
                (PolicyID checkpointScriptHash)
                (Map.singleton (AssetName (SBS.toShort $ BS.replicate 32 0x31)) 1)
        )

fundingInputs :: [(TxIn, TxOut ConwayEra)]
fundingInputs =
    [ (stubTxIn 1, plainTxOut 200_000_000)
    , (stubTxIn 2, plainTxOut 50_000_000)
    ]

activeInput :: (TxIn, TxOut ConwayEra)
activeInput = (activeTxIn, mkBasicTxOut checkpointAddr checkpointValue)

activeTxIn, checkpointReference :: TxIn
activeTxIn = stubTxIn 20
checkpointReference = stubTxIn 21

fundingAddr, checkpointAddr :: Addr
fundingAddr = testAddr 1
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
plainTxOut lovelace =
    mkBasicTxOut fundingAddr (MaryValue (Coin lovelace) $ MultiAsset mempty)

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
renderAddr addr =
    Bech32.encodeLenient
        (either (error . show) id $ Bech32.humanReadablePartFromText "addr_test")
        (Bech32.dataPartFromBytes (serialiseAddr addr))

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

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
                pure (Submitted (transactionId tx))
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

redeemerData ::
    ConwayPlutusPurpose AsIx ConwayEra ->
    Map.Map
        (ConwayPlutusPurpose AsIx ConwayEra)
        (LedgerData.Data ConwayEra, a) ->
    Maybe Data
redeemerData purpose redeemers =
    (\(LedgerData.Data datum, _) -> datum) <$> Map.lookup purpose redeemers

recordCall :: IORef [String] -> String -> IO ()
recordCall ref tag = modifyIORef' ref (tag :)
