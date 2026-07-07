{- |
Module      : Cardano.AID.Cage.Sign
Description : Value-write message construction and Ed25519 signing
License     : Apache-2.0

Constructs the domain-tagged message for AID owner authorization
and signs it with an Ed25519 key. The signed message binds to the
request UTxO's output reference, providing replay protection.
-}
module Cardano.AID.Cage.Sign
    ( -- * Domain tag
      valueWriteDomain

      -- * Message construction
    , valueWriteMessage

      -- * Signing
    , signValueWrite
    ) where

import Cardano.Crypto.DSIGN
    ( SignKeyDSIGN
    , rawSerialiseSigDSIGN
    , signDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Crypto.Hash.Blake2b
    ( Blake2b_256
    )
import Cardano.Crypto.Hash.Class
    ( digest
    )
import Data.Bits
    ( shiftR
    , (.&.)
    )
import Data.ByteString
    ( ByteString
    )
import qualified Data.ByteString as BS
import Data.Proxy
    ( Proxy (..)
    )

-- | Domain separator for value-write authorization messages.
valueWriteDomain :: ByteString
valueWriteDomain = "cardano-aid/value-write/v1"

{- | Build the message to sign:
@blake2b_256(domain ++ tx_id ++ be2(output_index))@.

The 2-byte big-endian output index matches Aiken's
@from_int_big_endian(output_index, 2)@.
-}
valueWriteMessage
    :: ByteString
    -- ^ Transaction id (32 bytes)
    -> Integer
    -- ^ Output index within the transaction
    -> ByteString
    -- ^ 32-byte blake2b_256 digest
valueWriteMessage txId idx =
    let hi = fromIntegral (idx `shiftR` 8 .&. 0xFF)
        lo = fromIntegral (idx .&. 0xFF)
        payload = valueWriteDomain <> txId <> BS.pack [hi, lo]
     in digest (Proxy @Blake2b_256) payload

{- | Sign a value-write authorization for a given request UTxO.

Returns the 64-byte raw Ed25519 signature.
-}
signValueWrite
    :: SignKeyDSIGN Ed25519DSIGN
    -- ^ Signing key
    -> ByteString
    -- ^ Transaction id of the request UTxO (32 bytes)
    -> Integer
    -- ^ Output index of the request UTxO
    -> ByteString
    -- ^ Raw 64-byte Ed25519 signature
signValueWrite sk txId idx =
    rawSerialiseSigDSIGN $ signDSIGN () (valueWriteMessage txId idx) sk
