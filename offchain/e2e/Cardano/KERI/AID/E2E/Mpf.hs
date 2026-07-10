{- |
Module      : Cardano.KERI.AID.E2E.Mpf
Description : Single-leaf MPF root computation for the #99 cage e2e smoke

Mirrors the Aiken @merkle_patricia_forestry@ leaf hashing so the offchain
builder can compute the exact roots the on-chain @mpfCage@ handler
recomputes, using empty (zero-depth) proofs for single-element tries.

This is the S9a scope: single-leaf identity trie and a single Insert into
the empty value trie. Non-zero-depth proofs are S9b.
-}
module Cardano.KERI.AID.E2E.Mpf (
    blake2b256,
    combine,
    suffix0,
    emptyRoot,
    identityRoot,
    insertRootFromEmpty,
) where

import Cardano.Crypto.Hash.Blake2b (Blake2b_256)
import Cardano.Crypto.Hash.Class (digest)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Proxy (Proxy (..))

-- | @blake2b_256@ digest (32 bytes), matching the Aiken builtin.
blake2b256 :: ByteString -> ByteString
blake2b256 = digest (Proxy @Blake2b_256)

-- | Aiken MPF branch combine: @blake2b_256(a ++ b)@.
combine :: ByteString -> ByteString -> ByteString
combine a b = blake2b256 (a <> b)

-- | Aiken MPF @suffix(path, cursor = 0)@: prepend the @0xff@ marker.
suffix0 :: ByteString -> ByteString
suffix0 = BS.cons 0xff

{- | Root of the empty MPF trie, matching Aiken's @root(empty)@ (32 zero
bytes). A fresh cage state carries this as its value-trie @root@.
-}
emptyRoot :: ByteString
emptyRoot = BS.replicate 32 0

{- | Root of a single-element identity trie mapping @owner_aid@ to
@blake2b_256(owner_key)@ (the value the handler's no-op update proves):

@root = combine(suffix0(blake2b_256(owner_aid)), blake2b_256(blake2b_256(owner_key)))@

The corresponding inclusion proof for this single-leaf trie is the empty
proof @[]@.
-}
identityRoot :: ByteString -> ByteString -> ByteString
identityRoot ownerAid ownerKey =
    combine (suffix0 (blake2b256 ownerAid)) (blake2b256 (blake2b256 ownerKey))

{- | Root obtained by inserting @key -> value@ into the empty value trie,
matching @root(insert(from_root(empty_root), key, value, []))@:

@root = combine(suffix0(blake2b_256(key)), blake2b_256(value))@

Valid with the empty proof @[]@ because the trie was empty beforehand.
-}
insertRootFromEmpty :: ByteString -> ByteString -> ByteString
insertRootFromEmpty key value =
    combine (suffix0 (blake2b256 key)) (blake2b256 value)
