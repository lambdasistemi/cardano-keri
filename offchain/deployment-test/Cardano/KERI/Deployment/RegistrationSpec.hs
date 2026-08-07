{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.RegistrationSpec
Description : #181 Slice 2C -- in-process Registration migration proof

Focused proof for the frozen Slice 2C gate, extending the
'Cardano.KERI.Deployment.PublisherSpec' discipline to the two-transaction
(premint\/register) registration path. Its pre-migration RED signal is the
subprocess path in 'Cardano.KERI.Deployment.Registration'; GREEN exercises the
shared build/sign kernel with real, hash-matching reference-script UTxOs.

Pruned per DIRECTION-006 (retiring-symbol-per-assertion): the
@premintBuildArguments@\/@registerBuildArguments@ cardano-cli argument-list
assertions and the @renderCardanoCliFailure@ tests are removed because those
symbols retire with the cardano-cli composition; 'mkRegistrationPlan' and the
checkpoint-status rendering assertions migrate byte-for-byte, unaffected by
the transaction-building change.

Per DIRECTION-004\/NOTE-003: no @withDevnet@, no live-validator claim. The
ledger-boundary\/PATH-absent fixtures below use a synthetic in-spec
'RegistrationPlan' (never derived from the real KLI\/manifest fixture used by
the pure @mkRegistrationPlan@ binding test), so this module stays independent
of the frozen, devalued e2e FOD.

Oracle repairs from the inherited draft strengthen rather than weaken the
proof: the signer returns its real @Either@ and attaches a real witness to the
captured signed transaction; call order freezes the exact terminal tail while
allowing fee-convergence evaluation retries; error assertions use the current
build-kernel constructors; and the configuration carries resolved reference
UTxOs because those bytes determine reference-script fees and the integrity
hash's Plutus language set.
-}
module Cardano.KERI.Deployment.RegistrationSpec (spec) where

import Cardano.Crypto.Hash (hashFromStringAsHex, hashToBytes)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    resolveActiveCheckpoint,
 )
import Cardano.KERI.Deployment.KEL (parseInceptionExport)
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    Reference (..),
    ScriptEntry (..),
    SourceInfo (..),
 )
import Cardano.KERI.Deployment.Registration (
    AssetObservationTimeout (..),
    RegisterConfig (..),
    RegistrationCheckError (..),
    RegistrationError (..),
    RegistrationPlan (..),
    awaitAsset,
    mkRegistrationPlan,
    plutusDataJson,
    premintOne,
    registerOne,
 )
import Cardano.KERI.Deployment.Script (
    computeScriptHash,
    mkCageScript,
    scriptHashText,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    AggregateExUnitsError (..),
    TransactionBuildError (..),
    TransactionRuntime (..),
    TransactionSigningError (..),
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
import Cardano.Ledger.Alonzo.PParams (ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (UnknownTxIn))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Datum (Datum))
import Cardano.Ledger.Api.Scripts.Data qualified as LedgerData
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    addrTxOutL,
    datumTxOutL,
    referenceScriptTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (addrTxWitsL, rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (Network (Testnet), StrictMaybe (SJust), TxIx (..))
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
    coinTxOutL,
    mkBasicTx,
    mkBasicTxOut,
    ppKeyDepositL,
 )
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..), extractHash, unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Cardano.Tx.Build (Check (..))
import Codec.Binary.Bech32 qualified as Bech32
import Data.Aeson (Value, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (isLeft)
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (elemIndex)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Lens.Micro ((&), (.~), (^.))
import Paths_cardano_keri (getDataFileName)
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
spec = do
    purePlanSpec
    registrationLedgerBoundarySpec
    failureTaxonomySpec
    awaitAssetSpec

-- ---------------------------------------------------------------------------
-- Pure plan/plutus-data behaviour (migrated byte-for-byte; the retired
-- cardano-cli argument-list assertions are pruned)

purePlanSpec :: Spec
purePlanSpec =
    describe "registration transaction plan" $ do
        it "encodes detailed Plutus script data" $
            plutusDataJson (Constr 0 [B "\xab\xcd", I 7])
                `shouldBe` object
                    [ "constructor" .= (0 :: Integer)
                    , "fields"
                        .= [ object ["bytes" .= ("abcd" :: String)]
                           , object ["int" .= (7 :: Integer)]
                           ]
                    ]

        it "binds the genuine KLI export to the immutable V1 manifest" $ do
            fixture <-
                getDataFileName
                    "deployment-test/fixtures/kli-export-single.cesr"
            kel <- BS.readFile fixture >>= either fail pure . parseInceptionExport
            plan <-
                either
                    fail
                    pure
                    (mkRegistrationPlan sampleManifest 1_007_000_000 kel)
            planProofPolicy plan
                `shouldBe` "d767a22b85d0a1c1e2a987b970e990c22c423b2211e788252d28deca"
            planCheckpointPolicy plan
                `shouldBe` "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
            planCheckpointAddress plan
                `shouldBe` "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
            T.length (planProofName plan) `shouldBe` 64
            T.length (planCheckpointName plan) `shouldBe` 64
            planEscrowLovelace plan `shouldBe` 1_007_000_000
            let active =
                    ChainAssetUtxo
                        "registertx"
                        0
                        (planCheckpointAddress plan)
                        1_007_000_000
                        [ ChainAsset
                            (planCheckpointPolicy plan)
                            (planCheckpointName plan)
                            1
                        ]
                        (Just $ planCheckpointDatum plan)
            resolveActiveCheckpoint
                sampleManifest
                (planAid plan)
                (planCheckpointName plan)
                []
                `shouldSatisfy` isLeft
            resolveActiveCheckpoint
                sampleManifest
                (planAid plan)
                (planCheckpointName plan)
                [active]
                `shouldSatisfy` either
                    (const False)
                    ((== Unweighted 1) . cdCurThreshold . activeCheckpointDatum)
            resolveActiveCheckpoint
                sampleManifest
                (planAid plan)
                (planCheckpointName plan)
                [active, active]
                `shouldSatisfy` isLeft

sampleManifest :: Manifest
sampleManifest =
    Manifest
        { manifestSchemaVersion = "cardano-keri/m1-deployment-manifest/v1"
        , manifestNetwork = NetworkInfo "preprod" 1
        , manifestSource = SourceInfo "repository" "commit"
        , manifestBlueprint = BlueprintInfo "digest"
        , manifestParameters =
            DeploymentParameters
                0
                0
                1_000_000_000
                5_000_000
                10_000
        , manifestCheckpoint =
            CheckpointInfo
                "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
                "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
        , manifestPublishedAt = "2026-07-28T14:37:05Z"
        , manifestScripts =
            [ entry
                "hash-proof"
                "d767a22b85d0a1c1e2a987b970e990c22c423b2211e788252d28deca"
                "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c"
            , entry
                "observer-lifecycle"
                "3d18237dc14be14284d775a5766016c7c4c432dedce287011701c6c7"
                "c1ebe8b9a69160a04a9e490d4ab1149882f945774fba0cffac2dec7e6886b26f"
            , entry
                "checkpoint-register"
                "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
                "8a1a404f13b50ec0a266e1427f602916d830b62d757f3ac69976ccba0213c5d1"
            ]
        }
  where
    entry name hash txId =
        ScriptEntry name "blueprint" "role" hash 1 (Reference txId 0)

-- ---------------------------------------------------------------------------
-- Synthetic ledger fixtures for the in-process ledger-boundary proofs
-- (DIRECTION-004: never derived from the real manifest/blueprint above)

fundingAddr :: Addr
fundingAddr = testAddr 1

checkpointAddr :: Addr
checkpointAddr =
    Addr
        Testnet
        (ScriptHashObj checkpointScriptHash)
        StakeRefNull

testAddr :: Int -> Addr
testAddr n =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromStringAsHex (pad n)))))
        StakeRefNull
  where
    pad k = replicate 55 '0' <> show (k `mod` 10)

stubTxIn :: Int -> TxIn
stubTxIn n =
    TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))) (TxIx 0)
  where
    hex = replicate 62 '0' <> hexByte n
    hexByte k = let d i = "0123456789abcdef" !! i in [d (k `div` 16 `mod` 16), d (k `mod` 16)]

renderTxId :: TxId -> Text
renderTxId = TE.decodeUtf8 . convertToBase Base16 . hashToBytes . extractHash . unTxId

plainTxOut :: Integer -> TxOut ConwayEra
plainTxOut coin = mkBasicTxOut fundingAddr (MaryValue (Coin coin) (MultiAsset mempty))

proofTxOut :: Integer -> TxOut ConwayEra
proofTxOut coin =
    mkBasicTxOut
        fundingAddr
        ( MaryValue
            (Coin coin)
            ( MultiAsset $
                Map.singleton
                    (PolicyID proofScriptHash)
                    (Map.singleton syntheticProofAssetName 1)
            )
        )

proofReferenceInput, checkpointReferenceInput, lifecycleReferenceInput :: TxIn
proofReferenceInput = stubTxIn 11
checkpointReferenceInput = stubTxIn 12
lifecycleReferenceInput = stubTxIn 13

proofProgram, checkpointProgram, lifecycleProgram :: SBS.ShortByteString
proofProgram = SBS.toShort "slice2c-proof-reference-script"
checkpointProgram = SBS.toShort "slice2c-checkpoint-reference-script"
lifecycleProgram = SBS.toShort "slice2c-lifecycle-reference-script"

proofScript, checkpointScript, lifecycleScript :: Script ConwayEra
proofScript = mkCageScript proofProgram
checkpointScript = mkCageScript checkpointProgram
lifecycleScript = mkCageScript lifecycleProgram

proofScriptHash, checkpointScriptHash, lifecycleScriptHash :: ScriptHash
proofScriptHash = computeScriptHash proofProgram
checkpointScriptHash = computeScriptHash checkpointProgram
lifecycleScriptHash = computeScriptHash lifecycleProgram

syntheticPolicy :: Text
syntheticPolicy = scriptHashText proofScriptHash

syntheticProofAssetName :: AssetName
syntheticProofAssetName = AssetName (SBS.toShort $ BS.replicate 32 0x51)

syntheticProofName :: Text
syntheticProofName = hexText (BS.replicate 32 0x51)

syntheticCheckpointPolicy :: Text
syntheticCheckpointPolicy = scriptHashText checkpointScriptHash

syntheticCheckpointAssetName :: AssetName
syntheticCheckpointAssetName =
    AssetName (SBS.toShort $ BS.replicate 32 0x52)

syntheticCheckpointName :: Text
syntheticCheckpointName = hexText (BS.replicate 32 0x52)

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

renderTxIn :: TxIn -> Text
renderTxIn (TxIn txId (TxIx txIx)) =
    renderTxId txId <> "#" <> T.pack (show txIx)

renderBech32 :: Text -> BS.ByteString -> Text
renderBech32 prefix bytes =
    Bech32.encodeLenient
        ( either
            (error . show)
            id
            (Bech32.humanReadablePartFromText prefix)
        )
        (Bech32.dataPartFromBytes bytes)

referenceTxOut :: Script ConwayEra -> TxOut ConwayEra
referenceTxOut script =
    plainTxOut 20_000_000
        & referenceScriptTxOutL .~ SJust script

syntheticReferenceUtxos :: [(TxIn, TxOut ConwayEra)]
syntheticReferenceUtxos =
    [ (proofReferenceInput, referenceTxOut proofScript)
    , (checkpointReferenceInput, referenceTxOut checkpointScript)
    , (lifecycleReferenceInput, referenceTxOut lifecycleScript)
    ]

syntheticPlan :: RegistrationPlan
syntheticPlan =
    RegistrationPlan
        { planAid = "aid-synthetic"
        , planProofPolicy = syntheticPolicy
        , planProofName = syntheticProofName
        , planProofReference = renderTxIn proofReferenceInput
        , planCheckpointPolicy = syntheticCheckpointPolicy
        , planCheckpointName = syntheticCheckpointName
        , planCheckpointReference = renderTxIn checkpointReferenceInput
        , planCheckpointAddress = renderBech32 "addr_test" (serialiseAddr checkpointAddr)
        , planLifecycleReference = renderTxIn lifecycleReferenceInput
        , planLifecycleRewardAddress =
            renderBech32
                "stake_test"
                (serialiseAccountAddress lifecycleRewardAccount)
        , planEscrowLovelace = 5_000_000
        , planPremintRedeemer = plutusDataJson syntheticPremintRedeemer
        , planCheckpointRedeemer = plutusDataJson syntheticCheckpointRedeemer
        , planProofBurnRedeemer = plutusDataJson syntheticProofBurnRedeemer
        , planObserverRedeemer = plutusDataJson syntheticObserverRedeemer
        , planLifecycleCertificateRedeemer =
            plutusDataJson syntheticLifecycleRedeemer
        , planCheckpointDatum = plutusDataJson syntheticCheckpointDatum
        }

syntheticPremintRedeemer :: Data
syntheticPremintRedeemer = Constr 6 [I 606]

syntheticCheckpointRedeemer :: Data
syntheticCheckpointRedeemer = Constr 1 [I 101]

syntheticProofBurnRedeemer :: Data
syntheticProofBurnRedeemer = Constr 2 [I 202]

syntheticObserverRedeemer :: Data
syntheticObserverRedeemer = Constr 3 [I 303]

syntheticLifecycleRedeemer :: Data
syntheticLifecycleRedeemer = Constr 4 [I 404]

syntheticCheckpointDatum :: Data
syntheticCheckpointDatum = Constr 5 [I 505]

lifecycleRewardAccount :: AccountAddress
lifecycleRewardAccount =
    AccountAddress
        Testnet
        (AccountId (ScriptHashObj lifecycleScriptHash))

recordCall :: IORef [String] -> String -> IO ()
recordCall ref tag = modifyIORef' ref (tag :)

disagreeingId :: TxId
disagreeingId =
    transactionId
        (mkBasicTx (mkBasicTxBody & feeTxBodyL .~ Coin 999_999))

standInRuntime :: IORef [String] -> IORef (Maybe ConwayTx) -> IO (TransactionRuntime IO)
standInRuntime callsRef signedRef =
    pure
        TransactionRuntime
            { trQueryProtocolParams =
                recordCall callsRef "query" >> pure testPParams
            , trEvaluate = \_ -> recordCall callsRef "evaluate" >> pure Map.empty
            , trSign = \tx -> do
                recordCall callsRef "sign"
                let signedResult = signWithPaymentKey registrationTestEnvelope tx
                modifyIORef'
                    signedRef
                    ( const $ case signedResult of
                        Left _ -> Nothing
                        Right signed -> Just signed
                    )
                pure signedResult
            , trSubmit = \tx -> do
                signed <- readIORef signedRef
                if signed == Just tx
                    then recordCall callsRef "submit" >> pure (Submitted disagreeingId)
                    else fail "trSubmit did not receive the transaction returned by trSign"
            , trObserve = \txId -> do
                signed <- readIORef signedRef
                if fmap transactionId signed == Just txId
                    then recordCall callsRef "observe"
                    else fail "trObserve did not receive the signed transaction id"
            }

registrationTestEnvelope :: Value
registrationTestEnvelope =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex"
            .= ( "582083c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde" ::
                    String
               )
        ]

{- | Answers 'awaitAsset'\'s injected query from the tx captured via
'trSign' -- the same source of truth the ledger-boundary assertions read,
never a preselected answer independent of what was built.
-}
standInQueryAsset ::
    IORef (Maybe ConwayTx) -> Text -> Text -> IO [ChainAssetUtxo]
standInQueryAsset signedRef policyId assetName = do
    signed <- readIORef signedRef
    pure $ case signed of
        Nothing -> []
        Just tx ->
            [ ChainAssetUtxo
                (renderTxId (transactionId tx))
                0
                (planCheckpointAddress syntheticPlan)
                (planEscrowLovelace syntheticPlan)
                [ChainAsset policyId assetName 1]
                Nothing
            ]

mkConfig :: TransactionRuntime IO -> (Text -> Text -> IO [ChainAssetUtxo]) -> RegisterConfig
mkConfig runtime queryAsset =
    RegisterConfig
        { registerRuntime = runtime
        , registerReferenceUtxos = syntheticReferenceUtxos
        , registerFundingAddress = fundingAddr
        , registerLifecycleRewardAccount = lifecycleRewardAccount
        , registerQueryAsset = queryAsset
        , registerTimeoutSeconds = 30
        , registerPollDelayMicros = 150_000
        }

-- ---------------------------------------------------------------------------
-- registerOne/premintOne: in-process ledger evolution
-- (PROVE-LIST #1-#3, #6, #9-#12; #13 is a CLI-level proof, tracked separately)

registrationLedgerBoundarySpec :: Spec
registrationLedgerBoundarySpec = describe "premintOne/registerOne" $ do
    it "registration completes with cardano-cli absent from PATH" $ do
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
        let config = mkConfig runtime (standInQueryAsset signedRef)
            premintInputs =
                [ (stubTxIn 1, plainTxOut 200_000_000)
                , (stubTxIn 2, plainTxOut 50_000_000)
                ]
        premintTxId <-
            premintOne config syntheticPlan premintInputs False
                >>= either (fail . ("expected premint success, got " <>) . show) pure
        proofUtxoResult <-
            awaitAsset
                (registerQueryAsset config)
                (registerPollDelayMicros config)
                (registerTimeoutSeconds config)
                (planProofPolicy syntheticPlan)
                (planProofName syntheticPlan)
                (renderTxId premintTxId)
                (planCheckpointAddress syntheticPlan)
        proofUtxo <- either (fail . ("expected proof utxo, got " <>) . show) pure proofUtxoResult
        chainAssetTxId proofUtxo `shouldBe` renderTxId premintTxId
        let registerInputs =
                [ (stubTxIn 3, plainTxOut 200_000_000)
                , (stubTxIn 4, plainTxOut 50_000_000)
                ]
            proofIn =
                ( TxIn premintTxId (TxIx $ fromIntegral $ chainAssetIndex proofUtxo)
                , proofTxOut (chainAssetLovelace proofUtxo)
                )
        registerResult <- registerOne config syntheticPlan registerInputs proofIn
        case registerResult of
            Left err -> fail ("expected register success, got " <> show err)
            Right _registerTxId -> pure ()
        pure ()

    it "premint freezes lifecycle certificate, deposit, redeemers, mint, references, collateral, signing, and settlement" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        let config = mkConfig runtime (standInQueryAsset signedRef)
            premintInputs =
                [ (stubTxIn 1, plainTxOut 200_000_000)
                , (stubTxIn 2, plainTxOut 50_000_000)
                ]
        result <- premintOne config syntheticPlan premintInputs True
        case result of
            Left err -> fail ("expected lifecycle premint success, got " <> show err)
            Right premintTxId -> do
                signed <- readIORef signedRef
                case signed of
                    Nothing -> fail "trSign was never called: no premint tx was built"
                    Just tx -> do
                        let body = tx ^. bodyTxL
                            MultiAsset minted = body ^. mintTxBodyL
                            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
                            expectedCertificate =
                                ConwayTxCertDeleg $
                                    ConwayRegCert
                                        (ScriptHashObj lifecycleScriptHash)
                                        (SJust $ testPParams ^. ppKeyDepositL)
                        minted
                            `shouldBe` Map.singleton
                                (PolicyID proofScriptHash)
                                (Map.singleton syntheticProofAssetName 1)
                        body ^. inputsTxBodyL
                            `shouldBe` Set.singleton (stubTxIn 1)
                        body ^. collateralInputsTxBodyL
                            `shouldBe` Set.singleton (stubTxIn 2)
                        body ^. referenceInputsTxBodyL
                            `shouldBe` Set.fromList
                                [proofReferenceInput, lifecycleReferenceInput]
                        toList (body ^. certsTxBodyL)
                            `shouldBe` [expectedCertificate]
                        redeemerData
                            (mintPurpose (PolicyID proofScriptHash) minted)
                            redeemers
                            `shouldBe` Just syntheticPremintRedeemer
                        redeemerData
                            (ConwayCertifying (AsIx 0))
                            redeemers
                            `shouldBe` Just syntheticLifecycleRedeemer
                        length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
                        transactionId tx `shouldBe` premintTxId
                        transactionId tx `shouldSatisfy` (/= disagreeingId)
                order <- reverse <$> readIORef callsRef
                take 1 order `shouldBe` ["query"]
                order `shouldContain` ["evaluate"]
                drop (length order - 3) order
                    `shouldBe` ["sign", "submit", "observe"]

    it "registration freezes datum, mint, reference inputs, fee, change, collateral, signing, tx id, submission, and settlement" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        let config = mkConfig runtime (standInQueryAsset signedRef)
            registerInputs =
                [ (stubTxIn 3, plainTxOut 200_000_000)
                , (stubTxIn 4, plainTxOut 50_000_000)
                ]
            proofIn =
                (stubTxIn 5, proofTxOut 5_000_000)
        result <- registerOne config syntheticPlan registerInputs proofIn
        case result of
            Left err -> fail ("expected success, got " <> show err)
            Right registerTxId -> do
                T.length (renderTxId registerTxId) `shouldBe` 64
                signed <- readIORef signedRef
                case signed of
                    Nothing -> fail "trSign was never called: no tx was built"
                    Just tx -> do
                        let body = tx ^. bodyTxL
                            outputs = toList (body ^. outputsTxBodyL)
                            MultiAsset minted = body ^. mintTxBodyL
                            Withdrawals withdrawals = body ^. withdrawalsTxBodyL
                            Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
                        -- mint: +1 checkpoint, -1 hash-proof, exactly these
                        -- two policies, no third.
                        minted
                            `shouldBe` Map.fromList
                                [
                                    ( PolicyID checkpointScriptHash
                                    , Map.singleton syntheticCheckpointAssetName 1
                                    )
                                ,
                                    ( PolicyID proofScriptHash
                                    , Map.singleton syntheticProofAssetName (-1)
                                    )
                                ]
                        -- checkpoint output: exactly one, at the escrow
                        -- lovelace, carrying an inline datum.
                        case [o | o <- outputs, o ^. coinTxOutL == Coin (planEscrowLovelace syntheticPlan)] of
                            [checkpointOut] -> do
                                checkpointOut ^. addrTxOutL `shouldBe` checkpointAddr
                                case checkpointOut ^. datumTxOutL of
                                    Datum binaryDatum ->
                                        let LedgerData.Data datum =
                                                LedgerData.binaryDataToData binaryDatum
                                         in datum `shouldBe` syntheticCheckpointDatum
                                    other -> fail ("expected inline checkpoint datum, got " <> show other)
                            other -> fail ("expected exactly one checkpoint output, got " <> show (length other))
                        -- change: a second output at the funding address.
                        length outputs `shouldBe` 2
                        length [o | o <- outputs, o ^. addrTxOutL == fundingAddr]
                            `shouldBe` 1
                        -- fee: real, positive.
                        (body ^. feeTxBodyL) `shouldSatisfy` (> Coin 0)
                        -- distinct collateral input, never also a regular spend.
                        body ^. collateralInputsTxBodyL
                            `shouldBe` Set.singleton (stubTxIn 4)
                        body ^. inputsTxBodyL
                            `shouldBe` Set.fromList [stubTxIn 3, stubTxIn 5]
                        -- reference inputs: checkpoint-mint, proof-burn, and
                        -- lifecycle-withdraw references, none of them the
                        -- regular spend/collateral inputs.
                        body ^. referenceInputsTxBodyL
                            `shouldBe` Set.fromList
                                [ proofReferenceInput
                                , checkpointReferenceInput
                                , lifecycleReferenceInput
                                ]
                        -- lifecycle withdrawal: zero-value, from the
                        -- configured reward account.
                        Map.lookup lifecycleRewardAccount withdrawals
                            `shouldBe` Just (Coin 0)
                        -- Every same-typed Plutus value is deliberately
                        -- distinct, freezing its purpose and preventing
                        -- argument swaps from surviving this proof.
                        redeemerData
                            (mintPurpose (PolicyID checkpointScriptHash) minted)
                            redeemers
                            `shouldBe` Just syntheticCheckpointRedeemer
                        redeemerData
                            (mintPurpose (PolicyID proofScriptHash) minted)
                            redeemers
                            `shouldBe` Just syntheticProofBurnRedeemer
                        redeemerData
                            (ConwayRewarding (AsIx 0))
                            redeemers
                            `shouldBe` Just syntheticObserverRedeemer
                        -- signing: exactly one vkey witness attached.
                        length (tx ^. witsTxL . addrTxWitsL) `shouldBe` 1
                        -- the reported id is the signed tx's own pure id,
                        -- proven to differ from the submitter's
                        -- deliberately-disagreeing echoed id.
                        transactionId tx `shouldBe` registerTxId
                        transactionId tx `shouldSatisfy` (/= disagreeingId)
                order <- reverse <$> readIORef callsRef
                take 1 order `shouldBe` ["query"]
                order `shouldContain` ["evaluate"]
                drop (length order - 3) order
                    `shouldBe` ["sign", "submit", "observe"]

    it "rejects when declared execution units exceed the protocol maximum" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        let overBudget = ExUnits 900_000_000 20_000_000_000
            runtime =
                baseRuntime
                    { trEvaluate = \_ ->
                        recordCall callsRef "evaluate"
                            >> pure (Map.singleton (ConwayMinting (AsIx 0)) (Right overBudget))
                    }
            config = mkConfig runtime (standInQueryAsset signedRef)
            registerInputs =
                [ (stubTxIn 3, plainTxOut 200_000_000)
                , (stubTxIn 4, plainTxOut 50_000_000)
                ]
            proofIn = (stubTxIn 5, proofTxOut 5_000_000)
            maximum' = testPParams ^. ppMaxTxExUnitsL
        result <- registerOne config syntheticPlan registerInputs proofIn
        case result of
            Left (RegistrationBuildFailed (TransactionBuildChecksRejected checks)) ->
                checks
                    `shouldSatisfy` any
                        ( \case
                            CustomFail
                                ( RegistrationAggregateExUnitsExceeded
                                        (AggregateExUnitsExceeded declared limit)
                                    ) ->
                                    declared == overBudget && limit == maximum'
                            _ -> False
                        )
            other -> fail ("expected aggregate execution-unit rejection, got " <> show other)

    it "rejects a resolved reference UTxO whose script hash disagrees with the plan" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        runtime <- standInRuntime callsRef signedRef
        let mismatchedReferences =
                (proofReferenceInput, referenceTxOut checkpointScript)
                    : drop 1 syntheticReferenceUtxos
            config =
                (mkConfig runtime (standInQueryAsset signedRef))
                    { registerReferenceUtxos = mismatchedReferences
                    }
            premintInputs =
                [ (stubTxIn 1, plainTxOut 200_000_000)
                , (stubTxIn 2, plainTxOut 50_000_000)
                ]
        result <- premintOne config syntheticPlan premintInputs False
        case result of
            Left (RegistrationPlanRejected detail) ->
                detail `shouldContain` "proof reference script hash"
            other -> fail ("expected reference-script mismatch, got " <> show other)
        readIORef callsRef >>= (`shouldBe` [])

mintPurpose ::
    PolicyID ->
    Map.Map PolicyID (Map.Map AssetName Integer) ->
    ConwayPlutusPurpose AsIx ConwayEra
mintPurpose policy minted =
    ConwayMinting . AsIx . fromIntegral . fromJust $
        elemIndex policy (Map.keys minted)

redeemerData ::
    ConwayPlutusPurpose AsIx ConwayEra ->
    Map.Map
        (ConwayPlutusPurpose AsIx ConwayEra)
        (LedgerData.Data ConwayEra, ExUnits) ->
    Maybe Data
redeemerData purpose redeemers =
    (\(LedgerData.Data datum, _units) -> datum) <$> Map.lookup purpose redeemers

-- ---------------------------------------------------------------------------
-- Error taxonomy through the real register path.

failureTaxonomySpec :: Spec
failureTaxonomySpec = describe "registration error taxonomy" $ do
    it "reports script evaluation rejection" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        let runtime =
                baseRuntime
                    { trEvaluate = \_ ->
                        recordCall callsRef "evaluate"
                            >> pure
                                ( Map.singleton
                                    (ConwayMinting (AsIx 0))
                                    (Left (UnknownTxIn (stubTxIn 99)))
                                )
                    }
            config = mkConfig runtime (standInQueryAsset signedRef)
            registerInputs =
                [ (stubTxIn 3, plainTxOut 200_000_000)
                , (stubTxIn 4, plainTxOut 50_000_000)
                ]
        result <-
            registerOne
                config
                syntheticPlan
                registerInputs
                (stubTxIn 5, proofTxOut 5_000_000)
        case result of
            Left (RegistrationBuildFailed (TransactionBuildEvaluationRejected _ detail)) ->
                detail `shouldContain` "UnknownTxIn"
            other -> fail ("expected build evaluation rejection, got " <> show other)
        order <- reverse <$> readIORef callsRef
        take 1 order `shouldBe` ["query"]
        order `shouldSatisfy` all (`elem` ["query", "evaluate"])

    it "reports submission rejection" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        let runtime =
                baseRuntime
                    { trSubmit = \_tx ->
                        recordCall callsRef "submit" >> pure (Rejected "node rejected the register tx")
                    }
            config = mkConfig runtime (standInQueryAsset signedRef)
            registerInputs =
                [ (stubTxIn 3, plainTxOut 200_000_000)
                , (stubTxIn 4, plainTxOut 50_000_000)
                ]
            proofIn = (stubTxIn 5, proofTxOut 5_000_000)
        result <- registerOne config syntheticPlan registerInputs proofIn
        result
            `shouldBe` Left
                ( RegistrationBuildFailed
                    (TransactionBuildSubmissionRejected "node rejected the register tx")
                )

    it "reports bad signing key" $ do
        callsRef <- newIORef []
        signedRef <- newIORef Nothing
        baseRuntime <- standInRuntime callsRef signedRef
        let runtime =
                baseRuntime
                    { trSign = \tx ->
                        recordCall callsRef "sign"
                            >> pure (signWithPaymentKey trulyMalformedEnvelope tx)
                    }
            config = mkConfig runtime (standInQueryAsset signedRef)
            registerInputs =
                [ (stubTxIn 3, plainTxOut 200_000_000)
                , (stubTxIn 4, plainTxOut 50_000_000)
                ]
        result <-
            registerOne
                config
                syntheticPlan
                registerInputs
                (stubTxIn 5, proofTxOut 5_000_000)
        case result of
            Left
                ( RegistrationBuildFailed
                        (TransactionBuildSigningRejected (TransactionSigningError _))
                    ) -> pure ()
            other -> fail ("expected registration signing rejection, got " <> show other)

trulyMalformedEnvelope :: Value
trulyMalformedEnvelope = object ["cborHex" .= ("00" :: String)]

-- ---------------------------------------------------------------------------
-- awaitAsset: exact-identity settlement matching behind an injected
-- chain-query primitive, mirroring Publisher's awaitReferenceSpec discipline.

awaitAssetSpec :: Spec
awaitAssetSpec = describe "awaitAsset" $ do
    it "reports observation timeout for registration, having actually polled" $ do
        pollsRef <- newIORef (0 :: Int)
        let neverMatches _policyId _assetName = do
                modifyIORef' pollsRef (+ 1)
                pure []
        result <-
            awaitAsset
                neverMatches
                100_000
                0
                "deadbeefpolicy"
                "cafef00dasset"
                "expectedtx"
                "expectedaddr"
        polls <- readIORef pollsRef
        polls `shouldSatisfy` (>= 1)
        case result of
            Left (AssetObservationTimeout policyId assetName txId address) -> do
                policyId `shouldBe` "deadbeefpolicy"
                assetName `shouldBe` "cafef00dasset"
                txId `shouldBe` "expectedtx"
                address `shouldBe` "expectedaddr"
            other -> fail ("expected AssetObservationTimeout, got " <> show other)

    it "reports registration observation timeout reached through the loop, not around it" $ do
        pollsRef <- newIORef (0 :: Int)
        let neverMatches _policyId _assetName = do
                modifyIORef' pollsRef (+ 1)
                pure []
        result <-
            awaitAsset
                neverMatches
                150_000
                1
                "deadbeefpolicy"
                "cafef00dasset"
                "expectedtx"
                "expectedaddr"
        polls <- readIORef pollsRef
        polls `shouldSatisfy` (>= 2)
        case result of
            Left (AssetObservationTimeout policyId assetName txId address) -> do
                policyId `shouldBe` "deadbeefpolicy"
                assetName `shouldBe` "cafef00dasset"
                txId `shouldBe` "expectedtx"
                address `shouldBe` "expectedaddr"
            other -> fail ("expected AssetObservationTimeout, got " <> show other)

    it "matches the exact policy, asset name, transaction id, and address once the chain reports it" $ do
        -- Decoys individually differ in each identity field, so the match
        -- proves the conjunction rather than any single field.
        let expectedAddr = "expectedaddr"
            expectedTxId = "matchingtx"
            candidates _policyId _assetName =
                pure
                    [ ChainAssetUtxo expectedTxId 0 "wrongaddr" 5_000_000 [ChainAsset "deadbeefpolicy" "cafef00dasset" 1] Nothing
                    , ChainAssetUtxo expectedTxId 1 expectedAddr 5_000_000 [ChainAsset "other-policy" "cafef00dasset" 1] Nothing
                    , ChainAssetUtxo expectedTxId 2 expectedAddr 5_000_000 [ChainAsset "deadbeefpolicy" "other-asset" 1] Nothing
                    , ChainAssetUtxo "wrongtx" 3 expectedAddr 5_000_000 [ChainAsset "deadbeefpolicy" "cafef00dasset" 1] Nothing
                    , ChainAssetUtxo expectedTxId 4 expectedAddr 5_000_000 [ChainAsset "deadbeefpolicy" "cafef00dasset" 1] Nothing
                    ]
        result <-
            awaitAsset
                candidates
                5_000_000
                30
                "deadbeefpolicy"
                "cafef00dasset"
                expectedTxId
                expectedAddr
        case result of
            Right utxo -> do
                chainAssetTxId utxo `shouldBe` "matchingtx"
                chainAssetIndex utxo `shouldBe` 4
            Left err -> fail ("expected a match, got " <> show err)
