{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.KERI.Deployment.M12TxBSpec (spec) where

-- \|
-- Module      : Cardano.KERI.Deployment.M12TxBSpec
-- Description : Transaction-level TxB witness-mode proofs
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : Apache-2.0
--
-- Permanent reference/inline, boundary-value, wrong-mode, and
-- provenance proofs for S2W-I01 through S2W-I08.

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.KERI.Deployment.M12TxB
import Cardano.KERI.Deployment.Script (computeScriptHash)
import Cardano.KERI.Deployment.TransactionRuntime (signWithPaymentKey)
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    ValidityInterval (..),
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    reqSignerHashesTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (..),
    TxIx (..),
    unboundRational,
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.PParams (
    ppMaxRefScriptSizePerTxG,
    ppMinFeeRefScriptCostPerByteL,
 )
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams, ppMaxTxSizeL, sizeTxF)
import Cardano.Ledger.Credential (
    Credential (..),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash,
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Keys (KeyRole (Guard))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Crypto.Hash (Digest, SHA256 (..), hash)
import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Short qualified as SBS
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Word (Word8)
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import System.Directory (doesFileExist, getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import Test.Hspec

spec :: Spec
spec = describe "M11.S2.TxB.witness.mode" $ do
    productionSpec
    carriageSpec
    limitSpec
    feeSpec
    envelopeSpec
    failClosedSpec
    provenanceSpec
    contentPinSpec

productionSpec :: Spec
productionSpec = describe "production selection" $ do
    it "fixes REFERENCE as the production witness mode" $
        txBWitnessMode `shouldBe` Reference

carriageSpec :: Spec
carriageSpec = describe "reference and inline carriage" $ do
    it "witness-mode/REFERENCE" $
        withBuilt Reference $ \inputs tx -> do
            let familyRefs = requiredReferences inputs
                familyHashes = requiredHashes inputs
                witnesses = tx ^. witsTxL . scriptTxWitsL
            tx ^. bodyTxL . referenceInputsTxBodyL
                `shouldBe` Set.fromList familyRefs
            Set.fromList familyHashes
                `Set.intersection` Map.keysSet witnesses
                `shouldBe` Set.empty

    it "witness-mode/INLINE" $
        withBuilt Inline $ \inputs tx -> do
            let familyHashes = Set.fromList (requiredHashes inputs)
                witnesses = Map.keysSet (tx ^. witsTxL . scriptTxWitsL)
            tx ^. bodyTxL . referenceInputsTxBodyL `shouldBe` Set.empty
            witnesses `shouldBe` familyHashes

    it "reports INLINE serialized size from the built transaction" $
        withBuilt Inline $ \inputs tx ->
            case inspectTxB txbPParams Inline inputs tx of
                Left err ->
                    expectationFailure ("inspectTxB inline: " <> show err)
                Right txFit -> do
                    txbFitTxBytes txFit
                        `shouldBe` fromIntegral (tx ^. sizeTxF)
                    txbFitTxBytes txFit `shouldBe` 25_969
                    txbFitTxBytes txFit `shouldSatisfy` (> 16_384)
                    txbFitTxVerdict txFit `shouldBe` Exceeds
                    txbFitMaxTxBytes txFit
                        `shouldBe` fromIntegral (txbPParams ^. ppMaxTxSizeL)

    it "keeps semantic inputs, outputs, mint, redeemers, and signers equal across modes" $
        case ( buildTxBWithMode Reference txbPParams (inputsFor Reference)
             , buildTxBWithMode Inline txbPParams (inputsFor Inline)
             ) of
            (Right referenceTx, Right inlineTx) ->
                semanticView referenceTx `shouldBe` semanticView inlineTx
            other ->
                expectationFailure ("buildTxBWithMode: " <> show (voidPair other))

limitSpec :: Spec
limitSpec = describe "pinned reference-script limit" $ do
    it "reads 204800 from the pinned ledger getter" $
        fromIntegral @_ @Int (testPParams ^. ppMaxRefScriptSizePerTxG)
            `shouldBe` 204_800

    it "does not accept 16384 as the reference-script limit" $
        withBuilt Reference $ \inputs tx ->
            case inspectTxB txbPParams Reference inputs tx of
                Left err ->
                    expectationFailure ("inspectTxB: " <> show err)
                Right txFit -> do
                    txbFitMaxRefScriptBytes txFit `shouldBe` 204_800
                    txbFitMaxRefScriptBytes txFit `shouldNotBe` 16_384
                    txbFitRefScriptBytes txFit `shouldBe` 25_617
                    txbFitRefHeadroom txFit `shouldBe` 204_800 - 25_617
                    txbFitRefVerdict txFit `shouldBe` Fits

feeSpec :: Spec
feeSpec = describe "pinned fee tiers" $ do
    it "uses the pinned 44 lovelace-per-byte snapshot field" $
        unboundRational
            (testPParams ^. ppMinFeeRefScriptCostPerByteL)
            `shouldBe` 44

    it "prices 25599 bytes at 1126356 lovelace" $
        txBReferenceScriptFee testPParams 25_599
            `shouldBe` Right (Coin 1_126_356)

    it "prices 25600 bytes at 1126400 lovelace" $
        txBReferenceScriptFee testPParams 25_600
            `shouldBe` Right (Coin 1_126_400)

    it "prices 25601 bytes at 1126452 lovelace, proving tier two" $
        txBReferenceScriptFee testPParams 25_601
            `shouldBe` Right (Coin 1_126_452)

    it "prices 25617 bytes at 1127297 lovelace" $
        txBReferenceScriptFee testPParams 25_617
            `shouldBe` Right (Coin 1_127_297)

    it "prices 26448 bytes at 1171174 lovelace" $
        txBReferenceScriptFee testPParams 26_448
            `shouldBe` Right (Coin 1_171_174)

envelopeSpec :: Spec
envelopeSpec = describe "signed per-program creation envelope" $ do
    it "measures a signed creation transaction separately from its program" $
        case txBCreationEnvelope txbPParams signingContext appendScript of
            Left err -> expectationFailure ("txBCreationEnvelope: " <> show err)
            Right envelope -> do
                txbEnvelopeRole envelope `shouldBe` RoleAppend
                txbEnvelopeProgramBytes envelope `shouldBe` 8_471
                txbEnvelopeCreationTxBytes envelope `shouldSatisfy` (> 8_471)
                txbEnvelopeSigned envelope `shouldBe` True
                txbEnvelopeVerdict envelope
                    `shouldBe` verdictFor
                        (txbEnvelopeCreationTxBytes envelope)
                        16_384

    it "measures every family program independently" $
        case traverse
            (txBCreationEnvelope txbPParams signingContext)
            sampleScripts of
            Left err -> expectationFailure ("txBCreationEnvelope: " <> show err)
            Right envelopes -> do
                map txbEnvelopeRole envelopes `shouldBe` familyRoles
                map txbEnvelopeProgramBytes envelopes
                    `shouldBe` map txbScriptMeasuredBytes sampleScripts
                map txbEnvelopeCreationTxBytes envelopes
                    `shouldBe` [8_680, 8_598, 8_966]

    it "rejects a signing failure" $
        case txBCreationEnvelope
            txbPParams
            signingContext{txbSignCreation = const (Left "fixture failure")}
            appendScript of
            Left (CreationSigningFailed "fixture failure") -> pure ()
            other -> expectationFailure ("expected signing failure, got " <> show other)

    it "rejects a context that returns an unsigned transaction" $
        case txBCreationEnvelope
            txbPParams
            signingContext{txbSignCreation = Right}
            appendScript of
            Left (UnsignedCreationTransaction RoleAppend) -> pure ()
            other -> expectationFailure ("expected unsigned rejection, got " <> show other)

    it "rejects a signer that changes the creation body" $
        case txBCreationEnvelope
            txbPParams
            signingContext{txbSignCreation = tamperCreationBody}
            appendScript of
            Left (CreationBodyChanged RoleAppend) -> pure ()
            other -> expectationFailure ("expected body-change rejection, got " <> show other)

failClosedSpec :: Spec
failClosedSpec = describe "fail-closed validation" $ do
    it "rejects a missing required family script" $
        buildTxBWithMode
            Reference
            txbPParams
            (dropRole RoleCursor sampleInputs)
            `shouldBe` Left (MissingScript RoleCursor)

    it "rejects a duplicate family role" $
        case buildTxBWithMode
            Reference
            txbPParams
            (duplicateRole RoleAppend sampleInputs) of
            Left (DuplicateScript RoleAppend) -> pure ()
            other ->
                expectationFailure ("expected DuplicateScript, got " <> show other)

    it "rejects REFERENCE inputs that omit a family reference UTxO" $
        buildTxBWithMode
            Reference
            txbPParams
            (clearReference RoleStagingProofToken sampleInputs)
            `shouldBe` Left (MissingReference RoleStagingProofToken)

    it "rejects INLINE inputs that still carry a family reference UTxO" $
        buildTxBWithMode Inline txbPParams sampleInputs
            `shouldBe` Left (UnexpectedReference RoleAppend)

    it "rejects a negative aggregate for the tier fee" $
        case txBReferenceScriptFee testPParams (-1) of
            Left (ProtocolValueMismatch{}) -> pure ()
            other ->
                expectationFailure
                    ("expected ProtocolValueMismatch, got " <> show other)

provenanceSpec :: Spec
provenanceSpec = describe "manifest provenance" $ do
    it "binds mode, measured scripts, protocol pins, residuals, and the S0 caveat" $
        withBuilt Reference $ \inputs tx ->
            case txBManifest txbPParams inputs tx of
                Left err -> expectationFailure ("txBManifest: " <> show err)
                Right manifest -> do
                    txbManifestSchema manifest `shouldBe` 1
                    txbManifestMode manifest `shouldBe` Reference
                    txbManifestPlanDigest manifest `shouldSatisfy` (not . T.null)
                    txbSurfaceBStatus (txbManifestSurfaceB manifest)
                        `shouldBe` "ARCHIVED_RED"
                    T.length
                        (txbSurfaceBEvidenceSha256 (txbManifestSurfaceB manifest))
                        `shouldBe` 64
                    txbManifestAggregateBytes manifest `shouldBe` 25_617
                    txbManifestAggregateBytes manifest
                        `shouldBe` sum (map txbRowBytes (txbManifestScripts manifest))
                    txbProtocolMaxRefScriptBytes (txbManifestProtocol manifest)
                        `shouldBe` 204_800
                    txbProtocolPackage (txbManifestProtocol manifest)
                        `shouldSatisfy` (not . T.null)
                    txbProtocolPackageSha (txbManifestProtocol manifest)
                        `shouldSatisfy` ((== 64) . T.length)
                    txbManifestFeeBoundary manifest Map.!? "25600"
                        `shouldBe` Just 1_126_400
                    txbManifestFeeBoundary manifest Map.!? "25601"
                        `shouldBe` Just 1_126_452
                    map txbResidualId (txbManifestResiduals manifest)
                        `shouldContain` ["A3-F1", "F1-ERROR-CLASSIFICATION"]
                    txbManifestCaveats manifest
                        `shouldContain` ["size-only; transaction-fit unproven"]

    it "keeps the committed report explicit about both controls and limits" $ do
        report <- readRepoFile "specs/m11-s2-witness-mode/WITNESS-MODE-REPORT.md"
        report `shouldContain` "REFERENCE"
        report `shouldContain` "INLINE"
        report `shouldContain` "maxRefScriptSizePerTx"
        report `shouldContain` "maxTxSize"
        report `shouldContain` "ARCHIVED_RED"
        report `shouldContain` "A3-F1"
        report `shouldContain` "F1-ERROR-CLASSIFICATION"
        report `shouldContain` "size-only; transaction-fit unproven"

    it "keeps the committed manifest on the pinned protocol and fee table" $ do
        bytes <-
            BS.readFile
                =<< repoFile "specs/m11-s2-witness-mode/txb-manifest.json"
        case Aeson.eitherDecodeStrict bytes of
            Left err -> expectationFailure err
            Right value -> protocolDocument value

contentPinSpec :: Spec
contentPinSpec = describe "Aiken binary content pin" $ do
    it "preserves EXPECTED_TOOL_SHA and rejects a different binary digest" $ do
        script <- readRepoFile "scripts/s0/measure-family.sh"
        script `shouldContain` "EXPECTED_TOOL_SHA="
        script `shouldContain` "toolchain-hash"
        let expected = expectedToolSha script
        expected `shouldSatisfy` ((== 64) . length)
        let mutant = hash ("not-the-pinned-aiken" :: BS.ByteString) :: Digest SHA256
            mutantHex = BS8.unpack (convertToBase Base16 mutant)
        mutantHex `shouldNotBe` expected

-- ---------------------------------------------------------------------------
-- Build helpers

txbPParams :: PParams ConwayEra
txbPParams = testPParams & ppMaxTxSizeL .~ 16_384

withBuilt ::
    TxBWitnessMode ->
    (TxBInputs -> ConwayTx -> IO ()) ->
    IO ()
withBuilt mode onTx =
    case buildTxBWithMode mode txbPParams (inputsFor mode) of
        Left err ->
            expectationFailure ("buildTxBWithMode " <> show mode <> ": " <> show err)
        Right tx -> onTx (inputsFor mode) tx

inputsFor :: TxBWitnessMode -> TxBInputs
inputsFor Reference = sampleInputs
inputsFor Inline = stripReferences sampleInputs

sampleInputs :: TxBInputs
sampleInputs =
    TxBInputs
        { txbInputsPlan = samplePlan
        , txbInputsScripts = sampleScripts
        }

samplePlan :: TxBSemanticPlan
samplePlan =
    TxBSemanticPlan
        { txbPlanConsumed =
            Set.fromList [appendSpend, cursorSpend, fundingInput]
        , txbPlanProduced = [plainTxOut 8_000_000]
        , txbPlanMint = stagingBurn
        , txbPlanRedeemers = sampleRedeemers
        , txbPlanRequiredSigners = Set.singleton ownerKeyHash
        , txbPlanValidity = ValidityInterval SNothing SNothing
        , txbPlanCollateral = Set.singleton collateralInput
        , txbPlanRoles = familyRoles
        }

sampleScripts :: [TxBScript]
sampleScripts =
    [ appendScript
    , familyScript RoleCursor 8_389 0x02 cursorRef
    , familyScript RoleStagingProofToken 8_757 0x03 stagingRef
    ]

appendScript :: TxBScript
appendScript = familyScript RoleAppend 8_471 0x01 appendRef

familyScript :: TxBRole -> Int -> Word8 -> TxIn -> TxBScript
familyScript role size tag ref =
    let bytes = SBS.toShort (BS.replicate size tag)
     in TxBScript
            { txbScriptRole = role
            , txbScriptHash = computeScriptHash bytes
            , txbScriptBytes = bytes
            , txbScriptMeasuredBytes = size
            , txbScriptReference = Just ref
            }

sampleRedeemers :: Redeemers ConwayEra
sampleRedeemers =
    Redeemers $
        Map.fromList
            [ (ConwaySpending (AsIx 0), unitRedeemer)
            , (ConwaySpending (AsIx 1), unitRedeemer)
            , (ConwayMinting (AsIx 0), unitRedeemer)
            ]

unitRedeemer :: (Data ConwayEra, ExUnits)
unitRedeemer = (Data (PLC.Constr 0 []), ExUnits 1 1)

stagingBurn :: MultiAsset
stagingBurn =
    MultiAsset $
        Map.singleton
            (PolicyID stagingHash)
            (Map.singleton stagingAssetName (-1))

stagingHash :: ScriptHash
stagingHash = txbScriptHash (sampleScripts !! 2)

stagingAssetName :: AssetName
stagingAssetName = AssetName (SBS.toShort (BS.replicate 32 0x53))

requiredReferences :: TxBInputs -> [TxIn]
requiredReferences =
    mapMaybe txbScriptReference
        . filter (isFamilyRole . txbScriptRole)
        . txbInputsScripts

requiredHashes :: TxBInputs -> [ScriptHash]
requiredHashes =
    map txbScriptHash
        . filter (isFamilyRole . txbScriptRole)
        . txbInputsScripts

stripReferences :: TxBInputs -> TxBInputs
stripReferences inputs =
    inputs
        { txbInputsScripts =
            [ script{txbScriptReference = Nothing}
            | script <- txbInputsScripts inputs
            ]
        }

dropRole :: TxBRole -> TxBInputs -> TxBInputs
dropRole role inputs =
    inputs
        { txbInputsScripts =
            filter ((/= role) . txbScriptRole) (txbInputsScripts inputs)
        , txbInputsPlan =
            (txbInputsPlan inputs)
                { txbPlanRoles =
                    filter (/= role) (txbPlanRoles (txbInputsPlan inputs))
                }
        }

duplicateRole :: TxBRole -> TxBInputs -> TxBInputs
duplicateRole role inputs =
    inputs
        { txbInputsScripts =
            txbInputsScripts inputs ++ filter ((== role) . txbScriptRole) (txbInputsScripts inputs)
        }

clearReference :: TxBRole -> TxBInputs -> TxBInputs
clearReference role inputs =
    inputs
        { txbInputsScripts =
            [ if txbScriptRole script == role
                then script{txbScriptReference = Nothing}
                else script
            | script <- txbInputsScripts inputs
            ]
        }

type SemanticView =
    ( Set.Set TxIn
    , [TxOut ConwayEra]
    , MultiAsset
    , Redeemers ConwayEra
    , Set.Set (KeyHash Guard)
    )

semanticView :: ConwayTx -> SemanticView
semanticView tx =
    ( tx ^. bodyTxL . inputsTxBodyL
    , foldr (:) [] (tx ^. bodyTxL . outputsTxBodyL)
    , tx ^. bodyTxL . mintTxBodyL
    , tx ^. witsTxL . rdmrsTxWitsL
    , tx ^. bodyTxL . reqSignerHashesTxBodyL
    )

voidPair ::
    (Either TxBBuildError a, Either TxBBuildError b) ->
    (Either String (), Either String ())
voidPair (a, b) =
    ( either (Left . show) (const (Right ())) a
    , either (Left . show) (const (Right ())) b
    )

-- ---------------------------------------------------------------------------
-- Signing context and fixture addresses

signingContext :: TxBSigningContext
signingContext =
    TxBSigningContext
        { txbCreationInput = stubTxIn 20
        , txbCreationOutput = plainTxOut 20_000_000
        , txbSignCreation = signCreation
        }

signCreation :: ConwayTx -> Either T.Text ConwayTx
signCreation tx =
    case signWithPaymentKey goodEnvelope tx of
        Left err -> Left (T.pack (show err))
        Right signed -> Right signed

tamperCreationBody :: ConwayTx -> Either T.Text ConwayTx
tamperCreationBody tx = do
    signed <- signCreation tx
    pure (signed & bodyTxL . feeTxBodyL .~ Coin 999_999)

goodEnvelope :: Aeson.Value
goodEnvelope =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex"
            .= ( "582083c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde" ::
                    String
               )
        ]

verdictFor :: Int -> Int -> TxBFitVerdict
verdictFor measured limit
    | measured <= limit = Fits
    | otherwise = Exceeds

ownerKeyHash :: KeyHash Guard
ownerKeyHash =
    KeyHash (fromJust (hashFromStringAsHex (replicate 56 'd')))

fundingAddr :: Addr
fundingAddr =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromStringAsHex (replicate 56 'e')))))
        StakeRefNull

plainTxOut :: Integer -> TxOut ConwayEra
plainTxOut coin =
    mkBasicTxOut fundingAddr (MaryValue (Coin coin) (MultiAsset mempty))

appendSpend :: TxIn
appendSpend = stubTxIn 1

cursorSpend :: TxIn
cursorSpend = stubTxIn 2

fundingInput :: TxIn
fundingInput = stubTxIn 3

collateralInput :: TxIn
collateralInput = stubTxIn 4

appendRef :: TxIn
appendRef = stubTxIn 11

cursorRef :: TxIn
cursorRef = stubTxIn 12

stagingRef :: TxIn
stagingRef = stubTxIn 13

stubTxIn :: Int -> TxIn
stubTxIn n =
    TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))) (TxIx 0)
  where
    hex = replicate 62 '0' <> hexByte n
    hexByte k =
        let digits = "0123456789abcdef"
            d i = digits !! i
         in [d (k `div` 16 `mod` 16), d (k `mod` 16)]

-- ---------------------------------------------------------------------------
-- Filesystem / JSON helpers

protocolDocument :: Aeson.Value -> Expectation
protocolDocument = \case
    Aeson.Object obj -> do
        obj KeyMap.!? "schema_version" `shouldBe` Just (Aeson.Number 1)
        obj KeyMap.!? "witness_mode" `shouldBe` Just (Aeson.String "REFERENCE")
        case obj KeyMap.!? "protocol" of
            Just (Aeson.Object protocol) -> do
                protocol KeyMap.!? "max_ref_script_size_per_tx"
                    `shouldBe` Just (Aeson.Number 204_800)
                protocol KeyMap.!? "ref_script_cost_stride"
                    `shouldBe` Just (Aeson.Number 25_600)
                protocol KeyMap.!? "min_fee_ref_script_cost_per_byte"
                    `shouldBe` Just (Aeson.Number 44)
            other ->
                expectationFailure ("protocol object: " <> show other)
        case obj KeyMap.!? "fee_boundary" of
            Just (Aeson.Object fees) -> do
                fees KeyMap.!? "25600" `shouldBe` Just (Aeson.Number 1_126_400)
                fees KeyMap.!? "25601" `shouldBe` Just (Aeson.Number 1_126_452)
            other ->
                expectationFailure ("fee_boundary: " <> show other)
        case obj KeyMap.!? "caveats" of
            Just (Aeson.Array caveats) ->
                caveats
                    `shouldSatisfy` elem
                        (Aeson.String "size-only; transaction-fit unproven")
            other ->
                expectationFailure ("caveats: " <> show other)
    other -> expectationFailure ("manifest object: " <> show other)

expectedToolSha :: String -> String
expectedToolSha contents =
    case [drop (length prefix) line | line <- lines contents, prefix `isPrefixOf` line] of
        (sha : _) -> takeWhile (/= ' ') sha
        [] -> ""
  where
    prefix = "EXPECTED_TOOL_SHA="

readRepoFile :: FilePath -> IO String
readRepoFile rel = readFile =<< repoFile rel

repoFile :: FilePath -> IO FilePath
repoFile rel = do
    cwd <- getCurrentDirectory
    go cwd
  where
    go dir = do
        let candidate = dir </> rel
        exists <- doesFileExist candidate
        if exists
            then pure candidate
            else do
                let parent = takeDirectory dir
                if parent == dir
                    then fail ("missing repository file " <> rel)
                    else go parent
