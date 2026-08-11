{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.TransactionRuntimeSpec
Description : #181 Slice 1 — indexer-neutral transaction runtime

Focused proof for @specs\/181-no-cardano-cli\/plan.md@ and gate v3
(sha256 175b6e638eeb14b2952250559ba39f8c64f6be5b4ca1572dae704ceb2ba6d63e):
call-order/fail-closed control flow, a parametric raw-map evaluation
classifier (per NOTE-007 — no ledger-internal constructor introspection), and
signing composed from the pinned, pure @cardano-tx-tools:tx-sign-core@
sublibrary's four operations (upstream PR #137, pin `497326d4…`).

Per NOTE-008: the exact production 'TransactionRuntime' (whose 'trEvaluate'
is pinned to @ConwayTx -> m (EvaluateTxResult ConwayEra)@) is exercised
directly wherever a trivial @Map.empty@ evaluation result suffices (the
success path and the submission-rejection path). Only the evaluation-
rejection short-circuit test — which genuinely needs a non-empty map entry —
goes through the separately named generic core
'runTransactionOperationGeneric' with local 'ProofPurpose'\/'ProofFailure'
stand-ins, so no ledger-internal 'TransactionScriptFailure' constructor is
ever built by this test.
-}
module Cardano.KERI.Deployment.TransactionRuntimeSpec (spec) where

import Cardano.Crypto.DSIGN.Class (deriveVerKeyDSIGN, rawDeserialiseSignKeyDSIGN)
import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript)
import Cardano.KERI.Deployment.TransactionRuntime (
    AggregateExUnitsError (..),
    BuildEvaluationResult,
    CollateralContract (..),
    CollateralSafetyError (..),
    FundingPair (..),
    PayerSelectionError (..),
    PureSignError (..),
    TransactionBuildError (..),
    TransactionRuntime (..),
    TransactionRuntimeError (..),
    TransactionSigningError (..),
    checkAggregateExUnits,
    classifyEvaluation,
    maximumCollateralLovelace,
    runPlutusTransactionBuild,
    runTransactionBuild,
    runTransactionBuildGeneric,
    runTransactionOperation,
    runTransactionOperationGeneric,
    selectFundingPair,
    signWithPaymentKey,
    transactionId,
    validateCollateralSafety,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (
    shouldDeclareBoundedCollateral,
    shouldDeclareNoCollateral,
    statedMaximumCollateralLovelace,
    statedRequiredCollateral,
    testPParams,
    withCollateralPercentage,
    withFixedFee,
 )
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (addrTxWitsL, bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    collateralReturnTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    totalCollateralTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, mkBasicTxOut)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (ConwaySpending))
import Cardano.Ledger.Core (PParams, mkBasicTx, witsTxL)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash, unsafeMakeSafeHash)
import Cardano.Ledger.Keys (
    DSIGN,
    KeyRole (Guard, Payment, Witness),
    VKey (..),
    WitVKey (..),
    hashKey,
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Cardano.Tx.Balance (CollateralUtxos (..))
import Cardano.Tx.Build (
    BuildOptions (..),
    Check (..),
    InterpretIO (..),
    TxBuild,
    attachScript,
    collateral,
    defaultBuildOptions,
    mint,
    spend,
    valid,
 )
import Cardano.Tx.Inputs (spendingIndex)
import Data.Aeson (Value, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (
    IORef,
    modifyIORef',
    newIORef,
    readIORef,
    writeIORef,
 )
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Word (Word16)
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import Test.Hspec (
    Expectation,
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldNotBe,
    shouldNotContain,
    shouldReturn,
    shouldSatisfy,
 )

-- ---------------------------------------------------------------------------
-- classifyEvaluation: parametric raw-map proof (NOTE-007)

data ProofPurpose = SpendPurpose | MintPurpose
    deriving stock (Eq, Ord, Show)

newtype ProofFailure = ProofFailure String
    deriving stock (Eq, Show)

evaluationSpec :: Spec
evaluationSpec = describe "classifyEvaluation" $ do
    it "accepts an all-success evaluation result" $ do
        let allSuccess :: Map ProofPurpose (Either ProofFailure Int)
            allSuccess =
                Map.fromList [(SpendPurpose, Right 10), (MintPurpose, Right 20)]
        classifyEvaluation allSuccess `shouldBe` Right ()

    it "rejects a mixed per-script evaluation result" $ do
        let mixed :: Map ProofPurpose (Either ProofFailure Int)
            mixed =
                Map.fromList
                    [ (SpendPurpose, Right 10)
                    , (MintPurpose, Left (ProofFailure "bad mint"))
                    ]
        case classifyEvaluation mixed of
            Right () ->
                fail "expected rejection: a rights/mapMaybe-shaped bug would drop the failure"
            Left detail -> do
                containsAsciiInfix detail "MintPurpose" `shouldBe` True
                containsAsciiInfix detail "bad mint" `shouldBe` True
  where
    containsAsciiInfix haystack needle =
        BS8.isInfixOf (BS8.pack needle) haystack

-- ---------------------------------------------------------------------------
-- Signing helper: real cardano-tx-tools reuse, positive + negative control

{- | Same throwaway-key shape as cardano-tx-tools' own
@test\/fixtures\/tx-sign\/payment.skey@ (no value outside tests).
-}
goodEnvelope :: Value
goodEnvelope =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex"
            .= ( "582083c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde" ::
                    String
               )
        ]

{- | Genuinely malformed: no @"type"@ key at all, so
'Cardano.Tx.Sign.Core.decodePaymentSigningKey' fails at the Aeson-shape
parse, before any type or length check runs.
-}
trulyMalformedEnvelope :: Value
trulyMalformedEnvelope =
    object ["cborHex" .= ("00" :: String)]

{- | Well-formed shape, unsupported @"type"@ value — a distinct failure path
from 'trulyMalformedEnvelope' (R2): the type check runs before the
@cborHex@/length checks, so this never reaches them.
-}
unsupportedTypeEnvelope :: Value
unsupportedTypeEnvelope =
    object
        [ "type" .= ("PaymentExtendedSigningKeyShelley_ed25519bip32" :: String)
        , "cborHex" .= ("00" :: String)
        ]

{- | Raw 32-byte Ed25519 signing key inside 'goodEnvelope''s @cborHex@, with
the CBOR @5820@ bytestring-length prefix already stripped.
-}
rawSigningKeyHex :: String
rawSigningKeyHex =
    "83c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde"

{- | Test-only oracle for the fixture key's derived payment key hash,
computed independently of any @cardano-tx-tools@ helper straight from
'Cardano.Crypto.DSIGN.Class'\/'Cardano.Ledger.Keys' primitives (per
NOTE-009 — the gated 'Cardano.Tx.Sign.Witness' module must not be reachable
from RED).
-}
expectedKeyHash :: KeyHash Guard
expectedKeyHash =
    case convertFromBase Base16 (BS8.pack rawSigningKeyHex) of
        Left err -> error ("test oracle: bad hex fixture: " <> err)
        Right rawBytes ->
            case rawDeserialiseSignKeyDSIGN @DSIGN rawBytes of
                Nothing -> error "test oracle: could not decode Ed25519 signing key bytes"
                Just signKey ->
                    let vkey = VKey (deriveVerKeyDSIGN signKey) :: VKey Witness
                     in guardHash (hashKey vkey)

unsignedFixtureTx :: ConwayTx
unsignedFixtureTx = mkBasicTx mkBasicTxBody

signingSpec :: Spec
signingSpec = describe "signWithPaymentKey" $ do
    it "signs with a PaymentSigningKeyShelley_ed25519 envelope" $
        case signWithPaymentKey goodEnvelope unsignedFixtureTx of
            Right signed -> do
                case Set.toList (signed ^. witsTxL . addrTxWitsL) of
                    [WitVKey vkey _] -> guardHash (hashKey vkey) `shouldBe` expectedKeyHash
                    other ->
                        fail
                            ( "expected exactly one vkey witness, got "
                                <> show (length other)
                            )
                -- R5: pins that attachPaymentWitness only touches the
                -- witness set — the body, and therefore the pure id, is
                -- unchanged. A key-hash match alone cannot detect the
                -- composition signing or attaching a different transaction.
                transactionId signed `shouldBe` transactionId unsignedFixtureTx
            Left err -> fail ("signing failed: " <> show err)

    it "rejects a malformed payment signing key envelope" $
        case signWithPaymentKey trulyMalformedEnvelope unsignedFixtureTx of
            Left (TransactionSigningError (PureSignMalformedSigningKey message)) ->
                -- C1: pin the discriminating substring, not a wildcard —
                -- already proven at this exact commit by the upstream
                -- WitnessCompatSpec row 1, so this is transcribed evidence.
                T.isInfixOf "key \"type\" not found" message `shouldBe` True
            other -> fail ("expected PureSignMalformedSigningKey, got " <> show other)

    it "rejects an unsupported payment signing key envelope type" $
        case signWithPaymentKey unsupportedTypeEnvelope unsignedFixtureTx of
            Left err ->
                err
                    `shouldBe` TransactionSigningError
                        ( PureSignUnsupportedEnvelopeType
                            "PaymentExtendedSigningKeyShelley_ed25519bip32"
                        )
            Right _ -> fail "expected PureSignUnsupportedEnvelopeType, got success"

guardHash :: KeyHash r -> KeyHash Guard
guardHash (KeyHash h) = KeyHash h

-- ---------------------------------------------------------------------------
-- runTransactionOperation: call order and fail-closed control flow

draftTx :: ConwayTx
draftTx = mkBasicTx mkBasicTxBody

{- | Same shape, different fee, so its pure id genuinely disagrees with
'draftTx''s — used to prove the runtime reports its own purely-derived id,
never a submitter-echoed one (item 7).
-}
differentTx :: ConwayTx
differentTx = draftTx & bodyTxL . feeTxBodyL .~ Coin 1

recordCall :: IORef [String] -> String -> IO ()
recordCall ref tag = modifyIORef' ref (tag :)

isEvaluationRejected :: Either TransactionRuntimeError a -> Bool
isEvaluationRejected (Left (TransactionEvaluationRejected _)) = True
isEvaluationRejected _ = False

runOrderSpec :: Spec
runOrderSpec = describe "runTransactionOperation" $ do
    it "submits and observes the signed transaction id" $ do
        -- Exact production 'TransactionRuntime' — a trivial empty evaluation
        -- map is a real, vacuously-accepting 'EvaluateTxResult ConwayEra'.
        callsRef <- newIORef []
        let expectedId = transactionId draftTx
            disagreeingId = transactionId differentTx
            runtime =
                TransactionRuntime
                    { trQueryProtocolParams =
                        recordCall callsRef "query" >> pure (error "unused pparams")
                    , trEvaluate = \_ -> recordCall callsRef "evaluate" >> pure Map.empty
                    , trSign = \tx -> recordCall callsRef "sign" >> pure (Right tx)
                    , trSubmit = \_ ->
                        recordCall callsRef "submit" >> pure (Submitted disagreeingId)
                    , trObserve = \_ -> recordCall callsRef "observe"
                    }
        result <- runTransactionOperation runtime (const draftTx)
        result `shouldBe` Right expectedId
        order <- readIORef callsRef
        reverse order `shouldBe` ["query", "evaluate", "sign", "submit", "observe"]

    it "short-circuits after submission rejection" $ do
        -- Exact production 'TransactionRuntime' again — evaluation trivially
        -- accepts, submission is the phase under test.
        callsRef <- newIORef []
        let runtime =
                TransactionRuntime
                    { trQueryProtocolParams = pure (error "unused pparams")
                    , trEvaluate = \_ -> pure Map.empty
                    , trSign = \tx -> recordCall callsRef "sign" >> pure (Right tx)
                    , trSubmit = \_ ->
                        recordCall callsRef "submit" >> pure (Rejected "node rejected it")
                    , trObserve = \_ -> recordCall callsRef "observe"
                    }
        result <- runTransactionOperation runtime (const draftTx)
        result `shouldBe` Left (TransactionSubmissionRejected "node rejected it")
        order <- readIORef callsRef
        reverse order `shouldBe` ["sign", "submit"]

    it "short-circuits after evaluation rejection" $ do
        -- Generic core with local 'ProofPurpose'/'ProofFailure' stand-ins:
        -- the only way to exercise a genuinely rejecting evaluation map
        -- without constructing an internal ledger 'TransactionScriptFailure'.
        callsRef <- newIORef []
        let rejecting :: Map ProofPurpose (Either ProofFailure Int)
            rejecting = Map.fromList [(SpendPurpose, Left (ProofFailure "boom"))]
        result <-
            runTransactionOperationGeneric
                (recordCall callsRef "query" >> pure (error "unused pparams"))
                (\_ -> recordCall callsRef "evaluate" >> pure rejecting)
                (\_ -> recordCall callsRef "sign" >> pure (Right draftTx))
                (\_ -> recordCall callsRef "submit" >> pure (Submitted (transactionId draftTx)))
                (\_ -> recordCall callsRef "observe")
                (const draftTx)
        isEvaluationRejected result `shouldBe` True
        order <- readIORef callsRef
        reverse order `shouldBe` ["query", "evaluate"]

-- ---------------------------------------------------------------------------
-- Slice 2A funding selection

stubAddr :: Addr
stubAddr =
    let h = fromJust (hashFromStringAsHex (replicate 56 '0'))
     in Addr
            Testnet
            (KeyHashObj (KeyHash h :: KeyHash Payment))
            StakeRefNull

stubTxIn :: Int -> TxIn
stubTxIn n =
    let hex =
            replicate 60 '0'
                <> hexByte (n `div` 256)
                <> hexByte (n `mod` 256)
        h = fromJust (hashFromStringAsHex hex)
     in TxIn (TxId (unsafeMakeSafeHash h)) (TxIx 0)
  where
    hexByte x =
        let digits = "0123456789abcdef"
         in [digits !! (x `div` 16), digits !! (x `mod` 16)]

fundingOutput :: Int -> Coin -> (TxIn, CardanoTxOut)
fundingOutput inputNumber amount =
    ( stubTxIn inputNumber
    , mkBasicTxOut stubAddr (MaryValue amount (MultiAsset mempty))
    )

type CardanoTxOut = TxOut ConwayEra

selectionSpec :: Spec
selectionSpec = describe "selectFundingPair" $ do
    it "distinguishes an empty indexed snapshot" $
        selectFundingPair (const True) (Coin 5_000_000) []
            `shouldBe` Left EmptyIndexedSnapshot

    it "distinguishes insufficient funding value" $ do
        let rows =
                [ fundingOutput 1 (Coin 2_000_000)
                , fundingOutput 2 (Coin 3_000_000)
                ]
        selectFundingPair (const True) (Coin 5_000_000) rows
            `shouldBe` Left
                InsufficientFundingValue
                    { requiredFundingValue = Coin 5_000_000
                    , greatestAvailableValue = Coin 3_000_000
                    }

    it "combines deterministic payer inputs while reserving collateral" $ do
        let low = fundingOutput 3 (Coin 2_000_000)
            medium = fundingOutput 4 (Coin 4_000_000)
            high = fundingOutput 5 (Coin 7_000_000)
        selectFundingPair (const True) (Coin 10_000_000) [low, medium, high]
            `shouldBe` Right
                FundingPair
                    { fundingSpend = high
                    , fundingAdditionalSpends = [medium]
                    , fundingCollateral = low
                    }

    it "reports zero eligible value for a non-empty indexed snapshot" $ do
        let rows =
                [ fundingOutput 3 (Coin 7_000_000)
                , fundingOutput 4 (Coin 9_000_000)
                ]
        selectFundingPair (const False) (Coin 5_000_000) rows
            `shouldBe` Left
                InsufficientFundingValue
                    { requiredFundingValue = Coin 5_000_000
                    , greatestAvailableValue = Coin 0
                    }

    it "distinguishes missing collateral" $ do
        let onlySpend = fundingOutput 5 (Coin 9_000_000)
        selectFundingPair (const True) (Coin 5_000_000) [onlySpend]
            `shouldBe` Left
                MissingCollateral
                    { selectedFundingInput = fst onlySpend
                    }

    it "is stable under indexed-row permutation and duplication" $ do
        let low = fundingOutput 6 (Coin 7_000_000)
            high = fundingOutput 7 (Coin 9_000_000)
            expected =
                Right
                    FundingPair
                        { fundingSpend = high
                        , fundingAdditionalSpends = []
                        , fundingCollateral = low
                        }
        selectFundingPair (const True) (Coin 5_000_000) [low, high]
            `shouldBe` expected
        selectFundingPair (const True) (Coin 5_000_000) [high, low, high, low]
            `shouldBe` expected

-- ---------------------------------------------------------------------------
-- Slice 2A converged build/sign/submit kernel

data NoCtx a

noCtx :: InterpretIO NoCtx
noCtx = InterpretIO $ \_ -> error "TransactionRuntimeSpec.noCtx: unreachable"

fundingUtxo :: (TxIn, CardanoTxOut)
fundingUtxo = fundingOutput 10 (Coin 100_000_000)

collateralUtxo :: (TxIn, CardanoTxOut)
collateralUtxo = fundingOutput 20 (Coin 20_000_000)

buildOptions :: BuildOptions
buildOptions =
    defaultBuildOptions
        { boCollateralUtxos = CollateralUtxos [collateralUtxo]
        }

buildProgram :: TxBuild NoCtx String ()
buildProgram = do
    resolvedIx <- spend (fst fundingUtxo)
    collateral (fst collateralUtxo)
    valid $ \tx ->
        let finalInputs = tx ^. bodyTxL . inputsTxBodyL
            pinnedIx = spendingIndex (fst fundingUtxo) finalInputs
         in if resolvedIx == pinnedIx && pinnedIx == 0
                then Pass
                else
                    CustomFail
                        ( "unexpected spending index: build="
                            <> show resolvedIx
                            <> ", inputs="
                            <> show pinnedIx
                        )

emptyBuildEvaluation :: ConwayTx -> IO BuildEvaluationResult
emptyBuildEvaluation _ = pure Map.empty

buildKernelSpec :: Spec
buildKernelSpec = describe "runTransactionBuild" $ do
    it "builds, balances, signs, derives, submits, and observes one transaction evolution" $ do
        callsRef <- newIORef []
        lastEvaluatedRef <- newIORef Nothing
        signInputRef <- newIORef Nothing
        submittedRef <- newIORef Nothing
        observedRef <- newIORef Nothing
        let evaluate tx = do
                recordCall callsRef "evaluate"
                writeIORef lastEvaluatedRef (Just tx)
                pure Map.empty
            sign tx = do
                recordCall callsRef "sign"
                writeIORef signInputRef (Just tx)
                pure (signWithPaymentKey goodEnvelope tx)
            submit tx = do
                recordCall callsRef "submit"
                writeIORef submittedRef (Just tx)
                pure (Submitted (transactionId differentTx))
            observe txId = do
                recordCall callsRef "observe"
                writeIORef observedRef (Just txId)
            runtime =
                TransactionRuntime
                    { trQueryProtocolParams =
                        recordCall callsRef "query" >> pure testPParams
                    , trEvaluate = evaluate
                    , trSign = sign
                    , trSubmit = submit
                    , trObserve = observe
                    }
        result <-
            runTransactionBuild
                buildOptions
                runtime
                noCtx
                [fundingUtxo]
                []
                stubAddr
                buildProgram
        signed <-
            readIORef submittedRef >>= \case
                Nothing -> fail "submit did not receive a transaction"
                Just tx -> pure tx
        signInput <-
            readIORef signInputRef >>= \case
                Nothing -> fail "sign did not receive a transaction"
                Just tx -> pure tx
        lastEvaluated <-
            readIORef lastEvaluatedRef >>= \case
                Nothing -> fail "build evaluator did not receive a transaction"
                Just tx -> pure tx
        let expectedId = transactionId signed
            finalBody = signed ^. bodyTxL
            finalInputs = finalBody ^. inputsTxBodyL
            finalCollateral = finalBody ^. collateralInputsTxBodyL
            finalOutputs = toList (finalBody ^. outputsTxBodyL)
        result `shouldBe` Right expectedId
        transactionId differentTx `shouldNotBe` expectedId
        readIORef observedRef `shouldReturn` Just expectedId
        lastEvaluated ^. bodyTxL `shouldBe` signInput ^. bodyTxL
        signInput ^. bodyTxL `shouldBe` finalBody
        finalInputs `shouldBe` Set.singleton (fst fundingUtxo)
        finalCollateral `shouldBe` Set.singleton (fst collateralUtxo)
        finalBody ^. feeTxBodyL `shouldSatisfy` (> Coin 0)
        finalOutputs `shouldSatisfy` (not . null)
        map (^. coinTxOutL) finalOutputs `shouldSatisfy` all (> Coin 0)
        spendingIndex (fst fundingUtxo) finalInputs `shouldBe` 0
        order <- reverse <$> readIORef callsRef
        take 1 order `shouldBe` ["query"]
        order `shouldContain` ["evaluate", "sign", "submit", "observe"]
        drop (length order - 3) order `shouldBe` ["sign", "submit", "observe"]

    it "reports script evaluation rejection" $ do
        callsRef <- newIORef []
        let purpose = ConwaySpending (AsIx 0)
            detail = "SpendPurpose: budget exceeded"
            evaluate _ =
                recordCall callsRef "evaluate"
                    >> pure (Map.singleton purpose (Left detail))
        result <-
            runTransactionBuildGeneric
                buildOptions
                (recordCall callsRef "query" >> pure testPParams)
                evaluate
                (\tx -> recordCall callsRef "sign" >> pure (Right tx))
                (\_ -> recordCall callsRef "submit" >> pure (Submitted (transactionId draftTx)))
                (\_ -> recordCall callsRef "observe")
                noCtx
                [fundingUtxo]
                []
                stubAddr
                buildProgram
        result `shouldBe` Left (TransactionBuildEvaluationRejected purpose detail)
        order <- reverse <$> readIORef callsRef
        -- Pinned Build.hs:1603,1667-1682 performs the second evaluation as its
        -- fee-estimate retry against a changed body; this is not our retry policy.
        order `shouldBe` ["query", "evaluate", "evaluate"]

    it "reports bad signing key" $ do
        callsRef <- newIORef []
        result <-
            runTransactionBuildGeneric
                buildOptions
                (recordCall callsRef "query" >> pure testPParams)
                (\tx -> recordCall callsRef "evaluate" >> emptyBuildEvaluation tx)
                ( \tx ->
                    recordCall callsRef "sign"
                        >> pure (signWithPaymentKey trulyMalformedEnvelope tx)
                )
                (\_ -> recordCall callsRef "submit" >> pure (Submitted (transactionId draftTx)))
                (\_ -> recordCall callsRef "observe")
                noCtx
                [fundingUtxo]
                []
                stubAddr
                buildProgram
        case result of
            Left
                ( TransactionBuildSigningRejected
                        (TransactionSigningError (PureSignMalformedSigningKey message))
                    ) -> do
                    T.isInfixOf "key \"type\" not found" message `shouldBe` True
                    T.isInfixOf (T.pack rawSigningKeyHex) message `shouldBe` False
            other -> fail ("expected typed bad-key rejection, got " <> show other)
        order <- reverse <$> readIORef callsRef
        order `shouldContain` ["evaluate", "sign"]
        order `shouldNotContain` ["submit", "observe"]
        last order `shouldBe` "sign"

    it "reports submission rejection" $ do
        callsRef <- newIORef []
        let reason = "node rejected shared build"
        result <-
            runTransactionBuildGeneric
                buildOptions
                (recordCall callsRef "query" >> pure testPParams)
                (\tx -> recordCall callsRef "evaluate" >> emptyBuildEvaluation tx)
                ( \tx ->
                    recordCall callsRef "sign"
                        >> pure (signWithPaymentKey goodEnvelope tx)
                )
                (\_ -> recordCall callsRef "submit" >> pure (Rejected reason))
                (\_ -> recordCall callsRef "observe")
                noCtx
                [fundingUtxo]
                []
                stubAddr
                buildProgram
        result `shouldBe` Left (TransactionBuildSubmissionRejected reason)
        order <- reverse <$> readIORef callsRef
        order `shouldContain` ["evaluate", "sign", "submit"]
        order `shouldNotContain` ["observe"]
        last order `shouldBe` "submit"

-- ---------------------------------------------------------------------------
-- Slice 2A aggregate execution-unit invariant

withDeclaredExUnits :: ExUnits -> ConwayTx
withDeclaredExUnits units =
    mkBasicTx mkBasicTxBody
        & witsTxL . rdmrsTxWitsL
            .~ Redeemers
                ( Map.singleton
                    (ConwaySpending (AsIx 0))
                    (Data (PLC.Constr 0 []), units)
                )

aggregateExUnitsSpec :: Spec
aggregateExUnitsSpec = describe "checkAggregateExUnits" $ do
    it "accepts aggregate execution units within the protocol maximum" $
        checkAggregateExUnits testPParams (withDeclaredExUnits (ExUnits 1 1))
            `shouldBe` Pass

    it "rejects aggregate execution units above the protocol maximum" $ do
        let declared = ExUnits 14_000_001 10_000_000_001
            maximumUnits = ExUnits 14_000_000 10_000_000_000
        checkAggregateExUnits testPParams (withDeclaredExUnits declared)
            `shouldBe` CustomFail
                AggregateExUnitsExceeded
                    { aggregateDeclaredExUnits = declared
                    , aggregateMaximumExUnits = maximumUnits
                    }

-- ---------------------------------------------------------------------------
-- #232 bounded phase-2 collateral loss
--
-- Two layers. 'collateralValidationSpec' polices
-- 'validateCollateralSafety' directly against synthetic converged bodies,
-- including shapes the pinned balancer emits today (notably the whole-input
-- fold it applies when the residual is below min-UTxO) and shapes only a
-- future balancer could emit. 'plutusKernelSpec' proves the shared Plutus
-- kernel actually runs that judgment on a really-converged body, before
-- signing, with a return address that is *not* the ordinary change address.

{- | The funding address that must receive the collateral remainder.
Deliberately distinct from 'stubAddr', the ordinary change address used by
every build in this module, so no assertion about the return destination can
pass by accident (RQ-232-03).
-}
returnAddr :: Addr
returnAddr =
    let h = fromJust (hashFromStringAsHex (replicate 55 '0' <> "1"))
     in Addr
            Testnet
            (KeyHashObj (KeyHash h :: KeyHash Payment))
            StakeRefNull

-- | The resolved 20 ADA collateral commitment used by the shared proofs.
boundedContract :: CollateralContract
boundedContract =
    CollateralContract
        { collateralInput = collateralUtxo
        , collateralReturnAddress = returnAddr
        }

{- | A synthetic converged body carrying exactly the Conway collateral fields
under test. Built by hand rather than by the balancer: these examples police
the judgment itself, so they must be able to present bodies no current
balancer would produce.
-}
collateralBody ::
    -- | final fee
    Coin ->
    -- | regular spending inputs
    Set TxIn ->
    -- | collateral inputs
    Set TxIn ->
    -- | declared total collateral
    StrictMaybe Coin ->
    -- | declared collateral return
    StrictMaybe CardanoTxOut ->
    ConwayTx
collateralBody fee spendInputs collateralInputs total returnOut =
    mkBasicTx mkBasicTxBody
        & bodyTxL . feeTxBodyL .~ fee
        & bodyTxL . inputsTxBodyL .~ spendInputs
        & bodyTxL . collateralInputsTxBodyL .~ collateralInputs
        & bodyTxL . totalCollateralTxBodyL .~ total
        & bodyTxL . collateralReturnTxBodyL .~ returnOut

-- | An ADA-only output at the funding address.
returnOutput :: Coin -> CardanoTxOut
returnOutput amount =
    mkBasicTxOut returnAddr (MaryValue amount (MultiAsset mempty))

ordinarySpends :: Set TxIn
ordinarySpends = Set.singleton (fst fundingUtxo)

declaredCollateral :: Set TxIn
declaredCollateral = Set.singleton (fst collateralUtxo)

{- | The reference conforming body: fee 1 ADA, so the exact requirement is
@ceiling (1_000_000 * 150 / 100) = 1_500_000@ against a 20 ADA collateral
input, leaving 18.5 ADA to return.
-}
conformingBody :: ConwayTx
conformingBody =
    collateralBody
        (Coin 1_000_000)
        ordinarySpends
        declaredCollateral
        (SJust (Coin 1_500_000))
        (SJust (returnOutput (Coin 18_500_000)))

validate :: ConwayTx -> Either CollateralSafetyError ConwayTx
validate = validateCollateralSafety testPParams boundedContract

collateralValidationSpec :: Spec
collateralValidationSpec = describe "#232 validateCollateralSafety" $ do
    it "states the product maximum as 5,000,000 lovelace" $ do
        maximumCollateralLovelace `shouldBe` statedMaximumCollateralLovelace
        maximumCollateralLovelace `shouldBe` Coin 5_000_000

    it "derives the exact protocol requirement from the final fee" $ do
        statedRequiredCollateral testPParams (Coin 1_000_000)
            `shouldBe` Coin 1_500_000
        -- Ceiling, not truncation: 3,333,333 * 150 / 100 = 4,999,999.5.
        statedRequiredCollateral testPParams (Coin 3_333_333)
            `shouldBe` Coin 5_000_000

    it "accepts an exactly conforming converged body" $
        validate conformingBody `shouldBe` Right conformingBody

    it "accepts a body sitting exactly on the 5,000,000-lovelace maximum" $ do
        let atMaximum =
                collateralBody
                    (Coin 3_333_333)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 5_000_000))
                    (SJust (returnOutput (Coin 15_000_000)))
        validate atMaximum `shouldBe` Right atMaximum

    it "rejects a requirement one lovelace above the 5,000,000 maximum" $ do
        -- The only difference from the accepted body above is one lovelace of
        -- fee, so nothing but the ceiling can be doing the rejecting.
        let overMaximum =
                collateralBody
                    (Coin 3_333_334)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 5_000_001))
                    (SJust (returnOutput (Coin 14_999_999)))
        validate overMaximum
            `shouldBe` Left
                ( CollateralRequirementAboveMaximum
                    (Coin 5_000_001)
                    (Coin 5_000_000)
                )

    it "rejects a collateral input that cannot fund the total and a valid return" $ do
        let smallInput = fundingOutput 21 (Coin 1_600_000)
            contract =
                CollateralContract
                    { collateralInput = smallInput
                    , collateralReturnAddress = returnAddr
                    }
            body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    (Set.singleton (fst smallInput))
                    (SJust (Coin 1_600_000))
                    SNothing
        case validateCollateralSafety testPParams contract body of
            Left
                CollateralInputInsufficient
                    { collateralRequiredLovelace
                    , collateralMinimumReturnLovelace
                    , collateralAvailableLovelace
                    } -> do
                    collateralRequiredLovelace `shouldBe` Coin 1_500_000
                    collateralAvailableLovelace `shouldBe` Coin 1_600_000
                    collateralMinimumReturnLovelace `shouldSatisfy` (> Coin 100_000)
            other -> fail ("expected CollateralInputInsufficient, got " <> show other)

    it "rejects a collateral input carrying native assets" $ do
        let assetInput =
                ( stubTxIn 22
                , mkBasicTxOut
                    stubAddr
                    ( MaryValue
                        (Coin 20_000_000)
                        ( MultiAsset $
                            Map.singleton
                                proofPolicy
                                (Map.singleton proofAssetName 1)
                        )
                    )
                )
            contract =
                CollateralContract
                    { collateralInput = assetInput
                    , collateralReturnAddress = returnAddr
                    }
            body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    (Set.singleton (fst assetInput))
                    (SJust (Coin 1_500_000))
                    (SJust (returnOutput (Coin 18_500_000)))
        validateCollateralSafety testPParams contract body
            `shouldBe` Left (CollateralInputNotAdaOnly (stubTxIn 22))

    it "rejects a collateral input set that is not exactly the contract input" $ do
        let foreign' = Set.singleton (stubTxIn 23)
            body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    foreign'
                    (SJust (Coin 1_500_000))
                    (SJust (returnOutput (Coin 18_500_000)))
        validate body
            `shouldBe` Left
                (CollateralInputSetMismatch (fst collateralUtxo) foreign')

    it "rejects a body that declares no collateral input at all" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    Set.empty
                    SNothing
                    SNothing
        validate body
            `shouldBe` Left
                (CollateralInputSetMismatch (fst collateralUtxo) Set.empty)

    it "rejects a collateral input that is also a regular spending input" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    (Set.insert (fst collateralUtxo) ordinarySpends)
                    declaredCollateral
                    (SJust (Coin 1_500_000))
                    (SJust (returnOutput (Coin 18_500_000)))
        validate body
            `shouldBe` Left (CollateralInputAlsoSpent (fst collateralUtxo))

    it "rejects a body that declares no total collateral" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    SNothing
                    (SJust (returnOutput (Coin 18_500_000)))
        validate body `shouldBe` Left (CollateralTotalMissing (Coin 1_500_000))

    it "rejects the upstream whole-input fold that consumes the entire collateral" $ do
        -- Exactly the shape pinned Balance.hs emits when the residual is below
        -- min-UTxO: total_collateral = the whole input, no return. This is the
        -- unbounded loss #232 exists to refuse.
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 20_000_000))
                    SNothing
        validate body
            `shouldBe` Left
                (CollateralTotalMismatch (Coin 1_500_000) (Coin 20_000_000))

    it "rejects an exact total with no collateral return" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 1_500_000))
                    SNothing
        validate body
            `shouldBe` Left (CollateralReturnMissing (Coin 18_500_000))

    it "rejects a collateral return paid to any address but the funding one" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 1_500_000))
                    ( SJust
                        ( mkBasicTxOut
                            stubAddr
                            (MaryValue (Coin 18_500_000) (MultiAsset mempty))
                        )
                    )
        validate body
            `shouldBe` Left (CollateralReturnMisaddressed returnAddr stubAddr)

    it "rejects a collateral return carrying native assets" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 1_500_000))
                    ( SJust
                        ( mkBasicTxOut
                            returnAddr
                            ( MaryValue
                                (Coin 18_500_000)
                                ( MultiAsset $
                                    Map.singleton
                                        proofPolicy
                                        (Map.singleton proofAssetName 1)
                                )
                            )
                        )
                    )
        validate body `shouldBe` Left (CollateralReturnNotAdaOnly returnAddr)

    it "rejects a collateral return below its own min-UTxO requirement" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 1_500_000))
                    (SJust (returnOutput (Coin 100_000)))
        case validate body of
            Left
                CollateralReturnBelowMinimum
                    { collateralDeclaredReturnLovelace
                    , collateralMinimumReturnLovelace
                    } -> do
                    collateralDeclaredReturnLovelace `shouldBe` Coin 100_000
                    collateralMinimumReturnLovelace
                        `shouldSatisfy` (> Coin 100_000)
            other -> fail ("expected CollateralReturnBelowMinimum, got " <> show other)

    it "rejects a body whose total plus return does not conserve the input" $ do
        let body =
                collateralBody
                    (Coin 1_000_000)
                    ordinarySpends
                    declaredCollateral
                    (SJust (Coin 1_500_000))
                    (SJust (returnOutput (Coin 18_499_999)))
        validate body
            `shouldBe` Left
                ( CollateralConservationViolated
                    (Coin 1_500_000)
                    (Coin 18_499_999)
                    (Coin 20_000_000)
                )

-- ---------------------------------------------------------------------------
-- #232 shared Plutus build kernel

proofScriptProgram :: SBS.ShortByteString
proofScriptProgram = SBS.toShort "s232-shared-kernel-proof-script"

proofScriptHash :: ScriptHash
proofScriptHash = computeScriptHash proofScriptProgram

proofPolicy :: PolicyID
proofPolicy = PolicyID proofScriptHash

proofAssetName :: AssetName
proofAssetName = AssetName (SBS.toShort "s232-marker")

{- | A genuinely script-bearing program: it attaches a script and mints under
its policy, so the converged body carries a redeemer and the pinned balancer
populates the Conway collateral fields at all. A redeemer-free program is used
separately, as its own negative control.
-}
plutusProgram :: TxBuild NoCtx String ()
plutusProgram = do
    _ <- spend (fst fundingUtxo)
    attachScript (mkCageScript proofScriptProgram)
    mint proofPolicy (Map.singleton proofAssetName 1) (232 :: Integer)

-- | A script-free program, mirroring Publisher: spend only, no collateral.
scriptFreeProgram :: TxBuild NoCtx String ()
scriptFreeProgram = do
    _ <- spend (fst fundingUtxo)
    pure ()

runKernel ::
    PParams ConwayEra ->
    CollateralContract ->
    TxBuild NoCtx String () ->
    IO (Either (TransactionBuildError String) TxId, Maybe ConwayTx, [String])
runKernel pparams contract program = do
    callsRef <- newIORef []
    signedRef <- newIORef Nothing
    let runtime =
            TransactionRuntime
                { trQueryProtocolParams =
                    recordCall callsRef "query" >> pure pparams
                , trEvaluate = \_ ->
                    recordCall callsRef "evaluate" >> pure Map.empty
                , trSign = \tx -> do
                    recordCall callsRef "sign"
                    let signed = signWithPaymentKey goodEnvelope tx
                    writeIORef signedRef (either (const Nothing) Just signed)
                    pure signed
                , trSubmit = \_ ->
                    recordCall callsRef "submit"
                        >> pure (Submitted (transactionId differentTx))
                , trObserve = \_ -> recordCall callsRef "observe"
                }
    result <-
        runPlutusTransactionBuild
            runtime
            noCtx
            [fundingUtxo]
            []
            stubAddr
            contract
            program
    calls <- reverse <$> readIORef callsRef
    signed <- readIORef signedRef
    pure (result, signed, calls)

plutusKernelSpec :: Spec
plutusKernelSpec = describe "#232 runPlutusTransactionBuild" $ do
    it "returns the remainder to the funding address, not the change address" $ do
        -- Non-vacuity: the two addresses genuinely differ, so an
        -- implementation that never overrides the return destination fails.
        returnAddr `shouldNotBe` stubAddr
        (result, signed, calls) <- runKernel testPParams boundedContract plutusProgram
        tx <- case (result, signed) of
            (Right txId, Just tx) -> do
                transactionId tx `shouldBe` txId
                pure tx
            (Left err, _) -> fail ("expected a bounded build, got " <> show err)
            (_, Nothing) -> fail "trSign was never called"
        shouldDeclareBoundedCollateral testPParams returnAddr collateralUtxo tx
        drop (length calls - 3) calls `shouldBe` ["sign", "submit", "observe"]

    it "refuses a converged body that declares no collateral commitment" $ do
        -- 'scriptFreeProgram' carries no redeemer, so the pinned balancer
        -- leaves both Conway collateral fields absent. A kernel that signs
        -- that body has signed an unbounded transaction.
        (result, signed, calls) <-
            runKernel testPParams boundedContract scriptFreeProgram
        case result of
            Left (TransactionBuildCollateralRejected (CollateralTotalMissing required)) ->
                required `shouldSatisfy` (> Coin 0)
            other -> fail ("expected a collateral rejection, got " <> show other)
        signed `shouldBe` Nothing
        calls `shouldNotContain` ["sign"]
        calls `shouldNotContain` ["submit"]
        calls `shouldNotContain` ["observe"]

    it "refuses a requirement above 5,000,000 lovelace before signing" $ do
        -- A flat fee of 4 ADA forces ceiling(fee * 150 / 100) >= 6 ADA,
        -- deterministically, whatever this body's size turns out to be.
        (result, signed, calls) <-
            runKernel
                (withFixedFee (Coin 4_000_000) testPParams)
                boundedContract
                plutusProgram
        case result of
            Left
                ( TransactionBuildCollateralRejected
                        CollateralRequirementAboveMaximum
                            { collateralRequiredLovelace
                            , collateralMaximumLovelace
                            }
                    ) -> do
                    collateralMaximumLovelace
                        `shouldBe` statedMaximumCollateralLovelace
                    collateralRequiredLovelace
                        `shouldSatisfy` (> statedMaximumCollateralLovelace)
            other -> fail ("expected a maximum-exceeded rejection, got " <> show other)
        signed `shouldBe` Nothing
        calls `shouldNotContain` ["sign"]
        calls `shouldNotContain` ["submit"]

    it "leaves the script-free entry point free of collateral fields" $ do
        -- DATA-INV-232-06: 'runTransactionBuild' is what Publisher uses, and
        -- it must not invent a collateral commitment.
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        let runtime =
                TransactionRuntime
                    { trQueryProtocolParams =
                        recordCall callsRef "query" >> pure testPParams
                    , trEvaluate = \_ -> pure Map.empty
                    , trSign = \tx -> do
                        let signed = signWithPaymentKey goodEnvelope tx
                        writeIORef signedRef (either (const Nothing) Just signed)
                        pure signed
                    , trSubmit = \_ -> pure (Submitted (transactionId differentTx))
                    , trObserve = \_ -> pure ()
                    }
        result <-
            runTransactionBuild
                defaultBuildOptions
                runtime
                noCtx
                [fundingUtxo]
                []
                stubAddr
                scriptFreeProgram
        case result of
            Left err -> fail ("expected a script-free build, got " <> show err)
            Right _ -> pure ()
        readIORef signedRef
            >>= maybe (fail "trSign was never called") shouldDeclareNoCollateral

-- ---------------------------------------------------------------------------
-- #232 protocol-relative value coverage
--
-- Audit finding on submission 1: every example above fixes
-- 'ppCollateralPercentageL' at the mainnet default of 150, so replacing the
-- production parameter read with a constant 150 left all 31 focused examples
-- green. Test coverage reached the right seams; *value* coverage could not
-- distinguish "reads the protocol parameter" from "happens to equal the value
-- it would have read".
--
-- The property below closes that class rather than the reported instance: the
-- percentage is varied across its whole legal range including both Word16
-- boundaries, so no fixed constant can satisfy it.

{- | The collateral percentages the proof derives against: both boundaries of
the parameter's legal 'Word16' range and a spread between them, deliberately
straddling the mainnet default so a constant 150 — or any other single
constant — fails somewhere in the table.
-}
provingCollateralPercentages :: [Word16]
provingCollateralPercentages =
    [ minBound -- 0
    , 1
    , 37
    , 100
    , 149
    , 150 -- the mainnet default the old proof was pinned to
    , 151
    , 213
    , 1_000
    , 12_345
    , 65_534
    , maxBound -- 65535
    ]

{- | Fees chosen so that @fee * p@ is frequently *not* a multiple of 100, which
is what separates a correct ceiling from a plausible truncation.
-}
provingFees :: [Coin]
provingFees =
    [ Coin 0
    , Coin 1
    , Coin 155_381
    , Coin 211_111
    , Coin 1_000_000
    , Coin 2_000_000
    ]

{- | The exact requirement, computed in the proof from the literal percentage
under test — never from anything the module under test reads.
-}
percentageRequired :: Word16 -> Coin -> Coin
percentageRequired percentage (Coin fee) =
    Coin ((fee * fromIntegral percentage + 99) `div` 100)

-- | What a plausible-but-wrong truncating implementation would produce.
percentageTruncated :: Word16 -> Coin -> Coin
percentageTruncated percentage (Coin fee) =
    Coin ((fee * fromIntegral percentage) `div` 100)

collateralAvailable :: Integer
collateralAvailable =
    let Coin available = snd collateralUtxo ^. coinTxOutL in available

{- | A conserving body at the given fee that declares exactly @declared@ as its
total collateral and returns the rest.

The remainder is clamped at zero, which matters only where the requirement
already exceeds the whole collateral input — that is, only on the
above-the-ceiling branch, which is rejected before any return is inspected.
A negative remainder is not merely uninteresting there: the ledger's own
'mkBasicTxOut' refuses to construct such an output at all.
-}
declaringTotal :: Coin -> Coin -> ConwayTx
declaringTotal fee declared@(Coin declaredLovelace) =
    collateralBody
        fee
        ordinarySpends
        declaredCollateral
        (SJust declared)
        (SJust (returnOutput remainder))
  where
    remainder = Coin (max 0 (collateralAvailable - declaredLovelace))

{- | For one @(p, fee)@ pair: the body declaring exactly
@ceiling (fee * p / 100)@ is accepted, and one lovelace either side of it is
rejected naming that exact requirement. Where the requirement itself exceeds
the product ceiling, the cap rejection carries the same derived value, so the
arithmetic is still pinned.
-}
assertPercentageDerivation :: Word16 -> Coin -> Expectation
assertPercentageDerivation percentage fee
    | required > statedMaximumCollateralLovelace =
        validateAt (declaringTotal fee required)
            `shouldBe` Left
                ( CollateralRequirementAboveMaximum
                    required
                    statedMaximumCollateralLovelace
                )
    | otherwise = do
        let conforming = declaringTotal fee required
        validateAt conforming `shouldBe` Right conforming
        mapM_ rejectsOffBy offsets
  where
    pparams = withCollateralPercentage percentage testPParams
    validateAt = validateCollateralSafety pparams boundedContract
    required@(Coin requiredLovelace) = percentageRequired percentage fee
    -- A zero requirement has no lovelace below it to test.
    offsets = 1 : [-1 | requiredLovelace > 0]
    rejectsOffBy delta =
        let declared = Coin (requiredLovelace + delta)
         in validateAt (declaringTotal fee declared)
                `shouldBe` Left (CollateralTotalMismatch required declared)

collateralPercentageSpec :: Spec
collateralPercentageSpec =
    describe "#232 protocol collateral percentage" $ do
        it "derives the exact total across the parameter's legal range, not from a constant" $
            sequence_
                [ assertPercentageDerivation percentage fee
                | percentage <- provingCollateralPercentages
                , fee <- provingFees
                ]

        it "spans both boundaries of the legal percentage range" $ do
            -- Guards the table itself. The finding this property answers was
            -- born from a fixture set that quietly sat on one value; if a later
            -- edit narrows the range back down, this goes RED rather than
            -- silently weakening the property above.
            minimum provingCollateralPercentages `shouldBe` minBound
            maximum provingCollateralPercentages `shouldBe` maxBound
            length (filter (/= 150) provingCollateralPercentages)
                `shouldSatisfy` (>= 8)

        it "includes a case where the ceiling and naive truncation differ" $ do
            -- 211,111 * 213 = 44,966,643, so the exact requirement is 449,667
            -- and a truncating implementation would say 449,666.
            percentageRequired 213 (Coin 211_111) `shouldBe` Coin 449_667
            percentageTruncated 213 (Coin 211_111) `shouldBe` Coin 449_666
            let differing =
                    [ (percentage, fee)
                    | percentage <- provingCollateralPercentages
                    , fee <- provingFees
                    , percentageRequired percentage fee
                        /= percentageTruncated percentage fee
                    ]
            differing `shouldSatisfy` (not . null)

        it "converges a real build against a non-default percentage snapshot" $ do
            -- End to end, not just the pure validator: the balancer derives
            -- total_collateral from the queried percentage, and an
            -- implementation reading anything else disagrees with the body it
            -- was handed and refuses to sign it.
            let pparams = withCollateralPercentage 200 testPParams
            (result, signed, _calls) <-
                runKernel pparams boundedContract plutusProgram
            tx <- case (result, signed) of
                (Right txId, Just tx) -> do
                    transactionId tx `shouldBe` txId
                    pure tx
                (Left err, _) ->
                    fail ("expected a bounded build at 200%, got " <> show err)
                (_, Nothing) -> fail "trSign was never called"
            shouldDeclareBoundedCollateral pparams returnAddr collateralUtxo tx
            let fee = tx ^. bodyTxL . feeTxBodyL
            tx ^. bodyTxL . totalCollateralTxBodyL
                `shouldBe` SJust (percentageRequired 200 fee)

spec :: Spec
spec = do
    evaluationSpec
    signingSpec
    runOrderSpec
    selectionSpec
    buildKernelSpec
    aggregateExUnitsSpec
    collateralValidationSpec
    plutusKernelSpec
    collateralPercentageSpec
