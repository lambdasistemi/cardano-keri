{- |
Module      : Cardano.KERI.AID.Blake3.Checkpoint
Description : Single-chunk BLAKE3 checkpoint support
License     : Apache-2.0

Pure Haskell support for the issue 97 checkpointed BLAKE3 spike.
The hash helpers cover one BLAKE3 chunk, up to 1024 bytes, and expose the
same chaining-value wire representation as the Aiken spike: eight little-endian
u32 words in @h0..h7@ order.

Hand-written 'ToData'\/'FromData' instances guarantee that checkpoint datum
and redeemer encodings match the Aiken constructor indices and field order.
-}
module Cardano.KERI.AID.Blake3.Checkpoint (
    -- * BLAKE3 checkpointing
    Blake3Checkpoint (..),
    initialChainingValue,
    absorbBlocks,
    finishFromCheckpoint,
    blake3Hash,
    blake3Verify,

    -- * PlutusData types
    CheckpointDatum (..),
    CheckpointRedeemer (..),
) where

import Data.Bits (
    rotateR,
    shiftL,
    shiftR,
    xor,
    (.|.),
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Word (
    Word32,
    Word64,
    Word8,
 )
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

-- | A BLAKE3 checkpoint after absorbing full 64-byte blocks.
data Blake3Checkpoint = Blake3Checkpoint
    { checkpointChainingValue :: !ByteString
    -- ^ Chaining value encoded as eight little-endian u32 words.
    , checkpointNextOffset :: !Integer
    -- ^ Next byte offset to process.
    }
    deriving stock (Show, Eq)

-- | Checkpoint datum matching Aiken @checkpoint.Datum@.
data CheckpointDatum = CheckpointDatum
    { inputCommitment :: !ByteString
    , checkpointCv :: !ByteString
    , checkpointOffset :: !Integer
    , checkpointLength :: !Integer
    , expectedPrefix :: !ByteString
    }
    deriving stock (Show, Eq)

-- | Checkpoint redeemer matching Aiken @checkpoint.Redeemer@.
data CheckpointRedeemer
    = CheckpointStep
        { stepInput :: !ByteString
        , stepBlocks :: !Integer
        }
    | CheckpointFinish
        { finishInput :: !ByteString
        }
    deriving stock (Show, Eq)

-- | Initial BLAKE3 hash-mode chaining value, in wire representation.
initialChainingValue :: ByteString
initialChainingValue = cvToBytes iv

-- | Absorb @blocks@ full 64-byte blocks from @offset@.
absorbBlocks ::
    -- | Current chaining value.
    ByteString ->
    -- | Full input chunk.
    ByteString ->
    -- | Byte offset.
    Integer ->
    -- | Number of full blocks to absorb.
    Integer ->
    Blake3Checkpoint
absorbBlocks cvBytes input offset blocks =
    Blake3Checkpoint
        { checkpointChainingValue = cvToBytes finalCv
        , checkpointNextOffset = finalOffset
        }
  where
    startCv = cvFromBytes cvBytes
    (finalCv, finalOffset) =
        foldl' absorbOne (startCv, offset) [0 .. blocks - 1]

    absorbOne (cv, currentOffset) _ =
        let block = blockWordsAt input currentOffset
            flags = startFlag currentOffset
            nextCv = compressChainingValue cv block 0 blockLen flags
         in (nextCv, currentOffset + blockLenInteger)

-- | Finish a one-chunk BLAKE3 hash from a checkpoint offset.
finishFromCheckpoint ::
    -- | Current chaining value.
    ByteString ->
    -- | Full input chunk.
    ByteString ->
    -- | Byte offset.
    Integer ->
    ByteString
finishFromCheckpoint cvBytes input offset =
    cvToBytes $ take 8 $ go (cvFromBytes cvBytes) offset
  where
    inputLength = fromIntegral $ BS.length input

    go cv currentOffset
        | inputLength > chunkLenInteger =
            error "finishFromCheckpoint: input exceeds one BLAKE3 chunk"
        | currentOffset < 0 || currentOffset > inputLength =
            error "finishFromCheckpoint: offset outside input"
        | remaining <= blockLenInteger =
            compressOutput
                cv
                (blockWordsAt input currentOffset)
                0
                (fromIntegral remaining)
                (startFlag currentOffset .|. flagChunkEnd .|. flagRoot)
        | otherwise =
            let nextCv =
                    compressChainingValue
                        cv
                        (blockWordsAt input currentOffset)
                        0
                        blockLen
                        (startFlag currentOffset)
             in go nextCv (currentOffset + blockLenInteger)
      where
        remaining = inputLength - currentOffset

-- | Hash one BLAKE3 chunk in hash mode.
blake3Hash :: ByteString -> ByteString
blake3Hash input = finishFromCheckpoint initialChainingValue input 0

-- | Verify a one-chunk BLAKE3 hash-mode digest.
blake3Verify :: ByteString -> ByteString -> Bool
blake3Verify input expected = blake3Hash input == expected

-- ---------------------------------------------------------
-- BLAKE3 compression
-- ---------------------------------------------------------

iv :: [Word32]
iv =
    [ 0x6A09E667
    , 0xBB67AE85
    , 0x3C6EF372
    , 0xA54FF53A
    , 0x510E527F
    , 0x9B05688C
    , 0x1F83D9AB
    , 0x5BE0CD19
    ]

messagePermutation :: [Int]
messagePermutation =
    [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

blockLen :: Word32
blockLen = 64

blockLenInteger :: Integer
blockLenInteger = 64

chunkLenInteger :: Integer
chunkLenInteger = 1024

flagChunkStart :: Word32
flagChunkStart = 1

flagChunkEnd :: Word32
flagChunkEnd = 2

flagRoot :: Word32
flagRoot = 8

startFlag :: Integer -> Word32
startFlag 0 = flagChunkStart
startFlag _ = 0

compressChainingValue ::
    [Word32] ->
    [Word32] ->
    Word64 ->
    Word32 ->
    Word32 ->
    [Word32]
compressChainingValue cv block counter len flags =
    take 8 $ compressOutput cv block counter len flags

compressOutput ::
    [Word32] ->
    [Word32] ->
    Word64 ->
    Word32 ->
    Word32 ->
    [Word32]
compressOutput cv block counter len flags =
    zipWith xor (take 8 finalState) (drop 8 finalState)
        <> zipWith xor (drop 8 finalState) cv
  where
    finalState = rounds initialState block
    initialState =
        cv
            <> take 4 iv
            <> [ fromIntegral counter
               , fromIntegral $ counter `shiftR` 32
               , len
               , flags
               ]

rounds :: [Word32] -> [Word32] -> [Word32]
rounds = go 0
  where
    go :: Int -> [Word32] -> [Word32] -> [Word32]
    go roundNo stateN wordsN
        | roundNo == 7 = stateN
        | otherwise =
            go (roundNo + 1) (roundFunction stateN wordsN) $
                permute wordsN

roundFunction :: [Word32] -> [Word32] -> [Word32]
roundFunction state wordsN =
    mix 3 4 9 14 (word 14) (word 15) $
        mix 2 7 8 13 (word 12) (word 13) $
            mix 1 6 11 12 (word 10) (word 11) $
                mix 0 5 10 15 (word 8) (word 9) $
                    mix 3 7 11 15 (word 6) (word 7) $
                        mix 2 6 10 14 (word 4) (word 5) $
                            mix 1 5 9 13 (word 2) (word 3) $
                                mix 0 4 8 12 (word 0) (word 1) state
  where
    word i = wordsN !! i

mix ::
    Int ->
    Int ->
    Int ->
    Int ->
    Word32 ->
    Word32 ->
    [Word32] ->
    [Word32]
mix a b c d x y state =
    setAt d d2 $
        setAt c c2 $
            setAt b b2 $
                setAt a a2 state
  where
    a0 = state !! a
    b0 = state !! b
    c0 = state !! c
    d0 = state !! d
    a1 = a0 + b0 + x
    d1 = (d0 `xor` a1) `rotateR` 16
    c1 = c0 + d1
    b1 = (b0 `xor` c1) `rotateR` 12
    a2 = a1 + b1 + y
    d2 = (d1 `xor` a2) `rotateR` 8
    c2 = c1 + d2
    b2 = (b1 `xor` c2) `rotateR` 7

permute :: [Word32] -> [Word32]
permute wordsN = fmap (wordsN !!) messagePermutation

setAt :: Int -> Word32 -> [Word32] -> [Word32]
setAt index value values =
    take index values <> [value] <> drop (index + 1) values

blockWordsAt :: ByteString -> Integer -> [Word32]
blockWordsAt input offset =
    fmap word32At [0, 4 .. 60]
  where
    block =
        BS.take (fromIntegral blockLenInteger) $
            BS.drop (fromIntegral offset) input
    padded = block <> BS.replicate (fromIntegral blockLenInteger - BS.length block) 0
    word32At i =
        fromIntegral (BS.index padded i)
            .|. shiftL (fromIntegral (BS.index padded (i + 1))) 8
            .|. shiftL (fromIntegral (BS.index padded (i + 2))) 16
            .|. shiftL (fromIntegral (BS.index padded (i + 3))) 24

cvToBytes :: [Word32] -> ByteString
cvToBytes wordsN = BS.pack $ wordsN >>= word32Bytes

word32Bytes :: Word32 -> [Word8]
word32Bytes word =
    [ fromIntegral word
    , fromIntegral $ word `shiftR` 8
    , fromIntegral $ word `shiftR` 16
    , fromIntegral $ word `shiftR` 24
    ]

cvFromBytes :: ByteString -> [Word32]
cvFromBytes bytes
    | BS.length bytes == 32 =
        fmap word32At [0, 4 .. 28]
    | otherwise =
        error "cvFromBytes: expected 32-byte chaining value"
  where
    word32At i =
        fromIntegral (BS.index bytes i)
            .|. shiftL (fromIntegral (BS.index bytes (i + 1))) 8
            .|. shiftL (fromIntegral (BS.index bytes (i + 2))) 16
            .|. shiftL (fromIntegral (BS.index bytes (i + 3))) 24

-- ---------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------

mkD :: Data -> BuiltinData
mkD = BuiltinData

unD :: BuiltinData -> Data
unD (BuiltinData datum) = datum

bsToD :: ByteString -> Data
bsToD = B

bsFromD :: Data -> Maybe ByteString
bsFromD (B bytes) = Just bytes
bsFromD _ = Nothing

-- ---------------------------------------------------------
-- ToData / FromData instances
-- ---------------------------------------------------------

-- | Constr 0 [B input_commitment, B cv, I offset, I len, B expected_prefix]
instance ToData CheckpointDatum where
    toBuiltinData CheckpointDatum{..} =
        mkD $
            Constr
                0
                [ bsToD inputCommitment
                , bsToD checkpointCv
                , I checkpointOffset
                , I checkpointLength
                , bsToD expectedPrefix
                ]

instance FromData CheckpointDatum where
    fromBuiltinData bd = case unD bd of
        Constr 0 [inputD, cvD, I offset, I len, prefixD] -> do
            inputCommitment <- bsFromD inputD
            checkpointCv <- bsFromD cvD
            expectedPrefix <- bsFromD prefixD
            Just
                CheckpointDatum
                    { checkpointOffset = offset
                    , checkpointLength = len
                    , ..
                    }
        _ -> Nothing

instance UnsafeFromData CheckpointDatum where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [B inputCommitment, B checkpointCv, I checkpointOffset, I checkpointLength, B expectedPrefix] ->
            CheckpointDatum{..}
        _ -> error "unsafeFromBuiltinData: CheckpointDatum"

-- | Step: Constr 0 [B input, I blocks]; Finish: Constr 1 [B input]
instance ToData CheckpointRedeemer where
    toBuiltinData CheckpointStep{..} =
        mkD $ Constr 0 [bsToD stepInput, I stepBlocks]
    toBuiltinData CheckpointFinish{..} =
        mkD $ Constr 1 [bsToD finishInput]

instance FromData CheckpointRedeemer where
    fromBuiltinData bd = case unD bd of
        Constr 0 [inputD, I blocks] -> do
            stepInput <- bsFromD inputD
            Just $ CheckpointStep stepInput blocks
        Constr 1 [inputD] ->
            CheckpointFinish <$> bsFromD inputD
        _ -> Nothing

instance UnsafeFromData CheckpointRedeemer where
    unsafeFromBuiltinData bd = case unD bd of
        Constr 0 [B input, I blocks] -> CheckpointStep input blocks
        Constr 1 [B input] -> CheckpointFinish input
        _ -> error "unsafeFromBuiltinData: CheckpointRedeemer"
