{- |
Module      : Cardano.KERI.Indexer.Query.Tx
Description : One-store-transaction composed reads for the query endpoint

FR-2/FR-3: each composed response reads its checkpoint\/board inputs and the
rollback-log watermark inside exactly one @kv-transactions@ transaction.
'watermarkTx' reads the highest key currently in @RollbackCol@ — the
store's own watermark — never
'Cardano.Node.Client.UTxOIndexer.Follower.Readiness.rProcessedSlot' (see the
module haddock on "Cardano.KERI.Indexer.Query.Server" for why that TVar is
the wrong source). 'scanAddressTx' duplicates the small private cursor walk
also found (twice, unexported) in the pinned node-clients
@Provider.hs@\/@Indexer.hs@ — both are private to their own modules, so this
is a minimal, unavoidable rewrite against the public 'Cols'\/'AddrKey'
surface, not a copy of anything this package could import.
-}
module Cardano.KERI.Indexer.Query.Tx (
    QueryHandle (..),
    scanAddressTx,
    payerUtxosTx,
    watermarkTx,
    checkpointTx,
    listCheckpointsTx,
    payerUtxosTx,
    boardTx,
    watchabilityTx,
) where

import Cardano.KERI.Deployment.EndpointBoard (BoardEntry)
import Cardano.KERI.Indexer.Board (indexedBoardCatalog)
import Cardano.KERI.Indexer.Codecs (
    CheckpointRecord (..),
    decodeCheckpointOutput,
 )
import Cardano.Ledger.Mary.Value (PolicyID)
import Cardano.Node.Client.UTxOIndexer.Columns (Cols (..))
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness)
import Cardano.Node.Client.UTxOIndexer.Types (
    AddrKey (..),
    Address,
    SlotNo,
    TxIn (..),
    TxOut,
 )
import Control.Concurrent.STM (STM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (rights)
import Data.List (find, nub, sortOn)
import Database.KV.Cursor (Entry (..), lastEntry, nextEntry, seekKey)
import Database.KV.Transaction (RunTransaction, Transaction, iterating)

{- | Everything a composed query response needs: one transaction runner, the
deployment's checkpoint\/board identity, and a non-transactional readiness
sample (readiness is sampled /after/ the transaction commits — see
'Cardano.KERI.Indexer.Query.Server').
-}
data QueryHandle cf op = QueryHandle
    { qhRunner :: !(RunTransaction IO cf Cols op)
    , qhCheckpointAddress :: !Address
    , qhCheckpointPolicy :: !PolicyID
    , qhBoardAddress :: !Address
    , qhReadiness :: !(STM Readiness)
    }

{- | Every indexed @(TxIn, TxOut)@ currently live at an address, in ascending
'TxIn' order. Mirrors the private cursor walk in the pinned node-clients
@Indexer.hs@\/@Provider.hs@ 'scanAddress' functions exactly.
-}
scanAddressTx ::
    Address -> Transaction IO cf Cols op [(TxIn, TxOut)]
scanAddressTx addr = iterating AddressIndex (seekKey seekTo >>= go [])
  where
    seekTo = AddrKey addr (TxIn (BS.replicate 32 0) 0)
    go acc Nothing = pure (reverse acc)
    go acc (Just Entry{entryKey = key, entryValue = value})
        | addrKeyAddress key == addr =
            nextEntry >>= go ((addrKeyTxIn key, value) : acc)
        | otherwise = pure (reverse acc)

{- | Every live UTxO across several payer addresses, gathered in exactly one
engine transaction by composing 'scanAddressTx' per deduplicated address.
The combined result is sorted by 'TxIn' so that operand order or duplicate
address configuration cannot change the selected candidate set (FR-2).
-}
payerUtxosTx ::
    [Address] -> Transaction IO cf Cols op [(TxIn, TxOut)]
payerUtxosTx addrs = do
    scanned <- traverse scanAddressTx (nub addrs)
    pure (sortOn fst (concat scanned))

{- | The store's own freshness watermark: the highest 'SlotNo' key currently
in @RollbackCol@ (both restoration and following rows are keyed by slot, so
this is the latest slot the store has recorded /anything/ for — not
'Cardano.Node.Client.UTxOIndexer.Follower.Readiness.rProcessedSlot', which a
rollback can leave stale ahead of the store per FR-3). 'Nothing' means a cold
store with no rollback-log entries yet.
-}
watermarkTx :: Transaction IO cf Cols op (Maybe SlotNo)
watermarkTx = fmap entryKey <$> iterating RollbackCol lastEntry

{- | The composed checkpoint read: matching live checkpoints for the exact
AID (decode failures on unrelated outputs at the same address are dropped,
exactly like 'Cardano.KERI.Indexer.Reads.liveCheckpoints') plus the store
watermark, in one transaction.
-}
checkpointTx ::
    QueryHandle cf op ->
    ByteString ->
    Transaction IO cf Cols op (Maybe CheckpointRecord, Maybe SlotNo)
checkpointTx handle aid = do
    entries <- scanAddressTx (qhCheckpointAddress handle)
    let decoded =
            rights
                [ decodeCheckpointOutput
                    (qhCheckpointPolicy handle)
                    txIn
                    (qhCheckpointAddress handle)
                    txOut
                | (txIn, txOut) <- entries
                ]
    watermark <- watermarkTx
    pure (find ((== aid) . crAid) decoded, watermark)

-- | Decode every live checkpoint and read the store watermark atomically.
listCheckpointsTx ::
    QueryHandle cf op ->
    Transaction IO cf Cols op ([CheckpointRecord], Maybe SlotNo)
listCheckpointsTx handle = do
    entries <- scanAddressTx (qhCheckpointAddress handle)
    let decoded =
            rights
                [ decodeCheckpointOutput
                    (qhCheckpointPolicy handle)
                    txIn
                    (qhCheckpointAddress handle)
                    txOut
                | (txIn, txOut) <- entries
                ]
    watermark <- watermarkTx
    pure (decoded, watermark)

-- | Read payer UTxOs and the store watermark in the same transaction.
payerUtxosTx ::
    QueryHandle cf op ->
    Address ->
    Transaction IO cf Cols op ([(TxIn, TxOut)], Maybe SlotNo)
payerUtxosTx _handle address = do
    utxos <- scanAddressTx address
    watermark <- watermarkTx
    pure (utxos, watermark)

{- | The composed board read: the authenticated catalog (or the fail-closed
'Left' from 'indexedBoardCatalog') plus the store watermark, in one
transaction.
-}
boardTx ::
    QueryHandle cf op ->
    Transaction IO cf Cols op (Either String [BoardEntry], Maybe SlotNo)
boardTx handle = do
    entries <- scanAddressTx (qhBoardAddress handle)
    watermark <- watermarkTx
    pure (indexedBoardCatalog (qhBoardAddress handle) entries, watermark)

{- | The composed watchability read: both the checkpoint-address scan and the
board-address scan, plus the watermark, in one transaction (FR-2's
explicit "watchability reads both addresses in that same transaction").
-}
watchabilityTx ::
    QueryHandle cf op ->
    ByteString ->
    Transaction
        IO
        cf
        Cols
        op
        (Maybe CheckpointRecord, Either String [BoardEntry], Maybe SlotNo)
watchabilityTx handle aid = do
    checkpointEntries <- scanAddressTx (qhCheckpointAddress handle)
    let decodedCheckpoints =
            rights
                [ decodeCheckpointOutput
                    (qhCheckpointPolicy handle)
                    txIn
                    (qhCheckpointAddress handle)
                    txOut
                | (txIn, txOut) <- checkpointEntries
                ]
    boardEntries <- scanAddressTx (qhBoardAddress handle)
    watermark <- watermarkTx
    pure
        ( find ((== aid) . crAid) decodedCheckpoints
        , indexedBoardCatalog (qhBoardAddress handle) boardEntries
        , watermark
        )
