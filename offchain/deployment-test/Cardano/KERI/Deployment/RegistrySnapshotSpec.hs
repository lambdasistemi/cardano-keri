{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistrySnapshotSpec
Description : the snapshot a folder is given names its supplier and both key sets, and refuses what is not one

The file format is spelled out here, by hand, as a reader of the documentation
would write it; the decoder is judged on that text and on what it refuses. A key
is the identifier's qualified text, the bytes the registry inserts.
-}
module Cardano.KERI.Deployment.RegistrySnapshotSpec (spec) where

import Cardano.KERI.Deployment.RegistrySnapshot
import Cardano.KERI.Deployment.RegistryTransactions (emptyRoot, registryRootOf)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as B8
import Data.Either (isLeft)
import Data.Text qualified as T
import Test.Hspec

-- | The text of the n-th identifier of these examples: 44 characters, the first the derivation code.
identifierN :: Int -> String
identifierN n = 'E' : replicate 43 (alphabet !! n)
  where
    alphabet = ['A' .. 'Z'] <> ['a' .. 'z'] <> ['0' .. '9'] <> "-_"

keyN :: Int -> ByteString
keyN = B8.pack . identifierN

document :: String -> String -> String -> ByteString
document supplier active terminal =
    B8.pack $
        "{\"schema_version\":1,\"supplied_by\":\"" <> supplier <> "\",\"active\":[" <> active <> "],\"terminal\":[" <> terminal <> "]}"

quoted :: Int -> String
quoted n = "\"" <> identifierN n <> "\""

spec :: Spec
spec = describe "#351 the registry snapshot a folder is given" $ do
    it "reads the document a person would write: who supplied it, the active keys and the terminal keys" $ do
        decodeSnapshot (document "the deployer" (quoted 1 <> "," <> quoted 2) (quoted 10))
            `shouldBe` Right (Snapshot "the deployer" [keyN 1, keyN 2] [keyN 10])
        decodeSnapshot (document "an empty registry" "" "")
            `shouldBe` Right (Snapshot "an empty registry" [] [])
    it "reads an identifier as the 44 bytes of its text, the bytes the registry inserts" $
        decodeSnapshot (document "x" "\"EPcveXNZuGWIbahVBVIMWN5fyIQTMGXqa0afXTOCsq1G\"" "")
            `shouldBe` Right (Snapshot "x" ["EPcveXNZuGWIbahVBVIMWN5fyIQTMGXqa0afXTOCsq1G"] [])
    it "writes what it reads, for none, one and several keys" $
        mapM_
            (\snapshot -> decodeSnapshot (encodeSnapshot snapshot) `shouldBe` Right snapshot)
            [ Snapshot "nobody holds anything" [] []
            , Snapshot "one active" [keyN 1] []
            , Snapshot "one terminal" [] [keyN 2]
            , Snapshot "several of each" [keyN 1, keyN 3, keyN 5] [keyN 2, keyN 4]
            ]
    it "is the registry whose root the keys give, in whatever order they are listed" $ do
        snapshotRoot (Snapshot "x" [] []) `shouldBe` emptyRoot
        snapshotRoot (Snapshot "x" [keyN 1, keyN 2] [keyN 9])
            `shouldBe` registryRootOf [keyN 1, keyN 2] [keyN 9]
        snapshotRoot (Snapshot "x" [keyN 2, keyN 1] [keyN 9])
            `shouldBe` snapshotRoot (Snapshot "x" [keyN 1, keyN 2] [keyN 9])
        snapshotRoot (Snapshot "x" [keyN 9] []) `shouldNotBe` snapshotRoot (Snapshot "x" [] [keyN 9])
    it "holds a key when it is listed active or terminal, and not otherwise" $ do
        let snapshot = Snapshot "x" [keyN 1, keyN 3] [keyN 2]
        map (snapshotHolds snapshot . keyN) [1, 2, 3, 4] `shouldBe` [True, True, True, False]
    it "refuses a document that is not one, each in its own way" $ do
        decodeSnapshot "not json" `shouldSatisfy` isLeft
        decodeSnapshot "[]" `shouldBe` Left (SnapshotWrongType "")
        decodeSnapshot "{\"schema_version\":2,\"supplied_by\":\"x\",\"active\":[],\"terminal\":[]}"
            `shouldBe` Left (SnapshotUnknownSchemaVersion 2)
        decodeSnapshot "{\"schema_version\":1,\"active\":[],\"terminal\":[]}"
            `shouldBe` Left (SnapshotMissingField "supplied_by")
        decodeSnapshot (document "" "" "") `shouldBe` Left SnapshotNoSupplier
        decodeSnapshot (document "the deployer\\nbooking-transaction: forged" "" "")
            `shouldBe` Left SnapshotSupplierHasControlCharacters
        decodeSnapshot (document "tab\\there" "" "")
            `shouldBe` Left SnapshotSupplierHasControlCharacters
        decodeSnapshot (document "x" "\"zz\"" "") `shouldBe` Left (SnapshotKeyNotAnIdentifier "zz")
        decodeSnapshot (document "x" ("\"" <> replicate 64 'a' <> "\"") "")
            `shouldBe` Left (SnapshotKeyNotAnIdentifier (T.pack (replicate 64 'a')))
        decodeSnapshot (document "x" ("\"E" <> replicate 42 'a' <> "!\"") "")
            `shouldBe` Left (SnapshotKeyNotAnIdentifier (T.pack ('E' : replicate 42 'a' <> "!")))
        decodeSnapshot (document "x" (quoted 1 <> "," <> quoted 1) "")
            `shouldBe` Left (SnapshotKeyListedTwice (T.pack (identifierN 1)))
        decodeSnapshot (document "x" (quoted 1) (quoted 1))
            `shouldBe` Left (SnapshotKeyListedTwice (T.pack (identifierN 1)))
