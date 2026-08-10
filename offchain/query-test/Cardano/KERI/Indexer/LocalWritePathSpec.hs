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

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.ChainQuery.Program (ChainQuery, payerUtxos)
import Cardano.KERI.ChainQuery.Settlement (SettlementObserver (..))
import Cardano.KERI.ChainQuery.Types (
    ChainQueryError,
    ChainReference (..),
    QuerySnapshot (..),
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
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Body (referenceScriptTxOutL)
import Cardano.Ledger.Api.Tx.Out (mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, TxOut, eraProtVerLow, fromStrictMaybeL)
import Cardano.Ledger.Credential (Credential (KeyHashObj), StakeReference (StakeRefNull))
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
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Functor.Identity (Identity (..), runIdentity)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction (..))
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
  where
    targetTxIn = sampleTxIn 0x30
    targetTxId = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0x30))))

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
