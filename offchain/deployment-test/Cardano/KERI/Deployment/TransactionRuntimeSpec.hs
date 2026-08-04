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
import Cardano.KERI.Deployment.TransactionRuntime (
    AggregateExUnitsError (..),
    BuildEvaluationResult,
    FundingPair (..),
    PayerSelectionError (..),
    PureSignError (..),
    TransactionBuildError (..),
    TransactionRuntime (..),
    TransactionRuntimeError (..),
    TransactionSigningError (..),
    checkAggregateExUnits,
    classifyEvaluation,
    runTransactionBuild,
    runTransactionBuildGeneric,
    runTransactionOperation,
    runTransactionOperationGeneric,
    selectFundingPair,
    signWithCardanoCliKey,
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (addrTxWitsL, bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, mkBasicTxOut)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (ConwaySpending))
import Cardano.Ledger.Core (mkBasicTx, witsTxL)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (KeyHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (
    DSIGN,
    KeyRole (Guard, Payment, Witness),
    VKey (..),
    WitVKey (..),
    hashKey,
 )
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
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
    collateral,
    defaultBuildOptions,
    spend,
    valid,
 )
import Cardano.Tx.Inputs (spendingIndex)
import Data.Aeson (Value, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString.Char8 qualified as BS8
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
import Data.Set qualified as Set
import Data.Text qualified as T
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import Test.Hspec (
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
signingSpec = describe "signWithCardanoCliKey" $ do
    it "signs with a PaymentSigningKeyShelley_ed25519 envelope" $
        case signWithCardanoCliKey goodEnvelope unsignedFixtureTx of
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
        case signWithCardanoCliKey trulyMalformedEnvelope unsignedFixtureTx of
            Left (TransactionSigningError (PureSignMalformedSigningKey message)) ->
                -- C1: pin the discriminating substring, not a wildcard —
                -- already proven at this exact commit by the upstream
                -- WitnessCompatSpec row 1, so this is transcribed evidence.
                T.isInfixOf "key \"type\" not found" message `shouldBe` True
            other -> fail ("expected PureSignMalformedSigningKey, got " <> show other)

    it "rejects an unsupported payment signing key envelope type" $
        case signWithCardanoCliKey unsupportedTypeEnvelope unsignedFixtureTx of
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
                pure (signWithCardanoCliKey goodEnvelope tx)
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
                        >> pure (signWithCardanoCliKey trulyMalformedEnvelope tx)
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
                        >> pure (signWithCardanoCliKey goodEnvelope tx)
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

spec :: Spec
spec = do
    evaluationSpec
    signingSpec
    runOrderSpec
    selectionSpec
    buildKernelSpec
    aggregateExUnitsSpec
