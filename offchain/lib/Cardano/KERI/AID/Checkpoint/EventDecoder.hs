{- |
Module      : Cardano.KERI.AID.Checkpoint.EventDecoder
Description : Bytes-only total parse of a KERI establishment event (#291)

Derives event variant, protected field values, and SAID blanking solely
from complete event bytes. No caller offset is accepted.
-}
module Cardano.KERI.AID.Checkpoint.EventDecoder (
    EventVariant (..),
    EventDecodeError (..),
    DecodedEstablishmentEvent (..),
    decodeEstablishmentEvent,
    decodeSaidPreimage,
) where

import Data.ByteString (ByteString)

-- | Structural establishment-event variant.
data EventVariant
    = -- | Inception.
      VariantIcp
    | -- | Delegated inception.
      VariantDip
    | -- | Rotation.
      VariantRot
    | -- | Delegated rotation.
      VariantDrt
    deriving stock (Show, Eq)

-- | Closed total-parse rejection.
data EventDecodeError
    = ErrLengthBound
    | ErrVersionPrefix
    | ErrVersionSize
    | ErrFraming
    | ErrFieldOrder
    | ErrValueShape
    | ErrUnsupportedType
    | ErrTrailing
    deriving stock (Show, Eq)

-- | Protected raw spellings from a successful total parse.
data DecodedEstablishmentEvent = DecodedEstablishmentEvent
    { deeVariant :: !EventVariant
    , deeSaid :: !ByteString
    , deeAid :: !ByteString
    , deeSeq :: !ByteString
    , deePrior :: !(Maybe ByteString)
    , deeKt :: !ByteString
    , deeK :: ![ByteString]
    , deeNt :: !ByteString
    , deeN :: ![ByteString]
    , deeBt :: !ByteString
    , deeB :: ![ByteString]
    , deeBr :: ![ByteString]
    , deeBa :: ![ByteString]
    , deeDi :: !(Maybe ByteString)
    , deeSaidPreimage :: !ByteString
    }
    deriving stock (Show, Eq)

-- | Placeholder until the decoder is ported: accepts any bytes as an
-- inception with empty fields.
decodeEstablishmentEvent
    :: ByteString
    -> Either EventDecodeError DecodedEstablishmentEvent
decodeEstablishmentEvent _ =
    Right
        DecodedEstablishmentEvent
            { deeVariant = VariantIcp
            , deeSaid = mempty
            , deeAid = mempty
            , deeSeq = mempty
            , deePrior = Nothing
            , deeKt = mempty
            , deeK = []
            , deeNt = mempty
            , deeN = []
            , deeBt = mempty
            , deeB = []
            , deeBr = []
            , deeBa = []
            , deeDi = Nothing
            , deeSaidPreimage = mempty
            }

-- | SAID-blanked preimage from a successful total parse.
decodeSaidPreimage
    :: ByteString -> Either EventDecodeError ByteString
decodeSaidPreimage raw =
    deeSaidPreimage <$> decodeEstablishmentEvent raw
