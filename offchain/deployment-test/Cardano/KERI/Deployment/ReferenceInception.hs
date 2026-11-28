{- |
Module      : Cardano.KERI.Deployment.ReferenceInception
Description : Inceptions of independent reference, built through the production builder

The reference inceptions (event bytes, indexed signatures, identifier, SAID and
proof name stated by an independent structural reference) and the keripy
prefix cases, turned into 'InceptionExport' values by 'inceptionFromEvent' and
the stream reader, for the specs that exercise the builder and the booking.
-}
module Cardano.KERI.Deployment.ReferenceInception (
    Reference (..),
    loadReferences,
    pick,
    exportOf,
    referenceExport,
    prefixCaseExport,
    futureCaseExport,
    streamOf,
    respell,
) where

import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    inceptionFromEvent,
    parseInceptionExport,
 )
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Bits (shiftR, (.&.))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (expectationFailure)

-- | One reference inception: signed bytes, signatures and the values the reference states.
data Reference = Reference
    { refId :: !Text
    , refEvent :: !ByteString
    , refCtrlSigs :: ![(Int, ByteString)]
    , refIdentifier :: !Text
    , refSaid :: !Text
    , refProofName :: !ByteString
    , refMint :: !(ByteString, ByteString)
    }

exportOf :: Reference -> IO InceptionExport
exportOf r =
    either (\e -> expectationFailure e >> fail e) pure $
        parseInceptionExport (streamOf (refEvent r) (refCtrlSigs r))

pick :: Text -> [Reference] -> Reference
pick name refs = case filter ((== name) . refId) refs of
    [r] -> r
    _ -> error ("reference " <> T.unpack name <> " is not in the fixture exactly once")

loadReferences :: IO [Reference]
loadReferences = do
    path <- getDataFileName "test/keri-fixtures/fixtures/registration_reference.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure $ do
        cases <- field "cases" top >>= array
        traverse one cases
  where
    one c = do
        i <- field "id" c >>= text
        event <- field "event_hex" c >>= text >>= hex
        sigs <- field "ctrl_sigs" c >>= array >>= traverse sigOf
        ident <- field "identifier" c >>= text
        said <- field "said" c >>= text
        name <- field "proof_name" c >>= text >>= hex
        mint <- field "mint_fields" c >>= array >>= traverse (text >=> hex)
        case mint of
            [e, raw] -> Right (Reference i event sigs ident said name (e, raw))
            _ -> Left "mint redeemer is not two fields"
    sigOf p = do
        pair <- array p
        case pair of
            [Number n, String s] -> (,) (truncate n) <$> hex s
            _ -> Left "not an indexed signature"
    (>=>) f g x = f x >>= g

field :: Text -> Value -> Either String Value
field k v = case v of
    Object o | Just x <- KM.lookup (K.fromText k) o -> Right x
    _ -> Left (show k <> " missing")

array :: Value -> Either String [Value]
array (Array xs) = Right (toList xs)
array _ = Left "not an array"

text :: Value -> Either String Text
text (String t) = Right t
text _ = Left "not a string"

hex :: Text -> Either String ByteString
hex = convertFromBase Base16 . TE.encodeUtf8

{- | A kli-export message: the event, its attachment group counter, and the
indexed controller signatures as 88-character CESR tokens.
-}
streamOf :: ByteString -> [(Int, ByteString)] -> ByteString
streamOf event sigs =
    event
        <> "-V"
        <> counter (1 + 22 * length sigs)
        <> "-A"
        <> counter (length sigs)
        <> BS.concat (map token sigs)
  where
    counter n = B8.pack [digit (n `shiftR` 6), digit (n .&. 63)]
    token (index, signature) =
        B8.pack ('A' : digit index : [digit (bits `shiftR` (6 * k) .&. 63) | k <- [85, 84 .. 0]])
      where
        bits = foldl (\acc b -> acc * 256 + fromIntegral b) (0 :: Integer) (BS.unpack signature)
    digit :: (Integral a) => a -> Char
    digit v =
        let n = fromIntegral v :: Int
         in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" !! n

{- | Replace one spelling in the signed bytes and keep the version string's size
field equal to the new length, so that only the spelling differs.
-}
respell :: ByteString -> ByteString -> ByteString -> ByteString
respell raw old new =
    let (before, rest) = BS.breakSubstring old raw
        edited = before <> new <> BS.drop (BS.length old) rest
        size = B8.pack (pad (showHex6 (BS.length edited)))
     in BS.take 16 edited <> size <> BS.drop 22 edited
  where
    pad s = replicate (6 - length s) '0' <> s
    showHex6 n = case n of
        0 -> "0"
        _ -> go n ""
    go 0 acc = acc
    go n acc = go (n `div` 16) ("0123456789abcdef" !! (n `mod` 16) : acc)

-- | The reference inception of the given id, through the stream reader.
referenceExport :: Text -> IO InceptionExport
referenceExport name = do
    refs <- loadReferences
    exportOf (pick name refs)

{- | A keripy prefix case by its label (one controller signature, index 0 over the
signed bytes), through the same construction.
-}
prefixCaseExport :: Text -> IO InceptionExport
prefixCaseExport = caseExport "inception_prefix_cases.json"

{- | A weighted next declaration of draft #600 by its label: the signed bytes keep the spelling the
row declares (a literal @2/4@ stays @2/4@), signed by the one current key.
-}
futureCaseExport :: Text -> IO InceptionExport
futureCaseExport = caseExport "inception_future_cases.json"

caseExport :: FilePath -> Text -> IO InceptionExport
caseExport file label = do
    path <- getDataFileName ("test/keri-fixtures/fixtures/" <> file)
    top <- eitherDecodeFileStrict path >>= either fail pure
    cases <- either fail pure (field "cases" top >>= array)
    found <-
        either fail pure . sequenceA $
            [ do
                raw <- field "raw_hex" c >>= text >>= hex
                signature <- field "signature_hex" c >>= text >>= hex
                pure (raw, signature)
            | c <- cases
            , Right (String l) <- [field "label" c]
            , l == label
            ]
    case found of
        [(raw, signature)] ->
            either (\e -> expectationFailure e >> fail e) pure $
                inceptionFromEvent raw [(0, signature)] []
        _ -> fail ("prefix case " <> T.unpack label <> " is not in the fixture exactly once")
