{- |
Module      : Cardano.KERI.AID.Cage.MpfProofMirrorSpec
Description : #307 MPF v2.1.0 wire-shape and cross-language mirror proofs

Three permanent proof families over the two frozen #307 gate fixtures
(leaf-fork and terminal-fork, sha256
97f5b3b80421894ed2848d29827f7fb10de468e164a58f9939791a0a51004714):

1. __Wire__ (I4): the local 'ProofStep'\/'Neighbor' 'ToData' encodings keep
   the exact PlutusData constructor indices and field orders (Branch 0
   @[skip,neighbors]@, Fork 1 @[skip,neighbor]@, Leaf 2 @[skip,key,value]@,
   Neighbor 0 @[nibble,prefix,root]@), asserted against hand-written 'Data'
   shapes — not just roundtrips, which a self-consistent wrong encoding
   would also satisfy.

2. __Mirror__ (I5): an independent Haskell rewind of each fixture proof
   (including and excluding directions, mirroring the v2.1.0
   @do_including@\/@do_excluding@ semantics: marker-first @suffix@,
   one-byte-per-nibble prefixes, 32-byte neighbor slicing, fork prefix
   reconstruction for skip>0) reproduces the exact expected pre-insert and
   post-insert roots that the Aiken library itself computes (gate-proven:
   @insert@ requires @excluding(key, proof) == root@ and stores
   @including(key, value, proof)@ as the new root). Neither side compares
   only with itself: the Aiken library owns the roots, this rewind
   independently reproduces them from the same fixture bytes.

3. __Negative controls__: mutations of the fixture proofs make the mirror
   assertions fail, so the passing case cannot be vacuous.
-}
module Cardano.KERI.AID.Cage.MpfProofMirrorSpec (
    spec,
) where

import Cardano.Crypto.Hash.Blake2b (Blake2b_256)
import Cardano.Crypto.Hash.Class (digest)
import Cardano.KERI.AID.Cage.Types (
    Neighbor (..),
    ProofStep (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Proxy (Proxy (..))
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
    UnsafeFromData (..),
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldSatisfy,
 )

-- ------------------------------------------------------------------------
-- Frozen #307 gate fixtures (bytes identical to the slice-gate controls)
-- ------------------------------------------------------------------------

{- | Leaf-fork fixture: inserted key and value, expected pre-insert and
post-insert roots, and the proof of the pre-insert neighbor structure
along the key's path (four branch steps, two leaf steps).
-}
leafForkProof :: [ProofStep]
leafForkProof =
    [ Branch 0 leafForkNeighbors0
    , Branch 0 leafForkNeighbors1
    , Branch 0 leafForkNeighbors2
    , Branch 0 leafForkNeighbors3
    , Leaf
        1
        ( hex
            "2b5b0ba7a99e17d9fde58f14dee61cccda9e3e9627b2ba2732ebed551ea9eaa4"
        )
        ( hex
            "3657998959985b7b75c734eb5b49d18cae9b353d00d811cb2c24ed6ed17b23d9"
        )
    , Leaf
        0
        ( hex
            "2b5b063719f4b7644c71adef1439c9aa78d34e684677dd61db0adffcc21797ec"
        )
        ( hex
            "4e397303e05277d98701446ee62f6f02bc013721fc12efba7300fb51ea935f9f"
        )
    ]

leafForkNeighbors0, leafForkNeighbors1, leafForkNeighbors2, leafForkNeighbors3 :: ByteString
leafForkNeighbors0 =
    hex
        "d0feb802cc999c500ec58b8e78bdb1b11bcb8e217d404c2cfb416669a6b2c240cd0c58152bf064f0c7834dd72f69d12651739b32caaa3c986a87937f125b500f1426fccf2a456bce3c25b43206d9b429d56515580d086a959ca730325411b3aada6ac4d7221f787b97e1ce677fdadc412e824a9816281b1259b91addeb37bb2c"
leafForkNeighbors1 =
    hex
        "098745f495c99b7627f559ac8ed8165e2392e2261ef8990291f13705adf78fcf3dcca881d4b45aabe746e7041f743baaa831029e7890df9587858d8be5dce648e02f31fe2936417a393df8def15d7d0c021a66cdb33c3fdda941ae70614913cb116fd5e6c499b71e229b88f5106975cbe83a8c44d3619541d7ddd7eae0a355bc"
leafForkNeighbors2 =
    hex
        "9732c3266e468dd27c4bd16af5a6e60c1f556bf91700f51554cfa33aa26b8d30f33c27ab7c5c85ef006c78f56ecd7e8c77c5fadd7910e9b178801d554f244977026104fc4aede0864d405db792691c4e4534b06ae7f58366b640f13ecfa549afa046a157d2e9b6c0793a506942eb8ff50dfeb7c5e7a2a51814c4b3a4d6af6fa0"
leafForkNeighbors3 =
    hex
        "5f3065e998b5fa89bb33d9204546c5dba2b075adc542688dcc1773a490fa739ac69ff52c5f575e9f1912664c1ebef2f9498775350b0077a6b59fe012861c3715657146a239aaea12b3091054e5846771bba6f721b1835d025fa08d1fc5c9b1c40000000000000000000000000000000000000000000000000000000000000000"

leafForkKey, leafForkValue, leafForkPreRoot, leafForkPostRoot :: ByteString
leafForkKey =
    hex "198d70e41146654a69e08c6682310a8c35816c8584431915a0eee4a62d39eda0"
leafForkValue = hex "9e36f867a374be"
leafForkPreRoot =
    hex "409bc367bec001f8c8af45fb86239d1f69763cb86e8e134c66bba15426cf176e"
leafForkPostRoot =
    hex "f19b7893c0ec34703790dadb8e3257196dcf7aabfa9426d68adf36a31a94ad9a"

{- | Terminal-fork fixture: three branch steps and a final fork whose
reconstructed neighbor prefix is non-empty (skip > 0) — the exact
rewind path that was broken in v2.0.0.
-}
terminalForkProof :: [ProofStep]
terminalForkProof =
    [ Branch 0 terminalForkNeighbors0
    , Branch 0 terminalForkNeighbors1
    , Branch 0 terminalForkNeighbors2
    , Fork
        1
        Neighbor
            { neighborNibble = 12
            , neighborPrefix = BS.empty
            , neighborRoot =
                hex
                    "136bca071d530710ba622dfd66fe1afb859d4f42d45f29ce252e862a92eb10c2"
            }
    ]

terminalForkNeighbors0, terminalForkNeighbors1, terminalForkNeighbors2 :: ByteString
terminalForkNeighbors0 =
    hex
        "d072e11c4f761d09ebe0c1df54b08d398977aa4e98e85e5e231f52dc32fdf8053861a5ea164ac3eb460e27f96ba934832bfc7b240dbf7be24d3fb7ae16f3e44fa965498aa2e219f45428bafc4f646a8f2b4d863bf730f802f81f4f713a465246cd28ad53627981fd212ebec41068fa0f4b0ae5e0e77af0143e296373c6c8f753"
terminalForkNeighbors1 =
    hex
        "6c2cf6703c1b121726899e4f1de29cf483227d9e75d5d7948b62b5904c7f1011165b8313abcd4f1c33b85a5dabf8c5096039b3aba1c1fedda2e247810090173998f6f58a03bc17874bff8ba7eda08d25623911dff348f57da60b8545044dcbb175d27abc4c3e1b9aa0a3161ea0f8067ef39885c30399c164395b181747ba4f51"
terminalForkNeighbors2 =
    hex
        "c5b1eb4266a20e13961f0b7b8f909a217141eecab5bbe3116665e382f87477fcf9a8a6a9e1e1cb7af32d1ffdf5c70643434337c3874d417de45f83e48f7c00afaf7180e918199dde712083a3f512483e89d756f25ddafe8b14b246499fe44dd3bda1f1a580cf7af9dd35c6ddfffa2ec8af0d41b00d7ca5ed25af8e54d4bef1f9"

terminalForkKey, terminalForkValue, terminalForkPreRoot, terminalForkPostRoot :: ByteString
terminalForkKey =
    hex "04811fc306a2021340b15ce6f025db1dc3d402f0829c7ee2100ca8fdd6ed10cd"
terminalForkValue = hex "0c43c3addce8b95e49eb0fb906"
terminalForkPreRoot =
    hex "76ff3670f2b81017d50354ca4a78792de31adbd23f456eec41d7a8c13fcdc91b"
terminalForkPostRoot =
    hex "a6eb3cdf9dd3da02d9463bd5cd68555ea11d6d5a77e2ece9ceb1cf6a5a9c7b27"

-- ------------------------------------------------------------------------
-- Independent rewind of the v2.1.0 verifier semantics (test-local; the
-- only primitive shared with the Aiken library is blake2b_256 itself)
-- ------------------------------------------------------------------------

-- | @blake2b_256@, matching the Aiken builtin.
blake2b256 :: ByteString -> ByteString
blake2b256 = digest (Proxy @Blake2b_256)

-- | @helpers.combine@: @blake2b_256(left ++ right)@.
combineHash :: ByteString -> ByteString -> ByteString
combineHash left right = blake2b256 (left <> right)

-- | @helpers.nibble@: high nibble first.
nibbleAt :: ByteString -> Int -> Int
nibbleAt bytes i
    | even i = fromIntegral (BS.index bytes (i `div` 2) `div` 16)
    | otherwise = fromIntegral (BS.index bytes (i `div` 2) `mod` 16)

-- | @helpers.nibbles path start end@: one byte per nibble, ascending.
nibblesBetween :: ByteString -> Int -> Int -> ByteString
nibblesBetween path start end =
    BS.pack
        [ fromIntegral (nibbleAt path i)
        | i <- [start .. end - 1]
        ]

{- | @helpers.suffix path cursor@: marker-first (empirical v2.1.0 bytes):

* even cursor: @0xff ++ drop (cursor 'div' 2) path@
* odd cursor: @0x00 ++ nibble(path, cursor) ++ drop ((cursor + 1) 'div' 2) path@
-}
suffixFrom :: ByteString -> Int -> ByteString
suffixFrom path cursor
    | even cursor = BS.cons 0xff (BS.drop (cursor `div` 2) path)
    | otherwise =
        BS.concat
            [ BS.pack [0x00, fromIntegral (nibbleAt path cursor)]
            , BS.drop ((cursor + 1) `div` 2) path
            ]

nullHash :: ByteString
nullHash = BS.replicate 32 0

nullHash2, nullHash4, nullHash8 :: ByteString
nullHash2 = combineHash nullHash nullHash
nullHash4 = combineHash nullHash2 nullHash2
nullHash8 = combineHash nullHash4 nullHash4

-- | @merkling.merkle_4@: sparse-merkle combination at 4-wide level.
merkle4 :: Int -> ByteString -> ByteString -> ByteString -> ByteString
merkle4 branch root neighbor2 neighbor1 =
    if branch <= 1
        then
            combineHash
                ( if branch == 0
                    then combineHash root neighbor1
                    else combineHash neighbor1 root
                )
                neighbor2
        else
            combineHash
                neighbor2
                ( if branch == 2
                    then combineHash root neighbor1
                    else combineHash neighbor1 root
                )

-- | @merkling.merkle_8@.
merkle8 :: Int -> ByteString -> ByteString -> ByteString -> ByteString -> ByteString
merkle8 branch root neighbor4 neighbor2 neighbor1 =
    if branch <= 3
        then combineHash (merkle4 branch root neighbor2 neighbor1) neighbor4
        else combineHash neighbor4 (merkle4 (branch - 4) root neighbor2 neighbor1)

{- | @merkling.merkle_16@: the rewound subtree root combined with the four
sibling roots at levels 8\/4\/2\/1.
-}
merkle16 ::
    Int ->
    ByteString ->
    ByteString ->
    ByteString ->
    ByteString ->
    ByteString ->
    ByteString
merkle16 branch root neighbor8 neighbor4 neighbor2 neighbor1 =
    if branch <= 7
        then combineHash (merkle8 branch root neighbor4 neighbor2 neighbor1) neighbor8
        else
            combineHash
                neighbor8
                (merkle8 (branch - 8) root neighbor4 neighbor2 neighbor1)

-- | @merkling.sparse_merkle_4@.
sparse4 :: Int -> ByteString -> Int -> ByteString -> ByteString
sparse4 me meHash neighbor neighborHash
    | me <= 1
    , neighbor <= 1 =
        combineHash (combineMe neighborHash) nullHash2
    | me <= 1 = combineHash (combineMe nullHash) (combineNeighbor nullHash)
    | neighbor >= 2 = combineHash nullHash2 (combineMe neighborHash)
    | otherwise = combineHash (combineNeighbor nullHash) (combineMe nullHash)
  where
    combineMe
        | even me = combineHash meHash
        | otherwise = (`combineHash` meHash)
    combineNeighbor
        | even neighbor = combineHash neighborHash
        | otherwise = (`combineHash` neighborHash)

-- | @merkling.sparse_merkle_8@.
sparse8 :: Int -> ByteString -> Int -> ByteString -> ByteString
sparse8 me meHash neighbor neighborHash
    | me <= 3 =
        if neighbor <= 3
            then combineHash (sparse4 me meHash neighbor neighborHash) nullHash4
            else
                combineHash
                    (merkle4 me meHash nullHash2 nullHash)
                    (merkle4 (neighbor - 4) neighborHash nullHash2 nullHash)
    | neighbor >= 4 =
        combineHash nullHash4 (sparse4 (me - 4) meHash (neighbor - 4) neighborHash)
    | otherwise =
        combineHash
            (merkle4 neighbor neighborHash nullHash2 nullHash)
            (merkle4 (me - 4) meHash nullHash2 nullHash)

-- | @merkling.sparse_merkle_16@.
sparse16 :: Int -> ByteString -> Int -> ByteString -> ByteString
sparse16 me meHash neighbor neighborHash
    | me <= 7 =
        if neighbor <= 7
            then combineHash (sparse8 me meHash neighbor neighborHash) nullHash8
            else
                combineHash
                    (merkle8 me meHash nullHash4 nullHash2 nullHash)
                    (merkle8 (neighbor - 8) neighborHash nullHash4 nullHash2 nullHash)
    | neighbor >= 8 =
        combineHash nullHash8 (sparse8 (me - 8) meHash (neighbor - 8) neighborHash)
    | otherwise =
        combineHash
            (merkle8 neighbor neighborHash nullHash4 nullHash2 nullHash)
            (merkle8 (me - 8) meHash nullHash4 nullHash2 nullHash)

{- | @do_branch@: @select(i)@ takes 32 bytes at offset @i@ — the builtin
is @slice_bytearray(from, length, bytes)@.
-}
doBranch :: ByteString -> Int -> Int -> ByteString -> ByteString -> ByteString
doBranch path cursor nextCursor root neighbors =
    combineHash
        (nibblesBetween path cursor nextCursor)
        ( merkle16
            (nibbleAt path nextCursor)
            root
            (select 0)
            (select 32)
            (select 64)
            (select 96)
        )
  where
    select i = BS.take 32 (BS.drop i neighbors)

-- | @do_fork@.
doFork :: ByteString -> Int -> Int -> ByteString -> Neighbor -> ByteString
doFork path cursor nextCursor root neighbor =
    combineHash
        (nibblesBetween path cursor nextCursor)
        ( sparse16
            (nibbleAt path nextCursor)
            root
            (fromIntegral (neighborNibble neighbor))
            (combineHash (neighborPrefix neighbor) (neighborRoot neighbor))
        )

{- | Including-direction rewind: the root @insert@ stores
(@including(key, value, proof)@).
-}
rewindIncluding :: ByteString -> ByteString -> [ProofStep] -> ByteString
rewindIncluding insertedKey insertedValue =
    doIncluding (blake2b256 insertedKey) (blake2b256 insertedValue) 0
  where
    doIncluding path valueHash cursor [] =
        combineHash (suffixFrom path cursor) valueHash
    doIncluding path valueHash cursor (Branch skip neighbors : steps) =
        doBranch
            path
            cursor
            nextCursor
            (doIncluding path valueHash (nextCursor + 1) steps)
            neighbors
      where
        nextCursor = cursor + fromIntegral skip
    doIncluding path valueHash cursor (Fork skip neighbor : steps) =
        doFork
            path
            cursor
            nextCursor
            (doIncluding path valueHash (nextCursor + 1) steps)
            neighbor
      where
        nextCursor = cursor + fromIntegral skip
    doIncluding path valueHash cursor (Leaf skip key value : steps) =
        doFork
            path
            cursor
            nextCursor
            (doIncluding path valueHash (nextCursor + 1) steps)
            Neighbor
                { neighborNibble = fromIntegral (nibbleAt key nextCursor)
                , neighborPrefix = suffixFrom key (nextCursor + 1)
                , neighborRoot = value
                }
      where
        nextCursor = cursor + fromIntegral skip

{- | Excluding-direction rewind: the root @insert@'s precondition checks
the key against (the property @miss@ exposes).
-}
rewindExcluding :: ByteString -> [ProofStep] -> ByteString
rewindExcluding insertedKey = doExcluding (blake2b256 insertedKey) 0
  where
    doExcluding _ _ [] = nullHash
    doExcluding path cursor (Branch skip neighbors : steps) =
        doBranch
            path
            cursor
            nextCursor
            (doExcluding path (nextCursor + 1) steps)
            neighbors
      where
        nextCursor = cursor + fromIntegral skip
    doExcluding path cursor (Fork skip neighbor : steps) =
        case steps of
            [] ->
                combineHash
                    ( if skip == 0
                        then neighborPrefixFull
                        else
                            nibblesBetween path cursor (cursor + fromIntegral skip)
                                <> neighborPrefixFull
                    )
                    (neighborRoot neighbor)
            _ ->
                doFork
                    path
                    cursor
                    nextCursor
                    (doExcluding path (nextCursor + 1) steps)
                    neighbor
      where
        nextCursor = cursor + fromIntegral skip
        neighborPrefixFull =
            BS.cons (fromIntegral (neighborNibble neighbor)) (neighborPrefix neighbor)
    doExcluding _ cursor [Leaf _ key value] =
        combineHash (suffixFrom key cursor) value
    doExcluding path cursor (Leaf skip key value : steps) =
        doFork
            path
            cursor
            nextCursor
            (doExcluding path (nextCursor + 1) steps)
            Neighbor
                { neighborNibble = fromIntegral (nibbleAt key nextCursor)
                , neighborPrefix = suffixFrom key (nextCursor + 1)
                , neighborRoot = value
                }
      where
        nextCursor = cursor + fromIntegral skip

-- ------------------------------------------------------------------------
-- Wire helpers
-- ------------------------------------------------------------------------

{- | Decode a fixture's hex bytes (kept in hex so the constants stay
visually identical to the slice-gate fixture).
-}
hex :: ByteString -> ByteString
hex h = case convertFromBase Base16 h of
    Left err -> error ("MpfProofMirrorSpec: bad fixture hex: " <> err)
    Right bytes -> bytes

-- | Unwrap 'BuiltinData' for exact shape assertions.
dataOf :: BuiltinData -> Data
dataOf (BuiltinData d) = d

-- ------------------------------------------------------------------------
-- Spec
-- ------------------------------------------------------------------------

spec :: Spec
spec = do
    describe "ProofStep wire shape (#307 I4)" $ do
        it "Branch encodes as Constr 0 [skip, neighbors]" $ do
            let neighbors = BS.pack [1, 2, 3]
            dataOf (toBuiltinData (Branch 7 neighbors))
                `shouldBe` Constr 0 [I 7, B neighbors]
        it "Fork encodes as Constr 1 [skip, neighbor]" $ do
            let neighbor =
                    Neighbor 3 (BS.pack [4]) (BS.replicate 32 5)
            dataOf (toBuiltinData (Fork 2 neighbor))
                `shouldBe` Constr
                    1
                    [ I 2
                    , Constr 0 [I 3, B (BS.pack [4]), B (BS.replicate 32 5)]
                    ]
        it "Leaf encodes as Constr 2 [skip, key, value]" $ do
            let key = BS.pack [6]
                value = BS.pack [7, 8]
            dataOf (toBuiltinData (Leaf 1 key value))
                `shouldBe` Constr 2 [I 1, B key, B value]
        it "fixture proofs decode back through FromData unchanged" $ do
            fromBuiltinData (toBuiltinData leafForkProof)
                `shouldBe` Just leafForkProof
            fromBuiltinData (toBuiltinData terminalForkProof)
                `shouldBe` Just terminalForkProof
        it "fixture proofs decode through UnsafeFromData unchanged" $ do
            unsafeFromBuiltinData (toBuiltinData leafForkProof)
                `shouldBe` leafForkProof
            unsafeFromBuiltinData (toBuiltinData terminalForkProof)
                `shouldBe` terminalForkProof

    describe "Haskell mirror byte-identity with the Aiken library (#307 I5)" $ do
        it "leaf-fork rewindIncluding reproduces the post-insert root" $
            rewindIncluding leafForkKey leafForkValue leafForkProof
                `shouldBe` leafForkPostRoot
        it "leaf-fork rewindExcluding reproduces the pre-insert root" $
            rewindExcluding leafForkKey leafForkProof
                `shouldBe` leafForkPreRoot
        it "terminal-fork rewindIncluding reproduces the post-insert root" $
            rewindIncluding terminalForkKey terminalForkValue terminalForkProof
                `shouldBe` terminalForkPostRoot
        it "terminal-fork rewindExcluding reproduces the pre-insert root" $
            rewindExcluding terminalForkKey terminalForkProof
                `shouldBe` terminalForkPreRoot

    describe "negative controls (mirror assertions can fail)" $ do
        it "a mutated leaf-fork neighbor byte breaks rewindIncluding" $ do
            let mutated = case leafForkProof of
                    (Branch skip neighbors : rest) ->
                        Branch
                            skip
                            (BS.init neighbors <> BS.singleton 0x01)
                            : rest
                    other -> other
            rewindIncluding leafForkKey leafForkValue mutated
                `shouldSatisfy` (/= leafForkPostRoot)
        it "a wrong inserted value breaks rewindIncluding" $
            rewindIncluding
                leafForkKey
                (BS.cons 0x00 leafForkValue)
                leafForkProof
                `shouldSatisfy` (/= leafForkPostRoot)
        it "fork skip 1 -> 0 breaks rewindExcluding (the v2.0.0 regression class)" $ do
            let mutated = case terminalForkProof of
                    [b1, b2, b3, Fork _ neighbor] ->
                        [b1, b2, b3, Fork 0 neighbor]
                    other -> other
            rewindExcluding terminalForkKey mutated
                `shouldSatisfy` (/= terminalForkPreRoot)
        it "a deliberately wrong expected root is distinguished" $
            rewindIncluding terminalForkKey terminalForkValue terminalForkProof
                `shouldSatisfy` (/= BS.cons 0x00 (BS.drop 1 terminalForkPostRoot))
