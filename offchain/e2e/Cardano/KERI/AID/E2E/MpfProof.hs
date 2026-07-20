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
    excludingRoot,
    includingRoot,
) where

import Cardano.KERI.AID.Cage.Types (Neighbor (..), ProofStep (..))
import Cardano.KERI.AID.E2E.Mpf (blake2b256, combine)
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

{- | Rewind an MPFS proof without the target key. This is the exact pure
mirror of Aiken MPF @excluding(key, proof)@ and therefore the pre-insert root
for an absence proof.
-}
excludingRoot :: ByteString -> [ProofStep] -> ByteString
excludingRoot key = excluding (blake2b256 key) 0

{- | Rewind an MPFS proof including @key -> value@. This mirrors Aiken MPF
@including(key, value, proof)@ and therefore yields the post-insert root.
-}
includingRoot :: ByteString -> ByteString -> [ProofStep] -> ByteString
includingRoot key value = including (blake2b256 key) (blake2b256 value) 0

including :: ByteString -> ByteString -> Int -> [ProofStep] -> ByteString
including path value cursor = \case
    [] -> combineRoot (suffix path cursor) value
    Branch skip neighbors : steps ->
        let next = cursor + 1 + fromIntegral skip
         in branchRoot path cursor next (including path value next steps) neighbors
    Fork skip neighbor : steps ->
        let next = cursor + 1 + fromIntegral skip
         in forkRoot path cursor next (including path value next steps) neighbor
    Leaf skip neighborKey neighborValue : steps ->
        let next = cursor + 1 + fromIntegral skip
            root = including path value next steps
            neighbor =
                Neighbor
                    { neighborNibble = fromIntegral (nibble neighborKey (next - 1))
                    , neighborPrefix = suffix neighborKey next
                    , neighborRoot = neighborValue
                    }
         in forkRoot path cursor next root neighbor

excluding :: ByteString -> Int -> [ProofStep] -> ByteString
excluding path cursor = \case
    [] -> nullHash
    Branch skip neighbors : steps ->
        let next = cursor + 1 + fromIntegral skip
         in branchRoot path cursor next (excluding path next steps) neighbors
    [Fork _ Neighbor{..}] ->
        combineRoot (BS.cons (fromIntegral neighborNibble) neighborPrefix) neighborRoot
    Fork skip neighbor : steps ->
        let next = cursor + 1 + fromIntegral skip
         in forkRoot path cursor next (excluding path next steps) neighbor
    [Leaf _ neighborKey neighborValue] ->
        combineRoot (suffix neighborKey cursor) neighborValue
    Leaf skip neighborKey neighborValue : steps ->
        let next = cursor + 1 + fromIntegral skip
            root = excluding path next steps
            neighbor =
                Neighbor
                    { neighborNibble = fromIntegral (nibble neighborKey cursor)
                    , neighborPrefix = suffix neighborKey next
                    , neighborRoot = neighborValue
                    }
         in forkRoot path cursor next root neighbor

branchRoot :: ByteString -> Int -> Int -> ByteString -> ByteString -> ByteString
branchRoot path cursor next root neighbors =
    combineRoot prefix (merkle16 branch root n8 n4 n2 n1)
  where
    branch = nibble path (next - 1)
    prefix = BS.pack (map fromIntegral (take (next - 1 - cursor) (drop cursor (toPath path))))
    n8 = BS.take 32 neighbors
    n4 = BS.take 32 (BS.drop 32 neighbors)
    n2 = BS.take 32 (BS.drop 64 neighbors)
    n1
        | BS.length neighbors == 128 = BS.drop 96 neighbors
        | otherwise = error "MpfProof.branchRoot: neighbors must be 128 bytes"

forkRoot :: ByteString -> Int -> Int -> ByteString -> Neighbor -> ByteString
forkRoot path cursor next root Neighbor{..}
    | branch == fromIntegral neighborNibble = error "MpfProof.forkRoot: equal branches"
    | otherwise =
        combineRoot
            prefix
            ( sparseMerkle16
                branch
                root
                (fromIntegral neighborNibble)
                (combineRoot neighborPrefix neighborRoot)
            )
  where
    branch = nibble path (next - 1)
    prefix = BS.pack (map fromIntegral (take (next - 1 - cursor) (drop cursor (toPath path))))

suffix :: ByteString -> Int -> ByteString
suffix path cursor
    | even cursor = BS.cons 0xff (BS.drop (cursor `div` 2) path)
    | otherwise =
        BS.pack [0, fromIntegral (nibble path cursor)]
            <> BS.drop ((cursor + 1) `div` 2) path

nibble :: ByteString -> Int -> Int
nibble path index
    | even index = fromIntegral (BS.index path (index `div` 2)) `div` 16
    | otherwise = fromIntegral (BS.index path (index `div` 2)) `mod` 16

toPath :: ByteString -> [Int]
toPath = concatMap (\w -> [fromIntegral w `div` 16, fromIntegral w `mod` 16]) . BS.unpack

combineRoot :: ByteString -> ByteString -> ByteString
combineRoot = combine

merkle16 :: Int -> ByteString -> ByteString -> ByteString -> ByteString -> ByteString -> ByteString
merkle16 branch root n8 n4 n2 n1
    | branch <= 7 = combineRoot (merkle8 branch root n4 n2 n1) n8
    | otherwise = combineRoot n8 (merkle8 (branch - 8) root n4 n2 n1)

merkle8 :: Int -> ByteString -> ByteString -> ByteString -> ByteString -> ByteString
merkle8 branch root n4 n2 n1
    | branch <= 3 = combineRoot (merkle4 branch root n2 n1) n4
    | otherwise = combineRoot n4 (merkle4 (branch - 4) root n2 n1)

merkle4 :: Int -> ByteString -> ByteString -> ByteString -> ByteString
merkle4 branch root n2 n1
    | branch <= 1 = combineRoot (merkle2 branch root n1) n2
    | otherwise = combineRoot n2 (merkle2 (branch - 2) root n1)

merkle2 :: Int -> ByteString -> ByteString -> ByteString
merkle2 branch root neighbor
    | branch <= 0 = combineRoot root neighbor
    | otherwise = combineRoot neighbor root

sparseMerkle16 :: Int -> ByteString -> Int -> ByteString -> ByteString
sparseMerkle16 me meHash neighbor neighborHash
    | me < 8 && neighbor < 8 =
        combineRoot (sparseMerkle8 me meHash neighbor neighborHash) nullHash8
    | me < 8 =
        combineRoot
            (merkle8 me meHash nullHash4 nullHash2 nullHash)
            (merkle8 (neighbor - 8) neighborHash nullHash4 nullHash2 nullHash)
    | neighbor >= 8 =
        combineRoot nullHash8 (sparseMerkle8 (me - 8) meHash (neighbor - 8) neighborHash)
    | otherwise =
        combineRoot
            (merkle8 neighbor neighborHash nullHash4 nullHash2 nullHash)
            (merkle8 (me - 8) meHash nullHash4 nullHash2 nullHash)

sparseMerkle8 :: Int -> ByteString -> Int -> ByteString -> ByteString
sparseMerkle8 me meHash neighbor neighborHash
    | me < 4 && neighbor < 4 =
        combineRoot (sparseMerkle4 me meHash neighbor neighborHash) nullHash4
    | me < 4 =
        combineRoot
            (merkle4 me meHash nullHash2 nullHash)
            (merkle4 (neighbor - 4) neighborHash nullHash2 nullHash)
    | neighbor >= 4 =
        combineRoot nullHash4 (sparseMerkle4 (me - 4) meHash (neighbor - 4) neighborHash)
    | otherwise =
        combineRoot
            (merkle4 neighbor neighborHash nullHash2 nullHash)
            (merkle4 (me - 4) meHash nullHash2 nullHash)

sparseMerkle4 :: Int -> ByteString -> Int -> ByteString -> ByteString
sparseMerkle4 me meHash neighbor neighborHash
    | me < 2 && neighbor < 2 =
        combineRoot (merkle2 me meHash neighborHash) nullHash2
    | me < 2 =
        combineRoot
            (merkle2 me meHash nullHash)
            (merkle2 (neighbor - 2) neighborHash nullHash)
    | neighbor >= 2 =
        combineRoot nullHash2 (merkle2 (me - 2) meHash neighborHash)
    | otherwise =
        combineRoot
            (merkle2 neighbor neighborHash nullHash)
            (merkle2 (me - 2) meHash nullHash)

nullHash2, nullHash4, nullHash8 :: ByteString
nullHash2 = combineRoot nullHash nullHash
nullHash4 = combineRoot nullHash2 nullHash2
nullHash8 = combineRoot nullHash4 nullHash4

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
