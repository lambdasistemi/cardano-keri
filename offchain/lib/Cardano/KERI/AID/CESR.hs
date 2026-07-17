module Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
    qb64Verkey,
) where

import Data.ByteArray.Encoding (
    Base (Base64URLUnpadded),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS

-- | Subset of CESR primitives needed for Ed25519 AID verification.
data Primitive
    = {- | @B@ (non-transferable) or @D@ (transferable) — a raw 32-byte
      Ed25519 public key. This module does not track transferability;
      no consumer needs the distinction.
      -}
      Ed25519PublicKey !ByteString
    | -- | 0B — 64-byte Ed25519 signature
      Ed25519Signature !ByteString
    | -- | E — 32-byte self-addressing identifier (Blake3-256 digest)
      SelfAddressing !ByteString
    deriving stock (Show, Eq)

{- | Parse one CESR primitive from the front of a Base64url text stream.
Returns the primitive and any unconsumed input.
-}
parsePrimitive :: ByteString -> Either String (Primitive, ByteString)
parsePrimitive bs = case BS.uncons bs of
    Nothing -> Left "empty input"
    Just (c0, _) -> case c0 of
        0x30 -> parse2char bs -- '0'
        _ -> parse1char bs

-- 1-char code: 44 chars total, 1 lead byte stripped → 32 bytes.
-- The code char occupies the first base64url slot; replace with 'A' to decode.
parse1char :: ByteString -> Either String (Primitive, ByteString)
parse1char bs
    | BS.length bs < 44 = Left "truncated 1-char primitive"
    | otherwise = do
        let (tok, rest) = BS.splitAt 44 bs
        raw <- decodeB64Url (BS.cons 0x41 (BS.tail tok)) -- 'A' + rest
        let payload = BS.drop 1 raw -- strip 1 lead byte
        case BS.index tok 0 of
            0x42 -> Right (Ed25519PublicKey payload, rest) -- 'B' (non-transferable)
            0x44 -> Right (Ed25519PublicKey payload, rest) -- 'D' (transferable)
            0x45 -> Right (SelfAddressing payload, rest) -- 'E'
            code -> Left $ "unknown 1-char code: " <> show code

-- 2-char code: 88 chars total, 2 lead bytes stripped → 64 bytes.
-- The two code chars occupy the first two base64url slots; replace with "AA".
parse2char :: ByteString -> Either String (Primitive, ByteString)
parse2char bs
    | BS.length bs < 88 = Left "truncated 2-char primitive"
    | otherwise = do
        let (tok, rest) = BS.splitAt 88 bs
        raw <- decodeB64Url ("AA" <> BS.drop 2 tok)
        let payload = BS.drop 2 raw -- strip 2 lead bytes
        case BS.take 2 tok of
            "0B" -> Right (Ed25519Signature payload, rest)
            code -> Left $ "unknown 2-char code: " <> show code

decodeB64Url :: ByteString -> Either String ByteString
decodeB64Url input = convertFromBase Base64URLUnpadded input :: Either String ByteString

{- | The fully qualified Base64url (qb64) form of a raw 32-byte transferable
Ed25519 verkey: code @\'D\'@ followed by @b64url(0x00 ‖ key)@ with the first
(always @\'A\'@) character replaced by the code — 44 ASCII characters. This is
the exact preimage KERI digests for KEL @n@ entries
(@keripy: Diger(ser=verfer.qb64b)@).
-}
qb64Verkey :: ByteString -> ByteString
qb64Verkey key =
    BS.cons 0x44 (BS.drop 1 b64) -- 'D' replaces the leading 'A'
  where
    b64 = convertToBase Base64URLUnpadded (BS.cons 0x00 key)
