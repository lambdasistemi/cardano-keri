{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.ReadsSpec (spec) where

import Cardano.Crypto.Hash.Class (
    hashFromBytes,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Cardano.KERI.Indexer.Codecs (
    CheckpointDecodeError (..),
    CheckpointRecord (..),
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
    checkpointForAid,
    liveCheckpoints,
    liveCheckpointsWithRejects,
    payerUtxos,
    storePoint,
 )
import Cardano.Ledger.Address (
    Addr (..),
    serialiseAddr,
 )
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    dataToBinaryData,
 )
import Cardano.Ledger.Api.Tx.Out (
    datumTxOutL,
    mkBasicTxOut,
 )
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
 )
import Cardano.Ledger.Binary (
    serialize',
 )
import Cardano.Ledger.Coin (
    Coin (..),
 )
import Cardano.Ledger.Conway (
    ConwayEra,
 )
import Cardano.Ledger.Core (
    eraProtVerLow,
 )
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (
    ScriptHash (..),
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexer,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function (
    (&),
 )
import Data.List (
    sortOn,
 )
import Data.Map.Strict qualified as Map
import Data.Word (
    Word16,
    Word64,
    Word8,
 )
import Lens.Micro (
    (.~),
 )
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.KERI.Indexer.Reads" $ do
    it "round-trips one live checkpoint and looks it up by AID" $
        withInMemoryIndexer $ \handle -> do
            let txIn = sampleTxIn 0x51 0
                record = checkpointRecord txIn aidX datumX0
                view = checkpointView handle
            applyBatch handle 1 0x81 [checkpointCreate txIn aidX datumX0]

            liveCheckpoints view `shouldReturnIO` [record]
            checkpointForAid view aidX `shouldReturnIO` Just record
            checkpointForAid view unknownAid `shouldReturnIO` Nothing

    it "removes a checkpoint when its carrying UTxO is spent" $
        withInMemoryIndexer $ \handle -> do
            let txIn = sampleTxIn 0x52 0
                record = checkpointRecord txIn aidX datumX0
                view = checkpointView handle
            applyBatch handle 1 0x82 [checkpointCreate txIn aidX datumX0]
            liveCheckpoints view `shouldReturnIO` [record]

            applyBatch handle 2 0x83 [UtxoSpend txIn]
            liveCheckpoints view `shouldReturnIO` []
            checkpointForAid view aidX `shouldReturnIO` Nothing

    it "keeps a valid neighbour and reports a non-checkpoint as NoInlineDatum" $
        withInMemoryIndexer $ \handle -> do
            let goodTxIn = sampleTxIn 0x53 0
                badTxIn = sampleTxIn 0x54 0
                record = checkpointRecord goodTxIn aidX datumX0
                badOutput = plainOutput checkpointLedgerAddress 3_000_000
                view = checkpointView handle
            applyBatch
                handle
                1
                0x84
                [ checkpointCreate goodTxIn aidX datumX0
                , UtxoCreate badTxIn checkpointAddress badOutput
                ]

            liveCheckpoints view `shouldReturnIO` [record]
            (accepted, rejected) <- liveCheckpointsWithRejects view
            accepted `shouldBe` [record]
            rejected `shouldBe` [(badTxIn, NoInlineDatum)]

    it "advances one AID without retaining its spent checkpoint" $
        withInMemoryIndexer $ \handle -> do
            let oldTxIn = sampleTxIn 0x55 0
                newTxIn = sampleTxIn 0x56 0
                oldRecord = checkpointRecord oldTxIn aidX datumX0
                newRecord = checkpointRecord newTxIn aidX datumX1
                view = checkpointView handle
            applyBatch handle 1 0x85 [checkpointCreate oldTxIn aidX datumX0]
            liveCheckpoints view `shouldReturnIO` [oldRecord]

            applyBatch
                handle
                2
                0x86
                [ UtxoSpend oldTxIn
                , checkpointCreate newTxIn aidX datumX1
                ]
            liveCheckpoints view `shouldReturnIO` [newRecord]
            checkpointForAid view aidX `shouldReturnIO` Just newRecord

    it "keeps two AIDs independently live without relying on scan order" $
        withInMemoryIndexer $ \handle -> do
            let txInX = sampleTxIn 0x72 0
                txInY = sampleTxIn 0x61 0
                recordX = checkpointRecord txInX aidX datumX0
                recordY = checkpointRecord txInY aidY datumY0
                view = checkpointView handle
            applyBatch
                handle
                1
                0x87
                [ checkpointCreate txInX aidX datumX0
                , checkpointCreate txInY aidY datumY0
                ]

            records <- liveCheckpoints view
            sortOn crAid records `shouldBe` sortOn crAid [recordX, recordY]
            checkpointForAid view aidX `shouldReturnIO` Just recordX
            checkpointForAid view aidY `shouldReturnIO` Just recordY

    it "reads Nothing for an empty store and the newest of two store points" $
        withInMemoryIndexer $ \handle -> do
            let view = checkpointView handle
                newestPoint = (Indexer.SlotNo 9, blockHash 0x92)
            storePoint view `shouldReturnIO` Nothing

            applyBatch handle 4 0x91 []
            applyBatch handle 9 0x92 []
            storePoint view `shouldReturnIO` Just newestPoint

    it "returns exact raw payer UTxOs, removes spends, and excludes other addresses" $
        withInMemoryIndexer $ \handle -> do
            let payer = Indexer.Address (BS.replicate 29 0xA1)
                other = Indexer.Address (BS.replicate 29 0xA2)
                kept = (sampleTxIn 0x63 0, Indexer.TxOut "payer-kept-raw")
                spent = (sampleTxIn 0x64 1, Indexer.TxOut "payer-spent-raw")
                otherPair = (sampleTxIn 0x65 2, Indexer.TxOut "other-raw")
            applyBatch
                handle
                1
                0x88
                [ createAt payer kept
                , createAt payer spent
                , createAt other otherPair
                ]
            payerUtxos handle payer `shouldReturnIO` [kept, spent]

            applyBatch handle 2 0x89 [UtxoSpend (fst spent)]
            payerUtxos handle payer `shouldReturnIO` [kept]

shouldReturnIO :: (Eq a, Show a) => IO a -> a -> IO ()
shouldReturnIO action expected = action >>= (`shouldBe` expected)

createAt :: Indexer.Address -> (Indexer.TxIn, Indexer.TxOut) -> UtxoOp
createAt address (txIn, txOut) = UtxoCreate txIn address txOut

applyBatch :: IndexerHandle -> Word64 -> Word8 -> [UtxoOp] -> IO ()
applyBatch handle slot hashByte =
    applyAtSlot
        handle
        (Indexer.SlotNo slot)
        (blockHash hashByte)

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)

checkpointView :: IndexerHandle -> CheckpointView
checkpointView handle =
    CheckpointView
        { cvHandle = handle
        , cvAddress = checkpointAddress
        , cvPolicy = checkpointPolicy
        }

checkpointCreate ::
    Indexer.TxIn ->
    ByteString ->
    CheckpointDatumV1 ->
    UtxoOp
checkpointCreate txIn aid datum =
    UtxoCreate
        txIn
        checkpointAddress
        (checkpointOutput aid datum)

checkpointRecord ::
    Indexer.TxIn ->
    ByteString ->
    CheckpointDatumV1 ->
    CheckpointRecord
checkpointRecord txIn aid datum =
    CheckpointRecord
        { crAid = aid
        , crAssetName = deriveAidAssetName aid
        , crTxIn = txIn
        , crAddress = checkpointAddress
        , crDatum = datum
        }

checkpointOutput :: ByteString -> CheckpointDatumV1 -> Indexer.TxOut
checkpointOutput aid datum =
    encodeOutput
        checkpointLedgerAddress
        5_000_000
        ( Map.singleton
            checkpointPolicy
            (Map.singleton (AssetName . SBS.toShort $ deriveAidAssetName aid) 1)
        )
        (inlineDatum . plutusData $ V1 datum)

plainOutput :: Addr -> Integer -> Indexer.TxOut
plainOutput address lovelace =
    encodeOutput address lovelace mempty NoDatum

encodeOutput ::
    Addr ->
    Integer ->
    Map.Map PolicyID (Map.Map AssetName Integer) ->
    Datum ConwayEra ->
    Indexer.TxOut
encodeOutput address lovelace assets datum =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            ( mkBasicTxOut
                address
                (MaryValue (Coin lovelace) (MultiAsset assets))
                & datumTxOutL .~ datum
            )

inlineDatum :: PLC.Data -> Datum ConwayEra
inlineDatum datum = Datum (dataToBinaryData $ Data datum)

plutusData :: (ToData a) => a -> PLC.Data
plutusData value =
    let BuiltinData datum = toBuiltinData value
     in datum

datumX0, datumX1, datumY0 :: CheckpointDatumV1
datumX0 = checkpointDatum aidX 0
datumX1 = checkpointDatum aidX 1
datumY0 = checkpointDatum aidY 0

checkpointDatum :: ByteString -> Integer -> CheckpointDatumV1
checkpointDatum aid sequenceNumber =
    CheckpointDatumV1
        { cdCesrAid = aid
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = sequenceNumber
        , cdNativeSn = 0
        }

aidX, aidY, unknownAid :: ByteString
aidX = BS.replicate 32 0x31
aidY = BS.replicate 32 0x32
unknownAid = BS.replicate 32 0x33

checkpointPolicy :: PolicyID
checkpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just hash -> hash
                Nothing -> error "invalid policy id width"

checkpointLedgerAddress :: Addr
checkpointLedgerAddress =
    let PolicyID scriptHash = checkpointPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

checkpointAddress :: Indexer.Address
checkpointAddress = Indexer.Address (serialiseAddr checkpointLedgerAddress)

sampleTxIn :: Word8 -> Word16 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte)
