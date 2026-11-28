{- |
Module      : Cardano.KERI.AID.Checkpoint.InvBindTopStringsSpec
Description : String validity of the top-level members of an event (#291)

The agreed grammar applies to every string of the event: member names and
values at the top level as well as nested ones. The rows
(@inv_bind_toplevel_strings.json@, @gen_toplevel_string_cases.py@) put one defect
in a top-level name or value of a genuine keripy inception, with the declared
size fixed up, and name the refusal the reader must give. A well-formed escape is
valid JSON: the reader keeps the raw spelling and the schema or the spelling check
refuses it. Each verdict is printed for the receipt.
-}
module Cardano.KERI.AID.Checkpoint.InvBindTopStringsSpec (spec) where

import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    EventDecodeError (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    loadFixture,
    lookupKey,
    textField,
 )
import Control.Monad (void)
import Data.Aeson (Value (..))
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as T
import Test.Hspec (Spec, describe, it, runIO, shouldBe)

data Row = Row
    { rowId :: Text
    , rowRaw :: ByteString
    , rowSha :: Text
    , rowExpected :: Either EventDecodeError ()
    , rowSeq :: Maybe ByteString
    -- ^ the raw spelling the reader must keep for the sequence number
    }

spec :: Spec
spec = describe "#291 top-level string validity" $ do
    fixture <- runIO (loadFixture "inv_bind_toplevel_strings.json")
    let rows = either (error . ("string rows: " <>)) id (loadRows fixture)
    runIO $
        mapM_
            ( \r ->
                putStrLn $
                    "STRING-ROW "
                        <> T.unpack (rowId r)
                        <> " expected="
                        <> either show (const "accept") (rowExpected r)
                        <> " reader="
                        <> either show (const "accept") (decodeEstablishmentEvent (rowRaw r))
                        <> " sha256="
                        <> T.unpack (rowSha r)
            )
            rows
    it "has the twelve base rows and the 76 rows of the four lexical paths" $ length rows `shouldBe` 88
    describe "gives the named verdict on every row" $
        mapM_
            ( \r ->
                it (T.unpack (rowId r)) $
                    ( void (decodeEstablishmentEvent (rowRaw r))
                    , rowSeq r >> either (const Nothing) (Just . deeSeq) (decodeEstablishmentEvent (rowRaw r))
                    )
                        `shouldBe` (rowExpected r, rowSeq r)
            )
            rows

loadRows :: Value -> Either String [Row]
loadRows fx = arrayField fx "rows" >>= mapM one
  where
    one r = do
        rid <- textField r "id"
        verdict <- textField r "expected"
        hex <- textField r "raw_hex"
        raw <- decodeHex hex
        sha <- textField r "sha256"
        expected <- case (verdict, lookupKey "error" r) of
            ("accept", _) -> Right (Right ())
            (_, Just (String e)) -> Left <$> errorOf e
            _ -> Left ("row " <> T.unpack rid)
        seqRaw <- case lookupKey "seq_raw_hex" r of
            Just (String q) -> Just <$> decodeHex q
            _ -> Right Nothing
        Right (Row rid raw sha expected seqRaw)
    errorOf = \case
        "ErrFraming" -> Right ErrFraming
        "ErrFieldOrder" -> Right ErrFieldOrder
        "ErrValueShape" -> Right ErrValueShape
        "ErrUnsupportedType" -> Right ErrUnsupportedType
        e -> Left ("error " <> T.unpack e)
