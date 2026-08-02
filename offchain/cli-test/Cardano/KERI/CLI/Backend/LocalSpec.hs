{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.CLI.Backend.LocalSpec
Description : #177 Slice 1 T177-S1-3 local mutation/rollback coherence (RED)

Mirrors "Cardano.KERI.Indexer.Query.ServerSpec"'s fixture shape (same
'withInMemoryIndexerRunner' upstream indexer, same inline-datum checkpoint
output construction) against the new local 'QueryBackend' adapter instead of
the HTTP layer.
-}
module Cardano.KERI.CLI.Backend.LocalSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (V1), CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.CLI.Backend (
    CheckpointFields (..),
    Freshness (..),
    StatusView (..),
    runBackendStatus,
 )
import Cardano.KERI.CLI.Backend.Local (mkLocalBackend)
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), dataToBinaryData)
import Cardano.Ledger.Api.Tx.Out (datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (IndexerHandle (..), UtxoOp (..), applyAtSlot, withInMemoryIndexerRunner)
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent.STM (STM, retry)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Lens.Micro ((.~))
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "local backend mutation/rollback coherence (T177-S1-3)" $ do
    it "reflects a fresh mutation immediately, with as_of_slot at the transaction watermark" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x01 [checkpointCreate (sampleTxIn 0x10) aidX datumX0]
            let backend = mkLocalBackend (QueryHandle runner checkpointAddress checkpointPolicy boardAddress undefinedReadiness)
            Right view <- runBackendStatus backend (renderAid aidX)
            svFreshness view `shouldBe` Freshness (Just 100) Nothing
            fmap cfSequence (svCheckpoint view) `shouldBe` Just 0

    it "reflects a second mutation (rotation) without a stale/cached first answer" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x01 [checkpointCreate (sampleTxIn 0x10) aidX datumX0]
            applyBatch
                handle
                200
                0x02
                [ UtxoSpend (sampleTxIn 0x10)
                , checkpointCreate (sampleTxIn 0x20) aidX datumX1
                ]
            let backend = mkLocalBackend (QueryHandle runner checkpointAddress checkpointPolicy boardAddress undefinedReadiness)
            Right view <- runBackendStatus backend (renderAid aidX)
            svFreshness view `shouldBe` Freshness (Just 200) Nothing
            fmap cfSequence (svCheckpoint view) `shouldBe` Just 1

    it "a rollback removes the mutation immediately, with as_of_slot at the rolled-back watermark" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 10 0x02 []
            applyBatch handle 100 0x01 [checkpointCreate (sampleTxIn 0x10) aidX datumX0]
            rollbackTo handle (Indexer.SlotNo 10)
            let backend = mkLocalBackend (QueryHandle runner checkpointAddress checkpointPolicy boardAddress undefinedReadiness)
            Right view <- runBackendStatus backend (renderAid aidX)
            svCheckpoint view `shouldBe` Nothing
            svFreshness view `shouldBe` Freshness (Just 10) Nothing

-- ---------------------------------------------------------------------------
-- Fixtures (mirrors Query.ServerSpec's shape; not shared/exported cross-module)

aidX :: ByteString
aidX = BS.replicate 32 0x31

renderAid :: ByteString -> Text
renderAid = TE.decodeUtf8 . qb64Aid

datumX0 :: CheckpointDatumV1
datumX0 =
    CheckpointDatumV1
        { cdCesrAid = aidX
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }

datumX1 :: CheckpointDatumV1
datumX1 = datumX0{cdSeq = 1, cdNativeSn = 1}

checkpointPolicy :: PolicyID
checkpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just h -> h
                Nothing -> error "LocalSpec: invalid checkpoint policy id width"

checkpointLedgerAddress :: Addr
checkpointLedgerAddress =
    let PolicyID scriptHash = checkpointPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

checkpointAddress :: Indexer.Address
checkpointAddress = Indexer.Address (serialiseAddr checkpointLedgerAddress)

boardAddress :: Indexer.Address
boardAddress = Indexer.Address (serialiseAddr (Addr Testnet (ScriptHashObj (ScriptHash (case hashFromBytes (BS.replicate 28 0x51) of Just h -> h; Nothing -> error "LocalSpec: invalid board policy id width"))) StakeRefNull))

{- | 'QueryHandle.qhReadiness' is a strict field, so a bottom placeholder
would throw the instant a 'QueryHandle' is constructed — before
'mkLocalBackend' ever gets a chance not to read it. 'retry' is a total,
never-forced-to-run STM value: fine as a placeholder because the local
backend's implementation is reviewed to never call it, not because touching
it would crash.
-}
undefinedReadiness :: STM a
undefinedReadiness = retry

checkpointCreate :: Indexer.TxIn -> ByteString -> CheckpointDatumV1 -> UtxoOp
checkpointCreate txIn aid datum =
    UtxoCreate txIn checkpointAddress (checkpointOutput aid datum)

checkpointOutput :: ByteString -> CheckpointDatumV1 -> Indexer.TxOut
checkpointOutput aid datum =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (plutusData (V1 datum)))
  where
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            checkpointLedgerAddress
            ( MaryValue
                (Coin 5_000_000)
                ( MultiAsset $
                    Map.singleton
                        checkpointPolicy
                        (Map.singleton (AssetName . SBS.toShort $ deriveAidAssetName aid) 1)
                )
            )

inlineDatum :: PLC.Data -> Datum ConwayEra
inlineDatum datum = Datum (dataToBinaryData (Data datum))

plutusData :: (ToData a) => a -> PLC.Data
plutusData value =
    let BuiltinData datum = toBuiltinData value
     in datum

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte) 0

applyBatch :: IndexerHandle -> Int -> Word8 -> [UtxoOp] -> IO ()
applyBatch handle slot hashByte =
    applyAtSlot handle (Indexer.SlotNo (fromIntegral slot)) (blockHash hashByte)

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)
