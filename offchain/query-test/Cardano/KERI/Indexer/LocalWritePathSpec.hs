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
function -- 'runLocalQuery', 'localReferenceScriptsTx' (via the small
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
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (V1), CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted, Weighted), Weight (Weight))
import Cardano.KERI.ChainQuery.LedgerOutput (
    chainAssetUtxoToLedgerOutput,
    chainReferenceToLedgerOutput,
 )
import Cardano.KERI.ChainQuery.Program (
    ChainQuery,
    boardCatalog,
    boardCatalogWithOutputs,
    currentCheckpoint,
    liveCheckpoints,
    outputAt,
    payerUtxos,
    referenceScripts,
 )
import Cardano.KERI.ChainQuery.Settlement (SettlementObserver (..))
import Cardano.KERI.ChainQuery.Types (
    ActiveCheckpoint (..),
    BoardEntry (..),
    BoardLocator (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainReference (..),
    ChainReferenceScript (..),
    CheckpointLocator (..),
    OutputLocator (..),
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
    RegisterRuntime (..),
    RegisterSettings (..),
    runAdvanceWith,
    runBoardDeployWith,
    runBoardPostWith,
    runBoardRetireWith,
    runBoardUpdateWith,
    runCloseWith,
    runDeployWith,
    runRegisterWith,
 )
import Cardano.KERI.Deployment.EndpointBoard (
    EndpointRecord (..),
    parseEndpointRecord,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    frozenEndpointBoardAddress,
    frozenEndpointBoardPolicyId,
    readEndpointBoardManifest,
    writeEndpointBoardManifestAtomic,
 )
import Cardano.KERI.Deployment.KEL (
    RotationExport (..),
    parseRotationExport,
 )
import Cardano.KERI.Deployment.LiveRuntime (LiveContext (..))
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    Reference (..),
    ScriptEntry (..),
    SourceInfo (..),
    readManifest,
    writeManifestAtomic,
 )
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (artifactProgram),
    computeScriptHash,
    deriveBoardScript,
    loadBlueprint,
    mkCageScript,
    scriptHashText,
 )
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..))
import Cardano.KERI.Indexer.ChainQuery (
    LocalQueryScope (..),
    LocalSettings (..),
    localSettlementObserver,
    localTransactionSettled,
    queryHandleLocalScope,
    runLocalQuery,
    runLocalRegistrationSnapshot,
 )
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.Ledger.Address (Addr (..), decodeAddr, serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), binaryDataToData, dataToBinaryData)
import Cardano.Ledger.Api.Tx.Body (referenceScriptTxOutL)
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, datumTxOutL, mkBasicTxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, TxOut, eraProtVerLow, fromStrictMaybeL)
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (UpstreamConnected))
import Cardano.Node.Client.Provider (Provider (..))
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
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Foldable (for_)
import Data.Function ((&))
import Data.Functor (void)
import Data.Functor.Identity (Identity (..), runIdentity)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Traversable (for)
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction (..))
import Lens.Micro ((.~), (^.))
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldNotBe)
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (
    Gen,
    Property,
    arbitraryBoundedIntegral,
    arbitrarySizedIntegral,
    chooseInt,
    forAll,
    ioProperty,
    oneof,
    vectorOf,
 )

{- | Every local write-path capability T240-S1-03 owns, as one test-local
adapter. Both RED ('redCapabilities') and the eventual GREEN construction
share this exact shape; only field BODIES differ.
-}
data LocalCapabilities cf op = LocalCapabilities
    { capAtomicQuery ::
        forall a.
        LocalQueryScope cf op ->
        ChainQuery (Either ChainQueryError a) ->
        IO (Either ChainQueryError (QuerySnapshot a))
    {- ^ RQ-240-03\/04: one program, one store transaction, one watermark.

    A-262-02: the program argument now states its own failure channel,
    because the runner that accepted any @'ChainQuery' a@ is deleted. Every
    program this field is ever handed already had that shape -- each is
    built from a validating smart constructor -- so nothing was lifted and
    no property lost coverage; the change is that the type now says so.
    -}
    , capReferenceScripts ::
        LocalQueryScope cf op -> [Text] -> IO (Either ChainQueryError [ChainReference])
    -- ^ RQ-240-05\/DATA-INV-240-01: derived reference resolution.
    , capSettlementObserver :: LocalQueryScope cf op -> SettlementObserver IO
    -- ^ RQ-240-06: follower-backed asset settlement probe.
    , capTransactionSettled :: LocalQueryScope cf op -> TxId -> IO Bool
    -- ^ RQ-240-06: follower-backed exact-transaction settlement probe.
    , capOutputAt ::
        LocalQueryScope cf op -> Text -> Int -> IO (Either ChainQueryError ChainAssetUtxo)
    {- ^ \#262 RQ-262-01: one live output by exact @(txid,index)@ identity, as
    the provider-neutral spendable shape, resolved through the algebra and
    the local interpreter.

    The arguments are the locator's own two PIECES rather than a locator
    value, and the result is the EXISTING neutral output type, so this
    field's type is identical before and after implementation: RED closes it
    with a stand-in, GREEN eta-expands it onto the real operation, and no
    property body below changes between the two. That is the same
    type-stable adapter discipline N-008 fixed for \#240's four fields.
    -}
    , capBoardCatalogWithOutputs ::
        LocalQueryScope cf op ->
        Text ->
        Text ->
        IO (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])
    {- ^ \#262 RQ-262-02: every authenticated board entry paired with the
    complete neutral output from its own row, all-or-nothing. Arguments are
    the board locator's policy id and address pieces, for the same
    type-stability reason as 'capOutputAt'.
    -}
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

\#262 GREEN: 'capOutputAt' and 'capBoardCatalogWithOutputs' are now the real
operations, run through the real local interpreter -- their RED stand-ins
are gone and no property body changed, exactly as their type-stable shape
was designed to allow.

'capReferenceScripts' changed route in the same commit. \#240 bracketed the
raw @localReferenceScriptsTx@ reader directly, because write composition
called that reader directly; \#262 withdrew it, so this capability now goes
through the 'Cardano.KERI.ChainQuery.Program.referenceScripts' OPERATION,
which is the route production takes. Every reference-derivation property
above therefore now proves the algebra route rather than a reader that no
longer has a production caller -- and it proves it against the same
fixtures, so a regression in either the reader or its wiring is still
caught.

A-262-02: 'capAtomicQuery' moved to 'runLocalQuery' in the same commit that
deleted the generic local runner. That is not a mechanical substitution --
it is what keeps this adapter pointed at the route production uses, which is
the only reason the \#240 atomicity properties below still mean anything.
Its program argument now states its own failure channel, so
'snapshotValue' hands back the resolved value directly and each property
reads one 'Either' instead of two.
-}
redCapabilities :: LocalCapabilities cf op
redCapabilities =
    LocalCapabilities
        { capAtomicQuery = runLocalQuery
        , capReferenceScripts = \scope hashes ->
            fmap snapshotValue <$> runLocalQuery scope (referenceScripts hashes)
        , capSettlementObserver = localSettlementObserver
        , capTransactionSettled = localTransactionSettled
        , capOutputAt = \scope txIdHex index ->
            runWritePathQuery
                writePathRunner
                scope
                (outputAt (OutputLocator{outputLocatorTxId = txIdHex, outputLocatorIndex = index}))
        , capBoardCatalogWithOutputs = \scope policyId address ->
            runWritePathQuery
                writePathRunner
                scope
                ( boardCatalogWithOutputs
                    BoardLocator{boardLocatorPolicyId = policyId, boardLocatorAddress = address}
                )
        }

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
                    Right snapshot -> length (snapshotValue snapshot) `shouldBe` 1
                    Left err -> fail ("expected a resolved payer list, got " <> show err)

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
                        Right snapshot -> snapshotValue snapshot `shouldBe` [parityExpectedUtxo]
                        Left err -> expectationFailure ("expected the acquired payer utxo, got " <> show err)

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
                        Right snapshot ->
                            snapshotValue snapshot
                                `shouldNotBe` [parityExpectedUtxo]
                        Left err -> expectationFailure ("expected the perturbed payer utxo to still decode, got " <> show err)

            it
                "capReferenceScripts's decode of the shared reference fixture is byte-identical to the real koiosInterpreter's two-endpoint (/reference_script_utxos then /utxo_info) decode of the same fixture"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [referenceCreateAtWithoutDatum parityReferenceTxIn parityReferenceScript parityReferenceAddr]
                    result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [parityReferenceHash]
                    case result of
                        Right refs -> refs `shouldBe` [parityExpectedReference]
                        Left err -> expectationFailure ("expected the acquired reference, got " <> show err)

            it
                "preserves a datum-bearing reference output's COMPLETE value: the acquired inline datum equals the frozen base-provider result, in the schema both interpreters share (A-018 finding 1, DATA-INV-240-01 + INV-240-PARITY)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [ UtxoCreate
                            parityReferenceTxIn
                            parityReferenceAddr
                            ( referenceOutput
                                parityReferenceScript
                                (Just referenceFixtureDatum)
                                parityReferenceAddr
                            )
                        ]
                    result <- capReferenceScripts redCapabilities (queryHandleLocalScope (testQueryHandle runner)) [parityReferenceHash]
                    case result of
                        Right refs -> refs `shouldBe` [parityExpectedReferenceWithDatum]
                        Left err -> expectationFailure ("expected the acquired datum-bearing reference, got " <> show err)

            it
                "rejects a one-side acquired-value perturbation -- two outputs differing ONLY in a datum leaf nested two levels deep acquire to different values, and differ in nothing else (MANDATORY falsifier, A-018 finding 1)"
                $ do
                    let acquire datum =
                            withInMemoryIndexerRunner $ \handle runner -> do
                                applyAtSlot
                                    handle
                                    (Indexer.SlotNo 10)
                                    (blockHash 0x01)
                                    [ UtxoCreate
                                        parityReferenceTxIn
                                        parityReferenceAddr
                                        (referenceOutput parityReferenceScript (Just datum) parityReferenceAddr)
                                    ]
                                capReferenceScripts
                                    redCapabilities
                                    (queryHandleLocalScope (testQueryHandle runner))
                                    [parityReferenceHash]
                    honest <- acquire referenceFixtureDatum
                    perturbed <- acquire perturbedReferenceFixtureDatum
                    case (honest, perturbed) of
                        (Right [honestRef], Right [perturbedRef]) -> do
                            -- Both sides are ACQUIRED, so this control is genuinely
                            -- able to fail: a decoder that discards inline datums
                            -- returns the identical value for both stored outputs
                            -- and every assertion below goes red at once. Comparing
                            -- the perturbed acquisition against a pinned literal
                            -- could not do that -- it would differ either way.
                            perturbedRef `shouldNotBe` honestRef
                            chainAssetInlineDatum (chainReferenceOutput perturbedRef)
                                `shouldNotBe` chainAssetInlineDatum (chainReferenceOutput honestRef)
                            -- and the perturbation is confined to the datum
                            chainReferenceScriptHash perturbedRef
                                `shouldBe` chainReferenceScriptHash honestRef
                            chainAssetTxId (chainReferenceOutput perturbedRef)
                                `shouldBe` chainAssetTxId (chainReferenceOutput honestRef)
                            chainAssetAddress (chainReferenceOutput perturbedRef)
                                `shouldBe` chainAssetAddress (chainReferenceOutput honestRef)
                            chainAssetLovelace (chainReferenceOutput perturbedRef)
                                `shouldBe` chainAssetLovelace (chainReferenceOutput honestRef)
                            chainAssetReferenceScript (chainReferenceOutput perturbedRef)
                                `shouldBe` chainAssetReferenceScript (chainReferenceOutput honestRef)
                            -- and only the honest one matches the frozen value
                            honestRef `shouldBe` parityExpectedReferenceWithDatum
                        other ->
                            expectationFailure
                                ("expected exactly one resolved reference on each side, got " <> show other)

            prop
                "for ANY legal Plutus datum, the acquired reference output round-trips back to exactly the seeded datum through the real builder conversion (A-018 finding 1, the whole property class)"
                referenceDatumRoundTripsToTheSeededValue

            it
                "rejects a one-side acquired-value perturbation -- a changed local reference-script BYTES value no longer matches the frozen base-provider value (permanent falsifier, family-specific field)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [referenceCreateAtWithoutDatum parityReferenceTxIn perturbedParityReferenceScript parityReferenceAddr]
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
                            Just checkpoint -> checkpoint `shouldBe` parityExpectedCheckpoint
                            Nothing -> expectationFailure "expected the acquired checkpoint, got Nothing"
                        Left err -> expectationFailure ("expected the acquired checkpoint, got " <> show err)

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
                            Just checkpoint -> checkpoint `shouldNotBe` parityExpectedCheckpoint
                            Nothing -> expectationFailure "expected the perturbed checkpoint to still decode, got Nothing"
                        Left err -> expectationFailure ("expected the perturbed checkpoint to still decode, got " <> show err)

            it "fails closed the same way on absence: no live checkpoint output for this AID at all (currentCheckpoint, both acquisition paths report no error)" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) []
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    case result of
                        Right snapshot -> snapshotValue snapshot `shouldBe` Nothing
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
                "fails closed the same way on a schema-malformed datum: the frozen base answers Left (DecodingFailure \"checkpoint inline datum is not the frozen V1 schema\") for its single malformed row, so the local path must report a DecodingFailure too -- never the Right Nothing its list-comprehension filter used to produce (A-013 finding 3 / NOTE-014 rule 3; the superseded example asserted the divergence instead of rejecting it)"
                $ withInMemoryIndexerRunner
                $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        [UtxoCreate parityCheckpointTxIn addrA schemaMalformedCheckpointOutput]
                    result <-
                        capAtomicQuery
                            redCapabilities
                            (queryHandleLocalScope (testQueryHandle runner))
                            (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
                    case flattenAcquisition result of
                        Left (DecodingFailure _) -> pure ()
                        other ->
                            expectationFailure
                                ( "expected the local path to fail closed with a DecodingFailure, matching the frozen \
                                  \base's MalformedSchema mode, got "
                                    <> show other
                                )

            describe
                "every acquisition family fails closed on malformed storage, in both malformed \
                \classes -- the module-wide property, not two coincidental point fixes (A-017 \
                \ruling 4a/5)"
                $ for_ malformedFamilies
                $ \family ->
                    it (malformedFamilyName family) $
                        withInMemoryIndexerRunner $ \handle runner -> do
                            applyAtSlot
                                handle
                                (Indexer.SlotNo 10)
                                (blockHash 0x01)
                                (malformedFamilySeed family)
                            result <-
                                malformedFamilyAcquire
                                    family
                                    (queryHandleLocalScope (testQueryHandle runner))
                            case result of
                                Left (DecodingFailure _) -> pure ()
                                other ->
                                    expectationFailure
                                        ( "expected this acquisition family to fail closed with a named \
                                          \DecodingFailure on a malformed stored row, got "
                                            <> show other
                                        )

    exactOutputAcquisition

    boardOutputAcquisition

    writeCompositionRouteBoundary

    eagerRejectionOpensNoStoreTransaction

    localtierClosureClaims

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
        "A-017 ruling 4b / A-002 ruling 1: every production write-verb entrypoint \
        \completes its WHOLE local read set in exactly one store transaction, and \
        \reaching that point genuinely depends on the complete read set \
        \(T240-S1-14 audit findings 1 and 2, INV-240-SNAPSHOT). This proves \
        \acquisition COUNT and read-set completeness only; it says nothing \
        \about which reads route through the free algebra"
        $ do
            it
                "runAdvanceWith's submit path reaches its builder boundary having acquired exactly once"
                $ do
                    rotation <- entrypointRotationExport
                    kelPath <-
                        getDataFileName
                            "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
                    signatures <-
                        entrypointSignatureTokens 2 "kli-export-2-of-5-rotation.cesr"
                    -- the spent state this fixture seeds is derived from the
                    -- export, so the pinned AID bytes must still be the
                    -- export's own: a drifted fixture is caught here, not by a
                    -- confusing failure deep inside advanceEqualities.
                    cdCesrAid (rotationDatum rotation) `shouldBe` rotationFixtureAidBytes
                    withBoundaryProbe
                        (entrypointAdvanceSeed rotation Nothing)
                        (entrypointAdvance kelPath signatures)
                        expectCompletePhase

            it
                "runAdvanceWith does NOT reach its builder boundary when one manifest reference output is withheld"
                $ do
                    rotation <- entrypointRotationExport
                    kelPath <-
                        getDataFileName
                            "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
                    signatures <-
                        entrypointSignatureTokens 2 "kli-export-2-of-5-rotation.cesr"
                    withBoundaryProbe
                        (entrypointAdvanceSeed rotation (Just "checkpoint-register"))
                        (entrypointAdvance kelPath signatures)
                        expectIncompletePhase

            it
                "runCloseWith's submit path reaches its builder boundary having acquired exactly once"
                $ do
                    kelPath <-
                        getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
                    signatures <-
                        entrypointSignatureTokens 1 "kli-export-2-of-5-rotation.cesr"
                    withBoundaryProbe
                        (entrypointCloseSeed True)
                        (entrypointClose kelPath signatures)
                        expectCompletePhase

            it
                "runCloseWith does NOT reach its builder boundary when the live checkpoint output is withheld"
                $ do
                    kelPath <-
                        getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
                    signatures <-
                        entrypointSignatureTokens 1 "kli-export-2-of-5-rotation.cesr"
                    withBoundaryProbe
                        (entrypointCloseSeed False)
                        (entrypointClose kelPath signatures)
                        expectIncompletePhase

            it
                "runRegisterWith's preflight reaches its submission boundary having acquired exactly once"
                $ do
                    kelPath <-
                        getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
                    records <- entrypointWitnessRecords
                    withBoundaryProbe
                        (entrypointBoardCatalogSeedWithout Nothing records)
                        (entrypointRegister kelPath)
                        expectCompletePhase

            it
                "runRegisterWith does NOT reach its submission boundary when one declared witness's board record is withheld"
                $ do
                    kelPath <-
                        getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
                    records <- entrypointWitnessRecords
                    withBoundaryProbe
                        (entrypointBoardCatalogSeedWithout (Just 0) records)
                        (entrypointRegister kelPath)
                        expectIncompletePhase

            it
                "runDeployWith's publish phase reaches its builder boundary having acquired exactly once"
                $ do
                    blueprintPath <- entrypointBlueprintPath
                    withBoundaryProbe
                        entrypointFundingSeed
                        (entrypointDeploy blueprintPath)
                        expectCompletePhase

            it
                "runDeployWith does NOT reach its builder boundary when one funding row is withheld"
                $ do
                    blueprintPath <- entrypointBlueprintPath
                    withBoundaryProbe
                        (entrypointFundingSeedWithout (Just 1))
                        (entrypointDeploy blueprintPath)
                        expectIncompletePhase

            it
                "runBoardDeployWith's publish phase reaches its builder boundary having acquired exactly once"
                $ withBoundaryProbe
                    entrypointFundingSeed
                    entrypointBoardDeploy
                    expectCompletePhase

            it
                "runBoardDeployWith does NOT reach its builder boundary when one funding row is withheld"
                $ withBoundaryProbe
                    (entrypointFundingSeedWithout (Just 1))
                    entrypointBoardDeploy
                    expectIncompletePhase

            -- #263 (RQ-263-06, T263-S1-05/06/07). #240's three residual
            -- readings are gone. Their obstacle was real and is now removed:
            -- the frozen board policy had no script preimage in this
            -- repository, so no fixture could seed the live reference output
            -- these verbs resolve first. The recovered artifact IS that
            -- preimage, so each verb below now proves the SAME complete
            -- statement as the other five: it reaches its real builder
            -- boundary having performed exactly one local acquisition.
            --
            -- Every board reference row below carries the exact recovered
            -- deployed script, seeded through the production
            -- loader/derivation -- never a hand-built hash and never a
            -- weakened manifest, resolution, or expectation.
            it
                "runBoardPostWith's phase reaches its builder boundary having acquired exactly once"
                $ do
                    recordPath <-
                        getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    reference <- entrypointBoardReferenceSeed
                    withBoundaryProbe
                        (reference <> entrypointFundingSeed)
                        (entrypointBoardPost recordPath)
                        expectCompletePhase

            it
                "runBoardPostWith does NOT reach its builder boundary when the recovered reference row is withheld"
                $ do
                    recordPath <-
                        getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    withBoundaryProbe
                        entrypointFundingSeed
                        (entrypointBoardPost recordPath)
                        expectIncompletePhase

            it
                "runBoardPostWith does NOT reach its builder boundary when the recovered script sits at a transaction the manifest locator does not name"
                $ do
                    recordPath <-
                        getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    reference <- entrypointBoardReferenceSeedAtWrongLocator
                    withBoundaryProbe
                        (reference <> entrypointFundingSeed)
                        (entrypointBoardPost recordPath)
                        expectLocatorDisagreement

            it
                "runBoardUpdateWith's phase reaches its builder boundary having acquired exactly once"
                $ do
                    records <- entrypointWitnessRecords
                    recordPath <-
                        getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    reference <- entrypointBoardReferenceSeed
                    withBoundaryProbe
                        ( reference
                            <> entrypointBoardCatalogSeedWithout Nothing records
                            <> entrypointFundingSeed
                        )
                        (entrypointBoardUpdate recordPath)
                        expectCompletePhase

            it
                "runBoardUpdateWith does NOT reach its builder boundary when the catalog row it must replace is withheld"
                $ do
                    records <- entrypointWitnessRecords
                    recordPath <-
                        getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    reference <- entrypointBoardReferenceSeed
                    withBoundaryProbe
                        ( reference
                            <> entrypointBoardCatalogSeedWithout (Just 0) records
                            <> entrypointFundingSeed
                        )
                        (entrypointBoardUpdate recordPath)
                        expectIncompletePhase

            it
                "runBoardUpdateWith does NOT reach its builder boundary when the recovered script sits at a transaction the manifest locator does not name"
                $ do
                    records <- entrypointWitnessRecords
                    recordPath <-
                        getDataFileName "deployment-test/fixtures/witness-1-oobi.cesr"
                    reference <- entrypointBoardReferenceSeedAtWrongLocator
                    withBoundaryProbe
                        ( reference
                            <> entrypointBoardCatalogSeedWithout Nothing records
                            <> entrypointFundingSeed
                        )
                        (entrypointBoardUpdate recordPath)
                        expectLocatorDisagreement

            it
                "runBoardRetireWith's phase reaches its builder boundary having acquired exactly once"
                $ do
                    records <- entrypointWitnessRecords
                    witness <- entrypointFirstWitnessIdentifier records
                    reference <- entrypointBoardReferenceSeed
                    withBoundaryProbe
                        ( reference
                            <> entrypointBoardCatalogSeedWithout Nothing records
                            <> entrypointFundingSeed
                        )
                        (entrypointBoardRetire witness)
                        expectCompletePhase

            it
                "runBoardRetireWith does NOT reach its builder boundary when the catalog row it must retire is withheld"
                $ do
                    records <- entrypointWitnessRecords
                    witness <- entrypointFirstWitnessIdentifier records
                    reference <- entrypointBoardReferenceSeed
                    withBoundaryProbe
                        ( reference
                            <> entrypointBoardCatalogSeedWithout (Just 0) records
                            <> entrypointFundingSeed
                        )
                        (entrypointBoardRetire witness)
                        expectIncompletePhase

            it
                "runBoardRetireWith does NOT reach its builder boundary when the recovered script sits at a transaction the manifest locator does not name"
                $ do
                    records <- entrypointWitnessRecords
                    witness <- entrypointFirstWitnessIdentifier records
                    reference <- entrypointBoardReferenceSeedAtWrongLocator
                    withBoundaryProbe
                        ( reference
                            <> entrypointBoardCatalogSeedWithout Nothing records
                            <> entrypointFundingSeed
                        )
                        (entrypointBoardRetire witness)
                        expectLocatorDisagreement
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

{- | The first @count@ real 88-character indexed-CESR controller-signature
tokens from a KEL export fixture -- the exact technique
"Cardano.KERI.Deployment.KELSpec"'s own "decodes bare indexed CESR
controller-signature lines" example already proves against this same
fixture family (searching for the @-AAFA@ count-code marker), generalised
from one token to @count@ because they are laid out back to back at a fixed
88-byte stride and the frozen rotation export's own successor threshold is
__2-of-5__: one token satisfies neither eq6(a) nor eq6(b), so the advance
fixture could not reach its builder boundary with a single signature.

These are the export's OWN event signatures over its OWN @rot@ event bytes,
by its OWN revealed successor keys, so 'advancePredicate' verifies them for
real -- no private key, and no weakened threshold, is involved anywhere.
The search deliberately starts AFTER the @rot@ message begins: the export's
FIRST @-AAF@ group belongs to the __inception__ event and its signatures are
by the inception's key list, which is not @new.cur_keys@ -- taking those
(as the single-token form did, since it never asserted cryptographic
validity) yields @Eq6CurrentQuorumUnsatisfied@, observed before this
correction.
-}
entrypointSignatureTokens :: Int -> FilePath -> IO ByteString
entrypointSignatureTokens count fixtureName = do
    path <- getDataFileName ("deployment-test/fixtures/" <> fixtureName)
    bytes <- BS.readFile path
    let afterRotation = snd (BS.breakSubstring "\"t\":\"rot\"" bytes)
        afterCounter = BS.drop 4 (snd (BS.breakSubstring "-AAFA" afterRotation))
        token index = BS.take 88 (BS.drop (88 * index) afterCounter)
    pure (BS.concat [token index <> "\n" | index <- [0 .. count - 1]])

{- | A fixed, provider-neutral checkpoint identity for this property's
fixtures (mirrors "Cardano.KERI.CLI.Backend.EndpointSpec"'s own proven
checkpoint-fixture pattern).
-}

{- | The two manifest scripts advance\/close actually require:
'mkAdvancePackage'\/'mkAdvancePlan' resolve @checkpoint-register@ and
@observer-advance@ by name and additionally require the manifest's checkpoint
policy to EQUAL the former's script hash. Real script bytes, so the manifest
entry, the checkpoint policy, and the seeded reference output all derive from
ONE source rather than three independently-pinned constants that can drift
apart while every individual assertion still passes.
-}
entrypointCheckpointScriptBytes :: SBS.ShortByteString
entrypointCheckpointScriptBytes = SBS.toShort "s240-entrypoint-checkpoint-register"

entrypointObserverScriptBytes :: SBS.ShortByteString
entrypointObserverScriptBytes = SBS.toShort "s240-entrypoint-observer-advance"

{- | The two further manifest scripts registration's own plan builder
requires ('Cardano.KERI.Deployment.Registration.mkRegistrationPlan' resolves
@hash-proof@ and @observer-lifecycle@ by name, additionally deriving a
reward address from the latter's 28-byte hash). They live in the SAME
manifest as advance\/close's two, so 'manifestReferencesTx' -- which
resolves EVERY manifest entry and fails closed on any that is absent --
makes the advance\/close read set four reference outputs wide rather than
two, and one shared manifest cannot drift from the four seeded rows.
-}
entrypointProofScriptBytes :: SBS.ShortByteString
entrypointProofScriptBytes = SBS.toShort "s240-entrypoint-hash-proof"

entrypointLifecycleScriptBytes :: SBS.ShortByteString
entrypointLifecycleScriptBytes = SBS.toShort "s240-entrypoint-observer-lifecycle"

entrypointCheckpointPolicy :: PolicyID
entrypointCheckpointPolicy = PolicyID (computeScriptHash entrypointCheckpointScriptBytes)

{- | Both manifest script entries, each pointing at the reference output the
fixture seeds for it. 'manifestReferencesTx' resolves every entry's hash
inside the acquisition and fails closed on any that is absent, so these two
entries are exactly what makes the advance\/close read set complete rather
than trivially satisfiable.
-}
entrypointManifestScripts :: [ScriptEntry]
entrypointManifestScripts =
    [ ScriptEntry
        { scriptName = "checkpoint-register"
        , scriptBlueprintTitle = "checkpoint.checkpoint.spend"
        , scriptRole = "spend"
        , scriptHash = scriptHashText (computeScriptHash entrypointCheckpointScriptBytes)
        , scriptProgramBytes = SBS.length entrypointCheckpointScriptBytes
        , scriptReference = Reference{referenceTxId = sampleTxIdHex 0x60, referenceIndex = 0}
        }
    , ScriptEntry
        { scriptName = "observer-advance"
        , scriptBlueprintTitle = "observer_advance.observer_advance.publish"
        , scriptRole = "publish"
        , scriptHash = scriptHashText (computeScriptHash entrypointObserverScriptBytes)
        , scriptProgramBytes = SBS.length entrypointObserverScriptBytes
        , scriptReference = Reference{referenceTxId = sampleTxIdHex 0x61, referenceIndex = 0}
        }
    , ScriptEntry
        { scriptName = "hash-proof"
        , scriptBlueprintTitle = "hash_proof.hash_proof.mint"
        , scriptRole = "mint"
        , scriptHash = scriptHashText (computeScriptHash entrypointProofScriptBytes)
        , scriptProgramBytes = SBS.length entrypointProofScriptBytes
        , scriptReference = Reference{referenceTxId = sampleTxIdHex 0x64, referenceIndex = 0}
        }
    , ScriptEntry
        { scriptName = "observer-lifecycle"
        , scriptBlueprintTitle = "observer_lifecycle.observer_lifecycle.publish"
        , scriptRole = "publish"
        , scriptHash = scriptHashText (computeScriptHash entrypointLifecycleScriptBytes)
        , scriptProgramBytes = SBS.length entrypointLifecycleScriptBytes
        , scriptReference = Reference{referenceTxId = sampleTxIdHex 0x65, referenceIndex = 0}
        }
    ]

{- | The seeded reference outputs answering 'entrypointManifestScripts', one
per entry. @withheld@ names the ONE entry a negative control removes;
'Nothing' seeds the complete set.
-}
entrypointReferenceSeedWithout :: Maybe Text -> [UtxoOp]
entrypointReferenceSeedWithout withheld =
    [ referenceCreateAt txIn (mkCageScript bytes) addr
    | (name, txIn, bytes, addr) <-
        [ ("checkpoint-register", sampleTxIn 0x60, entrypointCheckpointScriptBytes, addrA)
        , ("observer-advance", sampleTxIn 0x61, entrypointObserverScriptBytes, addrB)
        , ("hash-proof", sampleTxIn 0x64, entrypointProofScriptBytes, addrA)
        , ("observer-lifecycle", sampleTxIn 0x65, entrypointLifecycleScriptBytes, addrB)
        ]
    , Just name /= withheld
    ]

-- | The complete seeded reference outputs answering 'entrypointManifestScripts'.
entrypointReferenceSeed :: [UtxoOp]
entrypointReferenceSeed = entrypointReferenceSeedWithout Nothing

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
    entrypointCheckpointOutputFor
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

{- | One live checkpoint output at 'entrypointCheckpointAddress' carrying an
arbitrary V1 @datum@ inline, with the singleton checkpoint token that
datum's own AID derives -- so the seeded row, the asset
'Cardano.KERI.Deployment.Advance.mkAdvancePackage' re-derives as
@scAidAssetName@, and the datum @advanceEqualities@ reads as the SPENT
state all come from one value and cannot drift apart.
-}
entrypointCheckpointOutputFor :: CheckpointDatumV1 -> Indexer.TxOut
entrypointCheckpointOutputFor datum =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatumOf (plutusData (V1 datum)))
  where
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            entrypointCheckpointLedgerAddress
            ( MaryValue
                (Coin 5_000_000)
                ( MultiAsset $
                    Map.singleton
                        entrypointCheckpointPolicy
                        ( Map.singleton
                            (AssetName . SBS.toShort . deriveAidAssetName $ cdCesrAid datum)
                            1
                        )
                )
            )
    plutusData :: (ToData a) => a -> PLC.Data
    plutusData value =
        let BuiltinData plutus = toBuiltinData value
         in plutus

-- | One inline datum, shared by every fixture below that seeds one.
inlineDatumOf :: PLC.Data -> Datum ConwayEra
inlineDatumOf plutus = Datum (dataToBinaryData (Data plutus))

{- | The one manifest every non-board entrypoint fixture below shares: the
frozen checkpoint identity above plus all four 'entrypointManifestScripts'
entries, each answered by its own seeded reference output. Because
'manifestReferencesTx' resolves EVERY entry and fails closed on any that is
absent, this manifest is what makes advance\/close's read set genuinely
four references wide, and registration's plan builder ('hash-proof',
'observer-lifecycle') buildable, from one source.
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
        , manifestScripts = entrypointManifestScripts
        }

-- ---------------------------------------------------------------------------
-- A-017 ruling 4b / A-002 ruling 1: the eight-entrypoint SNAPSHOT harness.
--
-- The six superseded examples asserted only `count == 1` around a
-- `try ... :: IO (Either SomeException ())`. Every one of their fixtures used
-- placeholder inputs ("unused-payer", "unused-funding-address", a manifest
-- with no scripts, a board reference locator resolving to nothing), so the
-- entrypoint threw BEFORE its read set completed and the example still
-- passed. Two things follow, and this harness exists to make both impossible:
--
--   * a passing example must be distinguishable from an early failure. The
--     builder boundary is observed explicitly, and reaching it entails that
--     every read in the phase resolved -- each acquisition step fails closed
--     (`fail . show`) before the boundary, so the boundary is unreachable on
--     an incomplete read set.
--   * the boundary signal must be shown able to FAIL. Every verb therefore
--     carries a negative control that withholds exactly one required row and
--     requires the boundary NOT to be reached. Without it, "boundary reached"
--     is a green nobody has ever seen go red.

{- | Marks that a production entrypoint reached the point where acquired
values are handed to the transaction builder, and carries the acquisition
count observed AT that moment -- so "one acquisition for the whole phase"
and "no acquisition after the boundary" are two separate, separately
falsifiable readings rather than one number read at the end.
-}
data BoundaryProbe = BoundaryProbe
    { probeAcquisitions :: IORef Int
    , probeAtBoundary :: IORef (Maybe Int)
    }

newBoundaryProbe :: IO BoundaryProbe
newBoundaryProbe = BoundaryProbe <$> newIORef 0 <*> newIORef Nothing

markBoundary :: BoundaryProbe -> IO ()
markBoundary probe =
    readIORef (probeAcquisitions probe)
        >>= writeIORef (probeAtBoundary probe) . Just

{- | Thrown the instant a production entrypoint reaches its builder
boundary. The live bracket is NOT universally that boundary: for the two
publish verbs it opens BEFORE the acquisition, so using it as one would
prove nothing -- 'publishBoundaryLiveOpener' exists for exactly that case.
-}
data ReachedBuilderBoundary = ReachedBuilderBoundary
    deriving stock (Show, Eq)

instance Exception ReachedBuilderBoundary

{- | The real 'LocalOpener' every entrypoint under test receives. Unlike
'entrypointCountingLocalOpener' it honours the 'LocalSettings' the
production entrypoint computed -- the board verbs' acquisition calls
'localBoardCatalogWithOutputs', which fails closed on a 'Nothing' board
identity, so hard-coding 'Nothing' would stop those phases inside the
acquisition and re-create the degeneracy this harness removes.
-}
boundaryLocalOpener :: BoundaryProbe -> RunTransaction IO cf Cols op -> LocalOpener
boundaryLocalOpener probe runner settings action =
    action
        LocalQueryScope
            { localScopeRunner = countingRunner (probeAcquisitions probe) runner
            , localScopeCheckpointIdentity = localCheckpointIdentity settings
            , localScopeBoardIdentity = localBoardIdentity settings
            }

{- | The builder boundary for the six verbs that acquire BEFORE opening the
live bracket (advance, close, register, board post\/update\/retire): the
bracket itself. Records the count first, then throws, so the acquisition
total is captured at the boundary rather than after unwinding.
-}
boundaryLiveOpener :: BoundaryProbe -> LiveOpener
boundaryLiveOpener probe _config _observeTransaction _action = do
    markBoundary probe
    throwIO ReachedBuilderBoundary

{- | The builder boundary for the two publish verbs (@runDeployWith@,
@runBoardDeployWith@), whose local acquisition runs INSIDE the live
bracket's own callback ('publishArtifactsLive' needs the live funding
address, which only 'LiveConfig' supplies). Their boundary is the first
'TransactionRuntime' operation 'publishScripts' performs, so the bracket is
entered for real and the stand-in runtime marks the boundary.
-}
publishBoundaryLiveOpener :: BoundaryProbe -> Addr -> LiveOpener
publishBoundaryLiveOpener probe fundingAddress config _observeTransaction action =
    action
        LiveContext
            { liveTransactionRuntime = boundaryRuntime probe
            , liveProvider = boundaryProvider probe
            , liveFundingAddress = fundingAddress
            , liveConfig = config
            }

{- | A stand-in N2C 'Provider' whose every query marks the builder boundary
and stops. 'LiveContext''s provider field is STRICT, so an @error@ thunk
there is forced the moment the context is constructed -- before the local
acquisition this property observes has even run, which would make the
publish verbs unprovable for a reason that has nothing to do with them.
Every field is a function or an action, so the record itself is a perfectly
ordinary value; only USING it stops, which is the honest reading: the
publish path must reach its builder before it ever needs a node.
-}
boundaryProvider :: BoundaryProbe -> Provider IO
boundaryProvider probe =
    Provider
        { withAcquired = const stop
        , queryUTxOs = const stop
        , queryUTxOByTxIn = const stop
        , queryProtocolParams = stop
        , queryLedgerSnapshot = stop
        , queryStakeRewards = const stop
        , queryRewardAccounts = const stop
        , queryVoteDelegatees = const stop
        , queryTreasury = stop
        , queryGovernanceState = stop
        , evaluateTx = const stop
        , posixMsToSlot = const stop
        , posixMsCeilSlot = const stop
        , queryUpperBoundSlot = const stop
        }
  where
    stop :: IO a
    stop = markBoundary probe >> throwIO ReachedBuilderBoundary

{- | A stand-in 'TransactionRuntime' whose every operation marks the builder
boundary and stops. Any of the five is a genuine "the builder was handed the
acquired values" signal; which one fires first is an implementation detail of
'publishScripts' this property deliberately does not pin.
-}
boundaryRuntime :: BoundaryProbe -> TransactionRuntime IO
boundaryRuntime probe =
    TransactionRuntime
        { trQueryProtocolParams = stop
        , trEvaluate = const stop
        , trSign = const stop
        , trSubmit = const stop
        , trObserve = const stop
        }
  where
    stop :: IO a
    stop = markBoundary probe >> throwIO ReachedBuilderBoundary

{- | The positive reading, shared by all eight entrypoints: the phase reached
its builder boundary, having performed EXACTLY one local store transaction,
and performed none afterwards.

@reachedBoundary@ being 'Just' is the non-degeneracy proof: every acquisition
step in every one of these phases fails closed before the boundary, so a
placeholder-shaped fixture -- the exact defect being repaired -- cannot
produce it.
-}
expectCompletePhase :: BoundaryProbe -> Either SomeException () -> IO ()
expectCompletePhase probe outcome = do
    atBoundary <- readIORef (probeAtBoundary probe)
    total <- readIORef (probeAcquisitions probe)
    case atBoundary of
        Nothing ->
            expectationFailure
                ( "the entrypoint never reached its builder boundary, so its read set did not \
                  \complete; outcome was "
                    <> show outcome
                )
        Just observed -> do
            -- exactly one local transaction for the whole build phase
            observed `shouldBe` 1
            -- and no acquisition after the boundary
            total `shouldBe` observed

{- | The negative control, shared by all eight: with one required row
withheld, the phase must NOT reach its builder boundary. This is what makes
'expectCompletePhase' a check that has been seen to fail, rather than a
green that happens to be true.
-}
expectIncompletePhase :: BoundaryProbe -> Either SomeException () -> IO ()
expectIncompletePhase probe outcome = do
    atBoundary <- readIORef (probeAtBoundary probe)
    case atBoundary of
        Nothing -> pure ()
        Just observed ->
            expectationFailure
                ( "the entrypoint reached its builder boundary at acquisition "
                    <> show observed
                    <> " despite a required row being withheld, so reaching the boundary does not \
                       \depend on the complete read set; outcome was "
                    <> show outcome
                )

{- | #263 (CORRECTION-001, REL-263-LOCATOR-AGREEMENT): the wrong-locator
control shared by all three board write verbs.

'boardReferenceOutputProgram' does two things, and only one of them is
observed by the positive readings above: it resolves the frozen board policy
to a live reference output, AND it requires that output's own @TxIn@ to equal
the transaction id and index the manifest's 'endpointBoardReference' records.
The second half is defence in depth against a stale or substituted manifest,
and nothing else in this suite would notice its removal -- a resolvable
reference row would satisfy every other assertion here.

So this control seeds the EXACT recovered deployed script -- the same bytes,
through the same production derivation, as the positive readings -- at a
transaction the manifest does not name, and requires three things:

  * the builder boundary was NOT reached;
  * exactly ONE acquisition ran, so the phase genuinely opened its local scope
    and got as far as resolving the reference (a manifest rejected at count 0
    would otherwise report the same absent boundary and prove nothing);
  * the failure names the locator disagreement specifically, not merely "some
    failure" -- an unresolvable hash produces a DIFFERENT message and would not
    satisfy this.

Delete the tx-id\/index equality from 'boardReferenceOutputProgram' and all
three examples go red: the row resolves, the phase reaches its boundary, and
both the boundary and the message assertions fail.
-}
expectLocatorDisagreement ::
    BoundaryProbe -> Either SomeException () -> IO ()
expectLocatorDisagreement probe outcome = do
    atBoundary <- readIORef (probeAtBoundary probe)
    total <- readIORef (probeAcquisitions probe)
    atBoundary `shouldBe` Nothing
    total `shouldBe` 1
    case outcome of
        Left err
            | locatorFailure `T.isInfixOf` T.pack (show err) -> pure ()
        _ ->
            expectationFailure
                ( "expected the phase to fail closed inside \
                  \boardReferenceOutputProgram naming the manifest locator \
                  \disagreement, got "
                    <> show outcome
                )
  where
    locatorFailure =
        "board reference output does not match the manifest's recorded locator"

{- | A board manifest carrying the SAME 'frozenEndpointBoardPolicyId'\/
'frozenEndpointBoardAddress' every real manifest must (every board plan
builder checks the manifest's own board identity against these frozen
constants BEFORE the acquisition step is ever reached -- an arbitrary
identity fails closed there, at count 0, before proving anything), and a
well-formed reference locator.

\#263: that locator is now ANSWERED. 'entrypointBoardReferenceSeed' seeds the
recovered deployed script at exactly @sampleTxIn 0x63@ index 0, so
'boardReferenceOutputProgram' -- every board verb's first acquisition step --
both resolves the frozen policy and agrees with this recorded locator. The
manifest itself is unchanged and is still accepted only because
@consumerErrors@ validates its identity and its locator's shape.
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
                , endpointBoardReference =
                    Reference{referenceTxId = sampleTxIdHex 0x63, referenceIndex = 0}
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
entrypointFundingLedgerAddress :: Addr
entrypointFundingLedgerAddress =
    Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull
  where
    keyHash = fromJust (hashFromBytes (BS.replicate 28 0x53))

entrypointFundingAddressText :: Text
entrypointFundingAddressText =
    Bech32.encodeLenient
        addrTestHrp
        (Bech32.dataPartFromBytes (serialiseAddr entrypointFundingLedgerAddress))

{- | The SAME address as stored-row bytes. 'fundingOutputsTx' re-derives each
returned row's address from its own ledger @TxOut@ and rejects any that does
not equal the requested text, so the seeded row, the requested selector, and
the manifest's funding address must all be this one value.
-}
entrypointFundingIndexerAddress :: Indexer.Address
entrypointFundingIndexerAddress =
    Indexer.Address (serialiseAddr entrypointFundingLedgerAddress)

{- | A live output at an EXACT ledger address. 'payerOutput' cannot serve
here: it derives a key-hash address from 28 raw indexer bytes, while a real
funding row is stored under a 29-byte serialised address.
-}
outputAtLedgerAddress :: Addr -> Integer -> Indexer.TxOut
outputAtLedgerAddress addr lovelace =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    txOut :: TxOut ConwayEra
    txOut = mkBasicTxOut addr (MaryValue (Coin lovelace) (MultiAsset mempty))

{- | The funding rows every submitting verb's acquisition must resolve.

TWO rows, not one, and both are genuinely required: the publish path's
@selectFundingPair@ reserves a SEPARATE collateral input, so a single row
fails closed with @PublishFundingSelectionFailed MissingCollateral@ before
any transaction-runtime operation -- which is exactly what makes
'entrypointFundingSeedWithout' a one-row negative control rather than an
all-or-nothing one.
-}
entrypointFundingSeedWithout :: Maybe Int -> [UtxoOp]
entrypointFundingSeedWithout withheld =
    [ UtxoCreate
        (sampleTxIn marker)
        entrypointFundingIndexerAddress
        (outputAtLedgerAddress entrypointFundingLedgerAddress 100_000_000)
    | (index, marker) <- zip [0 :: Int ..] [0x62, 0x66]
    , Just index /= withheld
    ]

-- | The complete funding read set.
entrypointFundingSeed :: [UtxoOp]
entrypointFundingSeed = entrypointFundingSeedWithout Nothing

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
-- The complete read sets: the real board artifact, the authenticated board
-- catalog, and the KEL-derived spent checkpoint state.
--
-- Every value below exists so that ONE production entrypoint's acquisition
-- can run to completion against real fixtures. Nothing here weakens a
-- production check: the board script is the real compiled artifact, the
-- catalog rows carry genuinely signed witness endpoint events, and the
-- advance fixture's spent state is derived from the frozen rotation export
-- itself rather than pinned beside it.

{- | The blueprint binding the flake sets for BOTH the permanent
@local-write-path-check@ runner and the development shell (A-002 ruling 2),
so the gate command and the focused
@nix develop -c cabal run local-write-path-tests@ command observe the same
value. Fails closed: an unset or empty binding would make the deploy
fixtures fail for a harness reason rather than a candidate reason, which is
exactly the degeneracy this repair exists to remove.
-}
entrypointBlueprintPath :: IO FilePath
entrypointBlueprintPath = do
    value <- lookupEnv "KERI_CHECKPOINT_BLUEPRINT"
    case value of
        Just path | not (null path) -> pure path
        _ ->
            fail
                "KERI_CHECKPOINT_BLUEPRINT is unset or empty; the complete \
                \deploy/board entrypoint fixtures cannot run"

{- | #263 (DAT-263-BOARD-BINDING): the recovered deployed board artifact's own
path, from its OWN required binding. Never @KERI_CHECKPOINT_BLUEPRINT@: that
blueprint is the current source build, whose endpoint-board validator hashes
to @398a358a…@ rather than the deployed @54494f8a…@ and could not seed these
reference rows. Fails closed on an unset or empty binding rather than falling
back to it -- the substitution this ticket exists to make impossible.
-}
entrypointBoardBlueprintPath :: IO FilePath
entrypointBoardBlueprintPath = do
    value <- lookupEnv "KERI_BOARD_BLUEPRINT"
    case value of
        Just path | not (null path) -> pure path
        _ ->
            fail
                "KERI_BOARD_BLUEPRINT is unset or empty; the board \
                \post/update/retire read-set proofs cannot run"

{- | #263: the exact deployed board program as a ledger 'Script', obtained
through the REAL production loader and derivation
('Cardano.KERI.Deployment.Script.loadBlueprint' then 'deriveBoardScript'),
never a hand-assembled fixture. Its hash is therefore whatever those functions
produce from the checked-in bytes; if that is not
'frozenEndpointBoardPolicyId', the seeded row does not answer the verbs'
reference lookup and every positive reading below fails closed rather than
quietly passing.
-}
entrypointRecoveredBoardScript :: IO (Script ConwayEra)
entrypointRecoveredBoardScript = do
    path <- entrypointBoardBlueprintPath
    blueprint <- loadBlueprint path >>= either fail pure
    artifact <- either fail pure (deriveBoardScript blueprint)
    pure (mkCageScript (artifactProgram artifact))

{- | The recovered board reference output, seeded at an arbitrary marker.

Its address is deliberately an ordinary key-hash address rather than the board
address: 'localReferenceScriptsTx' scans every live row with no address
scoping, and keeping the reference row off both the funding address and the
board catalog address is what stops it from perturbing the OTHER two families
in these verbs' read sets.
-}
entrypointBoardReferenceSeedAt :: Word8 -> IO [UtxoOp]
entrypointBoardReferenceSeedAt marker = do
    script <- entrypointRecoveredBoardScript
    pure [referenceCreateAt (sampleTxIn marker) script addrA]

{- | The reference row at exactly the locator 'entrypointBoardManifest'
records (@sampleTxIn 0x63@, index 0), so 'boardReferenceOutputProgram' 's
locator check agrees.
-}
entrypointBoardReferenceSeed :: IO [UtxoOp]
entrypointBoardReferenceSeed = entrypointBoardReferenceSeedAt 0x63

{- | CORRECTION-001: the SAME recovered script at a transaction id the
manifest's locator does not name. Marker @0x6A@ collides with no other seeded
row in this suite. Paired with 'expectLocatorDisagreement'.
-}
entrypointBoardReferenceSeedAtWrongLocator :: IO [UtxoOp]
entrypointBoardReferenceSeedAtWrongLocator = entrypointBoardReferenceSeedAt 0x6A

-- | 'frozenEndpointBoardPolicyId' as its raw 28-byte script hash.
entrypointBoardScriptHash :: ScriptHash
entrypointBoardScriptHash =
    case convertFromBase Base16 (TE.encodeUtf8 frozenEndpointBoardPolicyId) of
        Right bytes
            | Just hash <- hashFromBytes bytes -> ScriptHash hash
        _ ->
            error
                "LocalWritePathSpec: frozenEndpointBoardPolicyId is not a 28-byte hash"

entrypointBoardPolicy :: PolicyID
entrypointBoardPolicy = PolicyID entrypointBoardScriptHash

{- | The frozen board address as the indexer stores it, decoded from
'frozenEndpointBoardAddress' by the SAME Bech32 route
'Cardano.KERI.Indexer.Config.decodeAddress' uses. Deriving the seeded row's
address bytes this way (rather than rebuilding an 'Addr' from the policy
hash and re-serialising it) is what guarantees the seeded row lies at
exactly the address the board verbs' own scope scans.
-}
entrypointBoardAddressBytes :: ByteString
entrypointBoardAddressBytes =
    case Bech32.decodeLenient frozenEndpointBoardAddress of
        Right (_hrp, dataPart)
            | Just bytes <- Bech32.dataPartToBytes dataPart -> bytes
        _ ->
            error "LocalWritePathSpec: frozenEndpointBoardAddress is not Bech32"

entrypointBoardIndexerAddress :: Indexer.Address
entrypointBoardIndexerAddress = Indexer.Address entrypointBoardAddressBytes

entrypointBoardLedgerAddress :: Addr
entrypointBoardLedgerAddress =
    case decodeAddr entrypointBoardAddressBytes :: Maybe Addr of
        Just addr -> addr
        Nothing ->
            error
                "LocalWritePathSpec: frozenEndpointBoardAddress is not a ledger address"

{- | The 28-byte payment key hash 'entrypointFundingLedgerAddress' carries.
'BoardTx.mkBoardUpdatePlan'\/'mkBoardRetirePlan' both require the funding
address's payment key to EQUAL the selected catalog row's own owner field,
so the seeded datum's owner and the funding address must be one value, not
two that happen to agree.
-}
entrypointOwnerKeyHash :: ByteString
entrypointOwnerKeyHash = BS.replicate 28 0x53

{- | One AUTHENTICATED board catalog row for @record@: the frozen board
marker asset (policy 'frozenEndpointBoardPolicyId', asset name the witness's
own 32-byte key, quantity 1) at the frozen board address, with the inline
datum shape 'Cardano.KERI.Deployment.EndpointBoardTransaction.endpointDatum'
itself writes. 'resolveBoardCatalog' re-verifies the datum's signature over
its own event bytes and re-derives the SAID, so a fabricated row cannot
enter the catalog -- the witness OOBI fixtures supply real signed events.
-}
entrypointBoardCatalogSeed :: Word8 -> EndpointRecord -> UtxoOp
entrypointBoardCatalogSeed marker record =
    UtxoCreate
        (sampleTxIn marker)
        entrypointBoardIndexerAddress
        (Indexer.TxOut (serialize' (eraProtVerLow @ConwayEra) txOut))
  where
    txOut :: TxOut ConwayEra
    txOut = baseTxOut & datumTxOutL .~ inlineDatumOf datum
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            entrypointBoardLedgerAddress
            ( MaryValue
                (Coin 2_000_000)
                ( MultiAsset $
                    Map.singleton
                        entrypointBoardPolicy
                        ( Map.singleton
                            (AssetName . SBS.toShort $ endpointWitnessKey record)
                            1
                        )
                )
            )
    datum =
        PLC.Constr
            0
            [ PLC.B (endpointWitnessKey record)
            , PLC.B (endpointEventBytes record)
            , PLC.B (endpointSignature record)
            , PLC.B entrypointOwnerKeyHash
            ]

{- | The three frozen witness OOBI fixtures, parsed by the real
'parseEndpointRecord' ("Cardano.KERI.Deployment.EndpointBoardSpec" already
proves they parse). Their witness keys are exactly the three @b@ entries the
frozen inception export declares, so a catalog seeded from all three is what
lets registration's watchability preflight pass WITHOUT
@--allow-unlisted-witnesses@ -- and withholding one is what makes it fail.
-}
entrypointWitnessRecords :: IO [EndpointRecord]
entrypointWitnessRecords =
    traverse
        readRecord
        [ "witness-1-oobi.cesr"
        , "witness-2-oobi.cesr"
        , "witness-3-oobi.cesr"
        ]
  where
    readRecord name = do
        path <- getDataFileName ("deployment-test/fixtures/" <> name)
        bytes <- BS.readFile path
        either fail pure (parseEndpointRecord bytes)

{- | The qb64 witness identifier the FIRST seeded catalog row carries, taken
from that row's own parsed record rather than pinned beside it:
'validateEndpointEvent' requires the endpoint event's @eid@ to equal the
marker asset's witness key, so this is by construction the identifier
@BoardTx.selectBoardEntry@ must match when board retire is asked to retire
that row.
-}
entrypointFirstWitnessIdentifier :: [EndpointRecord] -> IO Text
entrypointFirstWitnessIdentifier records =
    case records of
        record : _ -> pure (endpointAid record)
        [] -> fail "LocalWritePathSpec: no witness OOBI fixture was parsed"

{- | The complete authenticated catalog, or the same catalog minus exactly
one row -- the single knob every board\/registration negative control turns.
-}
entrypointBoardCatalogSeedWithout :: Maybe Int -> [EndpointRecord] -> [UtxoOp]
entrypointBoardCatalogSeedWithout withheld records =
    [ entrypointBoardCatalogSeed (0x70 + fromIntegral index) record
    | (index, record) <- zip [0 :: Int ..] records
    , Just index /= withheld
    ]

{- | The SPENT checkpoint state that makes the frozen rotation export's own
successor datum a valid advance -- derived from that export, never pinned
beside it, so the fixture cannot drift away from the bytes
'advancePredicate' actually reads:

  * eq2: the spent AID is the successor's own AID, and
    'entrypointCheckpointOutputFor' derives the marker asset from it, so
    @scAidAssetName@ matches by construction;
  * eq5: one sequence step back, and one native sequence step back;
  * eq6(a): the two attached signatures are the export's own, over its own
    event bytes, by two of its own revealed successor keys;
  * eq6(b): the committed @next_keys@ ARE
    @map (blake3Hash . qb64Verkey)@ of the successor's current keys, in the
    same order, under the successor's own threshold -- so exactly the
    positions that satisfy eq6(a) satisfy the pre-rotation gate too;
  * eq7: @wit_cut@\/@wit_add@ are both empty in this export, so the derived
    incoming set is the spent witness set, which is the successor's.
-}
entrypointAdvanceSpentDatum :: RotationExport -> CheckpointDatumV1
entrypointAdvanceSpentDatum rotation =
    CheckpointDatumV1
        { cdCesrAid = cdCesrAid successor
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = map (blake3Hash . qb64Verkey) (cdCurKeys successor)
        , cdNextThreshold = cdCurThreshold successor
        , cdWitnesses = cdWitnesses successor
        , cdToad = cdToad successor
        , cdSeq = cdSeq successor - 1
        , cdNativeSn = cdNativeSn successor - 1
        }
  where
    successor = rotationDatum rotation

{- | The real registration effects, with ONLY the live submission boundary
replaced. 'registerQuerySnapshot' is the production body verbatim -- the
same guarded 'runLocalRegistrationSnapshot' on the
scope's own runner -- because the acquisition it performs IS the thing this
property observes; substituting a stand-in there would prove nothing.
'registerSubmit' is registration's builder boundary: it is reached only
after the snapshot resolved AND 'registerPreflight' accepted it.
-}
entrypointBoundaryRegisterRuntime :: BoundaryProbe -> RegisterRuntime
entrypointBoundaryRegisterRuntime probe =
    RegisterRuntime
        { registerReadKel = BS.readFile
        , registerReadManifest = readManifest
        , registerReadBoardManifest = readEndpointBoardManifest
        , registerQuerySnapshot = runLocalRegistrationSnapshot
        , registerWriteLine = \_line -> pure ()
        , registerSubmit = \_scope _settings _manifest _plan -> do
            markBoundary probe
            throwIO ReachedBuilderBoundary
        }

{- | Run one production entrypoint against a fresh probe and a complete (or
deliberately incomplete) seeded read set, and hand the caller both the probe
and the entrypoint's own outcome. Every one of the nineteen examples above is
this shape, so a verb's positive case and its negative control differ in
exactly one thing: which rows were seeded.
-}
withBoundaryProbe ::
    [UtxoOp] ->
    (forall cf op. BoundaryProbe -> RunTransaction IO cf Cols op -> IO ()) ->
    (BoundaryProbe -> Either SomeException () -> IO ()) ->
    IO ()
withBoundaryProbe seed entrypoint expectation =
    withInMemoryIndexerRunner $ \handle runner -> do
        applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) seed
        probe <- newBoundaryProbe
        outcome <-
            try (entrypoint probe runner) :: IO (Either SomeException ())
        expectation probe outcome

-- ---------------------------------------------------------------------------
-- The eight production entrypoints, each driven through the boundary
-- harness, and each verb's complete seeded read set.
--
-- Every runner below calls the REAL exported production entrypoint with the
-- real settings a real invocation would carry; only the two brackets (local
-- scope, live node) are the harness's, and both are real 'LocalOpener'/
-- 'LiveOpener' values, never re-implementations of the entrypoint's body.

-- | The frozen rotation export, parsed once per example by the real parser.
entrypointRotationExport :: IO RotationExport
entrypointRotationExport = do
    path <- getDataFileName "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
    bytes <- BS.readFile path
    either fail pure (parseRotationExport bytes)

{- | Advance's complete read set: the spent checkpoint output the rotation
export advances, every manifest reference output, and the funding row.
@withheldReference@ names the ONE manifest reference a negative control
removes.
-}
entrypointAdvanceSeed :: RotationExport -> Maybe Text -> [UtxoOp]
entrypointAdvanceSeed rotation withheldReference =
    UtxoCreate
        (sampleTxIn 0x50)
        entrypointCheckpointAddress
        (entrypointCheckpointOutputFor (entrypointAdvanceSpentDatum rotation))
        : entrypointReferenceSeedWithout withheldReference
            <> entrypointFundingSeed

entrypointAdvance ::
    FilePath ->
    ByteString ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointAdvance kelPath signatures probe runner =
    withSystemTempDirectory "ckeri-advance-entrypoint" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            sigPath = dir </> "controller-signatures.txt"
        writeManifestAtomic manifestPath entrypointManifest
        BS.writeFile sigPath signatures
        runAdvanceWith
            (boundaryLocalOpener probe runner)
            (boundaryLiveOpener probe)
            AdvanceSettings
                { advanceNetwork = "preprod"
                , advanceNetworkMagic = 1
                , advanceConfiguredAid = rotationFixtureAidText
                , advanceKel = kelPath
                , advanceSigningPackage = Nothing
                , advanceControllerSignatures = Just sigPath
                , advancePayer = Just "unused-payer"
                , advanceNodeSocket = Just "unused-node-socket"
                , advanceFundingAddress = Just entrypointFundingAddressText
                , advanceManifest = manifestPath
                , advanceStorePath = "unused-store-path"
                , advanceTimeoutSeconds = 30
                , advanceValidatorTestUnderSigned = False
                , advanceValidatorTestUnderWitnessed = False
                , advanceValidatorTestStale = False
                }

{- | Close's complete read set: the live checkpoint output for the inception
export's own AID, every manifest reference output, and the funding row.
@withCheckpoint@ is the ONE row a negative control withholds.
-}
entrypointCloseSeed :: Bool -> [UtxoOp]
entrypointCloseSeed withCheckpoint =
    [ UtxoCreate
        (sampleTxIn 0x51)
        entrypointCheckpointAddress
        (entrypointCheckpointOutput inceptionFixtureAidBytes)
    | withCheckpoint
    ]
        <> entrypointReferenceSeed
        <> entrypointFundingSeed

{- | Close runs in its production @--validator-test-non-controller@ mode.
Close's controller evidence is Ed25519 over a preimage this fixture's own
synthetic spent datum determines, and no private key for that datum's
current keys exists anywhere -- the alternative would be to weaken the
spent datum's threshold to @Unweighted 0@, i.e. to fabricate a checkpoint
that anyone could close. The validator-test mode is a real production path
that skips only 'closePredicate'; it changes NOTHING about the read set
this property observes, which is complete before that check is reached.
-}
entrypointClose ::
    FilePath ->
    ByteString ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointClose kelPath signatures probe runner =
    withSystemTempDirectory "ckeri-close-entrypoint" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            sigPath = dir </> "controller-signatures.txt"
        writeManifestAtomic manifestPath entrypointManifest
        BS.writeFile sigPath signatures
        runCloseWith
            (boundaryLocalOpener probe runner)
            (boundaryLiveOpener probe)
            CloseSettings
                { closeNetwork = "preprod"
                , closeNetworkMagic = 1
                , closeConfiguredAid = inceptionFixtureAidText
                , closeKel = kelPath
                , closeTo = entrypointFundingAddressText
                , closeSigningPackage = Nothing
                , closeControllerSignatures = Just sigPath
                , closePayer = Just "unused-payer"
                , closeNodeSocket = Just "unused-node-socket"
                , closeFundingAddress = Just entrypointFundingAddressText
                , closeChangeAddress = Just entrypointFundingAddressText
                , closeManifest = manifestPath
                , closeStorePath = "unused-store-path"
                , closeTimeoutSeconds = 30
                , closeValidatorTestNonController = True
                }

{- | Registration's read set is the authenticated board catalog (no
checkpoint may exist yet, and no reference hash is requested), so a catalog
missing one declared witness is exactly one withheld required row: the
production watchability preflight rejects it before the submission boundary.
-}
entrypointRegister ::
    FilePath ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointRegister kelPath probe runner =
    withSystemTempDirectory "ckeri-register-entrypoint" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            boardManifestPath = dir </> "board-manifest.json"
        writeManifestAtomic manifestPath entrypointManifest
        writeEndpointBoardManifestAtomic boardManifestPath entrypointBoardManifest
        runRegisterWith
            (boundaryLocalOpener probe runner)
            (entrypointBoundaryRegisterRuntime probe)
            RegisterSettings
                { registerNetwork = "preprod"
                , registerNetworkMagic = 1
                , registerKel = kelPath
                , registerPayer = "unused-payer"
                , registerNodeSocket = "unused-node-socket"
                , registerFundingAddress = entrypointFundingAddressText
                , registerManifest = manifestPath
                , registerBoardManifest = boardManifestPath
                , registerStorePath = "unused-store-path"
                , registerTimeoutSeconds = 30
                , registerAllowUnlistedWitnesses = False
                , registerAllowExistingCheckpoint = False
                , registerEscrowLovelace = 1_007_000_000
                }

{- | 'runDeployWith' begins at @loadArtifacts@ -> @deriveV1Scripts@, which
APPLIES parameters through @uncheckedDeserialiseUPLC@ and therefore needs
the REAL compiled blueprint (A-002 ruling 2) -- the arbitrary-hex shortcut
'entrypointBoardBlueprintJson' takes for 'deriveBoardScript' cannot reach
it. Its local acquisition runs INSIDE the live bracket, so the boundary is
'publishBoundaryLiveOpener''s stand-in runtime; @selectFundingPair@ fails
closed BEFORE the first runtime operation, which is what makes the funding
row a genuinely required part of this phase's read set.
-}
entrypointDeploy ::
    FilePath ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointDeploy blueprintPath probe runner =
    withSystemTempDirectory "ckeri-deploy-entrypoint" $ \dir -> do
        let sourceRepo = dir </> "source-repo"
        createDirectoryIfMissing True (sourceRepo </> "onchain")
        runDeployWith
            (boundaryLocalOpener probe runner)
            (publishBoundaryLiveOpener probe entrypointFundingLedgerAddress)
            (entrypointDeploySettings blueprintPath sourceRepo (dir </> "manifest.json"))

entrypointBoardDeploy ::
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointBoardDeploy probe runner =
    withSystemTempDirectory "ckeri-board-deploy-entrypoint" $ \dir -> do
        let blueprintPath = dir </> "blueprint.json"
            sourceRepo = dir </> "source-repo"
        createDirectoryIfMissing True (sourceRepo </> "onchain")
        BSL.writeFile blueprintPath entrypointBoardBlueprintJson
        runBoardDeployWith
            (boundaryLocalOpener probe runner)
            (publishBoundaryLiveOpener probe entrypointFundingLedgerAddress)
            ( entrypointDeploySettings
                blueprintPath
                sourceRepo
                (dir </> "board-manifest.json")
            )

-- | The settings both publish verbs share.
entrypointDeploySettings :: FilePath -> FilePath -> FilePath -> DeploySettings
entrypointDeploySettings blueprintPath sourceRepo outPath =
    DeploySettings
        { deployNetwork = "preprod"
        , deployNetworkMagic = 1
        , deployBlueprint = blueprintPath
        , deployNodeSocket = "unused-node-socket"
        , deployFundingAddress = entrypointFundingAddressText
        , deploySigningKeyFile = "unused-signing-key"
        , deploySourceRepo = sourceRepo
        , deploySourceRepositoryUrl = "unused-repo-url"
        , deploySourceCommit = Just (T.replicate 40 "a")
        , deployOut = outPath
        , deployReferenceLovelace = 5_000_000
        , deployStorePath = "unused-store-path"
        , deployTimeoutSeconds = 30
        }

entrypointBoardPost ::
    FilePath ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointBoardPost endpointRecordPath probe runner =
    withSystemTempDirectory "ckeri-board-post-entrypoint" $ \dir -> do
        let manifestPath = dir </> "board-manifest.json"
        writeEndpointBoardManifestAtomic manifestPath entrypointBoardManifest
        runBoardPostWith
            (boundaryLocalOpener probe runner)
            (boundaryLiveOpener probe)
            BoardPostSettings
                { boardPostEndpointRecord = endpointRecordPath
                , boardPostDepositLovelace = 2_000_000
                , boardPostTransaction = entrypointBoardTransactionSettings manifestPath
                }

entrypointBoardUpdate ::
    FilePath ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointBoardUpdate endpointRecordPath probe runner =
    withSystemTempDirectory "ckeri-board-update-entrypoint" $ \dir -> do
        let manifestPath = dir </> "board-manifest.json"
        writeEndpointBoardManifestAtomic manifestPath entrypointBoardManifest
        runBoardUpdateWith
            (boundaryLocalOpener probe runner)
            (boundaryLiveOpener probe)
            BoardUpdateSettings
                { boardUpdateEndpointRecord = endpointRecordPath
                , boardUpdateOutReference = Nothing
                , boardUpdateTransaction = entrypointBoardTransactionSettings manifestPath
                }

entrypointBoardRetire ::
    Text ->
    BoundaryProbe ->
    RunTransaction IO cf Cols op ->
    IO ()
entrypointBoardRetire witness probe runner =
    withSystemTempDirectory "ckeri-board-retire-entrypoint" $ \dir -> do
        let manifestPath = dir </> "board-manifest.json"
        writeEndpointBoardManifestAtomic manifestPath entrypointBoardManifest
        runBoardRetireWith
            (boundaryLocalOpener probe runner)
            (boundaryLiveOpener probe)
            BoardRetireSettings
                { boardRetireWitness = witness
                , boardRetireOutReference = Nothing
                , boardRetireTo = entrypointFundingAddressText
                , boardRetireTransaction = entrypointBoardTransactionSettings manifestPath
                }

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

-- ---------------------------------------------------------------------------
-- #262 S262-1: the two acquisition families the free algebra was missing, and
-- the routing/disposition boundaries that keep them the only way in.
--
-- Every property below observes the LOCAL route end to end (seeded store row
-- in, provider-neutral value out) through 'capOutputAt'/
-- 'capBoardCatalogWithOutputs'. What it deliberately does NOT observe is the
-- eager rejection of an invalid locator BEFORE an interpreter is invoked:
-- that is a provider-neutral, interpreter-independent claim, and the only
-- instrument that can actually see it is a logging interpreter, which lives
-- in "Cardano.KERI.ChainQuery.ProgramSpec". Asserting it here against a real
-- store would prove only that an invalid locator finds no row -- which is
-- true of a lazily-validating implementation too, and is exactly the shape of
-- green that cannot fail.

{- | The exact identity every exact-output fixture below is stored at. The
index is deliberately NOT zero: an implementation that matched on the
transaction id alone, or that dropped the index, would still pass at index 0
and is caught here.
-}
exactOutputIndex :: Int
exactOutputIndex = 3

exactOutputTxIn :: Indexer.TxIn
exactOutputTxIn = Indexer.TxIn (BS.replicate 32 0xAB) (fromIntegral exactOutputIndex)

{- | Deliberately a transaction id containing hex LETTERS. The malformed-
locator table below upper-cases this value, and an all-digit id would
upper-case to itself: the case row would assert nothing while reporting a
pass. Observed for real -- the first version of this fixture used @0x91@ and
the upper-case row was silently degenerate. 'malformedExactLocators' now
carries a fixture control that fails if that ever comes back.
-}
exactOutputTxIdHex :: Text
exactOutputTxIdHex = sampleTxIdHex 0xAB

exactOutputLedgerTxIn :: TxIn
exactOutputLedgerTxIn =
    TxIn
        (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xAB)))))
        (TxIx (fromIntegral exactOutputIndex))

{- | A nested inline datum with a byte string, a negative integer, a list and
a map inside it -- so a reconstruction that flattened, truncated, or dropped
nesting is caught, not only one that dropped the datum outright.
-}
exactOutputDatum :: PLC.Data
exactOutputDatum =
    PLC.Constr
        0
        [ PLC.B (BS.replicate 4 0xAB)
        , PLC.I (-7)
        , PLC.List [PLC.I 1, PLC.B BS.empty]
        , PLC.Map [(PLC.I 2, PLC.B (BS.replicate 2 0xCD))]
        ]

{- | The exact ledger output this fixture puts on chain: a script address, a
native asset beside the lovelace, and the nested inline datum above. This
value -- not a re-decode of the bytes, and not a pinned literal transcribed
beside it -- is what every parity assertion below compares against, so the
comparison is against the output that was stored rather than against another
copy of the code under test.
-}
exactOutputStoredTxOut :: TxOut ConwayEra
exactOutputStoredTxOut =
    mkBasicTxOut
        entrypointCheckpointLedgerAddress
        ( MaryValue
            (Coin 5_000_000)
            ( MultiAsset $
                Map.singleton
                    entrypointCheckpointPolicy
                    (Map.singleton (AssetName (SBS.toShort (BS.replicate 8 0x5A))) 1)
            )
        )
        & datumTxOutL .~ inlineDatumOf exactOutputDatum

exactOutputRow :: UtxoOp
exactOutputRow =
    UtxoCreate
        exactOutputTxIn
        entrypointCheckpointAddress
        (Indexer.TxOut (serialize' (eraProtVerLow @ConwayEra) exactOutputStoredTxOut))

{- | The same output with ONE datum leaf changed two levels down and nothing
else touched. Both sides are acquired, so the control is genuinely able to
fail: a route that discards inline datums answers the identical value for
both stored rows and every assertion in the falsifier goes red at once.
-}
perturbedExactOutputDatum :: PLC.Data
perturbedExactOutputDatum =
    PLC.Constr
        0
        [ PLC.B (BS.replicate 4 0xAB)
        , PLC.I (-7)
        , PLC.List [PLC.I 1, PLC.B BS.empty]
        , PLC.Map [(PLC.I 2, PLC.B (BS.replicate 2 0xCE))]
        ]

perturbedExactOutputRow :: UtxoOp
perturbedExactOutputRow =
    UtxoCreate
        exactOutputTxIn
        entrypointCheckpointAddress
        ( Indexer.TxOut $
            serialize' (eraProtVerLow @ConwayEra) $
                exactOutputStoredTxOut & datumTxOutL .~ inlineDatumOf perturbedExactOutputDatum
        )

{- | The same output carrying a datum HASH instead of an inline datum. The
provider-neutral spendable shape has no field that can carry it, so a route
that answered this row at all would hand a builder an output whose datum had
silently become absent -- a wrong transaction, not a wrong read. The
operation must fail closed instead, and this is the named mutant for
REL-262-NEUTRAL-OUTPUT-LOSSLESS.
-}
datumHashOutputRow :: UtxoOp
datumHashOutputRow =
    UtxoCreate
        exactOutputTxIn
        entrypointCheckpointAddress
        ( Indexer.TxOut $
            serialize' (eraProtVerLow @ConwayEra) $
                exactOutputStoredTxOut
                    & datumTxOutL
                        .~ DatumHash
                            (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0x44))))
        )

{- | A local scope carrying NEITHER a checkpoint nor a board identity. The
exact-output operation is identified wholly by its own locator, so it must
resolve against a scope that configures no address at all -- and a scope-
scoped implementation would fail every example below.
-}
bareScope :: RunTransaction IO cf Cols op -> LocalQueryScope cf op
bareScope runner =
    LocalQueryScope
        { localScopeRunner = runner
        , localScopeCheckpointIdentity = Nothing
        , localScopeBoardIdentity = Nothing
        }

-- | A local scope configured with the frozen board address, and nothing else.
boardOnlyScope :: RunTransaction IO cf Cols op -> LocalQueryScope cf op
boardOnlyScope runner =
    LocalQueryScope
        { localScopeRunner = runner
        , localScopeCheckpointIdentity = Nothing
        , localScopeBoardIdentity = Just entrypointBoardIndexerAddress
        }

{- | Everything a Conway transaction output carries, and therefore everything
a builder can consume from one: 'Cardano.Ledger.Babbage.TxBody.BabbageTxOut'
has exactly these four fields. Projecting them explicitly (rather than
comparing whole 'TxOut' values) states what "the same output" means and keeps
the comparison independent of memoised-CBOR representation, while still being
complete by the era's own shape.
-}
data OutputFacts = OutputFacts
    { factsAddress :: Addr
    , factsValue :: MaryValue
    , factsInlineDatum :: Maybe PLC.Data
    , factsReferenceScript :: Maybe (Script ConwayEra)
    }
    deriving stock (Show, Eq)

outputFacts :: TxOut ConwayEra -> OutputFacts
outputFacts txOut =
    OutputFacts
        { factsAddress = txOut ^. addrTxOutL
        , factsValue = txOut ^. valueTxOutL
        , factsInlineDatum = case txOut ^. datumTxOutL of
            Datum binaryDatum ->
                let Data plutus = binaryDataToData binaryDatum in Just plutus
            NoDatum -> Nothing
            DatumHash _ -> Nothing
        , factsReferenceScript = txOut ^. (referenceScriptTxOutL . fromStrictMaybeL)
        }

{- | Reconstruct a builder input from an acquired neutral output exactly the
way production does, through the shared pure conversion, and report the
result as facts. A lossy acquisition cannot be hidden behind this: the
conversion is the same one every migrated write verb calls.
-}
acquiredFacts :: ChainAssetUtxo -> Either ChainQueryError (TxIn, OutputFacts)
acquiredFacts utxo = do
    (txIn, txOut) <- chainAssetUtxoToLedgerOutput utxo
    pure (txIn, outputFacts txOut)

{- | \#262 RQ-262-01\/DATA-INV-262-02\/INV-262-NO-REGRESSION: the exact-output
operation resolves one live row by its own @(txid,index)@ identity, hands
back the provider-neutral spendable shape, and that shape reconstructs to the
output that is actually stored -- address, value, inline datum, and reference
script alike. Absence and an unrepresentable row both fail closed with a
named error rather than a reduced answer.
-}
exactOutputAcquisition :: Spec
exactOutputAcquisition =
    describe
        "#262 RQ-262-01 -- exact output by (txid,index) through the algebra, \
        \RED against the closed test-local stand-in"
        $ do
            it "resolves the one live row at the exact identity and preserves every field a builder consumes (DATA-INV-262-02)" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [exactOutputRow]
                    result <-
                        capOutputAt
                            redCapabilities
                            (bareScope runner)
                            exactOutputTxIdHex
                            exactOutputIndex
                    case result of
                        Left err ->
                            expectationFailure
                                ("expected the stored output to resolve, got " <> show err)
                        Right utxo -> do
                            chainAssetTxId utxo `shouldBe` exactOutputTxIdHex
                            chainAssetIndex utxo `shouldBe` exactOutputIndex
                            acquiredFacts utxo
                                `shouldBe` Right
                                    ( exactOutputLedgerTxIn
                                    , outputFacts exactOutputStoredTxOut
                                    )

            it "rejects a one-side acquired-value perturbation -- two rows differing ONLY in a datum leaf two levels down acquire to different builder inputs (mandatory falsifier)" $ do
                let acquire row =
                        withInMemoryIndexerRunner $ \handle runner -> do
                            applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [row]
                            capOutputAt
                                redCapabilities
                                (bareScope runner)
                                exactOutputTxIdHex
                                exactOutputIndex
                honest <- acquire exactOutputRow
                perturbed <- acquire perturbedExactOutputRow
                case (honest, perturbed) of
                    (Right honestUtxo, Right perturbedUtxo) -> do
                        perturbedUtxo `shouldNotBe` honestUtxo
                        fmap (fmap factsInlineDatum) (acquiredFacts perturbedUtxo)
                            `shouldNotBe` fmap (fmap factsInlineDatum) (acquiredFacts honestUtxo)
                        -- and the perturbation is confined to the datum
                        chainAssetTxId perturbedUtxo `shouldBe` chainAssetTxId honestUtxo
                        chainAssetIndex perturbedUtxo `shouldBe` chainAssetIndex honestUtxo
                        chainAssetAddress perturbedUtxo `shouldBe` chainAssetAddress honestUtxo
                        chainAssetLovelace perturbedUtxo `shouldBe` chainAssetLovelace honestUtxo
                        chainAssetList perturbedUtxo `shouldBe` chainAssetList honestUtxo
                    other ->
                        expectationFailure
                            ("expected both stored rows to acquire, got " <> show other)

            it "does not answer a different index at the same transaction id" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [exactOutputRow]
                    result <-
                        capOutputAt
                            redCapabilities
                            (bareScope runner)
                            exactOutputTxIdHex
                            (exactOutputIndex + 1)
                    case result of
                        Left (DecodingFailure _) -> pure ()
                        other ->
                            expectationFailure
                                ("expected a named absence failure, got " <> show other)

            it "fails closed on absence rather than answering an empty or invented output" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) []
                    result <-
                        capOutputAt
                            redCapabilities
                            (bareScope runner)
                            exactOutputTxIdHex
                            exactOutputIndex
                    case result of
                        Left (DecodingFailure _) -> pure ()
                        other ->
                            expectationFailure
                                ("expected a named absence failure, got " <> show other)

            it "fails closed on a row the neutral shape cannot carry -- a datum HASH must never reconstruct as a datum-less builder input (REL-262-NEUTRAL-OUTPUT-LOSSLESS)" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [datumHashOutputRow]
                    result <-
                        capOutputAt
                            redCapabilities
                            (bareScope runner)
                            exactOutputTxIdHex
                            exactOutputIndex
                    case result of
                        Left (DecodingFailure _) -> pure ()
                        Right utxo ->
                            expectationFailure
                                ( "expected the unrepresentable row to fail closed, but it \
                                  \acquired as "
                                    <> show utxo
                                )
                        other ->
                            expectationFailure
                                ("expected a named DecodingFailure, got " <> show other)

            it "rejects a malformed locator through the local route instead of scanning for it (RQ-262-03)" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [exactOutputRow]
                    -- fixture control: the upper-case row below can only test
                    -- anything if upper-casing actually CHANGES the id. An
                    -- all-digit fixture upper-cases to itself and the row
                    -- passes while asserting nothing.
                    T.toUpper exactOutputTxIdHex `shouldNotBe` exactOutputTxIdHex
                    for_ malformedExactLocators $ \(label, txIdHex, index) -> do
                        result <- capOutputAt redCapabilities (bareScope runner) txIdHex index
                        case result of
                            Left (InvalidLocator _) -> pure ()
                            other ->
                                expectationFailure
                                    ( "expected "
                                        <> label
                                        <> " to be rejected as an invalid locator, got "
                                        <> show other
                                    )

{- | Every shape a concrete exact-output locator can be wrong in. The
uppercase case matters on its own: hex decoding accepts it, so a check
written only as "decodes to 32 bytes" would admit a non-canonical identity
that no stored row's own lowercase rendering can ever equal -- an absence
reported as a locator that simply never matches.
-}
malformedExactLocators :: [(String, Text, Int)]
malformedExactLocators =
    [ ("a non-hexadecimal transaction id", T.replicate 64 "z", exactOutputIndex)
    , ("a short transaction id", T.replicate 62 "9", exactOutputIndex)
    , ("a long transaction id", T.replicate 66 "9", exactOutputIndex)
    , ("an upper-case transaction id", T.toUpper exactOutputTxIdHex, exactOutputIndex)
    , ("an empty transaction id", "", exactOutputIndex)
    , ("a negative output index", exactOutputTxIdHex, -1)
    , ("an output index outside the ledger range", exactOutputTxIdHex, 65_536)
    ]

{- | \#262 RQ-262-02\/DATA-INV-262-03: the board catalog and the complete
neutral output of each entry's own row arrive together, identity-consistent,
as one all-or-nothing observation.
-}
boardOutputAcquisition :: Spec
boardOutputAcquisition =
    describe
        "#262 RQ-262-02 -- authenticated board entries paired with their own \
        \outputs, RED against the closed test-local stand-in"
        $ do
            it "pairs every authenticated entry with the output from its own row, identities equal (DATA-INV-262-03)" $ do
                records <- entrypointWitnessRecords
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        (entrypointBoardCatalogSeedWithout Nothing records)
                    result <-
                        capBoardCatalogWithOutputs
                            redCapabilities
                            (boardOnlyScope runner)
                            frozenEndpointBoardPolicyId
                            frozenEndpointBoardAddress
                    case result of
                        Left err ->
                            expectationFailure
                                ("expected the paired catalog to resolve, got " <> show err)
                        Right pairs -> do
                            length pairs `shouldBe` length records
                            for_ pairs $ \(entry, utxo) -> do
                                chainAssetTxId utxo `shouldBe` boardTxId entry
                                chainAssetIndex utxo `shouldBe` boardIndex entry
                                chainAssetLovelace utxo `shouldBe` boardLovelace entry

            it "reconstructs each paired output into the builder input the row actually stores" $ do
                records <- entrypointWitnessRecords
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        (entrypointBoardCatalogSeedWithout Nothing records)
                    result <-
                        capBoardCatalogWithOutputs
                            redCapabilities
                            (boardOnlyScope runner)
                            frozenEndpointBoardPolicyId
                            frozenEndpointBoardAddress
                    case result of
                        Left err ->
                            expectationFailure
                                ("expected the paired catalog to resolve, got " <> show err)
                        Right pairs ->
                            for_ pairs $ \(entry, utxo) ->
                                case ( acquiredFacts utxo
                                     , find ((== boardWitnessKey entry) . endpointWitnessKey) records
                                     ) of
                                    (Left err, _) ->
                                        expectationFailure
                                            ("expected the paired output to convert, got " <> show err)
                                    (_, Nothing) ->
                                        expectationFailure
                                            "the resolved catalog names a witness key no seeded record carries"
                                    (Right (_txIn, facts), Just record) -> do
                                        factsAddress facts `shouldBe` entrypointBoardLedgerAddress
                                        factsInlineDatum facts
                                            `shouldBe` Just (entrypointBoardDatum record)

            it "fails the WHOLE operation on one undecodable row at the board address -- never a partial catalog" $ do
                records <- entrypointWitnessRecords
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        ( entrypointBoardCatalogSeedWithout Nothing records
                            <> [UtxoCreate (sampleTxIn 0x7F) entrypointBoardIndexerAddress malformedTxOut]
                        )
                    result <-
                        capBoardCatalogWithOutputs
                            redCapabilities
                            (boardOnlyScope runner)
                            frozenEndpointBoardPolicyId
                            frozenEndpointBoardAddress
                    case result of
                        Left (DecodingFailure _) -> pure ()
                        Right pairs ->
                            expectationFailure
                                ( "expected the whole operation to fail closed, got a partial \
                                  \catalog of length "
                                    <> show (length pairs)
                                )
                        other ->
                            expectationFailure
                                ("expected a named DecodingFailure, got " <> show other)

            it "fails closed when the write command has no board identity configured at all" $ do
                records <- entrypointWitnessRecords
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 10)
                        (blockHash 0x01)
                        (entrypointBoardCatalogSeedWithout Nothing records)
                    result <-
                        capBoardCatalogWithOutputs
                            redCapabilities
                            (bareScope runner)
                            frozenEndpointBoardPolicyId
                            frozenEndpointBoardAddress
                    case result of
                        Left (InvalidLocator _) -> pure ()
                        other ->
                            expectationFailure
                                ("expected a named InvalidLocator, got " <> show other)

{- | The inline datum a seeded board row carries, spelled exactly as
'entrypointBoardCatalogSeed' writes it. The assertion above looks the record
up by the WITNESS KEY the resolved entry carries, so an implementation that
paired an entry with a different entry's row acquires a datum naming the
wrong key and is caught -- the identity check and the value check are the
same check.
-}
entrypointBoardDatum :: EndpointRecord -> PLC.Data
entrypointBoardDatum record =
    PLC.Constr
        0
        [ PLC.B (endpointWitnessKey record)
        , PLC.B (endpointEventBytes record)
        , PLC.B (endpointSignature record)
        , PLC.B entrypointOwnerKeyHash
        ]

{- | \#262 INV-262-SOLE-ROUTE: the local interpreter is the sole build-phase
acquisition authority, expressed as an executing source\/component boundary
over the shipped write-composition module and the shipped interpreter
module's own export list (MOD-262-PROOF).

Be precise about what this establishes and what it cannot. It establishes
that the shipped write composition contains no direct local-store acquisition
route, and that the raw readers are not exported for one to be written
against -- which is what makes the compiler, not a convention, the thing
stopping a reintroduction. It does not observe routing at run time, and no
instrument in this repository can: a raw bundle and an algebra program both
enter the store runner exactly once, so the acquisition-count properties
above cannot tell them apart. That is why this boundary is a source and
export property rather than a counting one, and saying so is part of the
proof.

The detector proves itself against every marker it carries, so a marker that
has stopped matching anything is caught. What it cannot catch is a marker
never added to the list; the list is therefore the reviewable surface, and it
is derived from the mandate's own named routes rather than from what the
current source happens to contain.
-}
writeCompositionRouteBoundary :: Spec
writeCompositionRouteBoundary =
    describe
        "#262 INV-262-SOLE-ROUTE -- no direct local acquisition route survives \
        \in write composition, and none is exported for one to be written against"
        $ do
            it "the detector flags every direct-acquisition marker it carries, and ignores unrelated text (self-test)" $ do
                for_ directAcquisitionMarkers $ \marker -> do
                    let seeded = "    result <- " <> marker <> " scope locator"
                    directAcquisitionViolations [seeded] `shouldBe` [seeded]
                directAcquisitionViolations ["an ordinary line naming no acquisition route"]
                    `shouldBe` []

            it "the shipped write-composition module reaches no raw local acquisition route" $ do
                contents <- BS.readFile writeCompositionSourcePath
                directAcquisitionViolations (T.lines (TE.decodeUtf8 contents))
                    `shouldBe` []

            it "the export-list parser finds the interpreter module's real exports (self-test)" $ do
                exports <- moduleExportList localInterpreterSourcePath
                exports `shouldNotBe` []
                ("runLocalQuery" `elem` exports) `shouldBe` True

            it "the shipped interpreter module exports no raw build-acquisition function" $ do
                exports <- moduleExportList localInterpreterSourcePath
                filter (`elem` withdrawnLocalExports) exports `shouldBe` []

            unsafeRunnerApiIsAbsent

writeCompositionSourcePath :: FilePath
writeCompositionSourcePath = "write-composition/Cardano/KERI/Deployment/CLI.hs"

localInterpreterSourcePath :: FilePath
localInterpreterSourcePath = "indexer/Cardano/KERI/Indexer/ChainQuery.hs"

{- | Every way write composition could reach the local store without going
through the algebra: the store transaction module itself, the raw snapshot
runner, each raw build-phase reader, and the store transaction TYPE (which a
reintroduced bundle's own signature must name).

The settlement probes are deliberately absent. They are post-submit temporal
observations, never build-phase reads, and \#240 established them as a
separate capability -- flagging them here would make the steady state
unreachable and the whole boundary vacuous.
-}
directAcquisitionMarkers :: [Text]
directAcquisitionMarkers =
    [ "Database.KV.Transaction"
    , "runLocalSnapshotTx"
    , "localSnapshotTx"
    , "localOutputAtTx"
    , "localOutputAt"
    , "localBoardCatalogWithOutputs"
    , "localBoardCatalog"
    , "localCurrentCheckpoint"
    , "localLiveCheckpoints"
    , "localPayerUtxos"
    , "localReferenceScriptsTx"
    , "Transaction IO"
    ]

directAcquisitionViolations :: [Text] -> [Text]
directAcquisitionViolations =
    filter (\line -> any (`T.isInfixOf` line) directAcquisitionMarkers)

{- | A-262-02 (NOTE-003, A-001 ruling 1): the two snapshot runners that
appended a watermark read to EVERY program, including one that rejected its
own argument before building an operation.

Submission 2 kept them, documented them as dangerous, and forbade write
composition from naming them. The fresh audit was right to reject that: a
public API that still has the defect, guarded only by what today's caller
chooses to pass it, is avoided rather than prevented -- and this ticket
exists to replace convention with boundaries. They are now DELETED, and the
epic owner authorized the resulting change to \#257's public surface
(A-001).

The names are assembled from fragments for the same reason
'localtierInvariantName' is: this module is one of the files the scan below
reads, so spelling them whole here would make the property flag its own
source and the absence it exists to prove could never be reached.
-}
retiredUnsafeRunners :: [Text]
retiredUnsafeRunners =
    [ "runChainQuery" <> "Snapshot"
    , "runLocal" <> "ChainQuery"
    ]

{- | A name no shipped source contains, for the control that proves the
scanner can report a genuine absence.

Assembled from fragments for the same reason the retired names are, and the
first version of this control did NOT do that -- it searched for a literal
that its own source then contained, so the scanner found itself and the
control failed. That is the identical self-reference trap the invariant-name
scan documents, met a second time; keeping the fix beside both is cheaper
than meeting it a third.
-}
absentSentinel :: Text
absentSentinel = "aNameNoShipped" <> "SourceContains"

{- | A-262-02: the retired runners are absent from EVERY shipped Haskell
source, so no caller -- production, test, or future -- can import or call
one. This is the whole difference between the submission-2 repair and this
one.

A per-call-site scan rots: it can only forbid the callers that exist when it
is written, and a new module is a new hole. An absence over the whole
compiled surface cannot: the name a reintroduced caller would need does not
exist, and if it comes back this row fails wherever it comes back.

The scan reads every @.hs@ file under the component tree, production and
proof alike -- deliberately not a curated list, because a curated list is
exactly the narrowing A-001 forbids.
-}
unsafeRunnerApiIsAbsent :: Spec
unsafeRunnerApiIsAbsent =
    describe
        "#262 A-262-02 -- the retired unsafe snapshot runners are absent from \
        \every shipped source, so no caller can name one"
        $ do
            it "self-test: the scanner sees a name that IS present, so an absence is not vacuous" $ do
                sources <- shippedHaskellSources
                length sources `shouldNotBe` 0
                hits <- sourcesMentioning sources ["runChainQueryResultSnapshot"]
                hits `shouldNotBe` []

            it "self-test: the scanner reports a name that is genuinely absent" $ do
                sources <- shippedHaskellSources
                hits <- sourcesMentioning sources [absentSentinel]
                hits `shouldBe` []

            it "no shipped source mentions a retired unsafe runner, in code or in prose" $ do
                sources <- shippedHaskellSources
                hits <- sourcesMentioning sources retiredUnsafeRunners
                hits `shouldBe` []

{- | Every Haskell source the components and their suites are built from.
Walks the tree rather than naming files, and skips only build output.
-}
shippedHaskellSources :: IO [FilePath]
shippedHaskellSources = go "."
  where
    go directory = do
        entries <- listDirectory directory
        fmap concat . for entries $ \entry -> do
            let path = directory </> entry
            isDirectory <- doesDirectoryExist path
            if isDirectory
                then if entry `elem` skipped then pure [] else go path
                else pure [path | ".hs" `isSuffixOf` entry]
    skipped = ["dist-newstyle", ".git", "result"]

{- | Every @path:line@ in @sources@ mentioning any of @needles@. Returns the
locations rather than a bare count so a failure names where the retired
runner came back.
-}
sourcesMentioning :: [FilePath] -> [Text] -> IO [String]
sourcesMentioning sources needles =
    fmap concat . for sources $ \path -> do
        contents <- TE.decodeUtf8 <$> BS.readFile path
        pure
            [ path <> ":" <> show lineNumber
            | (lineNumber, line) <- zip [1 :: Int ..] (T.lines contents)
            , any (`T.isInfixOf` line) needles
            ]

{- | The raw build-acquisition functions that must not be exported once every
caller has migrated (RQ-262-05, T262-S1-10). They remain DEFINED -- the local
interpreter needs them -- but as private implementation details.
-}
withdrawnLocalExports :: [Text]
withdrawnLocalExports =
    [ "runLocalSnapshotTx"
    , "localOutputAtTx"
    , "localOutputAt"
    , "localBoardCatalogWithOutputs"
    , "localBoardCatalog"
    , "localCurrentCheckpoint"
    , "localPayerUtxos"
    , "localReferenceScriptsTx"
    ]

{- | The names a module's export list carries. Deliberately a small reader
over the header rather than a general Haskell parser: the region between the
@module@ keyword's own opening parenthesis and the closing @) where@ is
unambiguous in this codebase's single-style module headers, and the self-test
above requires the reader to find a known export before any absence it
reports is believed.
-}
moduleExportList :: FilePath -> IO [Text]
moduleExportList path = do
    contents <- TE.decodeUtf8 <$> BS.readFile path
    let afterModule = T.drop 1 (T.dropWhile (/= '(') (snd (T.breakOn "\nmodule " contents)))
        exportRegion = withoutComments (fst (T.breakOn ") where" afterModule))
    pure
        [ name
        | chunk <- T.splitOn "," exportRegion
        , let name = T.takeWhile (\c -> c /= ' ' && c /= '(') (T.strip chunk)
        , not (T.null name)
        ]
  where
    withoutComments =
        T.unwords
            . filter (not . ("--" `T.isPrefixOf`))
            . map T.strip
            . T.lines

{- | A-262-01 (RQ-262-03\/DATA-INV-262-01), the store-runner half: an eagerly
rejected locator opens NO store transaction at all through the write path's
own runner.

The companion property in "Cardano.KERI.ChainQuery.InterpreterSpec" proves
zero interpreter handlers, including the watermark handler. That is the
query layer, and it is not enough on its own: a runner can invoke zero
handlers and still have entered @RunTransaction@ to find that out. This is
the layer where "no store effect" is either true or false, and the counting
runner is the only instrument that can see it.

The count is proved non-vacuous in the same example set: a VALID locator
through the SAME runner must count exactly one. Without that row, "counted
zero" would also be true of a runner that never ran anything.
-}
eagerRejectionOpensNoStoreTransaction :: Spec
eagerRejectionOpensNoStoreTransaction =
    describe
        "#262 RQ-262-03/DATA-INV-262-01 -- an eagerly rejected locator opens no \
        \store transaction through the write path's runner (A-262-01)"
        $ do
            it "self-test: a VALID locator through the same runner opens exactly one, so a zero is not vacuous" $
                withInMemoryIndexerRunner $ \handle runner -> do
                    applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [exactOutputRow]
                    counter <- newIORef (0 :: Int)
                    let scope = bareScope (countingRunner counter runner)
                    outcome <-
                        runWritePathQuery
                            writePathRunner
                            scope
                            (outputAt (exactLocator exactOutputTxIdHex exactOutputIndex))
                    readIORef counter `shouldReturnCount` 1
                    case outcome of
                        Right _ -> pure ()
                        Left err ->
                            expectationFailure
                                ("expected the valid locator to resolve, got " <> show err)

            for_ rejectableLocalFamilies $ \(label, program) ->
                it (label <> ": zero store transactions, InvalidLocator") $
                    withInMemoryIndexerRunner $ \handle runner -> do
                        applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [exactOutputRow]
                        counter <- newIORef (0 :: Int)
                        let scope = boardOnlyScope (countingRunner counter runner)
                        outcome <- runWritePathQuery writePathRunner scope program
                        readIORef counter `shouldReturnCount` 0
                        case outcome of
                            Left (InvalidLocator _) -> pure ()
                            other ->
                                expectationFailure
                                    ("expected a named InvalidLocator, got " <> show other)

{- | Every family a write verb can build from a concrete locator, each with
an argument it must reject. Enumerated, not sampled: an omitted family is
one whose production runner nobody counts.
-}
rejectableLocalFamilies :: [(String, ChainQuery (Either ChainQueryError ()))]
rejectableLocalFamilies =
    [ ("outputAt", erased (outputAt badOutputLocator))
    , ("boardCatalogWithOutputs", erased (boardCatalogWithOutputs badBoardLocator))
    , ("boardCatalog", erased (boardCatalog badBoardLocator))
    , ("currentCheckpoint", erased (currentCheckpoint badCheckpointLocator parityCheckpointAid))
    , ("liveCheckpoints", erased (liveCheckpoints badCheckpointLocator))
    , ("payerUtxos", erased (payerUtxos ["not-an-address"]))
    , ("referenceScripts", erased (referenceScripts ["not-canonical-hex"]))
    ]

erased :: ChainQuery (Either ChainQueryError a) -> ChainQuery (Either ChainQueryError ())
erased = fmap void

exactLocator :: Text -> Int -> OutputLocator
exactLocator txIdHex index =
    OutputLocator{outputLocatorTxId = txIdHex, outputLocatorIndex = index}

badOutputLocator :: OutputLocator
badOutputLocator = exactLocator (T.replicate 64 "A") 0

badBoardLocator :: BoardLocator
badBoardLocator =
    BoardLocator{boardLocatorPolicyId = "not-a-policy-id", boardLocatorAddress = "not-an-address"}

badCheckpointLocator :: CheckpointLocator
badCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = "not-a-policy-id"
        , checkpointLocatorAddress = "not-an-address"
        }

{- | The write path's own snapshot runner, behind one named field, so this
property is aimed at whatever production actually calls. The shipped
source-boundary property separately forbids write composition from naming
any other runner, which is what keeps this binding honest rather than
merely intended.
-}
newtype WritePathRunner = WritePathRunner
    { runWritePathQuery ::
        forall cf op a.
        LocalQueryScope cf op ->
        ChainQuery (Either ChainQueryError a) ->
        IO (Either ChainQueryError a)
    }

writePathRunner :: WritePathRunner
writePathRunner = WritePathRunner{runWritePathQuery = repairedWritePathQuery}

{- | The repaired write-path route: exactly what
@Cardano.KERI.Deployment.CLI.acquire@ calls, with only the final
@fail . show@ replaced by returning the error so a property can inspect it.
-}
repairedWritePathQuery ::
    LocalQueryScope cf op ->
    ChainQuery (Either ChainQueryError a) ->
    IO (Either ChainQueryError a)
repairedWritePathQuery scope program =
    fmap snapshotValue <$> runLocalQuery scope program

shouldReturnCount :: IO Int -> Int -> IO ()
shouldReturnCount action expected = action >>= (`shouldBe` expected)

{- | \#262 RQ-262-07\/INV-262-DISPOSITION, the same permanently executing
property A-018 finding 2 established for \#240, turned around: the local-tier
invariant is no longer deferred, so every shipped occurrence of its name must
now state that algebra-only local routing is MET by \#262. The detector this
replaces required the opposite text and would pass on a source that still
claimed the invariant open, which is precisely why the change belongs in the
same behavior commit as the routing itself rather than in a later tidy-up.

The detector proves itself in FOUR directions before it is trusted, one more
than its predecessor: it must flag a bare claim, must flag a RESTORED
deferral (the named killing mutant for this campaign row -- the thing a
partial or reverted migration actually leaves behind), must accept the
closure statement, and must NOT flag text that never names the invariant. A
detector that only accepted the new text without rejecting the old one would
be green against a source that never migrated.

A file with no occurrence passes, and that remains the intended steady state:
the rows exist to catch a future edit that reintroduces a deferral or a bare
claim.
-}
localtierClosureClaims :: Spec
localtierClosureClaims =
    describe
        "every shipped occurrence of the local-tier invariant states that \
        \algebra-only local routing is now MET by #262 (RQ-262-07, \
        \INV-262-DISPOSITION)"
        $ do
            it "the detector flags a bare claim and a restored deferral, accepts the closure statement, and ignores unrelated text (self-test)" $ do
                let bareClaim =
                        "acquisition complete (" <> localtierInvariantName <> "/INV-240-SNAPSHOT)"
                    restoredDeferral =
                        localtierInvariantName
                            <> " is OPEN -- "
                            <> deferralWord
                            <> " to "
                            <> issueTag
                    closureClaim =
                        localtierInvariantName <> " is " <> closureMarker <> ": every write build read routes through the local interpreter"
                localtierClaimViolations [bareClaim] `shouldBe` [bareClaim]
                localtierClaimViolations [restoredDeferral] `shouldBe` [restoredDeferral]
                localtierClaimViolations [closureClaim] `shouldBe` []
                localtierClaimViolations ["an ordinary line naming no invariant"]
                    `shouldBe` []

            for_ shippedLocaltierSources $ \path ->
                it ("every local-tier occurrence in " <> path <> " states the #262 closure") $ do
                    contents <- BS.readFile path
                    localtierClaimViolations (T.lines (TE.decodeUtf8 contents))
                        `shouldBe` []

{- | The shipped sources this campaign touches that may name the invariant.
Paths are relative to @offchain@, the working directory both the focused
@cabal run@ command and the packaged @local-write-path-check@ runner execute
from.
-}
shippedLocaltierSources :: [FilePath]
shippedLocaltierSources =
    [ "indexer/Cardano/KERI/Indexer/ChainQuery.hs"
    , "write-composition/Cardano/KERI/Deployment/CLI.hs"
    , "query-test/Cardano/KERI/Indexer/LocalWritePathSpec.hs"
    ]

{- | Spelled in two pieces on purpose. This module is one of the files the
property scans, so writing the name whole here would make the detector flag
its own source and the scan could never reach the steady state it exists to
protect. Every prose mention in this module is phrased around the name for
the same reason.
-}
localtierInvariantName :: Text
localtierInvariantName = "INV-240-" <> "LOCALTIER"

{- | The old deferral vocabulary, assembled from pieces for a second,
independent reason: the immutable slice gate greps the three shipped sources
AND this suite for a line carrying both the deferral word and the issue tag,
so spelling the restored-deferral fixture whole on one line here would make
this file fail that gate while proving nothing extra.
-}
deferralWord :: Text
deferralWord = "DEFER" <> "RED"

issueTag :: Text
issueTag = "#" <> "262"

{- | The closure vocabulary a shipped occurrence must now carry. Kept as one
named value so the detector, its self-test, and the shipped sources cannot
drift into two different spellings of "closed".
-}
closureMarker :: Text
closureMarker = "MET by " <> issueTag

{- | Every line naming the invariant without stating its \#262 closure. A
restored deferral is flagged by exactly this rule, because deferral text
does not carry the closure marker.
-}
localtierClaimViolations :: [Text] -> [Text]
localtierClaimViolations =
    filter $ \line ->
        localtierInvariantName `T.isInfixOf` line
            && not (closureMarker `T.isInfixOf` line)

{- | A-018 finding 1, the property class rather than one more fixture: for
ANY legal inline datum, acquiring the reference output and converting it the
way production actually converts it -- 'chainReferenceToLedgerOutput', the
same function every write verb's @referenceOutputsTx@ calls, whose
'Cardano.KERI.ChainQuery.LedgerOutput.attachDatum' rebuilds the datum from
@chainAssetInlineDatum@ -- must yield back exactly the datum that was
stored.

This crosses the seam the finding is about. A lossy acquisition cannot pass
it for any datum at all: with @chainAssetInlineDatum = Nothing@ the rebuilt
output carries 'NoDatum' and the property fails on the first generated
value. It is also not vacuous in the other direction -- the generator emits
nested constructors, maps, lists, negative integers, and empty and
non-empty byte strings, so a decoder that flattened or truncated nesting
would be caught too.
-}
referenceDatumRoundTripsToTheSeededValue :: Property
referenceDatumRoundTripsToTheSeededValue =
    forAll genPlutusData $ \datum -> ioProperty $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyAtSlot
                handle
                (Indexer.SlotNo 10)
                (blockHash 0x01)
                [ UtxoCreate
                    parityReferenceTxIn
                    parityReferenceAddr
                    (referenceOutput parityReferenceScript (Just datum) parityReferenceAddr)
                ]
            result <-
                capReferenceScripts
                    redCapabilities
                    (queryHandleLocalScope (testQueryHandle runner))
                    [parityReferenceHash]
            case result of
                Left err ->
                    expectationFailure
                        ("expected the datum-bearing reference to resolve, got " <> show err)
                Right [reference] ->
                    case chainReferenceToLedgerOutput reference of
                        Left err ->
                            expectationFailure
                                ("expected the acquired reference to convert to a builder input, got " <> show err)
                        Right (_txIn, ledgerTxOut) ->
                            rebuiltDatum ledgerTxOut `shouldBe` Just datum
                Right other ->
                    expectationFailure
                        ("expected exactly one resolved reference, got " <> show (length other))
  where
    rebuiltDatum :: TxOut ConwayEra -> Maybe PLC.Data
    rebuiltDatum ledgerTxOut =
        case ledgerTxOut ^. datumTxOutL of
            Datum binaryDatum ->
                let Data plutus = binaryDataToData binaryDatum
                 in Just plutus
            NoDatum -> Nothing
            DatumHash _ -> Nothing

{- | Explicit generator (no 'Arbitrary' instance, per this codebase's
convention): every 'PLC.Data' arm, bounded in depth so the fixture stays a
legal inline datum rather than an unbounded tree.
-}
genPlutusData :: Gen PLC.Data
genPlutusData = go (3 :: Int)
  where
    go depth
        | depth <= 0 = oneof [leafInteger, leafBytes]
        | otherwise =
            oneof
                [ leafInteger
                , leafBytes
                , PLC.Constr <$> genConstructorTag <*> listOf' (go (depth - 1))
                , PLC.List <$> listOf' (go (depth - 1))
                , PLC.Map <$> listOf' ((,) <$> go (depth - 1) <*> go (depth - 1))
                ]
    leafInteger = PLC.I <$> arbitrarySizedIntegral
    leafBytes = PLC.B . BS.pack <$> listOf' arbitraryBoundedIntegral
    genConstructorTag = fromIntegral <$> chooseInt (0, 5)
    -- bounded width as well as depth: an unbounded list at depth 3 makes a
    -- single example seconds long for no additional coverage.
    listOf' generator = chooseInt (0, 3) >>= \n -> vectorOf n generator

{- | A-018 finding 1 (DATA-INV-240-01 + the reference half of
INV-240-PARITY): the SAME captured reference output, now carrying an inline
datum. Its expected @chainAssetInlineDatum@ below is pinned as an
INDEPENDENT literal in the detailed JSON schema, never as
@plutusDataJson referenceFixtureDatum@ -- deriving both sides from one
expression is exactly how a comparison passes unconditionally in the case it
exists to catch.

The schema this literal is written in is not guesswork: it is the one
"Cardano.KERI.ChainQuery.PlutusJson" documents as "the detailed JSON shape
Koios's @inline_datum@ and this package's own manifests share", which the
frozen base provider reads verbatim out of @inline_datum.value@
('parseExtendedChainAssetUtxo') and which
'Cardano.KERI.ChainQuery.LedgerOutput.attachDatum' feeds back through
'plutusDataFromJson' when it rebuilds a builder input. The
'referenceDatumRoundTripsToTheSeededValue' property below closes the same
class over generated data through that real conversion, so this literal
pins the shape while the property pins the behaviour.
-}
parityExpectedReferenceDatum :: Value
parityExpectedReferenceDatum =
    object
        [ "constructor" .= (1 :: Integer)
        , "fields"
            .= [ object ["bytes" .= ("733234302d7265666572656e63652d646174756d" :: Text)]
               , object ["int" .= (-9 :: Integer)]
               , object
                    [ "list"
                        .= [ object ["int" .= (0 :: Integer)]
                           , object ["bytes" .= ("0102" :: Text)]
                           , object ["constructor" .= (0 :: Integer), "fields" .= ([] :: [Value])]
                           ]
                    ]
               , object
                    [ "map"
                        .= [ object
                                [ "k" .= object ["bytes" .= ("6b" :: Text)]
                                , "v" .= object ["list" .= [object ["int" .= (7 :: Integer)]]]
                                ]
                           ]
                    ]
               ]
        ]

{- | 'parityExpectedReference' with the datum dimension filled in -- the
comparison target for the datum-bearing row.
-}
parityExpectedReferenceWithDatum :: ChainReference
parityExpectedReferenceWithDatum =
    parityExpectedReference
        { chainReferenceOutput =
            (chainReferenceOutput parityExpectedReference)
                { chainAssetInlineDatum = Just parityExpectedReferenceDatum
                }
        }

{- | The MANDATORY one-sided datum perturbation (A-018 finding 1): the same
script, tx identity, address and lovelace, differing ONLY in the inline
datum. Before the repair this fixture was indistinguishable from
'referenceFixtureDatum' -- both decoded to 'Nothing' -- so this example is
the one that proves the datum dimension is now observed at all.
-}
perturbedReferenceFixtureDatum :: PLC.Data
perturbedReferenceFixtureDatum =
    PLC.Constr
        1
        [ PLC.B "s240-reference-datum"
        , PLC.I (-9)
        , PLC.List [PLC.I 0, PLC.B "\x01\x02", PLC.Constr 0 []]
        , -- the single perturbed leaf: 7 becomes 8, nested two levels deep
          PLC.Map [(PLC.B "k", PLC.List [PLC.I 8])]
        ]

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

{- | A checkpoint output that is well-formed at every level EXCEPT its
inline datum's schema: valid ledger 'TxOut' CBOR, at 'addrA', carrying the
one checkpoint NFT under 'unusedCheckpointPolicy', but whose inline datum
is @Constr 1 []@ -- valid 'PLC.Data', not the frozen V1 checkpoint schema.

This is the EXACT malformed shape the frozen base's own capture used
(@{"constructor":1,"fields":[]}@, see
@evidence\/a013-finding3\/A013AcquisitionCapture-currentCheckpoint.hs@'s
@malformedDatumJson@), so the two sides are compared on the same malformed
class rather than on two different ones. It is deliberately distinct from
'malformedTxOut', which is not a decodable ledger 'TxOut' at all: the two
fail at DIFFERENT decode steps, and a repair that closes only one of them
leaves the other open.
-}
schemaMalformedCheckpointOutput :: Indexer.TxOut
schemaMalformedCheckpointOutput =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ Datum (dataToBinaryData (Data (PLC.Constr 1 []))))
  where
    Indexer.Address addrABytes = addrA
    keyHash = fromJust (hashFromBytes addrABytes)
    assetName = AssetName (SBS.toShort (deriveAidAssetName (cdCesrAid parityCheckpointDatum)))
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            ( MaryValue
                (Coin 5_000_000)
                (MultiAsset (Map.singleton unusedCheckpointPolicy (Map.singleton assetName 1)))
            )

{- | The board locator matching 'testQueryHandle''s own board identity
('addrA') and the frozen board policy every real manifest carries, so the
@boardCatalog@ family is genuinely reachable in this harness rather than
failing at 'boardLocatorOk' before any store read.
-}
parityBoardLocator :: BoardLocator
parityBoardLocator =
    BoardLocator
        { boardLocatorPolicyId = frozenEndpointBoardPolicyId
        , boardLocatorAddress = addrText addrA
        }

{- | Collapse an acquisition to "did this fail, and with which named error".

A-262-02: this used to unwrap TWO 'Either' layers, because the runner of the
day appended its own operation to the program and so reported an
interpreter-level failure outside the program's own result. The result-aware
runner flattens both layers itself -- a failure never carries a watermark it
never fetched -- so there is one layer to inspect and the family matrix
below cannot pass by looking at the wrong one.
-}
flattenAcquisition ::
    Either ChainQueryError (QuerySnapshot a) ->
    Either ChainQueryError ()
flattenAcquisition outcome = do
    _snapshot <- outcome
    pure ()

{- | One acquisition family, one malformed class, one required fail-closed
answer (INV-240-PARITY, A-017 ruling 4a).

The matrix is the module-wide property the ruling asked for rather than a
pair of point fixes: every family whose acquisition DECODES a stored output
appears here, in every malformed class that family can meet. Adding a sixth
decoding family without adding its row leaves a visibly incomplete table,
which is the point -- the fail-open shape must be hard to write by accident.

@storeWatermark@ is deliberately absent and this is its answer: it reads the
follower's own slot\/hash point and decodes no stored output, so it has no
malformed class to fail closed on. Every other family in
"Cardano.KERI.ChainQuery.Program" is covered.

Three families ('payerUtxos', 'referenceScripts', 'boardCatalog') already
fail closed by using 'traverse'; two ('currentCheckpoint',
'liveCheckpoints') used a @Right record <- [...]@ list-comprehension filter,
which silently drops an undecodable row and reports absence. Those two are
what this matrix turns red before the repair.
-}
data MalformedFamily = MalformedFamily
    { malformedFamilyName :: String
    , malformedFamilySeed :: [UtxoOp]
    , malformedFamilyAcquire ::
        forall cf op. LocalQueryScope cf op -> IO (Either ChainQueryError ())
    }

malformedFamilies :: [MalformedFamily]
malformedFamilies =
    [ MalformedFamily
        { malformedFamilyName =
            "currentCheckpoint fails closed on a schema-malformed inline datum"
        , malformedFamilySeed =
            [UtxoCreate parityCheckpointTxIn addrA schemaMalformedCheckpointOutput]
        , malformedFamilyAcquire = \scope ->
            flattenAcquisition
                <$> capAtomicQuery
                    redCapabilities
                    scope
                    (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
        }
    , MalformedFamily
        { malformedFamilyName =
            "currentCheckpoint fails closed on an undecodable stored TxOut"
        , malformedFamilySeed = [UtxoCreate parityCheckpointTxIn addrA malformedTxOut]
        , malformedFamilyAcquire = \scope ->
            flattenAcquisition
                <$> capAtomicQuery
                    redCapabilities
                    scope
                    (currentCheckpoint parityCheckpointLocator parityCheckpointAid)
        }
    , MalformedFamily
        { malformedFamilyName =
            "liveCheckpoints fails closed on a schema-malformed inline datum"
        , malformedFamilySeed =
            [UtxoCreate parityCheckpointTxIn addrA schemaMalformedCheckpointOutput]
        , malformedFamilyAcquire = \scope ->
            flattenAcquisition
                <$> capAtomicQuery redCapabilities scope (liveCheckpoints parityCheckpointLocator)
        }
    , MalformedFamily
        { malformedFamilyName =
            "liveCheckpoints fails closed on an undecodable stored TxOut"
        , malformedFamilySeed = [UtxoCreate parityCheckpointTxIn addrA malformedTxOut]
        , malformedFamilyAcquire = \scope ->
            flattenAcquisition
                <$> capAtomicQuery redCapabilities scope (liveCheckpoints parityCheckpointLocator)
        }
    , MalformedFamily
        { malformedFamilyName =
            "payerUtxos fails closed on an undecodable stored TxOut"
        , malformedFamilySeed = [UtxoCreate (sampleTxIn 0x26) addrA malformedTxOut]
        , malformedFamilyAcquire = \scope ->
            flattenAcquisition
                <$> capAtomicQuery redCapabilities scope (payerUtxos [addrText addrA])
        }
    , MalformedFamily
        { malformedFamilyName =
            "boardCatalog fails closed on an undecodable stored TxOut"
        , malformedFamilySeed = [UtxoCreate (sampleTxIn 0x27) addrA malformedTxOut]
        , malformedFamilyAcquire = \scope ->
            flattenAcquisition
                <$> capAtomicQuery redCapabilities scope (boardCatalog parityBoardLocator)
        }
    , MalformedFamily
        { malformedFamilyName =
            "referenceScripts fails closed on an undecodable stored TxOut it was not asked about"
        , malformedFamilySeed =
            [ referenceCreateAt (sampleTxIn 0x20) scriptA addrA
            , UtxoCreate (sampleTxIn 0x28) addrB malformedTxOut
            ]
        , malformedFamilyAcquire = \scope ->
            void <$> capReferenceScripts redCapabilities scope [hashA]
        }
    ]

{- | One live output at @addr@ carrying @script@ as its reference script AND
the shared non-degenerate inline datum.

A-018 finding 1: every reference fixture used to be datum-free, and the
production decoder hard-coded @chainAssetInlineDatum = Nothing@, so the two
sides agreed vacuously in exactly the dimension the decoder discarded. The
default is now datum-BEARING, so the whole reference family -- ordering,
absence, duplicates, hash mismatch, malformed rows, mixed requests, and
every entrypoint's manifest reference seed -- carries a datum that a lossy
decoder would drop.
-}
referenceCreateAt :: Indexer.TxIn -> Script ConwayEra -> Indexer.Address -> UtxoOp
referenceCreateAt txIn script addr =
    UtxoCreate txIn addr (referenceOutput script (Just referenceFixtureDatum) addr)

{- | The datum-FREE shape, kept for the frozen-base parity row that was
captured against a datum-free output ('parityExpectedReference'). Changing
that row's fixture would invalidate a capture this seat cannot re-run.
-}
referenceCreateAtWithoutDatum ::
    Indexer.TxIn -> Script ConwayEra -> Indexer.Address -> UtxoOp
referenceCreateAtWithoutDatum txIn script addr =
    UtxoCreate txIn addr (referenceOutput script Nothing addr)

referenceOutput ::
    Script ConwayEra -> Maybe PLC.Data -> Indexer.Address -> Indexer.TxOut
referenceOutput script datum (Indexer.Address bytes) =
    Indexer.TxOut $ serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash = fromJust (hashFromBytes bytes)
    plain :: TxOut ConwayEra
    plain =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            (MaryValue (Coin 100_000_000) (MultiAsset mempty))
    withScript :: TxOut ConwayEra
    withScript =
        runIdentity $
            (referenceScriptTxOutL . fromStrictMaybeL) (\_ -> Identity (Just script)) plain
    txOut :: TxOut ConwayEra
    txOut =
        case datum of
            Nothing -> withScript
            Just plutus -> withScript & datumTxOutL .~ inlineDatumOf plutus

{- | The shared reference-fixture datum: a nested value exercising every
'PLC.Data' arm a legal inline datum can carry -- a constructor wrapping
bytes, an integer, a list, and a map whose own key and value are themselves
compound. A single flat @Constr 0 []@ would be preserved by several lossy
decoders that mangle nesting.
-}
referenceFixtureDatum :: PLC.Data
referenceFixtureDatum =
    PLC.Constr
        1
        [ PLC.B "s240-reference-datum"
        , PLC.I (-9)
        , PLC.List [PLC.I 0, PLC.B "\x01\x02", PLC.Constr 0 []]
        , PLC.Map [(PLC.B "k", PLC.List [PLC.I 7])]
        ]

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
