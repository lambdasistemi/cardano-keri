{- |
Module      : Cardano.KERI.Indexer.Query.TxSpec
Description : #181 Slice 1 — coherent plural payer address reads

Focused proof for @specs\/181-no-cardano-cli\/plan.md@: plural payer
addresses must be scanned through exactly one engine transaction, reusing the
sole 'Cardano.KERI.Indexer.Query.Tx.scanAddressTx' cursor walk, and the
resulting candidate set must be independent of address order or duplication.
'Cardano.KERI.Indexer.Query.Tx.payerUtxosTxAcrossAddresses' composes that scan and is proven
green here (gate v3, sha256
175b6e638eeb14b2952250559ba39f8c64f6be5b4ca1572dae704ceb2ba6d63e).
-}
module Cardano.KERI.Indexer.Query.TxSpec (spec) where

import Cardano.KERI.Indexer.Query.Tx (payerUtxosTxAcrossAddresses)
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.ByteString qualified as BS
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (sortOn)
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction (..))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "payerUtxosTxAcrossAddresses (#181 Slice 1, FR-2)" $ do
    it "reads plural payer addresses in one engine transaction" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 10 0x01 [payerCreate (sampleTxIn 0x10) addrA]
            applyBatch handle 11 0x02 [payerCreate (sampleTxIn 0x20) addrB]
            counter <- newIORef (0 :: Int)
            let counting = countingRunner counter runner
            result <-
                runTransaction counting (payerUtxosTxAcrossAddresses [addrA, addrB])
            count <- readIORef counter
            count `shouldBe` 1
            sortOn fst result
                `shouldBe` sortOn
                    fst
                    [ (sampleTxIn 0x10, payerOutput addrA)
                    , (sampleTxIn 0x20, payerOutput addrB)
                    ]

    it "does not split payer snapshot by address" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 10 0x03 [payerCreate (sampleTxIn 0x30) addrA]
            applyBatch handle 11 0x04 [payerCreate (sampleTxIn 0x31) addrB]
            direct <- runTransaction runner (payerUtxosTxAcrossAddresses [addrA, addrB])
            permuted <- runTransaction runner (payerUtxosTxAcrossAddresses [addrB, addrA])
            duplicated <-
                runTransaction runner (payerUtxosTxAcrossAddresses [addrA, addrA, addrB])
            sortOn fst permuted `shouldBe` sortOn fst direct
            sortOn fst duplicated `shouldBe` sortOn fst direct

    it "returns no candidates for an empty address list inside one call" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 10 0x05 [payerCreate (sampleTxIn 0x40) addrA]
            counter <- newIORef (0 :: Int)
            let counting = countingRunner counter runner
            result <- runTransaction counting (payerUtxosTxAcrossAddresses [])
            count <- readIORef counter
            count `shouldBe` 1
            result `shouldBe` []

countingRunner ::
    IORef Int ->
    RunTransaction IO cf Cols op ->
    RunTransaction IO cf Cols op
countingRunner counter runner =
    RunTransaction
        { runTransaction = \tx -> do
            atomicModifyIORef' counter (\n -> (n + 1, ()))
            runTransaction runner tx
        }

payerCreate :: Indexer.TxIn -> Indexer.Address -> UtxoOp
payerCreate txIn addr = UtxoCreate txIn addr (payerOutput addr)

payerOutput :: Indexer.Address -> Indexer.TxOut
payerOutput (Indexer.Address bytes) = Indexer.TxOut ("payer-utxo:" <> bytes)

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte) 0

addrA :: Indexer.Address
addrA = Indexer.Address (BS.replicate 28 0xA1)

addrB :: Indexer.Address
addrB = Indexer.Address (BS.replicate 28 0xB2)

applyBatch :: IndexerHandle -> Int -> Word8 -> [UtxoOp] -> IO ()
applyBatch handle slot hashByte =
    applyAtSlot handle (Indexer.SlotNo (fromIntegral slot)) (blockHash hashByte)

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)
