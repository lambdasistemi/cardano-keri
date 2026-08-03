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
import Cardano.KERI.Deployment.TransactionRuntime (
    PureSignError (..),
    TransactionRuntime (..),
    TransactionRuntimeError (..),
    TransactionSigningError (..),
    classifyEvaluation,
    runTransactionOperation,
    runTransactionOperationGeneric,
    signWithCardanoCliKey,
    transactionId,
 )
import Cardano.Ledger.Api.Tx (addrTxWitsL, bodyTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, mkBasicTxBody)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Core (mkBasicTx, witsTxL)
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (DSIGN, KeyRole (Guard, Witness), VKey (..), WitVKey (..), hashKey)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Data.Aeson (Value, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString.Char8 qualified as BS8
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldBe)

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
                    , trSign = \tx -> recordCall callsRef "sign" >> pure tx
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
                    , trSign = \tx -> recordCall callsRef "sign" >> pure tx
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
                (\_ -> recordCall callsRef "sign" >> pure draftTx)
                (\_ -> recordCall callsRef "submit" >> pure (Submitted (transactionId draftTx)))
                (\_ -> recordCall callsRef "observe")
                (const draftTx)
        isEvaluationRejected result `shouldBe` True
        order <- readIORef callsRef
        reverse order `shouldBe` ["query", "evaluate"]

spec :: Spec
spec = do
    evaluationSpec
    signingSpec
    runOrderSpec
