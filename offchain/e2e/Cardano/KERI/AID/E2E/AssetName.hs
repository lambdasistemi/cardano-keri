{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.AID.E2E.AssetName
Description : Cage thread-token asset-name derivation

Mirrors the Aiken @lib.assetName@: the SHA2-256 of the consumed output
reference's transaction id concatenated with its output index encoded as
two big-endian bytes. This is the cage minting policy's uniqueness
foundation, so the offchain builder must reproduce it byte-for-byte.
-}
module Cardano.KERI.AID.E2E.AssetName (
    computeAssetName,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Crypto.Hash.Class (digest)
import Cardano.Crypto.Hash.SHA256 (SHA256)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Core (extractHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Proxy (Proxy (..))
import Data.Word (Word16)

-- | @sha2_256(tx_id ++ from_int_big_endian(output_index, 2))@.
computeAssetName :: TxIn -> ByteString
computeAssetName (TxIn (TxId h) (TxIx ix)) =
    digest (Proxy @SHA256) (txIdBytes <> indexBytes)
  where
    txIdBytes :: ByteString
    txIdBytes = hashToBytes (extractHash h)

    indexBytes :: ByteString
    indexBytes =
        let w16 = fromIntegral ix :: Word16
         in BS.pack
                [ fromIntegral (w16 `shiftR` 8)
                , fromIntegral w16
                ]
