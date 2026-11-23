{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistrySnapshot
Description : The keys a registry holds, as one party supplies them to a folder

A fold must show the registry state it builds on: the keys the registry holds as
active and as terminal. The party that folds does not keep that list; it is given
one, in a file that names who supplied it, and checks it against the registry
state the chain holds before it pays anything. The file is an input, never a
record the command trusts.

A key is written as the identifier's qualified text, 44 characters as the KEL
spells it: those bytes are what the registry's state inserts, what a booking
commits and what a fold looks up, so a key is one value in every layer.
-}
module Cardano.KERI.Deployment.RegistrySnapshot (
    Snapshot (..),
    SnapshotError (..),
    snapshotRoot,
    snapshotHolds,
    encodeSnapshot,
    decodeSnapshot,
) where

import Cardano.KERI.Deployment.RegistryTransactions (registryRootOf)
import Control.Monad (forM_, unless, when, (>=>))
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isAsciiUpper, isControl, isDigit)
import Data.Foldable (toList)
import Data.Scientific (isInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

-- | The active and the terminal keys of a registry, and the party that supplied them.
data Snapshot = Snapshot
    { snapshotSuppliedBy :: !Text
    , snapshotActive :: ![ByteString]
    , snapshotTerminal :: ![ByteString]
    }
    deriving stock (Eq, Show)

-- | Why a document is not a snapshot.
data SnapshotError
    = SnapshotNotJson !String
    | SnapshotUnknownSchemaVersion !Integer
    | SnapshotMissingField !Text
    | SnapshotWrongType !Text
    | SnapshotNoSupplier
    | -- | the supplier is printed as one line: it may not hold a line break or another control character
      SnapshotSupplierHasControlCharacters
    | -- | a key that is not an identifier: 44 characters of the URL-safe base64 alphabet
      SnapshotKeyNotAnIdentifier !Text
    | SnapshotKeyListedTwice !Text
    deriving stock (Eq, Show)

-- | The root of the registry the snapshot describes.
snapshotRoot :: Snapshot -> ByteString
snapshotRoot snapshot = registryRootOf (snapshotActive snapshot) (snapshotTerminal snapshot)

-- | Whether the snapshot holds the key, active or terminal.
snapshotHolds :: Snapshot -> ByteString -> Bool
snapshotHolds snapshot key = key `elem` snapshotActive snapshot || key `elem` snapshotTerminal snapshot

schemaVersion :: Integer
schemaVersion = 1

{- | A key as the document writes it: the identifier's qualified text, which is
also the bytes the registry inserts.
-}
keyText :: ByteString -> Text
keyText = TE.decodeUtf8

-- | The document a snapshot is written as.
encodeSnapshot :: Snapshot -> ByteString
encodeSnapshot snapshot =
    BL.toStrict . Aeson.encode $
        object
            [ "schema_version" .= schemaVersion
            , "supplied_by" .= snapshotSuppliedBy snapshot
            , "active" .= map keyText (snapshotActive snapshot)
            , "terminal" .= map keyText (snapshotTerminal snapshot)
            ]

-- | The snapshot a document is, or why it is none.
decodeSnapshot :: ByteString -> Either SnapshotError Snapshot
decodeSnapshot bytes = do
    document <- first SnapshotNotJson (Aeson.eitherDecodeStrict bytes)
    fields <- case document of
        Object fields -> Right fields
        _ -> Left (SnapshotWrongType "")
    version <- field fields "schema_version" >>= asInteger "schema_version"
    unless (version == schemaVersion) $ Left (SnapshotUnknownSchemaVersion version)
    supplier <- field fields "supplied_by" >>= asText "supplied_by"
    when (T.null (T.strip supplier)) $ Left SnapshotNoSupplier
    when (T.any isControl supplier) $ Left SnapshotSupplierHasControlCharacters
    active <- field fields "active" >>= keysOf "active"
    terminal <- field fields "terminal" >>= keysOf "terminal"
    let listed = active <> terminal
    forM_ (zip [0 :: Int ..] listed) $ \(index, key) ->
        when (key `elem` take index listed) $ Left (SnapshotKeyListedTwice (keyText key))
    pure (Snapshot supplier active terminal)
  where
    field fields name = maybe (Left (SnapshotMissingField name)) Right (KeyMap.lookup (Key.fromText name) fields)
    asInteger name = \case
        Number n | isInteger n -> Right (truncate n)
        _ -> Left (SnapshotWrongType name)
    asText name = \case
        String text -> Right text
        _ -> Left (SnapshotWrongType name)
    keysOf name = \case
        Array items -> traverse (asText name >=> keyOf) (toList items)
        _ -> Left (SnapshotWrongType name)
    keyOf text = do
        unless (T.length text == 44 && T.all isIdentifierCharacter text) $ Left (SnapshotKeyNotAnIdentifier text)
        pure (TE.encodeUtf8 text)
    isIdentifierCharacter c = isAsciiUpper c || isAsciiLower c || isDigit c || c == '-' || c == '_'
