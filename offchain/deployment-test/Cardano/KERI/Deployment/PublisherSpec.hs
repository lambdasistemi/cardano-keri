{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.PublisherSpec
Description : #181 Slice 2B -- in-process Publisher migration proof

Focused proof for the frozen Slice 2B gate
(sha256 2c656cf9bb7dbaeaa1dea1085c8dfb3a37508931aead0cd33b66a6bdb36a6280).
Its pre-migration RED signal is the subprocess transaction path in
'Cardano.KERI.Deployment.Publisher'; its GREEN signal exercises the shared
'selectFundingPair' funding selection and the migrated in-process
'Cardano.KERI.Deployment.Publisher.publishOne'.

Per DIRECTION-004\/NOTE-003: no @withDevnet@, no live-validator claim.
Every proof here is a deterministic construction/runtime-order proof against
a controlled stand-in 'TransactionRuntime', never a claim about validator
acceptance. The reference-script artifact is synthesized in this spec (never
loaded from a blueprint\/@KERI_CHECKPOINT_BLUEPRINT@), so this spec is
independent of the frozen, devalued e2e FOD.
-}
module Cardano.KERI.Deployment.PublisherSpec (spec) where

import Cardano.Crypto.Hash (hashFromStringAsHex, hashToBytes)
import Cardano.KERI.Deployment.ChainIndex (ChainReference (..))
import Cardano.KERI.Deployment.Manifest (Reference (..))
import Cardano.KERI.Deployment.Publisher (
    PublishConfig (..),
    PublishError (..),
    awaitReference,
    publishOne,
 )
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    computeScriptHash,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    PayerSelectionError (..),
    TransactionRuntime (..),
    selectFundingPair,
    signWithPaymentKey,
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceScriptTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (addrTxWitsL)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (
    TxOut,
    coinTxOutL,
    fromStrictMaybeL,
    mkBasicTx,
    mkBasicTxOut,
 )
import Cardano.Ledger.Credential (Credential (KeyHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), extractHash, unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Data.Aeson (Value, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Lens.Micro ((&), (.~), (^.))
import System.Directory (findExecutable)
import Test.Hspec (Spec, describe, it, shouldBe, shouldContain, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Synthetic ledger fixtures (DIRECTION-004: never loaded from a blueprint)

fundingAddr :: Addr
fundingAddr = testAddr 1

testAddr :: Int -> Addr
testAddr n =
    Addr Testnet (KeyHashObj (KeyHash (fromJust (hashFromStringAsHex (pad n))))) StakeRefNull
  where
    pad k = replicate 55 '0' <> show (k `mod` 10)

-- | A synthetic 'TxIn' keyed by an integer tag, distinct tags avoid dedup.
stubTxIn :: Int -> TxIn
stubTxIn n =
    TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))) (TxIx 0)
  where
    hex = replicate 62 '0' <> hexByte n
    hexByte k = let d i = "0123456789abcdef" !! i in [d (k `div` 16 `mod` 16), d (k `mod` 16)]

{- | Hex-render a pure 'TxId', matching the 64-hex-character shape
'Reference'\/on-chain matching expects.
-}
renderTxId :: TxId -> Text
renderTxId = TE.decodeUtf8 . convertToBase Base16 . hashToBytes . extractHash . unTxId

plainTxOut :: Integer -> TxOut ConwayEra
plainTxOut coin = mkBasicTxOut fundingAddr (MaryValue (Coin coin) (MultiAsset mempty))

-- Oracle repair (type-level, not a weakening): 'referenceScriptTxOutL'
-- focuses a 'StrictMaybe' in the pinned ledger; compose 'fromStrictMaybeL' to
-- read it as the plain 'Maybe' this predicate checks. Semantics unchanged.
isReferenceScriptFree :: TxOut ConwayEra -> Bool
isReferenceScriptFree out =
    isNothing (out ^. (referenceScriptTxOutL . fromStrictMaybeL))

-- ---------------------------------------------------------------------------
-- selectFundingPair: shared pure error taxonomy (PROVE-LIST #4)

selectFundingPairSpec :: Spec
selectFundingPairSpec = describe "selectFundingPair" $ do
    it "distinguishes an empty indexed snapshot" $
        selectFundingPair isReferenceScriptFree (Coin 5_000_000) []
            `shouldBe` Left EmptyIndexedSnapshot

    it "distinguishes insufficient funding value" $
        selectFundingPair
            isReferenceScriptFree
            (Coin 5_000_000)
            [ (stubTxIn 1, plainTxOut 1_000_000)
            , (stubTxIn 2, plainTxOut 2_000_000)
            ]
            `shouldBe` Left
                InsufficientFundingValue
                    { requiredFundingValue = Coin 5_000_000
                    , greatestAvailableValue = Coin 2_000_000
                    }

    it "distinguishes missing collateral" $
        -- Oracle repair (type-level, not a weakening): the Slice 2A kernel's
        -- 'MissingCollateral' carries 'selectedFundingInput', so the bare
        -- constructor cannot type-check; supply the selected spend input,
        -- exactly mirroring TransactionRuntimeSpec's own selectionSpec.
        selectFundingPair
            isReferenceScriptFree
            (Coin 5_000_000)
            [(stubTxIn 1, plainTxOut 10_000_000)]
            `shouldBe` Left
                MissingCollateral
                    { selectedFundingInput = stubTxIn 1
                    }

-- ---------------------------------------------------------------------------
-- publishOne: in-process ledger evolution (PROVE-LIST #1-#3, #6, #9-#11)

sampleArtifact :: ScriptArtifact
sampleArtifact =
    ScriptArtifact
        { artifactName = "hash-proof"
        , artifactBlueprintTitle = "hash_proof.mint"
        , artifactRole = "mint"
        , artifactProgram = program
        , artifactScriptHash = computeScriptHash program
        }
  where
    program = SBS.toShort "slice2-red-synthetic-plutus-v3-program-bytes"

recordCall :: IORef [String] -> String -> IO ()
recordCall ref tag = modifyIORef' ref (tag :)

{- | Throwaway payment signing key envelope (same shape and key as
'TransactionRuntimeSpec'\'s fixture) used by the stand-in runtime's
'trSign' so the frozen ledger evolution carries exactly one real vkey
witness. No value outside this proof.
-}
publisherTestEnvelope :: Value
publisherTestEnvelope =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex"
            .= ( "582083c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde" ::
                    String
               )
        ]

{- | A tx with a different fee, hence a genuinely different pure id -- used to
prove the reported id is the *signed* tx's own id, never a
submitter-echoed one (Slice 1's 'TransactionRuntimeSpec' "differentTx"
technique, item 7\/PROVE-LIST #2).
-}
disagreeingId :: TxId
disagreeingId =
    transactionId
        (mkBasicTx (mkBasicTxBody & feeTxBodyL .~ Coin 999_999))

{- | A stand-in runtime that signs with the pinned signer
('signWithPaymentKey' over 'publisherTestEnvelope') and freezes the
post-sign transaction, so the test can independently assert on the exact
ledger evolution 'publishOne' built. The one-vkey-witness assertion lands
on that post-sign value (A-001 Finding 3), mirroring
'TransactionRuntimeSpec'\'s kernel-proof stand-in where the runtime's
signer attaches the witness.
-}
standInRuntime :: IORef [String] -> IORef (Maybe ConwayTx) -> IO (TransactionRuntime IO)
standInRuntime callsRef signedRef =
    pure
        TransactionRuntime
            { trQueryProtocolParams =
                recordCall callsRef "query" >> pure testPParams
            , trEvaluate = \_ -> recordCall callsRef "evaluate" >> pure Map.empty
            , trSign = \tx -> do
                recordCall callsRef "sign"
                let signedResult = signWithPaymentKey publisherTestEnvelope tx
                modifyIORef'
                    signedRef
                    ( const
                        ( case signedResult of
                            Right signed -> Just signed
                            Left _ -> Nothing
                        )
                    )
                pure signedResult
            , trSubmit = \_tx ->
                -- Deliberately echoes a *disagreeing* id: proves 'publishOne'
                -- reports 'transactionId' of the signed tx, not this one.
                recordCall callsRef "submit" >> pure (Submitted disagreeingId)
            , trObserve = \_ -> recordCall callsRef "observe"
            }

{- | Answers 'awaitReference'\'s query with the tx captured via 'trSign' --
i.e. "the chain now shows the transaction this run actually built as
settled", the same source of truth the ledger-boundary assertions below
already use, not a preselected answer independent of what was built.
-}
standInQueryReferences :: IORef (Maybe ConwayTx) -> Text -> IO [ChainReference]
standInQueryReferences signedRef scriptHash = do
    signed <- readIORef signedRef
    pure $ case signed of
        Nothing -> []
        Just tx -> [ChainReference scriptHash (renderTxId (transactionId tx)) 0]

publishOneSpec :: Spec
publishOneSpec = describe "publishOne" $ do
    it "publisher completes with cardano-cli absent from PATH" $ do
        -- No 'System.Process' call anywhere in this call graph. Guard: under
        -- the `publisher-path-check` recipe's restricted PATH, cardano-cli
        -- must be unresolvable, otherwise "completes without it" would be
        -- vacuous (the absence is what the rest of this proof relies on).
        -- The paired RestrictedPathSpec positive control proves the
        -- restriction mechanism itself can detect presence.
        findExecutable "cardano-cli" >>= \case
            Just path ->
                fail $
                    "cardano-cli is reachable at "
                        <> path
                        <> "; the restricted-PATH control is not in force"
            Nothing -> pure ()
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        let config =
                PublishConfig
                    { publishRuntime = runtime
                    , publishInputUtxos =
                        [ (stubTxIn 1, plainTxOut 200_000_000)
                        , (stubTxIn 2, plainTxOut 50_000_000)
                        ]
                    , publishFundingAddress = fundingAddr
                    , publishReferenceLovelace = 100_000_000
                    , publishQueryReferences = standInQueryReferences signedRef
                    , publishTimeoutSeconds = 30
                    }
        result <- publishOne config sampleArtifact
        case result of
            Left err -> fail ("expected success, got " <> show err)
            Right (_name, _reference) -> pure ()

    it "publisher freezes reference output, fee, change, collateral, signing, tx id, submission, and settlement" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        let inputUtxos =
                [ (stubTxIn 1, plainTxOut 200_000_000)
                , (stubTxIn 2, plainTxOut 50_000_000)
                ]
            config =
                PublishConfig
                    { publishRuntime = runtime
                    , publishInputUtxos = inputUtxos
                    , publishFundingAddress = fundingAddr
                    , publishReferenceLovelace = 100_000_000
                    , publishQueryReferences = standInQueryReferences signedRef
                    , publishTimeoutSeconds = 30
                    }
        result <- publishOne config sampleArtifact
        case result of
            Left err -> fail ("expected success, got " <> show err)
            Right (name, reference) -> do
                name `shouldBe` artifactName sampleArtifact
                T.length (referenceTxId reference) `shouldBe` 64
                signed <- readIORef signedRef
                case signed of
                    Nothing -> fail "trSign was never called: no tx was built"
                    Just tx -> do
                        let body = tx ^. bodyTxL
                            outputs = toList (body ^. outputsTxBodyL)
                        -- reference output: exactly one output carries the
                        -- reference script, at the configured lovelace.
                        case [o | o <- outputs, not (isReferenceScriptFree o)] of
                            [refOut] -> refOut ^. coinTxOutL `shouldBe` Coin 100_000_000
                            other -> fail ("expected exactly one reference output, got " <> show (length other))
                        -- change: a second, reference-script-free output.
                        length [o | o <- outputs, isReferenceScriptFree o] `shouldBe` 1
                        -- fee: real, positive -- non-degenerate PParams pays for it.
                        (body ^. feeTxBodyL) `shouldSatisfy` (> Coin 0)
                        -- PROVE-LIST #11, honest per RULING-001 SS11: a
                        -- script-free publish witnesses no scripts and
                        -- declares no collateral -- state that truth.
                        body ^. collateralInputsTxBodyL `shouldBe` mempty
                        -- signing: exactly one vkey witness attached.
                        length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
                        -- one evolution: the reported id is the *signed*
                        -- tx's own pure id, proven to differ from the
                        -- submitter's deliberately-disagreeing echoed id.
                        renderTxId (transactionId tx) `shouldBe` referenceTxId reference
                        transactionId tx `shouldSatisfy` (/= disagreeingId)
                -- A-001 Finding 2: Slice 2A's proven order shape. The pinned
                -- builder's fee-convergence retry may evaluate more than once
                -- on the success path, so the middle is a containment, while
                -- the first phase and the final sign/submit/observe tail are
                -- exact (TransactionRuntimeSpec kernel precedent).
                order <- reverse <$> readIORef callsRef
                take 1 order `shouldBe` ["query"]
                order `shouldContain` ["evaluate"]
                drop (length order - 3) order `shouldBe` ["sign", "submit", "observe"]

-- ---------------------------------------------------------------------------
-- awaitReference: exact-id settlement matching behind an injected chain-query
-- primitive (DIRECTION-008 SS2/SS3: production code under test, driven by a
-- controlled clock and a controlled observation source -- never a
-- 'trObserve' stand-in that hands back the answer).

awaitReferenceSpec :: Spec
awaitReferenceSpec = describe "awaitReference" $ do
    it "reports observation timeout, having actually polled" $ do
        -- DIRECTION-009: timeoutSeconds=0 alone cannot distinguish a real
        -- poll-with-deadline from a short-circuit that never queries the
        -- chain at all. Count invocations of the injected query and require
        -- at least one, so the timeout is reached by observing and
        -- rejecting a real (empty) answer, not by skipping the observation.
        pollsRef <- newIORef (0 :: Int)
        let neverMatches _scriptHash = do
                modifyIORef' pollsRef (+ 1)
                pure []
        result <- awaitReference neverMatches 100_000 0 "deadbeef" "cafef00d"
        polls <- readIORef pollsRef
        polls `shouldSatisfy` (>= 1)
        case result of
            Left (TransactionObservationTimeout scriptHash txId) -> do
                scriptHash `shouldBe` "deadbeef"
                txId `shouldBe` "cafef00d"
            other -> fail ("expected TransactionObservationTimeout, got " <> show other)

    it "reports observation timeout reached through the loop, not around it" $ do
        -- The deadline is crossed only after several real, observed,
        -- non-matching polls -- proving the elapsed-time branch is reached
        -- by iterating the loop, not merely checked once before any query.
        -- A short real poll delay (0.15s) keeps this a fast unit test while
        -- still being a genuine multi-iteration wait.
        pollsRef <- newIORef (0 :: Int)
        let neverMatches _scriptHash = do
                modifyIORef' pollsRef (+ 1)
                pure []
        result <- awaitReference neverMatches 150_000 1 "deadbeef" "cafef00d"
        polls <- readIORef pollsRef
        polls `shouldSatisfy` (>= 2)
        case result of
            Left (TransactionObservationTimeout scriptHash txId) -> do
                scriptHash `shouldBe` "deadbeef"
                txId `shouldBe` "cafef00d"
            other -> fail ("expected TransactionObservationTimeout, got " <> show other)

    it "matches the exact script hash and transaction id once the chain reports it" $ do
        -- The query genuinely returns candidates; the match is decided by
        -- 'awaitReference' itself, not preselected. One decoy differs only
        -- in script hash, another only in transaction id, so the match
        -- proves the conjunction of both, not either half alone.
        let candidates =
                [ ChainReference "other-script" "cafef00d" 0
                , ChainReference "deadbeef" "wrong-tx-id" 1
                , ChainReference "deadbeef" "cafef00d" 3
                ]
        result <- awaitReference (\_ -> pure candidates) 5_000_000 30 "deadbeef" "cafef00d"
        case result of
            Right reference -> do
                referenceTxId reference `shouldBe` "cafef00d"
                referenceIndex reference `shouldBe` 3
            Left err -> fail ("expected a match, got " <> show err)

spec :: Spec
spec = do
    selectFundingPairSpec
    awaitReferenceSpec
    publishOneSpec
