{- |
Module      : Cardano.KERI.AID.Checkpoint.InvBindFrozenGrammarSpec
Description : The event object and anchor grammar rows of the readers' gate (#291)

The rows are shared bytes (@inv_bind_grammar_frozen.json@, @gen_grammar_cases.py@): one
genuine keripy self-addressing inception with single defects and the declared
size fixed up, each with its sha256, for both readers. A positive row must also
project its anchors typed, each element with its exact bytes. Each row's verdict
is printed so the receipt names it.
-}
module Cardano.KERI.AID.Checkpoint.InvBindFrozenGrammarSpec (spec) where

import Cardano.KERI.AID.Checkpoint.EventDecoder (
    AnchorItem (..),
    AnchorKind (..),
    DecodedEstablishmentEvent (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    loadFixture,
    lookupKey,
    textField,
 )
import Data.Aeson (Value (..))
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (Spec, describe, it, runIO, shouldBe)

data Row = Row
    { rowId :: Text
    , rowAccept :: Bool
    , rowRaw :: ByteString
    , rowSha :: Text
    , rowItems :: Maybe [AnchorItem]
    }

spec :: Spec
spec = describe "#291 event object and anchor grammar, the 35 frozen rows" $ do
    fixture <- runIO (loadFixture "inv_bind_grammar_frozen.json")
    let rows = either (error . ("grammar fixture: " <>)) id (loadRows fixture)
    runIO $
        mapM_
            ( \r ->
                putStrLn $
                    "GRAMMAR-ROW "
                        <> T.unpack (rowId r)
                        <> " expected="
                        <> (if rowAccept r then "accept" else "refuse")
                        <> " reader="
                        <> either show (const "accept") (decodeEstablishmentEvent (rowRaw r))
                        <> " sha256="
                        <> T.unpack (rowSha r)
            )
            rows
    it "has the ten structural rows and the well-formedness rows" $
        (length rows >= 35, length (filter rowAccept rows)) `shouldBe` (True, 7)
    describe "refuses every defective row" $
        mapM_
            ( \r ->
                it (T.unpack (rowId r)) $
                    either (const True) (const False) (decodeEstablishmentEvent (rowRaw r))
                        `shouldBe` True
            )
            [r | r <- rows, not (rowAccept r)]
    describe "accepts every positive row and projects its anchors typed" $
        mapM_
            ( \r ->
                it (T.unpack (rowId r)) $
                    fmap deeAnchorItems (decodeEstablishmentEvent (rowRaw r))
                        `shouldBe` Right (fromMaybe [] (rowItems r))
            )
            [r | r <- rows, rowAccept r]

loadRows :: Value -> Either String [Row]
loadRows fx = arrayField fx "rows" >>= mapM one
  where
    one r = do
        rid <- textField r "id"
        verdict <- textField r "expected"
        hex <- textField r "raw_hex"
        raw <- decodeHex hex
        sha <- textField r "sha256"
        items <- case lookupKey "anchor_items" r of
            Just (Array xs) -> Just <$> mapM item (toList xs)
            _ -> Right Nothing
        Right (Row rid (verdict == "accept") raw sha items)
    item v = do
        kind <- textField v "kind"
        raw <- textField v "raw"
        k <- case kind of
            "object" -> Right AnchorObject
            "array" -> Right AnchorArray
            "string" -> Right AnchorString
            "number" -> Right AnchorNumber
            "literal" -> Right AnchorLiteral
            _ -> Left ("kind " <> T.unpack kind)
        Right (AnchorItem k (TE.encodeUtf8 raw))
