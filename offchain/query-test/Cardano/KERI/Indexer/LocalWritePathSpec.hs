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
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted, Weighted), Weight (Weight))
import Cardano.KERI.ChainQuery.Program (ChainQuery, currentCheckpoint, payerUtxos)
import Cardano.KERI.ChainQuery.Settlement (SettlementObserver (..))
import Cardano.KERI.ChainQuery.Types (
    ActiveCheckpoint (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainReference (..),
    ChainReferenceScript (..),
    CheckpointLocator (..),
    QuerySnapshot (..),
 )
import Cardano.KERI.Deployment.CLI (
    AdvanceSettings (..),
    BoardPostSettings (..),
    BoardRetireSettings (..),
    BoardTransactionSettings (..),
    BoardUpdateSettings (..),
    CloseSettings (..),
    DeploySettings (..),
    LiveOpener,
    LocalOpener,
    runAdvanceWith,
    runBoardDeployWith,
    runBoardPostWith,
    runBoardRetireWith,
    runBoardUpdateWith,
    runCloseWith,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    frozenEndpointBoardAddress,
    frozenEndpointBoardPolicyId,
    writeEndpointBoardManifestAtomic,
 )
import Cardano.KERI.Deployment.LiveRuntime (LiveContext (..))
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    Reference (..),
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
import Data.Aeson (encode, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
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
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldNotBe)

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

    describe "RQ-240-05 -- derived reference resolution (DATA-INV-240-01), RED against the existing local interpreter" $ do
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

        it
            "resolves a multi-hash request in the caller's own (non-sorted) order, with the exact full output identity, not just the hash (DATA-INV-240-01)"
            $ withInMemoryIndexerRunner
            $ \handle runner -> do
                applyAtSlot
                    handle
                    (Indexer.SlotNo 10)
                    (blockHash 0x01)
                    [ referenceCreateAt (sampleTxIn 0x20) scriptA addrA
                    , referenceCreateAt (sampleTxIn 0x22) scriptB addrB
                    ]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashB, hashA]
                case result of
                    Right [refB, refA] -> do
                        -- caller-order preserved (requested [hashB, hashA], not sorted)
                        chainReferenceScriptHash refB `shouldBe` hashB
                        chainReferenceScriptHash refA `shouldBe` hashA
                        -- full output identity, not merely the hash field
                        chainAssetTxId (chainReferenceOutput refB) `shouldBe` sampleTxIdHex 0x22
                        chainAssetIndex (chainReferenceOutput refB) `shouldBe` 0
                        chainAssetAddress (chainReferenceOutput refB) `shouldBe` referenceOutputAddressText addrB
                        chainAssetLovelace (chainReferenceOutput refB) `shouldBe` 100_000_000
                        chainAssetTxId (chainReferenceOutput refA) `shouldBe` sampleTxIdHex 0x20
                        chainAssetIndex (chainReferenceOutput refA) `shouldBe` 0
                        chainAssetAddress (chainReferenceOutput refA) `shouldBe` referenceOutputAddressText addrA
                    Right other -> expectationFailure ("expected exactly the 2 requested references in order, got " <> show (length other))
                    Left err -> expectationFailure ("expected both references to resolve, got " <> show err)

        it "fails closed on a wholly absent hash -- no live output carries any reference script at all (DATA-INV-240-01)" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x23) addrA]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashA]
                case result of
                    Left (DecodingFailure _) -> pure ()
                    other -> expectationFailure ("expected a named DecodingFailure for the absent hash, got " <> show other)

        it "fails closed on a hash that mismatches every live reference, even when other references exist (DATA-INV-240-01)" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot
                    handle
                    (Indexer.SlotNo 10)
                    (blockHash 0x01)
                    [ referenceCreateAt (sampleTxIn 0x20) scriptA addrA
                    , referenceCreateAt (sampleTxIn 0x22) scriptB addrB
                    ]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashC]
                case result of
                    Left (DecodingFailure _) -> pure ()
                    other -> expectationFailure ("expected a named DecodingFailure for the mismatched hash, got " <> show other)

        it "fails closed on duplicate live reference rows for the same hash, never picks one arbitrarily (DATA-INV-240-01)" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot
                    handle
                    (Indexer.SlotNo 10)
                    (blockHash 0x01)
                    [ referenceCreateAt (sampleTxIn 0x20) scriptA addrA
                    , referenceCreateAt (sampleTxIn 0x24) scriptA addrB
                    ]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashA]
                case result of
                    Left (AmbiguousCurrentState _) -> pure ()
                    other -> expectationFailure ("expected a named AmbiguousCurrentState for the duplicate rows, got " <> show other)

        it
            "fails closed on a malformed stored row even when the requested hash does not involve it -- no row is silently skipped (DATA-INV-240-01)"
            $ withInMemoryIndexerRunner
            $ \handle runner -> do
                applyAtSlot
                    handle
                    (Indexer.SlotNo 10)
                    (blockHash 0x01)
                    [ referenceCreateAt (sampleTxIn 0x20) scriptA addrA
                    , UtxoCreate (sampleTxIn 0x25) addrB malformedTxOut
                    ]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashA]
                case result of
                    Left (DecodingFailure _) -> pure ()
                    other -> expectationFailure ("expected a named DecodingFailure from the malformed row, got " <> show other)

        it "fails closed on a mixed good/bad request -- never a partial list, all-or-nothing (DATA-INV-240-01)" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [referenceCreateAt (sampleTxIn 0x20) scriptA addrA]
                result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [hashA, hashC]
                case result of
                    Left (DecodingFailure _) -> pure ()
                    Right partial ->
                        expectationFailure
                            ("expected the whole mixed request to fail closed, got a partial result of length " <> show (length partial))
                    other -> expectationFailure ("expected a named DecodingFailure, got " <> show other)

    describe
        "A-013 finding 3: candidate local-interpreter acquisition matches the real \
        \frozen-base provider's acquisition, byte for byte (INV-240-PARITY)"
        $ do
            it
                "capAtomicQuery's payerUtxos decode of the shared fixture is byte-identical to the real koiosInterpreter's decode of the same fixture"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [parityCreate parityTxIn parityAddr]
                    result <- capAtomicQuery redCapabilities (queryHandleLocalScope (testQueryHandle runner)) (payerUtxos [addrText parityAddr])
                    case result of
                        Right snapshot -> case snapshotValue snapshot of
                            Right utxos -> utxos `shouldBe` [parityExpectedUtxo]
                            Left err -> expectationFailure ("expected the acquired payer utxo, got " <> show err)
                        Left err -> expectationFailure ("expected a snapshot, got " <> show err)

            it
                "rejects a one-side acquired-value perturbation -- a changed local lovelace no longer matches the frozen base-provider value (permanent falsifier)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [UtxoCreate parityTxIn parityAddr (perturbedParityOutput parityAddr)]
                    result <- capAtomicQuery redCapabilities (queryHandleLocalScope (testQueryHandle runner)) (payerUtxos [addrText parityAddr])
                    case result of
                        Right snapshot -> case snapshotValue snapshot of
                            Right utxos ->
                                utxos
                                    `shouldNotBe` [parityExpectedUtxo]
                            Left err -> expectationFailure ("expected the perturbed payer utxo to still decode, got " <> show err)
                        Left err -> expectationFailure ("expected a snapshot, got " <> show err)

            it
                "capReferenceScripts's decode of the shared reference fixture is byte-identical to the real koiosInterpreter's two-endpoint (/reference_script_utxos then /utxo_info) decode of the same fixture"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [referenceCreateAt parityReferenceTxIn parityReferenceScript parityReferenceAddr]
                    result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [parityReferenceHash]
                    case result of
                        Right refs -> refs `shouldBe` [parityExpectedReference]
                        Left err -> expectationFailure ("expected the acquired reference, got " <> show err)

            it
                "rejects a one-side acquired-value perturbation -- a changed local reference-script BYTES value no longer matches the frozen base-provider value (permanent falsifier, family-specific field)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [referenceCreateAt parityReferenceTxIn perturbedParityReferenceScript parityReferenceAddr]
                    result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [perturbedParityReferenceHash]
                    case result of
                        Right refs -> refs `shouldNotBe` [parityExpectedReference]
                        Left err -> expectationFailure ("expected the perturbed reference to still decode, got " <> show err)

            it
                "capAtomicQuery's currentCheckpoint decode of the shared checkpoint fixture (nested Weighted-threshold datum) is byte-identical to the real koiosInterpreter's inline-datum-JSON decode of the same fixture"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [UtxoCreate parityCheckpointTxIn addrA (parityCheckpointOutput parityCheckpointDatum)]
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    case result of
                        Right snapshot -> case snapshotValue snapshot of
                            Right (Just checkpoint) -> checkpoint `shouldBe` parityExpectedCheckpoint
                            Right Nothing -> expectationFailure "expected the acquired checkpoint, got Nothing"
                            Left err -> expectationFailure ("expected the acquired checkpoint, got " <> show err)
                        Left err -> expectationFailure ("expected a snapshot, got " <> show err)

            it
                "rejects a one-side acquired-value perturbation -- a changed local Weight numerator (inside the nested Weighted threshold) no longer matches the frozen base-provider value (permanent falsifier, family-specific field)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [UtxoCreate parityCheckpointTxIn addrA (parityCheckpointOutput perturbedParityCheckpointDatum)]
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    case result of
                        Right snapshot -> case snapshotValue snapshot of
                            Right (Just checkpoint) -> checkpoint `shouldNotBe` parityExpectedCheckpoint
                            Right Nothing -> expectationFailure "expected the perturbed checkpoint to still decode, got Nothing"
                            Left err -> expectationFailure ("expected the perturbed checkpoint to still decode, got " <> show err)
                        Left err -> expectationFailure ("expected a snapshot, got " <> show err)

            it "fails closed the same way on absence: no live checkpoint output for this AID at all (currentCheckpoint, both acquisition paths report no error)" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) []
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    case result of
                        Right snapshot -> snapshotValue snapshot `shouldBe` Right Nothing
                        Left err -> expectationFailure ("expected a snapshot, got " <> show err)

            it
                "fails closed the same way on ambiguity: two live checkpoint outputs for the same AID -- byte-identical AmbiguousCurrentState text on both acquisition paths (confirmed by direct comparison, not assumed)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [ UtxoCreate parityCheckpointTxIn addrA (parityCheckpointOutput parityCheckpointDatum)
                        , UtxoCreate (Indexer.TxIn (BS.replicate 32 0x75) 0) addrA (parityCheckpointOutput parityCheckpointDatum)
                        ]
                    -- Unlike absence (a genuine Right Nothing, no short-circuit),
                    -- an interpreter-level AmbiguousCurrentState short-circuits
                    -- the whole free-algebra computation and surfaces at
                    -- capAtomicQuery's own outer Either, never nested inside
                    -- snapshotValue -- confirmed by this example itself, not
                    -- assumed.
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    result `shouldBe` Left (AmbiguousCurrentState "more than one live checkpoint output for this AID")

            it
                "diverges from the provider on a malformed datum -- confirmed, not assumed: the base path surfaces a named DecodingFailure for its single malformed row, while the local path's list-comprehension filter (Right record <- [decodeCheckpointOutput ...]) silently excludes an undecodable row from the match set, reporting absence rather than an error (a pre-existing #257 local-interpreter behavior, out of this repair's fence to change; recorded, not treated as a defect)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [UtxoCreate parityCheckpointTxIn addrA malformedTxOut]
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    case result of
                        Right snapshot -> snapshotValue snapshot `shouldBe` Right Nothing
                        Left err -> expectationFailure ("expected a snapshot, got " <> show err)

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

            it "runBoardDeployWith's phase invokes the local runner exactly once (one artifact, one funding acquisition)" $
                withInMemoryIndexerRunner $ \_handle runner -> do
                    counter <- newIORef (0 :: Int)
                    withSystemTempDirectory "ckeri-board-deploy-entrypoint" $ \dir -> do
                        let blueprintPath = dir </> "blueprint.json"
                            sourceRepo = dir </> "source-repo"
                            outPath = dir </> "board-manifest.json"
                        createDirectoryIfMissing True (sourceRepo </> "onchain")
                        BSL.writeFile blueprintPath entrypointBoardBlueprintJson
                        let settings =
                                DeploySettings
                                    { deployNetwork = "preprod"
                                    , deployNetworkMagic = 1
                                    , deployBlueprint = blueprintPath
                                    , deployNodeSocket = "unused-node-socket"
                                    , deployFundingAddress = "unused-funding-address"
                                    , deploySigningKeyFile = "unused-signing-key"
                                    , deploySourceRepo = sourceRepo
                                    , deploySourceRepositoryUrl = "unused-repo-url"
                                    , deploySourceCommit = Just (T.replicate 40 "a")
                                    , deployOut = outPath
                                    , deployReferenceLovelace = 5_000_000
                                    , deployStorePath = "unused-store-path"
                                    , deployTimeoutSeconds = 30
                                    }
                        _ <-
                            try
                                ( runBoardDeployWith
                                    (entrypointCountingLocalOpener counter runner)
                                    entrypointLazyStubLiveOpener
                                    settings
                                ) ::
                                IO (Either SomeException ())
                        count <- readIORef counter
                        count `shouldBe` 1

            it "runBoardPostWith's phase invokes the local runner exactly once" $
                withInMemoryIndexerRunner $ \_handle runner -> do
                    counter <- newIORef (0 :: Int)
                    endpointRecordPath <- getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    withSystemTempDirectory "ckeri-board-post-entrypoint" $ \dir -> do
                        let manifestPath = dir </> "board-manifest.json"
                        writeEndpointBoardManifestAtomic manifestPath entrypointBoardManifest
                        let settings =
                                BoardPostSettings
                                    { boardPostEndpointRecord = endpointRecordPath
                                    , boardPostDepositLovelace = 2_000_000
                                    , boardPostTransaction = entrypointBoardTransactionSettings manifestPath
                                    }
                        _ <-
                            try (runBoardPostWith (entrypointCountingLocalOpener counter runner) entrypointStubLiveOpener settings) ::
                                IO (Either SomeException ())
                        count <- readIORef counter
                        count `shouldBe` 1

            it "runBoardUpdateWith's phase invokes the local runner exactly once" $
                withInMemoryIndexerRunner $ \_handle runner -> do
                    counter <- newIORef (0 :: Int)
                    endpointRecordPath <- getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    withSystemTempDirectory "ckeri-board-update-entrypoint" $ \dir -> do
                        let manifestPath = dir </> "board-manifest.json"
                        writeEndpointBoardManifestAtomic manifestPath entrypointBoardManifest
                        let settings =
                                BoardUpdateSettings
                                    { boardUpdateEndpointRecord = endpointRecordPath
                                    , boardUpdateOutReference = Nothing
                                    , boardUpdateTransaction = entrypointBoardTransactionSettings manifestPath
                                    }
                        _ <-
                            try (runBoardUpdateWith (entrypointCountingLocalOpener counter runner) entrypointStubLiveOpener settings) ::
                                IO (Either SomeException ())
                        count <- readIORef counter
                        count `shouldBe` 1

            it "runBoardRetireWith's phase invokes the local runner exactly once" $
                withInMemoryIndexerRunner $ \_handle runner -> do
                    counter <- newIORef (0 :: Int)
                    withSystemTempDirectory "ckeri-board-retire-entrypoint" $ \dir -> do
                        let manifestPath = dir </> "board-manifest.json"
                        writeEndpointBoardManifestAtomic manifestPath entrypointBoardManifest
                        let settings =
                                BoardRetireSettings
                                    { boardRetireWitness = entrypointWitnessKeyText
                                    , boardRetireOutReference = Nothing
                                    , boardRetireTo = "unused-refund-address"
                                    , boardRetireTransaction = entrypointBoardTransactionSettings manifestPath
                                    }
                        _ <-
                            try (runBoardRetireWith (entrypointCountingLocalOpener counter runner) entrypointStubLiveOpener settings) ::
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

{- | A real 'LiveOpener' for the two write verbs (board-deploy\/deploy) whose
LOCAL acquisition runs INSIDE the live bracket's own callback
('Cardano.KERI.Deployment.CLI.publishArtifactsLive' needs the live
funding address text, which only 'LiveConfig' -- not a real node
connection -- supplies): reaches the real callback with a 'LiveContext'
carrying the REAL 'LiveConfig' but bottom ('error') in every other field.
This is safe specifically because the one acquisition this property
observes only forces 'liveConfig'; forcing any other field (submitting a
real transaction) happens strictly after, exactly like the clean
downstream failures 'entrypointStubLiveOpener''s sibling examples above
already accept as equally valid evidence.
-}
entrypointLazyStubLiveOpener :: LiveOpener
entrypointLazyStubLiveOpener config _observeTransaction action =
    action
        LiveContext
            { liveTransactionRuntime = error "LocalWritePathSpec: liveTransactionRuntime not exercised by this property"
            , liveProvider = error "LocalWritePathSpec: liveProvider not exercised by this property"
            , liveFundingAddress = error "LocalWritePathSpec: liveFundingAddress not exercised by this property"
            , liveConfig = config
            }

{- | The frozen OOBI fixture's own witness key ("Cardano.KERI.Deployment.
EndpointBoardSpec" already proves @witness-1-oobi.cesr@ parses via
'parseEndpointRecord'; this is that same stream's own inception @i@\/@k@
key, reused as the board-retire witness parameter).
-}
entrypointWitnessKeyText :: Text
entrypointWitnessKeyText = "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"

{- | A board manifest carrying the SAME 'frozenEndpointBoardPolicyId'\/
'frozenEndpointBoardAddress' every real manifest must (every board plan
builder checks the manifest's own board identity against these frozen
constants BEFORE this property's acquisition step is ever reached -- an
arbitrary identity fails closed there, at count 0, before proving
anything), with a reference locator that resolves to no live output --
'boardReferenceOutputTx' (every board verb's first acquisition step)
fails closed shortly after this property's one observed acquisition (no
reference row is seeded), exactly matching 'entrypointManifest''s "clean
failure after one acquisition is equally valid evidence" contract above.
-}
entrypointBoardManifest :: EndpointBoardManifest
entrypointBoardManifest =
    EndpointBoardManifest
        { endpointBoardManifestSchemaVersion = "cardano-keri/m1-endpoint-board-manifest/v1"
        , endpointBoardManifestNetwork = NetworkInfo{networkName = "preprod", networkMagic = 1}
        , endpointBoardManifestSource = SourceInfo{sourceRepository = "unused", sourceCommit = T.replicate 40 "0"}
        , endpointBoardManifestBlueprint = BlueprintInfo{blueprintDigestSha256 = T.replicate 64 "0"}
        , endpointBoardManifestInfo =
            EndpointBoardInfo
                { endpointBoardPolicyId = frozenEndpointBoardPolicyId
                , endpointBoardAddress = frozenEndpointBoardAddress
                , endpointBoardProgramBytes = 1
                , endpointBoardReference = Reference{referenceTxId = T.replicate 64 "0", referenceIndex = 0}
                }
        , endpointBoardManifestPublishedAt = "2026-01-01T00:00:00Z"
        }

{- | A well-formed, payment-key-credentialled (never script-credentialled)
testnet address -- 'BoardTx.mkBoardPostPlan' requires "board ownership"
(a Cardano payment verification key) BEFORE this property's acquisition
step is ever reached (board-post's plan is built before the local scope
opens, unlike update\/retire's), so 'entrypointCheckpointAddressText' (a
script address) or an arbitrary non-Bech32 placeholder both fail closed
at count 0, before proving anything.
-}
entrypointFundingAddressText :: Text
entrypointFundingAddressText =
    Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes (serialiseAddr fundingLedgerAddress))
  where
    fundingLedgerAddress =
        Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull
    keyHash = fromJust (hashFromBytes (BS.replicate 28 0x53))

entrypointBoardTransactionSettings :: FilePath -> BoardTransactionSettings
entrypointBoardTransactionSettings manifestPath =
    BoardTransactionSettings
        { boardTransactionNetwork = "preprod"
        , boardTransactionNetworkMagic = 1
        , boardTransactionPayer = "unused-payer"
        , boardTransactionNodeSocket = "unused-node-socket"
        , boardTransactionFundingAddress = entrypointFundingAddressText
        , boardTransactionChangeAddress = Nothing
        , boardTransactionManifest = manifestPath
        , boardTransactionStorePath = "unused-store-path"
        , boardTransactionTimeoutSeconds = 30
        }

{- | A blueprint JSON with exactly the one validator
'Cardano.KERI.Deployment.Script.deriveBoardScript' requires
(@endpoint_board.endpoint_board.mint@). Unlike the five-validator
'Cardano.KERI.Deployment.Script.deriveV1Scripts' path (which APPLIES
parameters through 'PlutusLedgerApi.V3.uncheckedDeserialiseUPLC', needing
genuinely valid compiled UPLC), 'deriveBoardScript' only extracts and
hashes the raw bytes -- an arbitrary even-length hex string decodes fine.
-}
entrypointBoardBlueprintJson :: BSL.ByteString
entrypointBoardBlueprintJson =
    encode $
        object
            [ "validators"
                .= [ object
                        [ "title" .= ("endpoint_board.endpoint_board.mint" :: Text)
                        , "hash" .= ("00" :: Text)
                        , "compiledCode" .= ("deadbeef" :: Text)
                        ]
                   ]
            ]

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

{- | A-013 finding 3 (INV-240-PARITY) fixture: the SAME payer output the
frozen-base worktree's proof-only 'koiosInterpreter' capture serves (as
Koios JSON, over a real Warp loopback server) -- same tx identity, address,
lovelace, and one native asset. 'parityExpectedUtxo' is the exact
'ChainAssetUtxo' the real, unmodified base interpreter decoded from it.
-}
parityCreate :: Indexer.TxIn -> Indexer.Address -> UtxoOp
parityCreate txIn addr = UtxoCreate txIn addr (parityOutput addr)

parityOutput :: Indexer.Address -> Indexer.TxOut
parityOutput (Indexer.Address bytes) =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash = fromJust (hashFromBytes bytes)
    txOut :: TxOut ConwayEra
    txOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            ( MaryValue
                (Coin 5_000_000)
                (MultiAsset (Map.singleton parityAssetPolicy (Map.singleton parityAssetName 1)))
            )

parityTxIn :: Indexer.TxIn
parityTxIn = Indexer.TxIn (BS.replicate 32 0x66) 0

parityAddr :: Indexer.Address
parityAddr = Indexer.Address (BS.replicate 28 0x77)

parityAssetPolicy :: PolicyID
parityAssetPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x88) of
                Just h -> h
                Nothing -> error "LocalWritePathSpec: invalid parity asset policy id width"

parityAssetName :: AssetName
parityAssetName = AssetName (SBS.toShort (BS.pack [0x11, 0x22]))

{- | The permanent falsifier's negative fixture: 'parityOutput' with a
DIFFERENT lovelace value (one side's acquired value perturbed) -- the
decoded 'ChainAssetUtxo' must no longer equal 'parityExpectedUtxo'.
-}
perturbedParityOutput :: Indexer.Address -> Indexer.TxOut
perturbedParityOutput (Indexer.Address bytes) =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash = fromJust (hashFromBytes bytes)
    txOut :: TxOut ConwayEra
    txOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            ( MaryValue
                (Coin 4_999_999)
                (MultiAsset (Map.singleton parityAssetPolicy (Map.singleton parityAssetName 1)))
            )

{- | The exact value produced by running the REAL, unmodified frozen-base
(@5bf84982f837c0f5bdd16fd244ae31b31224d147@) 'Cardano.KERI.ChainQuery.Koios.koiosInterpreter'
against a real Warp loopback server serving 'parityCreate''s fixture as
Koios JSON -- captured once via a proof-only executable in a detached
worktree (never committed; N-071/evidence/a013-finding3), reproduced here
verbatim as this property's frozen comparison target. A change to either
side's acquisition/decode logic that stops producing this exact value is
exactly the drift INV-240-PARITY exists to catch.
-}
parityExpectedUtxo :: ChainAssetUtxo
parityExpectedUtxo =
    ChainAssetUtxo
        { chainAssetTxId = T.replicate 64 "6"
        , chainAssetIndex = 0
        , chainAssetAddress = "addr_test1vpmhwamhwamhwamhwamhwamhwamhwamhwamhwamhwamhwacunv2nq"
        , chainAssetLovelace = 5_000_000
        , chainAssetList =
            [ ChainAsset
                { chainAssetPolicy = T.replicate 56 "8"
                , chainAssetName = "1122"
                , chainAssetQuantity = 1
                }
            ]
        , chainAssetInlineDatum = Nothing
        , chainAssetReferenceScript = Nothing
        }

{- | A-015\/N-073 continuation: the SAME reference-script output the
frozen-base worktree's proof-only 'koiosInterpreter' capture served over
its real two-endpoint chain (@\/reference_script_utxos@ then
@\/utxo_info@) as Koios JSON -- same script identity, tx identity,
address, and lovelace. 'parityExpectedReference' is the exact
'ChainReference' the real, unmodified base interpreter decoded from it
(matches @evidence\/a013-finding3\/reference-scripts-capture-output.log@'s
@Happy@ mode verbatim).
-}
parityReferenceScriptBytes :: SBS.ShortByteString
parityReferenceScriptBytes = SBS.toShort "s240-a015-refscript"

parityReferenceScript :: Script ConwayEra
parityReferenceScript = mkCageScript parityReferenceScriptBytes

parityReferenceHash :: Text
parityReferenceHash = scriptHashText (computeScriptHash parityReferenceScriptBytes)

parityReferenceTxIn :: Indexer.TxIn
parityReferenceTxIn = Indexer.TxIn (BS.replicate 32 0x55) 0

parityReferenceAddr :: Indexer.Address
parityReferenceAddr = Indexer.Address (BS.replicate 28 0x99)

parityExpectedReference :: ChainReference
parityExpectedReference =
    ChainReference
        { chainReferenceScriptHash = "2411a1b88f1c639d7eedead150ee18d3701ddbb5aef3691cd579c588"
        , chainReferenceOutput =
            ChainAssetUtxo
                { chainAssetTxId = T.replicate 64 "5"
                , chainAssetIndex = 0
                , chainAssetAddress = "addr_test1vzvenxvenxvenxvenxvenxvenxvenxvenxvenxvenxvenxgkl7z82"
                , chainAssetLovelace = 100_000_000
                , chainAssetList = []
                , chainAssetInlineDatum = Nothing
                , chainAssetReferenceScript =
                    Just
                        ChainReferenceScript
                            { chainReferenceScriptHashField = "2411a1b88f1c639d7eedead150ee18d3701ddbb5aef3691cd579c588"
                            , chainReferenceScriptType = "PlutusV3"
                            , chainReferenceScriptBytes = "733234302d613031352d726566736372697074"
                            }
                }
        }

{- | The permanent falsifier's negative fixture: DIFFERENT reference-script
bytes -- the family-specific field this continuation adds over
'payerUtxos'. The script hash is cryptographically bound to its bytes
(@hashScript@), so a real, honest bytes perturbation on the local side
necessarily changes the resolved hash too (the local path cannot
misreport hash independent of content the way an untrusted JSON payload
technically could) -- this falsifier therefore requests the PERTURBED
script's own (different) hash and asserts the result still fails to equal
the frozen value, catching either field, both real and both meaningful.
-}
perturbedParityReferenceScriptBytes :: SBS.ShortByteString
perturbedParityReferenceScriptBytes = SBS.toShort "s240-a015-refscript-PERTURBED"

perturbedParityReferenceScript :: Script ConwayEra
perturbedParityReferenceScript = mkCageScript perturbedParityReferenceScriptBytes

perturbedParityReferenceHash :: Text
perturbedParityReferenceHash = scriptHashText (computeScriptHash perturbedParityReferenceScriptBytes)

{- | A-015\/N-075 continuation (the dangerous one, INV-240-PARITY):
'currentCheckpoint' acquisition parity. The datum uses a __'Weighted'__
threshold, not 'Unweighted' -- the only shape exercising the 3-level
nested @Constr\/List\/Constr\/[I,I]@ structure where a JSON-detailed-Data
(provider) versus CBOR-native-Data (local) divergence would plausibly
hide (an 'Unweighted' threshold is a single flat @Constr 0 [I m]@ and
would pass even if the two 'Data' codecs disagreed about nested
@Constr@\/@List@ handling entirely).

Fixture reuses 'testQueryHandle''s own checkpoint identity
('unusedCheckpointPolicy', 'addrA') so 'capAtomicQuery' via
'queryHandleLocalScope' finds it without a bespoke scope. Carries exactly
ONE asset (its own checkpoint NFT) -- every real checkpoint output in
this system does; this is not merely convenient, it deliberately avoids a
provider-order-vs-local-key-sorted-order ordering question that does not
arise in genuine checkpoint data. If any later slice makes a checkpoint
output carry more than one asset, THAT comparison would need to answer
an ordering question this one does not (a note for whoever cuts that
slice, per A-016).
-}
parityCheckpointDatum :: CheckpointDatumV1
parityCheckpointDatum =
    CheckpointDatumV1
        { cdCesrAid = BS.replicate 32 0x71
        , cdCurKeys = [BS.replicate 32 0x11, BS.replicate 32 0x12]
        , cdCurThreshold = Weighted [[Weight 1 2, Weight 1 2]]
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }

{- | 'qb64Aid' of 'parityCheckpointDatum''s own @cdCesrAid@
(@BS.replicate 32 0x71@) -- both 'activeCheckpointAid' (requested,
echoed unchanged on both sides) and the datum's own recorded AID must
decode to this same identity for the acquisition to resolve at all.
-}
parityCheckpointAid :: Text
parityCheckpointAid = "EHFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFx"

parityCheckpointLocator :: CheckpointLocator
parityCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = "41414141414141414141414141414141414141414141414141414141"
        , checkpointLocatorAddress = addrText addrA
        }

parityCheckpointTxIn :: Indexer.TxIn
parityCheckpointTxIn = Indexer.TxIn (BS.replicate 32 0x44) 0

{- | One live checkpoint output at 'addrA' carrying @datum@'s inline
Plutus datum and exactly the one checkpoint NFT under
'unusedCheckpointPolicy', named for @datum@'s own AID.
-}
parityCheckpointOutput :: CheckpointDatumV1 -> Indexer.TxOut
parityCheckpointOutput datum =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (plutusData (V1 datum)))
  where
    Indexer.Address addrABytes = addrA
    keyHash = fromJust (hashFromBytes addrABytes)
    assetName = AssetName (SBS.toShort (deriveAidAssetName (cdCesrAid datum)))
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            ( MaryValue
                (Coin 5_000_000)
                (MultiAsset (Map.singleton unusedCheckpointPolicy (Map.singleton assetName 1)))
            )
    inlineDatum :: PLC.Data -> Datum ConwayEra
    inlineDatum plutus = Datum (dataToBinaryData (Data plutus))
    plutusData :: (ToData a) => a -> PLC.Data
    plutusData value =
        let BuiltinData plutus = toBuiltinData value
         in plutus

{- | The permanent falsifier's negative fixture: 'parityCheckpointDatum'
with ONE 'Weight' numerator changed to another legal, canonically-reduced
weight (@1\/2 -> 1\/3@, still satisfies @canonicalWeight@: den > 0,
0 <= num <= den, gcd num den == 1) -- a well-formed-but-different value
inside the exact nested path identified above, never a decode rejection.
-}
perturbedParityCheckpointDatum :: CheckpointDatumV1
perturbedParityCheckpointDatum =
    parityCheckpointDatum{cdCurThreshold = Weighted [[Weight 1 3, Weight 1 2]]}

{- | The exact value produced by running the REAL, unmodified frozen-base
(@5bf84982f837c0f5bdd16fd244ae31b31224d147@) 'Cardano.KERI.ChainQuery.Koios.koiosInterpreter'
against a real Warp loopback server serving 'parityCheckpointOutput'
'parityCheckpointDatum' as Koios @\/asset_utxos@ JSON (inline datum
rendered by the real, shared @plutusDataJson@ codec, never hand-written)
-- captured once via a proof-only executable in a detached worktree
(never committed; N-075\/evidence\/a013-finding3), reproduced here
verbatim as this property's frozen comparison target.

Two request-echo fields, not independently derived on either side:
'activeCheckpointAid' is the REQUESTED @aid@ text, and
'activeCheckpointAssetName' is the REQUESTED-derived asset-name hex
(@checkpointAssetName aid@ on the base side; independently RE-derived
from the stored output and cross-checked on the local side -- both equal
the same value for a well-formed fixture, but by a different route,
confirmed by direct source reading, not assumed).

One field is a genuine, confirmed asymmetry, not a coincidence:
'activeCheckpointAddress' is the PROVIDER's own reported row address on
the base side (checked equal to the locator, per
'resolveActiveCheckpointOne'), but on the LOCAL side it is
@renderIndexerAddress addr@ -- the QUERY SCOPE's own configured address,
never read off the stored @ledgerTxOut@ at all (confirmed by direct
source reading of 'decodeActiveCheckpoint'). The local side therefore
structurally relies on @scanAddressTx@ returning only rows at its
requested address; recorded under the advisory INV-240-SWEEP row per
A-016, not treated as a blocker.
-}
parityExpectedCheckpoint :: ActiveCheckpoint
parityExpectedCheckpoint =
    ActiveCheckpoint
        { activeCheckpointAid = "EHFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFx"
        , activeCheckpointAssetName = "50100c04b8b91223e65ecb9b4af5dae97ca65576fa7970dae91adc759711c230"
        , activeCheckpointTxId = T.replicate 64 "4"
        , activeCheckpointIndex = 0
        , activeCheckpointAddress = "addr_test15xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6zp6kz48"
        , activeCheckpointLovelace = 5_000_000
        , activeCheckpointAssets =
            [ ChainAsset
                { chainAssetPolicy = "41414141414141414141414141414141414141414141414141414141"
                , chainAssetName = "50100c04b8b91223e65ecb9b4af5dae97ca65576fa7970dae91adc759711c230"
                , chainAssetQuantity = 1
                }
            ]
        , activeCheckpointDatum = parityCheckpointDatum
        }

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

{- | Finding-2 full-output-identity assertions: the exact
'chainAssetAddress' text 'toChainAssetUtxo' reports for a
'referenceOutput'\/'payerOutput'-style fixture -- re-derives the SAME
ledger address ('referenceOutput''s own key-hash-credentialled 'Addr',
never a bare bech32 encoding of the indexer address bytes) and renders it
the identical way (@serialiseAddr@ then bech32), so this is the row's own
recorded address, not a coincidentally-matching guess.
-}
referenceOutputAddressText :: Indexer.Address -> Text
referenceOutputAddressText (Indexer.Address bytes) =
    addrText (Indexer.Address (serialiseAddr (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)))
  where
    keyHash = fromJust (hashFromBytes bytes)

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

{- | Finding-2 (DATA-INV-240-01) reference-edge coverage: a SECOND
distinct live reference, at a distinct hash and address, so a multi-hash
request has genuinely distinct rows to preserve caller-order over --
never a repeat of 'scriptA'\/'hashA'\/'addrA' under another name.
-}
scriptBBytes :: SBS.ShortByteString
scriptBBytes = SBS.toShort "s240-red-synthetic-script-b"

scriptB :: Script ConwayEra
scriptB = mkCageScript scriptBBytes

hashB :: Text
hashB = scriptHashText (computeScriptHash scriptBBytes)

{- | A THIRD hash that is never seeded by any fixture -- the absence\/
mismatch controls' requested hash.
-}
hashC :: Text
hashC = scriptHashText (computeScriptHash (SBS.toShort "s240-red-synthetic-script-c-never-seeded"))

{- | A stored row whose raw bytes are not a decodable ledger 'TxOut' at
all -- 'toChainAssetUtxo' (every reference-resolution row's own first
decode step) must fail on it, regardless of which hash was requested.
-}
malformedTxOut :: Indexer.TxOut
malformedTxOut = Indexer.TxOut "not a valid ledger TxOut CBOR encoding"

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte) 0

{- | The exact hex text 'chainAssetTxId' renders for 'sampleTxIn' 's own
identity byte, independent of any 'Cardano.KERI.Indexer.ChainQuery'
internals -- so the full-output-identity assertion is not circular.
-}
sampleTxIdHex :: Word8 -> Text
sampleTxIdHex byte = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 32 byte))

addrA :: Indexer.Address
addrA = Indexer.Address (BS.replicate 28 0xA1)

addrB :: Indexer.Address
addrB = Indexer.Address (BS.replicate 28 0xB2)

addrText :: Indexer.Address -> Text
addrText (Indexer.Address bytes) =
    Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes bytes)

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)
