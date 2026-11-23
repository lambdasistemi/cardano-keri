{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFiles
Description : The two files a registry deployment writes

A deployment of a registry leaves two files. The release identity is the
document of "Cardano.KERI.ChainQuery.ReleaseIdentity": everything a program
needs to follow and read the registry. The reference-output record says where
the deployment published what its transactions read by reference: the state
template, the application, the state script, the registration observer, the
hash-proof policy and the checkpoint validator, and the registry's
configuration record. It holds only facts a reader can rebuild from the chain:
output references, script hashes, transaction ids and the network. It names no
registered identity.

This is the one module of the deployment that touches the release identity's
file codec: the commands take and give an identity through here.
-}
module Cardano.KERI.Deployment.RegistryFiles (
    -- * The reference-output record
    ScriptReference (..),
    ReferenceRecord (..),
    ReferenceRecordError (..),
    encodeReferenceRecord,
    decodeReferenceRecord,

    -- * Agreement of the two files
    RecordMismatch (..),
    recordMismatches,

    -- * The files
    FilesError (..),
    checkFilesWritable,
    writeDeploymentFiles,
    writeFileNew,
    readDeploymentFiles,
    renderIdentity,
) where

import Cardano.KERI.AID.Application (OutputReference (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.ChainQuery.ReleaseIdentity (
    ReleaseIdentityError,
    decodeReleaseIdentity,
    encodeReleaseIdentity,
 )
import Control.Exception (IOException, try)
import Control.Monad (forM_, unless)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Scientific (base10Exponent, floatingOrInteger, isInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (
    canonicalizePath,
    doesDirectoryExist,
    doesFileExist,
    removeFile,
 )
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hClose, openBinaryTempFile)
import System.IO.Error (isAlreadyExistsError)
import System.Posix.Files (createLink)

-- | A published script: the output that holds it and its script hash.
data ScriptReference = ScriptReference
    { scriptOutput :: !OutputReference
    , scriptHash :: !ByteString
    -- ^ the 28 bytes of the script's hash
    }
    deriving stock (Eq, Show)

{- | Where a deployment published what its transactions read by reference. The
transaction ids are 32 bytes, the hashes 28.
-}
data ReferenceRecord = ReferenceRecord
    { recordNetwork :: !Integer
    -- ^ the network discriminator the deployment ran on: 0 or 1
    , recordTemplate :: !OutputReference
    -- ^ the output whose inline datum is the state template
    , recordApplication :: !ScriptReference
    , recordState :: !ScriptReference
    , recordRegistration :: !ScriptReference
    -- ^ the registration (lifecycle) observer
    , recordHashProof :: !ScriptReference
    , recordCheckpoint :: !ScriptReference
    , recordConfiguration :: !OutputReference
    -- ^ the registry's configuration record
    , recordRegistryState :: !OutputReference
    -- ^ the output the genesis created to hold the registry's state
    , recordCredentialRegistration :: !(Maybe ByteString)
    -- ^ the transaction that registered the registration observer's reward credential; absent when an earlier deployment had registered it
    , recordGenesis :: !ByteString
    -- ^ the transaction that created the registry
    }
    deriving stock (Eq, Show)

-- | Why a document is not a reference-output record: one constructor per kind of problem.
data ReferenceRecordError
    = -- | the text is not JSON
      RecordNotJson !String
    | -- | the value at this path (empty for the document) is not an object
      RecordNotAnObject !Text
    | -- | no value at this path
      RecordMissingField !Text
    | -- | the value at this path is not of the type of the field
      RecordWrongType !Text
    | -- | the schema version of the document is not the one this reader knows
      RecordUnknownSchemaVersion !Integer
    | -- | the text at this path is not hexadecimal
      RecordNotHex !Text
    | -- | the hash or transaction id at this path has this many bytes where it needs that many
      RecordWrongLength !Text !Int !Int
    | -- | the output index at this path is below zero
      RecordNegativeIndex !Text
    | -- | the network is neither 0 nor 1
      RecordNetworkOutOfRange !Integer
    deriving stock (Eq, Show)

recordSchemaVersion :: Integer
recordSchemaVersion = 1

-- | The document of a record.
encodeReferenceRecord :: ReferenceRecord -> ByteString
encodeReferenceRecord record =
    BL.toStrict . Aeson.encode $
        object
            [ "schema_version" .= recordSchemaVersion
            , "network" .= recordNetwork record
            , "template" .= outputValue (recordTemplate record)
            , "application" .= scriptValue (recordApplication record)
            , "state" .= scriptValue (recordState record)
            , "registration_observer" .= scriptValue (recordRegistration record)
            , "hash_proof" .= scriptValue (recordHashProof record)
            , "checkpoint_validator" .= scriptValue (recordCheckpoint record)
            , "configuration" .= outputValue (recordConfiguration record)
            , "registry_state" .= outputValue (recordRegistryState record)
            , "credential_registration" .= fmap hex (recordCredentialRegistration record)
            , "genesis" .= hex (recordGenesis record)
            ]
  where
    outputValue (OutputReference transaction index) =
        object ["transaction_id" .= hex transaction, "index" .= index]
    scriptValue (ScriptReference output hash) =
        object
            [ "output" .= outputValue output
            , "script_hash" .= hex hash
            ]

hex :: ByteString -> Text
hex = TE.decodeUtf8 . convertToBase Base16

-- | The record a document names, or why it names none.
decodeReferenceRecord :: ByteString -> Either ReferenceRecordError ReferenceRecord
decodeReferenceRecord bytes = do
    document <- either (Left . RecordNotJson) Right (Aeson.eitherDecodeStrict bytes)
    root <- objectOf "" document
    version <- integerAt [] root "schema_version"
    unless (version == recordSchemaVersion) $
        Left (RecordUnknownSchemaVersion version)
    network <- integerAt [] root "network"
    unless (network `elem` [0, 1]) $
        Left (RecordNetworkOutOfRange network)
    ReferenceRecord network
        <$> outputAt [] root "template"
        <*> scriptAt root "application"
        <*> scriptAt root "state"
        <*> scriptAt root "registration_observer"
        <*> scriptAt root "hash_proof"
        <*> scriptAt root "checkpoint_validator"
        <*> outputAt [] root "configuration"
        <*> outputAt [] root "registry_state"
        <*> optionalHashAt [] root "credential_registration" 32
        <*> hashAt [] root "genesis" 32
  where
    scriptAt fields name = do
        script <- objectAt [] fields name
        ScriptReference
            <$> outputAt [name] script "output"
            <*> hashAt [name] script "script_hash" 28

type Fields = KeyMap.KeyMap Value

pathOf :: [Text] -> Text -> Text
pathOf parents name = T.intercalate "." (parents <> [name])

objectOf :: Text -> Value -> Either ReferenceRecordError Fields
objectOf _ (Object fields) = Right fields
objectOf at _ = Left (RecordNotAnObject at)

fieldAt :: [Text] -> Fields -> Text -> Either ReferenceRecordError Value
fieldAt parents fields name =
    maybe
        (Left (RecordMissingField (pathOf parents name)))
        Right
        (KeyMap.lookup (Key.fromText name) fields)

objectAt :: [Text] -> Fields -> Text -> Either ReferenceRecordError Fields
objectAt parents fields name =
    fieldAt parents fields name >>= objectOf (pathOf parents name)

integerAt :: [Text] -> Fields -> Text -> Either ReferenceRecordError Integer
integerAt parents fields name = do
    value <- fieldAt parents fields name
    case value of
        Number n
            | isInteger n
            , base10Exponent n < 100_000
            , Right integer <- floatingOrInteger @Double n ->
                Right integer
        _ -> Left (RecordWrongType (pathOf parents name))

hashAt ::
    [Text] -> Fields -> Text -> Int -> Either ReferenceRecordError ByteString
hashAt parents fields name expected = do
    value <- fieldAt parents fields name
    text <- case value of
        String t -> Right t
        _ -> Left (RecordWrongType (pathOf parents name))
    bytes <-
        either
            (const (Left (RecordNotHex (pathOf parents name))))
            Right
            (convertFromBase Base16 (TE.encodeUtf8 text))
    if BS.length bytes /= expected
        then Left (RecordWrongLength (pathOf parents name) expected (BS.length bytes))
        else Right bytes

optionalHashAt ::
    [Text] -> Fields -> Text -> Int -> Either ReferenceRecordError (Maybe ByteString)
optionalHashAt parents fields name expected = do
    value <- fieldAt parents fields name
    case value of
        Null -> Right Nothing
        _ -> Just <$> hashAt parents fields name expected

outputAt ::
    [Text] -> Fields -> Text -> Either ReferenceRecordError OutputReference
outputAt parents fields name = do
    output <- objectAt parents fields name
    let at = parents <> [name]
    transaction <- hashAt at output "transaction_id" 32
    index <- integerAt at output "index"
    if index < 0
        then Left (RecordNegativeIndex (pathOf at "index"))
        else Right (OutputReference transaction index)

-- | A fact the two files state differently.
data RecordMismatch
    = NetworkDiffers
    | ApplicationHashDiffers
    | StateHashDiffers
    | CheckpointHashDiffers
    deriving stock (Eq, Show)

{- | Where the reference-output record and the release identity say different
things about one registry: the network, and the script hash of the
application, of the state script and of the checkpoint validator.
-}
recordMismatches :: ReleaseIdentity -> ReferenceRecord -> [RecordMismatch]
recordMismatches identity record =
    [NetworkDiffers | recordNetwork record /= riNetwork identity]
        <> [ ApplicationHashDiffers
           | scriptHash (recordApplication record) /= rlApplicationPolicy release
                || scriptHash (recordApplication record) /= rlApplicationCredential release
           ]
        <> [StateHashDiffers | scriptHash (recordState record) /= rlStatePolicy release]
        <> [ CheckpointHashDiffers
           | scriptHash (recordCheckpoint record) /= riCheckpointValidator identity
           ]
  where
    release = riRelease identity

-- | Why the files were not written or read.
data FilesError
    = -- | a file is already there; a deployment does not overwrite another's
      FileExists !FilePath
    | -- | the directory the file goes to does not exist
      DirectoryMissing !FilePath
    | -- | files cannot be created in the directory the file goes to
      DirectoryNotWritable !FilePath
    | -- | something other than a file is where a file goes
      NotAFile !FilePath
    | -- | the two files are given the same destination
      SameDestination !FilePath
    | -- | the system refused this file
      FileIo !FilePath !String
    | -- | the release identity file is not a release identity
      IdentityFileInvalid !FilePath !ReleaseIdentityError
    | -- | the reference-output record file is not a record
      RecordFileInvalid !FilePath !ReferenceRecordError
    | -- | the two files describe different registries
      FilesDisagree ![RecordMismatch]
    deriving stock (Eq, Show)

{- | Whether the two files can be written: neither is there and their
directories are. A deployment asks before it spends anything.
-}
checkFilesWritable :: FilePath -> FilePath -> IO (Either FilesError ())
checkFilesWritable identityPath recordPath = do
    sameIdentity <- canonical identityPath
    sameRecord <- canonical recordPath
    if sameIdentity == sameRecord
        then pure (Left (SameDestination identityPath))
        else do
            results <- traverse check [identityPath, recordPath]
            pure (sequence_ results)
  where
    canonical path = do
        parent <- canonicalizePath (directoryOf path)
        pure (parent </> takeFileName path)
    check path = do
        isDirectory <- doesDirectoryExist path
        isFile <- doesFileExist path
        parent <- doesDirectoryExist (directoryOf path)
        probed <- if parent then probeWritable (directoryOf path) else pure True
        pure $
            if isDirectory
                then Left (NotAFile path)
                else
                    if isFile
                        then Left (FileExists path)
                        else
                            if not parent
                                then Left (DirectoryMissing (directoryOf path))
                                else
                                    if probed
                                        then Right ()
                                        else Left (DirectoryNotWritable (directoryOf path))

{- | Whether a file can be created in a directory: one is created there and
removed, because the permission bits do not say what a user, a mount or a
quota allows.
-}
probeWritable :: FilePath -> IO Bool
probeWritable directory = do
    probe <- try @IOException $ do
        (temporary, handle) <- openBinaryTempFile directory ".ckeri-registry.probe"
        hClose handle
        removeFile temporary
    pure (either (const False) (const True) probe)

directoryOf :: FilePath -> FilePath
directoryOf path = case takeDirectory path of
    "" -> "."
    directory -> directory

-- | The text of the release identity file.
renderIdentity :: ReleaseIdentity -> ByteString
renderIdentity = encodeReleaseIdentity

{- | Write both files, each linked into place from a finished temporary file,
refusing to replace anything that is there.
-}
writeDeploymentFiles ::
    FilePath -> FilePath -> ReleaseIdentity -> ReferenceRecord -> IO (Either FilesError ())
writeDeploymentFiles identityPath recordPath identity record = do
    checked <- checkFilesWritable identityPath recordPath
    case checked of
        Left refusal -> pure (Left refusal)
        Right () -> do
            first <- writeFileNew identityPath (renderIdentity identity <> "\n")
            case first of
                Left failure -> pure (Left failure)
                Right () -> do
                    second <- writeFileNew recordPath (encodeReferenceRecord record <> "\n")
                    case second of
                        Left failure -> do
                            _ <- try @IOException (removeFile identityPath)
                            pure (Left failure)
                        Right () -> pure (Right ())

{- | Write a file that is not there: the contents are finished in a temporary
file and linked to the destination, which fails if anything is already there, so
a file that appeared in the meantime is never replaced.
-}
writeFileNew :: FilePath -> ByteString -> IO (Either FilesError ())
writeFileNew path contents = do
    created <- try @IOException $ openBinaryTempFile (directoryOf path) ".ckeri-registry.tmp"
    case created of
        Left failure -> pure (Left (FileIo path (show failure)))
        Right (temporary, handle) -> do
            result <- try @IOException $ do
                BS.hPut handle contents
                hClose handle
                createLink temporary path
            _ <- try @IOException (removeFile temporary)
            pure $ case result of
                Right () -> Right ()
                Left failure
                    | isAlreadyExistsError failure -> Left (FileExists path)
                    | otherwise -> Left (FileIo path (show failure))

{- | Read both files and refuse the pair unless each decodes and they agree on
the registry.
-}
readDeploymentFiles ::
    FilePath -> FilePath -> IO (Either FilesError (ReleaseIdentity, ReferenceRecord))
readDeploymentFiles identityPath recordPath = do
    identityBytes <- readOne identityPath
    recordBytes <- readOne recordPath
    pure $ do
        identityText <- identityBytes
        recordText <- recordBytes
        identity <-
            either (Left . IdentityFileInvalid identityPath) Right (decodeReleaseIdentity identityText)
        record <-
            either (Left . RecordFileInvalid recordPath) Right (decodeReferenceRecord recordText)
        let mismatches = recordMismatches identity record
        forM_ [() | not (null mismatches)] $ \() -> Left (FilesDisagree mismatches)
        pure (identity, record)
  where
    readOne path = do
        result <- try @IOException (BS.readFile path)
        pure (either (Left . FileIo path . show) Right result)
