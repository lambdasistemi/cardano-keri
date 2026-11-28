{- |
Module      : Cardano.KERI.AID.Checkpoint.Qualified
Description : Qualified spellings of identifiers and keys in the checkpoint datum

The datum keeps what the event signed: the identifier @i@ and each current key @k@ as their exact 44 character
qualified text (code, then the base64url of the raw payload). The raw 32 byte payload is derived at the boundaries that
need it: the proof token name, the signature checks and the key set rules. Mirrors @checkpoint/qualified.ak@.
-}
module Cardano.KERI.AID.Checkpoint.Qualified (
    codeB,
    codeD,
    codeE,
    payloadOf,
    qualify,
    identifierParts,
    identifierPayload,
    keyPayload,
    keyPayloads,
    digestPayload,
) where

import Data.ByteArray.Encoding (
    Base (Base64URLUnpadded),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word8)

-- | Code byte @B@: an Ed25519 verification key that cannot rotate.
codeB :: Word8
codeB = 66

-- | Code byte @D@: an Ed25519 verification key that can rotate.
codeD :: Word8
codeD = 68

-- | Code byte @E@: a 256 bit digest.
codeE :: Word8
codeE = 69

{- | The raw 32 byte payload of a 44 character qualified text whose code is one of @codes@. The padding bits must be
zero: 'Nothing' unless @qualify code payload == text@.
-}
payloadOf :: [Word8] -> ByteString -> Maybe ByteString
payloadOf codes text
    | BS.length text == 44 && BS.head text `elem` codes =
        case convertFromBase Base64URLUnpadded (BS.cons 65 (BS.drop 1 text)) :: Either String ByteString of
            Right raw | BS.length raw == 33 && BS.head raw == 0 -> Just (BS.drop 1 raw)
            _ -> Nothing
    | otherwise = Nothing

-- | The qualified text of a raw 32 byte payload under a code.
qualify :: Word8 -> ByteString -> ByteString
qualify code payload =
    BS.cons code (BS.drop 1 (convertToBase Base64URLUnpadded (BS.cons 0 payload)))

-- | The code and raw payload of an identifier: a key (@B@, @D@) or a digest (@E@).
identifierParts :: ByteString -> Maybe (Word8, ByteString)
identifierParts text = (,) (BS.head text) <$> identifierPayload text

-- | The raw payload of an identifier of any of the three codes.
identifierPayload :: ByteString -> Maybe ByteString
identifierPayload = payloadOf [codeB, codeD, codeE]

-- | The raw payload of a current key: a @B@ or @D@ verification key.
keyPayload :: ByteString -> Maybe ByteString
keyPayload = payloadOf [codeB, codeD]

-- | The raw payloads of a list of current keys, in order, or 'Nothing' when one is not a qualified key.
keyPayloads :: [ByteString] -> Maybe [ByteString]
keyPayloads = traverse keyPayload

-- | The raw payload of a digest text, code @E@.
digestPayload :: ByteString -> Maybe ByteString
digestPayload = payloadOf [codeE]
