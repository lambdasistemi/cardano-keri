module Main (main) where

import Cardano.AID.Cage.Sign (valueWriteMessage)
import Cardano.Crypto.DSIGN
    ( SignKeyDSIGN
    , deriveVerKeyDSIGN
    , genKeyDSIGN
    , rawSerialiseSigDSIGN
    , rawSerialiseVerKeyDSIGN
    , signDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Hash.Blake2b (Blake2b_256)
import Cardano.Crypto.Hash.Class (digest)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Proxy (Proxy (..))
import Numeric (showHex)
import Data.Word (Word8)

blake :: ByteString -> ByteString
blake = digest (Proxy @Blake2b_256)

-- Aiken MPF combine: blake2b_256(a ++ b)
combine :: ByteString -> ByteString -> ByteString
combine a b = blake (a <> b)

-- Aiken MPF suffix(path, cursor=0): [0xff] ++ path  (cursor even, push prepends)
suffix0 :: ByteString -> ByteString
suffix0 path = BS.cons 0xff path

-- Identity trie root for a single-element trie:
-- root = combine(suffix(blake2b_256(owner_aid), 0), blake2b_256(blake2b_256(owner_key)))
identityRoot :: ByteString -> ByteString -> ByteString
identityRoot ownerAid ownerKey =
    combine (suffix0 (blake ownerAid)) (blake (blake ownerKey))

toHex :: ByteString -> String
toHex bs = concatMap showByte (BS.unpack bs)
  where
    showByte :: Word8 -> String
    showByte w =
        let s = showHex w ""
        in if length s == 1 then '0' : s else s

main :: IO ()
main = do
    let seed = BS.replicate 32 0x42
        sk :: SignKeyDSIGN Ed25519DSIGN
        sk = genKeyDSIGN (mkSeedFromBytes seed)
        vk = deriveVerKeyDSIGN sk
        ownerKey = rawSerialiseVerKeyDSIGN vk
        ownerAid = "test-aid" :: ByteString
        txId = BS.replicate 32 0xde
        outputIndex = 0 :: Integer
        msg = valueWriteMessage txId outputIndex
        ownerSig = rawSerialiseSigDSIGN $ signDSIGN () msg sk
        idRoot = identityRoot ownerAid ownerKey

    putStrLn "// Aiken test vectors for verifyOwnerAuth"
    putStrLn $ "let owner_key = #\"" <> toHex ownerKey <> "\""
    putStrLn $ "let owner_aid = #\"" <> toHex ownerAid <> "\""
    putStrLn $ "let owner_sig = #\"" <> toHex ownerSig <> "\""
    putStrLn $ "let identity_root = #\"" <> toHex idRoot <> "\""
    putStrLn $ "let tx_id = #\"" <> toHex txId <> "\""
    putStrLn "let output_index = 0"
    putStrLn "let identity_proof: Proof = []  // single-element trie"
