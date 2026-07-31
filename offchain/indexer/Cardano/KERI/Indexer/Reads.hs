{- |
Module      : Cardano.KERI.Indexer.Reads
Description : Derived checkpoint reads over the upstream live UTxO store

Consumes 'Cardano.Node.Client.UTxOIndexer.Indexer.IndexerHandle' snapshots and
resume points, plus raw values from
'Cardano.Node.Client.UTxOIndexer.Types'. Checkpoint decoding is delegated to
'Cardano.KERI.Indexer.Codecs'.
-}
module Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
    liveCheckpoints,
    liveCheckpointsWithRejects,
    checkpointForAid,
    storePoint,
    payerUtxos,
) where

import Cardano.KERI.Indexer.Codecs (
    CheckpointDecodeError,
    CheckpointRecord (..),
    decodeCheckpointOutput,
 )
import Cardano.Ledger.Mary.Value (
    PolicyID,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
    BlockHash,
    SlotNo,
    TxIn,
    TxOut,
 )
import Data.ByteString (
    ByteString,
 )
import Data.Either (
    partitionEithers,
 )
import Data.List (
    find,
 )
import Data.Maybe (
    listToMaybe,
 )

-- | Everything a read needs: the store handle plus the deployment's identity.
data CheckpointView = CheckpointView
    { cvHandle :: !IndexerHandle
    , cvAddress :: !Address
    -- ^ The deployment's checkpoint address.
    , cvPolicy :: !PolicyID
    -- ^ The deployment's checkpoint policy.
    }

-- | Every live checkpoint, decoded. Non-checkpoint outputs are dropped.
liveCheckpoints :: CheckpointView -> IO [CheckpointRecord]
liveCheckpoints view =
    fst <$> liveCheckpointsWithRejects view

-- | Every live checkpoint plus every rejected output and its decode error.
liveCheckpointsWithRejects ::
    CheckpointView ->
    IO ([CheckpointRecord], [(TxIn, CheckpointDecodeError)])
liveCheckpointsWithRejects CheckpointView{..} = do
    entries <- snapshotAt cvHandle cvAddress
    let (rejected, accepted) =
            partitionEithers $
                fmap decodeEntry entries
    pure (accepted, rejected)
  where
    decodeEntry (txIn, txOut) =
        case decodeCheckpointOutput cvPolicy txIn cvAddress txOut of
            Left decodeError -> Left (txIn, decodeError)
            Right record -> Right record

-- | Look up the live checkpoint for a raw, E-code-stripped 32-byte AID.
checkpointForAid ::
    CheckpointView ->
    ByteString ->
    IO (Maybe CheckpointRecord)
checkpointForAid view aid =
    find ((== aid) . crAid) <$> liveCheckpoints view

-- | Read the store's current chain point, if the store is non-empty.
storePoint :: CheckpointView -> IO (Maybe (SlotNo, BlockHash))
storePoint CheckpointView{cvHandle} =
    listToMaybe <$> getResumePoints cvHandle

{- | Return every live UTxO at a payer address without checkpoint decoding.

The result is deliberately raw because its consumer is a coin selector, which
needs the original inputs and outputs for fees, collateral, and min-ADA rather
than checkpoint-shaped records.
-}
payerUtxos :: IndexerHandle -> Address -> IO [(TxIn, TxOut)]
payerUtxos = snapshotAt
