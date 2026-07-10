{- |
Module      : Cardano.KERI.AID.E2E.MpfTrie
Description : Radix-16 Merkle Patricia Forestry trie + root (non-zero-depth)

A Haskell port of the Aiken @merkle_patricia_forestry@ off-chain trie
(mirroring @aiken-lang/merkle-patricia-forestry@'s @lib/trie.js@, the
read-only mpfs precedent) so the S9b e2e builder can construct
MULTI-element value tries and compute the exact roots the on-chain
@mpfCage@ handler recomputes via @mpf.insert@.

This module provides the trie construction and root hashing (used to set a
batch @Modify@'s continuing-state root). Non-zero-depth inclusion PROOF
generation lives in "Cardano.KERI.AID.E2E.MpfProof".

The hashing matches Aiken byte-for-byte: for a single leaf,
@rootOf (build [(k, v)])@ equals the S9a
@Cardano.KERI.AID.E2E.Mpf.insertRootFromEmpty k v@.
-}
module Cardano.KERI.AID.E2E.MpfTrie (
    Nibble,
    Trie (..),
    pathOf,
    toNibbles,
    packNibbles,
    commonPrefixAll,
    nullHash,
    combine,
    leafHash,
    branchHash,
    merkleRoot16,
    build,
    rootOf,
) where

import Cardano.KERI.AID.E2E.Mpf (blake2b256)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (foldl1')
import Data.Word (Word8)

-- | A hex digit (0..15).
type Nibble = Int

{- | A radix-16 Merkle Patricia Forestry trie with RELATIVE prefixes (each
node's prefix is relative to its parent), matching the off-chain lib.
-}
data Trie
    = -- | The empty trie (root = 'nullHash').
      TEmpty
    | -- | A single element: relative path prefix, original key, value.
      TLeaf ![Nibble] !ByteString !ByteString
    | -- | A branch: relative prefix + 16 children slots.
      TBranch ![Nibble] ![Maybe Trie]
    deriving stock (Show, Eq)

-- | The trie path of a key: the nibbles of @blake2b_256(key)@ (64 nibbles).
pathOf :: ByteString -> [Nibble]
pathOf = toNibbles . blake2b256

-- | Expand bytes into nibbles (high nibble first).
toNibbles :: ByteString -> [Nibble]
toNibbles = concatMap byteNibbles . BS.unpack
  where
    byteNibbles :: Word8 -> [Nibble]
    byteNibbles w = [fromIntegral w `div` 16, fromIntegral w `mod` 16]

-- | Pack an EVEN-length nibble list back into bytes (two nibbles per byte).
packNibbles :: [Nibble] -> ByteString
packNibbles = BS.pack . go
  where
    go (a : b : rest) = fromIntegral (a * 16 + b) : go rest
    go [] = []
    go [_] = error "packNibbles: odd nibble count"

-- | Longest common prefix of a non-empty list of nibble sequences.
commonPrefixAll :: [[Nibble]] -> [Nibble]
commonPrefixAll [] = []
commonPrefixAll xs = foldl1' common2 xs
  where
    common2 as bs = map fst (takeWhile (uncurry (==)) (zip as bs))

-- | Hash of the empty trie/tree: 32 zero bytes.
nullHash :: ByteString
nullHash = BS.replicate 32 0

-- | Aiken MPF @combine@: @blake2b_256(left ++ right)@.
combine :: ByteString -> ByteString -> ByteString
combine a b = blake2b256 (a <> b)

{- | Leaf hash: @blake2b_256(head ++ tail ++ valueHash)@ where head/tail
encode the relative prefix (the Aiken @suffix@ shape): an even-length
prefix is @[0xFF] ++ packNibbles prefix@; an odd-length prefix is
@[0x00, firstNibble] ++ packNibbles (drop 1 prefix)@. @valueHash@ is the
32-byte @blake2b_256@ of the value.
-}
leafHash :: [Nibble] -> ByteString -> ByteString
leafHash prefix valueHash =
    blake2b256 (hd <> tl <> valueHash)
  where
    hd = case prefix of
        (n0 : _) | odd (length prefix) -> BS.pack [0x00, fromIntegral n0]
        _ -> BS.pack [0xFF]
    tl = packNibbles (if odd (length prefix) then drop 1 prefix else prefix)

{- | Branch hash: @blake2b_256(prefixNibbleBytes ++ merkleRoot)@ where each
nibble of the relative prefix is a single byte and @merkleRoot@ is the
sparse-merkle-16 root of the children.
-}
branchHash :: [Nibble] -> ByteString -> ByteString
branchHash prefix root =
    blake2b256 (BS.pack (map fromIntegral prefix) <> root)

{- | Sparse-merkle-16 root of a node's 16 (already-hashed) children:
pairwise @combine@ up the binary tree (16 -> 8 -> 4 -> 2 -> 1).
-}
merkleRoot16 :: [ByteString] -> ByteString
merkleRoot16 [h] = h
merkleRoot16 hs = merkleRoot16 (pairUp hs)
  where
    pairUp (a : b : rest) = combine a b : pairUp rest
    pairUp _ = []

-- | Build a trie from a list of @(key, value)@ pairs (keys must be distinct).
build :: [(ByteString, ByteString)] -> Trie
build kvs = buildAt [(pathOf k, k, v) | (k, v) <- kvs]

-- | Build the sub-trie for a set of entries carrying their REMAINING path.
buildAt :: [([Nibble], ByteString, ByteString)] -> Trie
buildAt [] = TEmpty
buildAt [(p, k, v)] = TLeaf p k v
buildAt entries =
    TBranch cp [child n | n <- [0 .. 15]]
  where
    cp = commonPrefixAll [p | (p, _, _) <- entries]
    stripped = [(drop (length cp) p, k, v) | (p, k, v) <- entries]
    child n =
        case [(rest, k, v) | (n0 : rest, k, v) <- stripped, n0 == n] of
            [] -> Nothing
            grp -> Just (buildAt grp)

-- | Root hash of a trie, matching the Aiken on-chain @mpf.root@.
rootOf :: Trie -> ByteString
rootOf TEmpty = nullHash
rootOf (TLeaf prefix _ value) = leafHash prefix (blake2b256 value)
rootOf (TBranch prefix children) =
    branchHash prefix (merkleRoot16 (map childHash children))
  where
    childHash = maybe nullHash rootOf
