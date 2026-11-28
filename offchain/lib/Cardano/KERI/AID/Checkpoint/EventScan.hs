{- |
Module      : Cardano.KERI.AID.Checkpoint.EventScan
Description : The anchor array scanner of a signed establishment event

The one place the rebuilt event binding reads the event rather than compares it: the anchor array after the last
field. The profile is compact JSON as keripy emits it: no whitespace; strings are valid UTF-8 without raw control
characters, a backslash followed by one of @\" \\ / b f n r t@ or by @u@ and four hexadecimal digits of either case (an
escaped surrogate, paired or lone, is admissible and its escape bytes are kept); numbers follow the JSON grammar; the
literals are @true@, @false@ and @null@. Mirrors @event_decoder.anchor_after@ of the validators.
-}
module Cardano.KERI.AID.Checkpoint.EventScan (
    anchorAfter,
    valueEnd,
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8

-- | The byte at a position, or -1.
byteAt :: ByteString -> Int -> Int
byteAt raw pos
    | pos >= 0 && pos < BS.length raw = fromIntegral (BS.index raw pos)
    | otherwise = -1

hasAt :: ByteString -> Int -> ByteString -> Bool
hasAt raw pos text =
    pos >= 0 && pos + n <= BS.length raw && BS.take n (BS.drop pos raw) == text
  where
    n = BS.length text

isDigit :: Int -> Bool
isDigit b = b >= 48 && b <= 57

isHex :: Int -> Bool
isHex b = isDigit b || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)

hexRun :: ByteString -> Int -> Int -> Bool
hexRun raw pos count = all (isHex . byteAt raw) [pos .. pos + count - 1]

continuation :: ByteString -> Int -> Int -> Int -> Bool
continuation raw pos low high = let b = byteAt raw pos in b >= low && b <= high

-- | The position after the one UTF-8 sequence at @pos@ (RFC 3629), or -1.
utf8End :: ByteString -> Int -> Int
utf8End raw pos
    | b0 >= 0 && b0 < 128 = pos + 1
    | b0 >= 194 && b0 <= 223 = need [(1, 128, 191)] 2
    | b0 == 224 = need [(1, 160, 191), (2, 128, 191)] 3
    | b0 == 237 = need [(1, 128, 159), (2, 128, 191)] 3
    | b0 >= 225 && b0 <= 239 = need [(1, 128, 191), (2, 128, 191)] 3
    | b0 == 240 = need [(1, 144, 191), (2, 128, 191), (3, 128, 191)] 4
    | b0 >= 241 && b0 <= 243 = need [(1, 128, 191), (2, 128, 191), (3, 128, 191)] 4
    | b0 == 244 = need [(1, 128, 143), (2, 128, 191), (3, 128, 191)] 4
    | otherwise = -1
  where
    b0 = byteAt raw pos
    need cs width
        | all (\(i, lo, hi) -> continuation raw (pos + i) lo hi) cs = pos + width
        | otherwise = -1

-- | The position after the closing quote of the string whose content starts at @pos@, or -1.
stringAfter :: ByteString -> Int -> Int
stringAfter raw pos
    | b == 34 = pos + 1
    | b == 92 =
        let e = byteAt raw (pos + 1)
         in if e == 117
                then if hexRun raw (pos + 2) 4 then stringAfter raw (pos + 6) else -1
                else
                    if e `elem` [34, 92, 47, 98, 102, 110, 114, 116]
                        then stringAfter raw (pos + 2)
                        else -1
    | b < 32 = -1
    | otherwise =
        let next = utf8End raw pos
         in if next < 0 then -1 else stringAfter raw next
  where
    b = byteAt raw pos

digitsEnd :: ByteString -> Int -> Int
digitsEnd raw pos
    | isDigit (byteAt raw pos) = digitsEnd raw (pos + 1)
    | otherwise = pos

-- | The position after the JSON number at @pos@, or -1.
numberAfter :: ByteString -> Int -> Int
numberAfter raw pos
    | integerEnd < 0 = -1
    | fractionEnd < 0 = -1
    | marker == 101 || marker == 69 =
        let sign = byteAt raw (fractionEnd + 1)
            from = if sign == 43 || sign == 45 then fractionEnd + 2 else fractionEnd + 1
            end = digitsEnd raw from
         in if end == from then -1 else end
    | otherwise = fractionEnd
  where
    start = if byteAt raw pos == 45 then pos + 1 else pos
    lead = byteAt raw start
    integerEnd
        | lead == 48 = start + 1
        | lead >= 49 && lead <= 57 = digitsEnd raw (start + 1)
        | otherwise = -1
    fractionEnd
        | byteAt raw integerEnd == 46 =
            let end = digitsEnd raw (integerEnd + 1)
             in if end == integerEnd + 1 then -1 else end
        | otherwise = integerEnd
    marker = byteAt raw fractionEnd

-- | The end of the compact JSON value at @pos@, or -1 when it is malformed.
valueEnd :: ByteString -> Int -> Int
valueEnd raw pos
    | b == 34 = stringAfter raw (pos + 1)
    | b == 91 = arrayAfter raw pos
    | b == 123 = objectAfter raw pos
    | hasAt raw pos (BS8.pack "true") = pos + 4
    | hasAt raw pos (BS8.pack "false") = pos + 5
    | hasAt raw pos (BS8.pack "null") = pos + 4
    | b == 45 || isDigit b = numberAfter raw pos
    | otherwise = -1
  where
    b = byteAt raw pos

arrayAfter :: ByteString -> Int -> Int
arrayAfter raw pos
    | hasAt raw pos (BS8.pack "[]") = pos + 2
    | otherwise = elementsAfter raw (pos + 1)

elementsAfter :: ByteString -> Int -> Int
elementsAfter raw pos
    | end < 0 = -1
    | hasAt raw end (BS8.pack ",") = elementsAfter raw (end + 1)
    | hasAt raw end (BS8.pack "]") = end + 1
    | otherwise = -1
  where
    end = valueEnd raw pos

objectAfter :: ByteString -> Int -> Int
objectAfter raw pos
    | hasAt raw pos (BS8.pack "{}") = pos + 2
    | otherwise = membersAfter raw (pos + 1)

membersAfter :: ByteString -> Int -> Int
membersAfter raw pos
    | byteAt raw pos /= 34 = -1
    | afterName < 0 || byteAt raw afterName /= 58 = -1
    | end < 0 = -1
    | hasAt raw end (BS8.pack ",") = membersAfter raw (end + 1)
    | hasAt raw end (BS8.pack "}") = end + 1
    | otherwise = -1
  where
    afterName = stringAfter raw (pos + 1)
    end = valueEnd raw (afterName + 1)

{- | The anchor array at @pos@: the number of its elements and the position after it, or 'Nothing' when it is not one
complete array of complete values.
-}
anchorAfter :: ByteString -> Int -> Maybe (Int, Int)
anchorAfter raw pos
    | byteAt raw pos /= 91 = Nothing
    | hasAt raw pos (BS8.pack "[]") = Just (0, pos + 2)
    | otherwise = items (pos + 1) 0
  where
    items p count =
        let end = valueEnd raw p
         in if end < 0
                then Nothing
                else
                    if hasAt raw end (BS8.pack ",")
                        then items (end + 1) (count + 1)
                        else
                            if hasAt raw end (BS8.pack "]")
                                then Just (count + 1, end + 1)
                                else Nothing
