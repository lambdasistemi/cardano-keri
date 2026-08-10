{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Indexer.LocalWritePathSpec
Description : T240-S1-03/06/07 -- local write-path atomicity, reference derivation, settlement

Proves T240-S1-03's three blocking properties (RQ-240-03\/04\/05\/06) through
one test-local typed adapter, 'LocalCapabilities', rather than importing
"Cardano.KERI.Indexer.ChainQuery" symbols directly into every assertion
(N-007\/N-008): while any of the four capabilities were not yet implemented,
a missing exported symbol would have made this WHOLE suite fail to compile,
silently stopping the base-oracle capture suites in the same combined proof
run from ever executing.

GREEN state (post T240-S1-06\/07): 'redCapabilities' is now every field
eta-expanded straight to the real exported "Cardano.KERI.Indexer.ChainQuery"
function -- 'runLocalChainQuery', 'localReferenceScriptsTx' (via the small
'IO'-bracketing wrapper 'localReferenceScriptsTxViaHandle'),
'localSettlementObserver', 'localTransactionSettled'. Retained under its
original name for continuity with the frozen RED-COMMIT (@1126a58@) and this
file's own 'it'\/'describe' text, which still names each invariant as "RED
against ..." to describe what the property PROVES, not this adapter's
current state. Every property body and every fixture below is
byte-for-byte identical to the RED bundle: only the four field bodies inside
'redCapabilities' changed, exactly the "same adapter constructed solely by
eta-expanding the real exported local functions" N-008 specified. Before
implementation this suite reported build 8's evidence (5 base-oracle
suites GREEN, this suite's atomicity example GREEN, its other three
examples RED for exactly their named reasons); now every example proves
the real local capability.

Reuses the exact proven in-memory harness and helper shapes from
"Cardano.KERI.Indexer.ChainQuerySpec" ('withInMemoryIndexerRunner',
'countingRunner', 'UtxoCreate'\/'applyAtSlot', 'testQueryHandle') rather than
inventing a new one. Each helper below is a per-spec copy, matching this
codebase's existing convention (see e.g. PublisherSpec\/RegistrationSpec\/
AdvanceSpec's own near-identical stubTxIn\/plainTxOut copies) rather than a
new shared test-only export.
-}
module Cardano.KERI.Indexer.LocalWritePathSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (V1), CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.ChainQuery.Program (ChainQuery, payerUtxos)
import Cardano.KERI.ChainQuery.Settlement (SettlementObserver (..))
import Cardano.KERI.ChainQuery.Types (
    ChainQueryError,
    ChainReference (..),
    QuerySnapshot (..),
 )
import Cardano.KERI.Deployment.CLI (
    AdvanceSettings (..),
    CloseSettings (..),
    LiveOpener,
    LocalOpener,
    runAdvanceWith,
    runCloseWith,
 )
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    SourceInfo (..),
    writeManifestAtomic,
 )
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript, scriptHashText)
import Cardano.KERI.Indexer.ChainQuery (
    LocalQueryScope (..),
    localReferenceScriptsTx,
    localSettlementObserver,
    localTransactionSettled,
    queryHandleLocalScope,
    runLocalChainQuery,
 )
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), dataToBinaryData)
import Cardano.Ledger.Api.Tx.Body (referenceScriptTxOutL)
import Cardano.Ledger.Api.Tx.Out (datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, TxOut, eraProtVerLow, fromStrictMaybeL)
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..))
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (UpstreamConnected))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent.STM (STM)
import Control.Exception (Exception, SomeException, throwIO, try)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.Functor.Identity (Identity (..), runIdentity)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction (..))
import Lens.Micro ((.~))
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

{- | Every local write-path capability T240-S1-03 owns, as one test-local
adapter. Both RED ('redCapabilities') and the eventual GREEN construction
share this exact shape; only field BODIES differ.
-}
data LocalCapabilities cf op = LocalCapabilities
    { capAtomicQuery ::
        forall a.
        LocalQueryScope cf op ->
        ChainQuery a ->
        IO (Either ChainQueryError (QuerySnapshot a))
    -- ^ RQ-240-03\/04: one program, one store transaction, one watermark.
    , capReferenceScripts ::
        LocalQueryScope cf op -> [Text] -> IO (Either ChainQueryError [ChainReference])
    -- ^ RQ-240-05\/DATA-INV-240-01: derived reference resolution.
    , capSettlementObserver :: LocalQueryScope cf op -> SettlementObserver IO
    -- ^ RQ-240-06: follower-backed asset settlement probe.
    , capTransactionSettled :: LocalQueryScope cf op -> TxId -> IO Bool
    -- ^ RQ-240-06: follower-backed exact-transaction settlement probe.
    }

{- | GREEN (T240-S1-06/07): every field is now the real exported
"Cardano.KERI.Indexer.ChainQuery" function, eta-expanded -- the property
bodies and fixtures below are byte-for-byte unchanged from RED, exactly the
"same adapter constructed solely by eta-expanding the real exported local
functions" N-008 specified. 'redCapabilities' keeps its RED name in this
committed history for continuity with the frozen RED-COMMIT and the
'it'\/'describe' text (still worded "RED against ..." to name the invariant
each property proves, not this adapter's current state); its own three
"closed test-local stand-in" field bodies from before implementation are
gone.
-}
redCapabilities :: LocalCapabilities cf op
redCapabilities =
    LocalCapabilities
        { capAtomicQuery = runLocalChainQuery
        , capReferenceScripts = localReferenceScriptsTxViaHandle
        , capSettlementObserver = localSettlementObserver
        , capTransactionSettled = localTransactionSettled
        }

{- | 'Cardano.KERI.Indexer.ChainQuery.localReferenceScriptsTx' is a plain
'Transaction', not an 'IO' action (it has no scope to open a runner
from -- #240's write path always already holds one open, mid-snapshot).
This adapter field promises 'IO' directly, matching 'capTransactionSettled'\/
'capSettlementObserver''s own shape, so this is the one-line bracket every
other IO-shaped local capability already gets for free.
-}
localReferenceScriptsTxViaHandle ::
    LocalQueryScope cf op -> [Text] -> IO (Either ChainQueryError [ChainReference])
localReferenceScriptsTxViaHandle scope hashes =
    runTransaction (localScopeRunner scope) (localReferenceScriptsTx hashes)

spec :: Spec
spec = describe "Cardano.KERI.Indexer.ChainQuery local write-path capabilities (#240 S240-1)" $ do
    describe "RQ-240-03/04 -- atomic local runner, one transaction per program" $
        it "capAtomicQuery invokes the transaction runner exactly once for a whole program" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x10) addrA]
                counter <- newIORef (0 :: Int)
                let scope = queryHandleLocalScope (testQueryHandle (countingRunner counter runner))
                result <- capAtomicQuery redCapabilities scope (payerUtxos [addrText addrA])
                count <- readIORef counter
                count `shouldBe` 1
                case result of
                    Right snapshot -> case snapshotValue snapshot of
                        Right utxos -> length utxos `shouldBe` 1
                        Left err -> fail ("expected a resolved payer list, got " <> show err)
                    Left err -> fail ("expected a snapshot, got " <> show err)

    describe "RQ-240-05 -- derived reference resolution (DATA-INV-240-01), RED against the existing local interpreter" $
        it "should derive the live reference output instead of reporting UnsupportedOperation" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [referenceCreateAt (sampleTxIn 0x20) scriptA addrA]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashA]
                case result of
                    Right [ref] -> chainReferenceScriptHash ref `shouldBe` hashA
                    Right other -> expectationFailure ("expected exactly one resolved reference, got " <> show (length other))
                    Left err ->
                        expectationFailure
                            ("RED: the local interpreter does not yet derive references from live stored outputs: " <> show err)

    describe "RQ-240-06 -- follower-backed temporal settlement, RED against the closed test-local stand-in" $ do
        it "capSettlementObserver's probe should reflect a live matching asset output, not a closed empty stand-in" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [assetCreateAt (sampleTxIn 0x40) addrA]
                let observer = capSettlementObserver redCapabilities (queryHandleLocalScope (testQueryHandle runner))
                matches <- probeSettlement observer policyHexA assetNameHexA
                case matches of
                    [_one] -> pure ()
                    other -> expectationFailure ("RED: expected the one live matching asset output, got " <> show (length other))

        it "capTransactionSettled should reflect a live tracked output of the exact tx id, not the closed False stand-in" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate targetTxIn addrA]
                settled <- capTransactionSettled redCapabilities (queryHandleLocalScope (testQueryHandle runner)) targetTxId
                settled `shouldBe` True

    describe
        "A-013 repair: production write-verb entrypoints acquire through exactly \
        \one local-store transaction, never a split acquisition (T240-S1-14 audit \
        \finding 1, INV-240-LOCALTIER/INV-240-SNAPSHOT)"
        $ do
            it "runAdvanceWith's submit path invokes the local runner exactly once" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [ UtxoCreate
                            (sampleTxIn 0x50)
                            entrypointCheckpointAddress
                            (entrypointCheckpointOutput rotationFixtureAidBytes)
                        ]
                    counter <- newIORef (0 :: Int)
                    kelPath <- getDataFileName "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
                    sigToken <- entrypointSignatureToken "kli-export-2-of-5-rotation.cesr"
                    withSystemTempDirectory "ckeri-advance-entrypoint" $ \dir -> do
                        let manifestPath = dir </> "manifest.json"
                            sigPath = dir </> "controller-signatures.txt"
                        writeManifestAtomic manifestPath entrypointManifest
                        BS.writeFile sigPath (sigToken <> "\n")
                        let settings =
                                AdvanceSettings
                                    { advanceNetwork = "preprod"
                                    , advanceNetworkMagic = 1
                                    , advanceConfiguredAid = rotationFixtureAidText
                                    , advanceKel = kelPath
                                    , advanceSigningPackage = Nothing
                                    , advanceControllerSignatures = Just sigPath
                                    , advancePayer = Just "unused-payer"
                                    , advanceNodeSocket = Just "unused-node-socket"
                                    , advanceFundingAddress = Just "unused-funding-address"
                                    , advanceManifest = manifestPath
                                    , advanceStorePath = "unused-store-path"
                                    , advanceTimeoutSeconds = 30
                                    , advanceValidatorTestUnderSigned = False
                                    , advanceValidatorTestUnderWitnessed = False
                                    , advanceValidatorTestStale = False
                                    }
                        _ <-
                            try (runAdvanceWith (entrypointCountingLocalOpener counter runner) entrypointStubLiveOpener settings) ::
                                IO (Either SomeException ())
                        count <- readIORef counter
                        count `shouldBe` 1

            it "runCloseWith's submit path invokes the local runner exactly once" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [ UtxoCreate
                            (sampleTxIn 0x51)
                            entrypointCheckpointAddress
                            (entrypointCheckpointOutput inceptionFixtureAidBytes)
                        ]
                    counter <- newIORef (0 :: Int)
                    kelPath <- getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
                    sigToken <- entrypointSignatureToken "kli-export-2-of-5-rotation.cesr"
                    withSystemTempDirectory "ckeri-close-entrypoint" $ \dir -> do
                        let manifestPath = dir </> "manifest.json"
                            sigPath = dir </> "controller-signatures.txt"
                        writeManifestAtomic manifestPath entrypointManifest
                        BS.writeFile sigPath (sigToken <> "\n")
                        let settings =
                                CloseSettings
                                    { closeNetwork = "preprod"
                                    , closeNetworkMagic = 1
                                    , closeConfiguredAid = inceptionFixtureAidText
                                    , closeKel = kelPath
                                    , closeTo = "unused-refund-address"
                                    , closeSigningPackage = Nothing
                                    , closeControllerSignatures = Just sigPath
                                    , closePayer = Just "unused-payer"
                                    , closeNodeSocket = Just "unused-node-socket"
                                    , closeFundingAddress = Just "unused-funding-address"
                                    , closeChangeAddress = Just "unused-change-address"
                                    , closeManifest = manifestPath
                                    , closeStorePath = "unused-store-path"
                                    , closeTimeoutSeconds = 30
                                    , closeValidatorTestNonController = False
                                    }
                        _ <-
                            try (runCloseWith (entrypointCountingLocalOpener counter runner) entrypointStubLiveOpener settings) ::
                                IO (Either SomeException ())
                        count <- readIORef counter
                        count `shouldBe` 1
  where
    targetTxIn = sampleTxIn 0x30
    targetTxId = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0x30))))

-- ---------------------------------------------------------------------------
-- A-013 repair helpers (T240-S1-14 audit finding 1): builds a REAL
-- 'LocalOpener' from a counting in-memory runner and calls the real,
-- unmodified production 'runAdvanceWith'\/'runCloseWith' entrypoints --
-- never a re-implementation or a helper the entrypoint merely happens to
-- also call -- so a production regression that stops calling the composed
-- acquisition, calls a raw runner beside it, or invokes it twice changes
-- what these examples observe. The live bracket is stubbed (throws a named
-- sentinel rather than dialing a socket); every fixture below reuses the
-- ALREADY-SIGNED\/self-addressed KEL exports "Cardano.KERI.Deployment.KELSpec"
-- proves parseable, decoded once (via 'Cardano.KERI.AID.CESR.parsePrimitive')
-- to the exact raw AID bytes each stream's own inception event carries, so
-- 'advanceConfiguredAid'\/'closeConfiguredAid' genuinely match what
-- 'parseRotationExport'\/'parseInceptionExport' return -- never a
-- fabricated AID. The manifest carries no script entries, so
-- 'mkAdvancePackage'\/'mkClosePackage' fail closed shortly AFTER the one
-- acquisition this property observes (T280-S1-14's own audited property is
-- acquisition COUNT, not full submission success); reaching that clean
-- failure, or the live-bracket sentinel, is equally valid evidence that
-- the local acquisition ran to completion exactly once.

{- | The frozen inception fixture's own AID ("Cardano.KERI.Deployment.KELSpec"
proves it parses; confirmed once via 'Cardano.KERI.AID.CESR.parsePrimitive'
and pinned here as literal bytes, matching 'inceptionFixtureAidText').
-}
inceptionFixtureAidText :: Text
inceptionFixtureAidText = "EN_OgA7LhFnVEX0jwoE9tSoh7-MfWx3TKzAVSIsrLiHW"

inceptionFixtureAidBytes :: ByteString
inceptionFixtureAidBytes =
    BS.pack
        [ 223
        , 206
        , 128
        , 14
        , 203
        , 132
        , 89
        , 213
        , 17
        , 125
        , 35
        , 194
        , 129
        , 61
        , 181
        , 42
        , 33
        , 239
        , 227
        , 31
        , 91
        , 29
        , 211
        , 43
        , 48
        , 21
        , 72
        , 139
        , 43
        , 46
        , 33
        , 214
        ]

{- | The frozen rotation fixture's own AID, decoded the same way (see
'inceptionFixtureAidText').
-}
rotationFixtureAidText :: Text
rotationFixtureAidText = "EDujsIfURabzXyyBulukdlPkG_BX9d4px6VEQFMd33zT"

rotationFixtureAidBytes :: ByteString
rotationFixtureAidBytes =
    BS.pack
        [ 59
        , 163
        , 176
        , 135
        , 212
        , 69
        , 166
        , 243
        , 95
        , 44
        , 129
        , 186
        , 91
        , 164
        , 118
        , 83
        , 228
        , 27
        , 240
        , 87
        , 245
        , 222
        , 41
        , 199
        , 165
        , 68
        , 64
        , 83
        , 29
        , 223
        , 124
        , 211
        ]

{- | Extract one real 88-character indexed-CESR controller-signature token
from a KEL export fixture -- the exact technique
"Cardano.KERI.Deployment.KELSpec"'s own "decodes bare indexed CESR
controller-signature lines" example already proves against this same
fixture family (searching for the @-AAFA@ count-code marker). Format-valid
so 'parseIndexedSignatureLines' accepts it; not asserted cryptographically
valid against this test's synthetic checkpoint (unnecessary -- the
acquisition this property observes completes, successfully or not, before
signature verification is ever reached).
-}
entrypointSignatureToken :: FilePath -> IO ByteString
entrypointSignatureToken fixtureName = do
    path <- getDataFileName ("deployment-test/fixtures/" <> fixtureName)
    bytes <- BS.readFile path
    let afterCounter = BS.drop 4 (snd (BS.breakSubstring "-AAFA" bytes))
    pure (BS.take 88 afterCounter)

{- | A fixed, provider-neutral checkpoint identity for this property's
fixtures (mirrors "Cardano.KERI.CLI.Backend.EndpointSpec"'s own proven
checkpoint-fixture pattern).
-}
entrypointCheckpointPolicy :: PolicyID
entrypointCheckpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x51) of
                Just h -> h
                Nothing -> error "LocalWritePathSpec: invalid entrypoint checkpoint policy id width"

entrypointCheckpointLedgerAddress :: Addr
entrypointCheckpointLedgerAddress =
    let PolicyID policyScriptHash = entrypointCheckpointPolicy
     in Addr Testnet (ScriptHashObj policyScriptHash) StakeRefNull

entrypointCheckpointAddress :: Indexer.Address
entrypointCheckpointAddress = Indexer.Address (serialiseAddr entrypointCheckpointLedgerAddress)

entrypointCheckpointAddressText :: Text
entrypointCheckpointAddressText =
    let Indexer.Address bytes = entrypointCheckpointAddress
     in Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes bytes)

entrypointCheckpointPolicyText :: Text
entrypointCheckpointPolicyText =
    let PolicyID (ScriptHash h) = entrypointCheckpointPolicy
     in TE.decodeUtf8 (convertToBase Base16 (hashToBytes h))

{- | One live checkpoint output at 'entrypointCheckpointAddress', carrying
@aid@ as its decoded CESR AID -- reused for both the advance (rotation
fixture AID) and close (inception fixture AID) examples.
-}
entrypointCheckpointOutput :: ByteString -> Indexer.TxOut
entrypointCheckpointOutput aid =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (plutusData (V1 datum)))
  where
    datum =
        CheckpointDatumV1
            { cdCesrAid = aid
            , cdCurKeys = [BS.replicate 32 0x11]
            , cdCurThreshold = Unweighted 1
            , cdNextKeys = [BS.replicate 32 0x22]
            , cdNextThreshold = Unweighted 1
            , cdWitnesses = []
            , cdToad = 0
            , cdSeq = 0
            , cdNativeSn = 0
            }
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            entrypointCheckpointLedgerAddress
            ( MaryValue
                (Coin 5_000_000)
                ( MultiAsset $
                    Map.singleton
                        entrypointCheckpointPolicy
                        (Map.singleton (AssetName . SBS.toShort $ deriveAidAssetName aid) 1)
                )
            )
    inlineDatum :: PLC.Data -> Datum ConwayEra
    inlineDatum plutus = Datum (dataToBinaryData (Data plutus))
    plutusData :: (ToData a) => a -> PLC.Data
    plutusData value =
        let BuiltinData plutus = toBuiltinData value
         in plutus

{- | A manifest with the frozen checkpoint identity above and NO script
entries -- 'mkAdvancePackage'\/'mkClosePackage' fail closed on a missing
@checkpoint-register@ script shortly after this property's one observed
acquisition (see the module Haddock above); no reference-script resolution
is exercised by this property (that is 'DATA-INV-240-01', proven
separately above).
-}
entrypointManifest :: Manifest
entrypointManifest =
    Manifest
        { manifestSchemaVersion = "cardano-keri/m1-deployment-manifest/v1"
        , manifestNetwork = NetworkInfo{networkName = "preprod", networkMagic = 1}
        , manifestSource = SourceInfo{sourceRepository = "unused", sourceCommit = T.replicate 40 "0"}
        , manifestBlueprint = BlueprintInfo{blueprintDigestSha256 = T.replicate 64 "0"}
        , manifestParameters =
            DeploymentParameters
                { parameterCheckpointVersion = 0
                , parameterNetworkDiscriminator = 0
                , parameterRegistrationBond = 1_000_000_000
                , parameterFreezeBond = 5_000_000
                , parameterFreezeWindow = 10_000
                }
        , manifestCheckpoint =
            CheckpointInfo
                { checkpointAddressBech32 = entrypointCheckpointAddressText
                , checkpointPolicyId = entrypointCheckpointPolicyText
                }
        , manifestPublishedAt = "2026-01-01T00:00:00Z"
        , manifestScripts = []
        }

{- | A real 'LocalOpener' (never a re-implementation of one): ignores the
'LocalSettings' argument (this test's scope is the in-memory fixture, not
a real store path) and hands the callback a 'LocalQueryScope' whose runner
is wrapped in 'countingRunner', so every store-transaction invocation the
production entrypoint's acquisition performs is counted.
-}
entrypointCountingLocalOpener :: IORef Int -> RunTransaction IO cf Cols op -> LocalOpener
entrypointCountingLocalOpener counter runner _localSettings action =
    action
        LocalQueryScope
            { localScopeRunner = countingRunner counter runner
            , localScopeCheckpointIdentity = Just (entrypointCheckpointPolicy, entrypointCheckpointAddress)
            , localScopeBoardIdentity = Nothing
            }

{- | Marks that a production entrypoint reached the live-node bracket
(i.e. its local acquisition already completed).
-}
data ReachedLiveBracket = ReachedLiveBracket
    deriving stock (Show, Eq)

instance Exception ReachedLiveBracket

{- | A real 'LiveOpener' that never dials a socket: throws
'ReachedLiveBracket' the moment production code tries to open the live
bracket, so a test can distinguish "acquisition ran, then reached
submission" from "acquisition never ran" without live node infrastructure.
-}
entrypointStubLiveOpener :: LiveOpener
entrypointStubLiveOpener _config _observeTransaction _action = throwIO ReachedLiveBracket

-- ---------------------------------------------------------------------------
-- Helpers -- per-spec copies of Cardano.KERI.Indexer.ChainQuerySpec's proven
-- shapes, plus new reference-script/asset output builders for this spec.

testQueryHandle :: RunTransaction IO cf Cols op -> QueryHandle cf op
testQueryHandle runner =
    QueryHandle
        { qhRunner = runner
        , qhCheckpointAddress = addrA
        , qhCheckpointPolicy = unusedCheckpointPolicy
        , qhBoardAddress = addrA
        , qhReadiness = unusedReadiness
        }

unusedCheckpointPolicy :: PolicyID
unusedCheckpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just h -> h
                Nothing -> error "LocalWritePathSpec: invalid checkpoint policy id width"

unusedReadiness :: STM Readiness
unusedReadiness =
    pure
        Readiness
            { rProcessedSlot = Nothing
            , rTipSlot = Nothing
            , rUpstream = UpstreamConnected
            , rUpdatedAt = UTCTime (fromGregorian 2026 1 1) 0
            }

countingRunner :: IORef Int -> RunTransaction IO cf Cols op -> RunTransaction IO cf Cols op
countingRunner counter runner =
    RunTransaction
        { runTransaction = \tx -> do
            atomicModifyIORef' counter (\n -> (n + 1, ()))
            runTransaction runner tx
        }

payerCreate :: Indexer.TxIn -> Indexer.Address -> UtxoOp
payerCreate txIn addr = UtxoCreate txIn addr (payerOutput addr)

payerOutput :: Indexer.Address -> Indexer.TxOut
payerOutput (Indexer.Address bytes) =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash = fromJust (hashFromBytes bytes)
    txOut :: TxOut ConwayEra
    txOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            (MaryValue (Coin 5_000_000) (MultiAsset mempty))

-- | One live output at @addr@ carrying @script@ as its reference script.
referenceCreateAt :: Indexer.TxIn -> Script ConwayEra -> Indexer.Address -> UtxoOp
referenceCreateAt txIn script addr = UtxoCreate txIn addr (referenceOutput script addr)

referenceOutput :: Script ConwayEra -> Indexer.Address -> Indexer.TxOut
referenceOutput script (Indexer.Address bytes) =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash = fromJust (hashFromBytes bytes)
    plain :: TxOut ConwayEra
    plain =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            (MaryValue (Coin 100_000_000) (MultiAsset mempty))
    txOut :: TxOut ConwayEra
    txOut =
        runIdentity $
            (referenceScriptTxOutL . fromStrictMaybeL) (\_ -> Identity (Just script)) plain

{- | One live output at @addr@ carrying exactly one unit of a fixed
(policy, asset name) native asset -- 'policyHexA'\/'assetNameHexA'.
-}
assetCreateAt :: Indexer.TxIn -> Indexer.Address -> UtxoOp
assetCreateAt txIn addr = UtxoCreate txIn addr (assetOutput addr)

assetOutput :: Indexer.Address -> Indexer.TxOut
assetOutput (Indexer.Address bytes) =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash = fromJust (hashFromBytes bytes)
    txOut :: TxOut ConwayEra
    txOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            ( MaryValue
                (Coin 2_000_000)
                (MultiAsset (Map.singleton assetPolicyA (Map.singleton (AssetName (SBS.toShort assetNameA)) 1)))
            )

assetPolicyA :: PolicyID
assetPolicyA = PolicyID (computeScriptHash scriptABytes)

assetNameA :: BS.ByteString
assetNameA = "s240-red-asset"

assetNameHexA :: Text
assetNameHexA = TE.decodeUtf8 (convertToBase Base16 assetNameA)

policyHexA :: Text
policyHexA = hashA

scriptABytes :: SBS.ShortByteString
scriptABytes = SBS.toShort "s240-red-synthetic-script-a"

scriptA :: Script ConwayEra
scriptA = mkCageScript scriptABytes

hashA :: Text
hashA = scriptHashText (computeScriptHash scriptABytes)

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte) 0

addrA :: Indexer.Address
addrA = Indexer.Address (BS.replicate 28 0xA1)

addrText :: Indexer.Address -> Text
addrText (Indexer.Address bytes) =
    Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes bytes)

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)
