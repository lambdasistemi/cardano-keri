{- |
Module      : Cardano.KERI.AID.E2E.MpfProof
Description : Non-zero-depth MPF inclusion-proof generation (S9b GREEN)

A Haskell port of the Aiken/mpfs off-chain proof generator
(@merkle-patricia-forestry@'s @Trie.walk@ + @Proof.rewind@, mirrored from
the read-only @/code/mpfs/off_chain/src/mpf/lib@) producing the
'ProofStep' list that the on-chain @mpfCage@ recomputes via
@excluding(key, proof)@ / @including(key, value, proof)@.

For a key present in a MULTI-element trie, 'prove' walks the trie down the
key's path and, at each internal branch, records the neighbouring subtries
as a Branch / Fork / Leaf step (depth > 0). For a single-leaf trie the proof
is empty (the S9a zero-depth case).
-}
module Cardano.KERI.AID.E2E.MpfProof (
    prove,
) where

import Cardano.KERI.AID.Cage.Types (Neighbor (..), ProofStep (..))
import Cardano.KERI.AID.E2E.Mpf (blake2b256)
import Cardano.KERI.AID.E2E.MpfTrie (
    Nibble,
    Trie (..),
    merkleRoot16,
    nullHash,
    pathOf,
    rootOf,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS

{- | Inclusion proof for @key@ in @trie@: the neighbouring subtries along the
key's path, root step first. Empty when @trie@ is a single leaf.
-}
prove :: Trie -> ByteString -> [ProofStep]
prove trie key = walk trie (pathOf key)

-- | Walk the trie down @path@, emitting one step per internal branch.
walk :: Trie -> [Nibble] -> [ProofStep]
walk (TBranch prefix children) path =
    mkStep skip children br : childSteps
  where
    skip = length prefix
    (br, childPath) = case drop skip path of
        (n0 : rest) -> (n0, rest)
        [] -> error "MpfProof.walk: path exhausted at a branch"
    childSteps = case children !! br of
        Just c -> walk c childPath
        Nothing -> error "MpfProof.walk: descended into an empty child"
walk TLeaf{} _ = []
walk TEmpty _ = []

{- | The proof step recording the neighbours of branch slot @me@ at a branch
whose relative prefix has @skip@ nibbles. A single non-empty neighbour
collapses to a Leaf (neighbour is a leaf) or Fork (neighbour is a branch);
two or more neighbours form a Branch step carrying the sparse-merkle proof
of @me@.
-}
mkStep :: Int -> [Maybe Trie] -> Nibble -> ProofStep
mkStep skip children me =
    case neighbors of
        [(_, TLeaf _ nk nv)] ->
            Leaf
                (fromIntegral skip)
                (blake2b256 nk)
                (blake2b256 nv)
        [(nix, TBranch np nch)] ->
            Fork
                (fromIntegral skip)
                Neighbor
                    { neighborNibble = fromIntegral nix
                    , neighborPrefix = BS.pack (map fromIntegral np)
                    , neighborRoot = merkleRoot16 (map childHash nch)
                    }
        _ ->
            Branch
                (fromIntegral skip)
                (BS.concat (merkleProof (map childHash children) me))
  where
    neighbors =
        [ (ix, c)
        | (ix, Just c) <- zip [0 ..] children
        , ix /= me
        ]

-- | Hash of a (possibly empty) child slot.
childHash :: Maybe Trie -> ByteString
childHash = maybe nullHash rootOf

{- | Sparse-merkle-16 inclusion proof of node @me@ among 16 leaves: the four
sibling subtree roots (levels 8, 4, 2, 1), matching the mpfs @merkleProof@.
-}
merkleProof :: [ByteString] -> Int -> [ByteString]
merkleProof nodes me = loop 8 8
  where
    loop _ 0 = []
    loop pivot n
        | me < pivot =
            merkleRoot16 (slice pivot (pivot + n))
                : loop (pivot - (n `div` 2)) (n `div` 2)
        | otherwise =
            merkleRoot16 (slice (pivot - n) pivot)
                : loop (pivot + (n `div` 2)) (n `div` 2)
    slice a b = take (b - a) (drop a nodes)
