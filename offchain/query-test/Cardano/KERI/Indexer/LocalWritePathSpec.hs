{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Indexer.LocalWritePathSpec
Description : RED T240-S1-03 -- local write-path atomicity, reference derivation, settlement

Proves T240-S1-03's three blocking properties (RQ-240-03\/04\/05\/06) through
one test-local typed adapter, 'LocalCapabilities', rather than importing
not-yet-implemented "Cardano.KERI.Indexer.ChainQuery" symbols directly
(N-007\/N-008): a missing exported symbol would make this WHOLE suite fail to
compile, which would also silently stop the base-oracle capture suites in
the same combined proof run from ever executing -- the wrong-reason failure
this design exists to rule out.

'redCapabilities' is this file's OWN RED instance of that adapter:

- 'capAtomicQuery' and 'capReferenceScripts' delegate to the REAL, already
  compiling local interface ('runLocalChainQuery', 'localInterpreter'\/
  'referenceScripts'\/'runChainQuery') exactly as it stands today. Atomicity
  already holds (T257-S2-03); reference derivation does not yet
  (DATA-INV-240-01's gap: 'localInterpreter''s 'referenceScripts' field
  unconditionally answers 'UnsupportedOperation', regardless of what the
  store holds).
- 'capSettlementObserver' and 'capTransactionSettled' have no existing
  counterpart at all (RQ-240-06). Their RED bodies are explicit, closed,
  test-local stand-ins -- \"no match, ever\" \/ \"never settled\" -- not a
  guess at future behaviour, just the honest current absence made
  observable. Every property below is proved against a NON-degenerate
  fixture (a live matching output really is in the store), so the closed
  stand-in is what makes each assertion fail today.

After implementation, GREEN is reached by eta-expanding 'redCapabilities'
into the real exported functions (@capSettlementObserver = localSettlementObserver@,
@capTransactionSettled = localTransactionSettled@, and 'capReferenceScripts'
routed through the new 'localReferenceScriptsTx' instead of the legacy
'UnsupportedOperation' path) -- the property bodies and fixtures below do not
change.

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
import Cardano.KERI.ChainQuery.Interpreter (runChainQuery)
import Cardano.KERI.ChainQuery.Program (ChainQuery, payerUtxos, referenceScripts)
import Cardano.KERI.ChainQuery.Settlement (SettlementObserver (..))
import Cardano.KERI.ChainQuery.Types (
    ChainQueryError,
    ChainReference (..),
    QuerySnapshot (..),
 )
import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript, scriptHashText)
import Cardano.KERI.Indexer.ChainQuery (localInterpreter, runLocalChainQuery)
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
        QueryHandle cf op ->
        ChainQuery a ->
        IO (Either ChainQueryError (QuerySnapshot a))
    -- ^ RQ-240-03\/04: one program, one store transaction, one watermark.
    , capReferenceScripts ::
        QueryHandle cf op -> [Text] -> IO (Either ChainQueryError [ChainReference])
    -- ^ RQ-240-05\/DATA-INV-240-01: derived reference resolution.
    , capSettlementObserver :: QueryHandle cf op -> SettlementObserver IO
    -- ^ RQ-240-06: follower-backed asset settlement probe.
    , capTransactionSettled :: QueryHandle cf op -> TxId -> IO Bool
    -- ^ RQ-240-06: follower-backed exact-transaction settlement probe.
    }

{- | This file's RED instance. 'capAtomicQuery'\/'capReferenceScripts'
delegate to the real, already-compiling local interface exactly as it
stands today (one already correct, one not yet). 'capSettlementObserver'\/
'capTransactionSettled' have no existing counterpart, so their bodies are
explicit closed stand-ins -- never a guess, just today's honest absence.
-}
redCapabilities :: LocalCapabilities cf op
redCapabilities =
    LocalCapabilities
        { capAtomicQuery = runLocalChainQuery
        , capReferenceScripts = \handle hashes ->
            -- 'referenceScripts' itself already answers 'Either
            -- ChainQueryError [ChainReference]' (DATA-INV-240-01's own inner
            -- candidate-resolution layer); 'runChainQuery' adds the outer
            -- OPERATION-failure 'Either'. Flatten to the one 'Either' this
            -- adapter's field promises -- a real operation failure and a
            -- real resolution failure are both "this call did not
            -- succeed" from this adapter's caller's point of view.
            either Left id
                <$> runTransaction
                    (qhRunner handle)
                    (runChainQuery (localInterpreter handle) (referenceScripts hashes))
        , capSettlementObserver = \_handle -> SettlementObserver (\_policy _assetName -> pure [])
        , capTransactionSettled = \_handle _txId -> pure False
        }

spec :: Spec
spec = describe "Cardano.KERI.Indexer.ChainQuery local write-path capabilities (#240 S240-1)" $ do
    describe "RQ-240-03/04 -- atomic local runner, one transaction per program" $
        it "capAtomicQuery invokes the transaction runner exactly once for a whole program" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x10) addrA]
                counter <- newIORef (0 :: Int)
                let scope = testQueryHandle (countingRunner counter runner)
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
                result <- capReferenceScripts redCapabilities (testQueryHandle runner) [hashA]
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
                let observer = capSettlementObserver redCapabilities (testQueryHandle runner)
                matches <- probeSettlement observer policyHexA assetNameHexA
                case matches of
                    [_one] -> pure ()
                    other -> expectationFailure ("RED: expected the one live matching asset output, got " <> show (length other))

        it "capTransactionSettled should reflect a live tracked output of the exact tx id, not the closed False stand-in" $
            withInMemoryIndexerRunner $ \handle runner -> do
                applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate targetTxIn addrA]
                settled <- capTransactionSettled redCapabilities (testQueryHandle runner) targetTxId
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

-- | One live output at @addr@ carrying exactly one unit of a fixed
-- (policy, asset name) native asset -- 'policyHexA'\/'assetNameHexA'.
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
