{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFilesSpec
Description : the reference-output record and the two files a deployment writes

The record holds facts a reader rebuilds from the chain and nothing else: its
leaf fields are spelled out here, and a document with one more is not what the
encoder writes. Each field deleted, cut, lengthened, made non-hexadecimal, given
the wrong type or a value outside its range has its own refusal, naming the
field. The two files are written without replacing either, read back together,
and refused when they describe different registries.
-}
module Cardano.KERI.Deployment.RegistryFilesSpec (spec) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), OutputReference (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.ChainQuery.ReleaseIdentity (decodeReleaseIdentity)
import Cardano.KERI.Deployment.RegistryFiles
import Control.Exception (finally)
import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word8)
import System.Directory (createDirectory, doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createSymbolicLink, setFileMode)
import System.Posix.User (getEffectiveUserID)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldReturn)

-- | A record whose every hash and transaction id is distinct from the next record's.
recordOf :: Word8 -> ReferenceRecord
recordOf n =
    ReferenceRecord
        { recordNetwork = fromIntegral (n `mod` 2)
        , recordTemplate = out 0x10 0
        , recordApplication = script 0x20 1
        , recordState = script 0x30 2
        , recordRegistration = script 0x40 3
        , recordHashProof = script 0x50 4
        , recordCheckpoint = script 0x60 5
        , recordConfiguration = out 0x70 1
        , recordRegistryState = out 0x70 0
        , recordCredentialRegistration = Just (BS.replicate 32 (n + 0x80))
        , recordGenesis = BS.replicate 32 (n + 0x90)
        }
  where
    out base = OutputReference (BS.replicate 32 (n + base))
    script base index =
        ScriptReference (out base index) (BS.replicate 28 (n + base + 1))

-- | The identity a record agrees with.
identityOf :: ReferenceRecord -> ReleaseIdentity
identityOf record =
    ReleaseIdentity
        { riNetwork = recordNetwork record
        , riRelease =
            Release
                { rlApplicationPolicy = scriptHash (recordApplication record)
                , rlApplicationCredential = scriptHash (recordApplication record)
                , rlStateProgram = scriptHash (recordState record)
                , rlStatePolicy = scriptHash (recordState record)
                }
        , riSeed = OutputReference (BS.replicate 32 0x0a) 7
        , riCheckpointValidator = scriptHash (recordCheckpoint record)
        , riDeposit = 1_000_000_000
        , riFreezeBond = 5_000_000
        , riPremium = 2_000_000
        , riMinimumAda = 2_000_000
        , riTerminationCarrier = 1_500_000
        , riApplicationParameters =
            ApplicationParameters
                { registrationCost = 1_000_000
                , minimumTip = 500_000
                , processTime = 90_000
                , bookingWidth = 5_000
                }
        }

-- | Every leaf of the document, by dotted path: the whole schema of the record.
schemaLeaves :: [Text]
schemaLeaves =
    sort $
        ["schema_version", "network", "credential_registration", "genesis"]
            <> [ field <> "." <> leaf
               | field <- ["template", "configuration", "registry_state"]
               , leaf <- ["transaction_id", "index"]
               ]
            <> [ field <> ".output." <> leaf
               | field <- scripts
               , leaf <- ["transaction_id", "index"]
               ]
            <> [field <> ".script_hash" | field <- scripts]
  where
    scripts =
        [ "application"
        , "state"
        , "registration_observer"
        , "hash_proof"
        , "checkpoint_validator"
        ]

leavesOf :: Value -> [Text]
leavesOf = sort . go []
  where
    go path (Object fields) =
        concat
            [ go (path <> [Key.toText key]) value
            | (key, value) <- KeyMap.toList fields
            ]
    go path _ = [T.intercalate "." path]

documentOf :: ReferenceRecord -> Value
documentOf record =
    case Aeson.decodeStrict (encodeReferenceRecord record) of
        Just value -> value
        Nothing -> error "the encoder wrote something that is not JSON"

reencode :: Value -> ByteString
reencode = BL.toStrict . Aeson.encode

alter :: [Text] -> (Maybe Value -> Maybe Value) -> Value -> Value
alter [] _ value = value
alter [key] change (Object fields) =
    Object (alterKey (Key.fromText key) change fields)
alter (key : rest) change (Object fields) =
    Object (alterKey (Key.fromText key) (fmap (alter rest change)) fields)
alter _ _ value = value

alterKey :: Key.Key -> (Maybe Value -> Maybe Value) -> KeyMap.KeyMap Value -> KeyMap.KeyMap Value
alterKey key change fields =
    case change (KeyMap.lookup key fields) of
        Nothing -> KeyMap.delete key fields
        Just value -> KeyMap.insert key value fields

valueAt :: [Text] -> Value -> Maybe Value
valueAt [] value = Just value
valueAt (key : rest) (Object fields) =
    KeyMap.lookup (Key.fromText key) fields >>= valueAt rest
valueAt _ _ = Nothing

spec :: Spec
spec = describe "#351 the reference-output record and the deployment's two files" $ do
    describe "the record" $ do
        it "is read back as written, for records that share no byte" $
            mapM_
                ( \n ->
                    decodeReferenceRecord (encodeReferenceRecord (recordOf n))
                        `shouldBe` Right (recordOf n)
                )
                [0, 1, 2, 3, 4, 5]
        it "states the facts of its schema and no other: no identity of a registrant, no key set" $
            mapM_
                (\n -> leavesOf (documentOf (recordOf n)) `shouldBe` schemaLeaves)
                [0, 1, 2]
        it "reads a record whose credential an earlier deployment registered: the registration is null, not missing" $ do
            let record = (recordOf 2){recordCredentialRegistration = Nothing}
            valueAt ["credential_registration"] (documentOf record) `shouldBe` Just Null
            decodeReferenceRecord (encodeReferenceRecord record) `shouldBe` Right record
            leavesOf (documentOf record) `shouldBe` schemaLeaves
        it "carries a schema version, and a reader of another version refuses it by name" $ do
            valueAt ["schema_version"] (documentOf (recordOf 1)) `shouldBe` Just (Number 1)
            decodeReferenceRecord
                (reencode (alter ["schema_version"] (const (Just (Number 2))) (documentOf (recordOf 1))))
                `shouldBe` Left (RecordUnknownSchemaVersion 2)
        it "refuses a document that is not JSON, and one that is not an object" $ do
            case decodeReferenceRecord "not json" of
                Left (RecordNotJson _) -> pure ()
                other -> fail ("expected not JSON, got " <> show other)
            decodeReferenceRecord "[]" `shouldBe` Left (RecordNotAnObject "")
        it "names the field a document lacks, for every field of the schema" $
            mapM_
                ( \leaf ->
                    decodeReferenceRecord
                        (reencode (alter (T.splitOn "." leaf) (const Nothing) (documentOf (recordOf 2))))
                        `shouldBe` Left (RecordMissingField (missingNameFor leaf))
                )
                [leaf | leaf <- schemaLeaves, leaf /= "schema_version"]
        it "names the hash a document cuts, lengthens or writes in no hexadecimal" $ do
            let hashes =
                    [ ("application.script_hash", 28)
                    , ("state.script_hash", 28)
                    , ("registration_observer.script_hash", 28)
                    , ("hash_proof.script_hash", 28)
                    , ("checkpoint_validator.script_hash", 28)
                    , ("genesis", 32)
                    , ("credential_registration", 32)
                    , ("template.transaction_id", 32)
                    , ("configuration.transaction_id", 32)
                    , ("registry_state.transaction_id", 32)
                    , ("application.output.transaction_id", 32)
                    ]
                alterHash leaf text =
                    reencode (alter (T.splitOn "." leaf) (const (Just (String text))) (documentOf (recordOf 2)))
            mapM_
                ( \(leaf, size) -> do
                    decodeReferenceRecord (alterHash leaf (T.replicate (size - 1) "ab"))
                        `shouldBe` Left (RecordWrongLength leaf size (size - 1))
                    decodeReferenceRecord (alterHash leaf (T.replicate (size + 1) "ab"))
                        `shouldBe` Left (RecordWrongLength leaf size (size + 1))
                    decodeReferenceRecord (alterHash leaf (T.replicate size "zz"))
                        `shouldBe` Left (RecordNotHex leaf)
                )
                hashes
        it "refuses a negative output index, a network that is neither 0 nor 1, and a field of the wrong type" $ do
            let withValue path value =
                    reencode (alter (T.splitOn "." path) (const (Just value)) (documentOf (recordOf 2)))
            decodeReferenceRecord (withValue "template.index" (Number (-1)))
                `shouldBe` Left (RecordNegativeIndex "template.index")
            decodeReferenceRecord (withValue "application.output.index" (Number (-3)))
                `shouldBe` Left (RecordNegativeIndex "application.output.index")
            decodeReferenceRecord (withValue "network" (Number 2))
                `shouldBe` Left (RecordNetworkOutOfRange 2)
            decodeReferenceRecord (withValue "network" (String "0"))
                `shouldBe` Left (RecordWrongType "network")
            decodeReferenceRecord (withValue "genesis" (Number 7))
                `shouldBe` Left (RecordWrongType "genesis")
            decodeReferenceRecord (withValue "state" (String "x"))
                `shouldBe` Left (RecordNotAnObject "state")

    describe "the agreement of the record with the release identity" $ do
        it "finds nothing between files that describe one registry" $
            mapM_
                (\n -> recordMismatches (identityOf (recordOf n)) (recordOf n) `shouldBe` [])
                [0, 1, 2, 3]
        it "names each fact the two files state differently" $ do
            let record = recordOf 1
                identity = identityOf record
                other = BS.replicate 28 0xee
            recordMismatches identity record{recordNetwork = 1 - recordNetwork record}
                `shouldBe` [NetworkDiffers]
            recordMismatches identity record{recordApplication = (recordApplication record){scriptHash = other}}
                `shouldBe` [ApplicationHashDiffers]
            recordMismatches identity record{recordState = (recordState record){scriptHash = other}}
                `shouldBe` [StateHashDiffers]
            recordMismatches identity record{recordCheckpoint = (recordCheckpoint record){scriptHash = other}}
                `shouldBe` [CheckpointHashDiffers]

    describe "the files" $ do
        it "are written, and read back together as the identity and the record" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let record = recordOf 3
                    identity = identityOf record
                    identityFile = directory </> "release-identity.json"
                    recordFile = directory </> "reference-outputs.json"
                checkFilesWritable identityFile recordFile `shouldReturn` Right ()
                writeDeploymentFiles identityFile recordFile identity record
                    `shouldReturn` Right ()
                readDeploymentFiles identityFile recordFile
                    `shouldReturn` Right (identity, record)
                BS.readFile identityFile >>= \bytes ->
                    decodeReleaseIdentity bytes `shouldBe` Right identity
                sort <$> listDirectory directory
                    `shouldReturn` ["reference-outputs.json", "release-identity.json"]
        it "are not written over: either file already there stops the deployment before it spends" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let record = recordOf 1
                    identityFile = directory </> "release-identity.json"
                    recordFile = directory </> "reference-outputs.json"
                BS.writeFile recordFile "someone else's"
                checkFilesWritable identityFile recordFile
                    `shouldReturn` Left (FileExists recordFile)
                writeDeploymentFiles identityFile recordFile (identityOf record) record
                    `shouldReturn` Left (FileExists recordFile)
                doesFileExist identityFile `shouldReturn` False
                BS.readFile recordFile `shouldReturn` "someone else's"
                BS.writeFile identityFile "another's"
                checkFilesWritable identityFile (directory </> "other.json")
                    `shouldReturn` Left (FileExists identityFile)
        it "need the directory they go to" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let missing = directory </> "absent"
                checkFilesWritable (missing </> "a.json") (directory </> "b.json")
                    `shouldReturn` Left (DirectoryMissing missing)
                createDirectory missing
                checkFilesWritable (missing </> "a.json") (directory </> "b.json")
                    `shouldReturn` Right ()
        it "need a directory a file can be created in: a read-only one is refused by name before anything is spent" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                root <- (== 0) <$> getEffectiveUserID
                if root
                    then pendingWith "a superuser can create files in a read-only directory"
                    else do
                        let record = recordOf 1
                            writable = directory </> "writable"
                            readOnly = directory </> "read-only"
                            identityFile = writable </> "release-identity.json"
                            recordFile = readOnly </> "reference-outputs.json"
                        createDirectory writable
                        createDirectory readOnly
                        setFileMode readOnly 0o555
                        ( do
                                checkFilesWritable identityFile recordFile
                                    `shouldReturn` Left (DirectoryNotWritable readOnly)
                                writeDeploymentFiles identityFile recordFile (identityOf record) record
                                    `shouldReturn` Left (DirectoryNotWritable readOnly)
                                -- nothing was written in the directory that could be
                                listDirectory writable `shouldReturn` []
                            )
                            `finally` setFileMode readOnly 0o755
        it "are not given one destination: the same path, however spelled, stops the deployment before it spends" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let record = recordOf 1
                    one = directory </> "both.json"
                    spelledOtherwise = directory </> "." </> "both.json"
                checkFilesWritable one one `shouldReturn` Left (SameDestination one)
                checkFilesWritable one spelledOtherwise `shouldReturn` Left (SameDestination one)
                writeDeploymentFiles one spelledOtherwise (identityOf record) record
                    `shouldReturn` Left (SameDestination one)
                listDirectory directory `shouldReturn` []
        it "are not given one destination under two names: a symlinked directory is the same destination, and two distinct paths are not" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let record = recordOf 1
                    out = directory </> "out"
                    alias = directory </> "alias"
                    other = directory </> "other"
                createDirectory out
                createDirectory other
                createSymbolicLink out alias
                let viaOut = out </> "result.json"
                    viaAlias = alias </> "result.json"
                checkFilesWritable viaOut viaAlias `shouldReturn` Left (SameDestination viaOut)
                writeDeploymentFiles viaOut viaAlias (identityOf record) record
                    `shouldReturn` Left (SameDestination viaOut)
                listDirectory out `shouldReturn` []
                -- the control: genuinely distinct destinations, one of them through the link
                checkFilesWritable viaAlias (other </> "result.json") `shouldReturn` Right ()
                checkFilesWritable (out </> "a.json") (alias </> "b.json") `shouldReturn` Right ()
        it "are not written where something other than a file is: a directory is refused by name before anything is spent" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let record = recordOf 1
                    identityFile = directory </> "release-identity.json"
                    recordFile = directory </> "reference-outputs.json"
                createDirectory recordFile
                checkFilesWritable identityFile recordFile `shouldReturn` Left (NotAFile recordFile)
                writeDeploymentFiles identityFile recordFile (identityOf record) record
                    `shouldReturn` Left (NotAFile recordFile)
                doesFileExist identityFile `shouldReturn` False
        it "are never written over, whatever appears between the check and the write" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let path = directory </> "appeared.json"
                BS.writeFile path "another's"
                writeFileNew path "ours" `shouldReturn` Left (FileExists path)
                BS.readFile path `shouldReturn` "another's"
                sort <$> listDirectory directory `shouldReturn` ["appeared.json"]
                let fresh = directory </> "fresh.json"
                writeFileNew fresh "ours" `shouldReturn` Right ()
                BS.readFile fresh `shouldReturn` "ours"
                sort <$> listDirectory directory `shouldReturn` ["appeared.json", "fresh.json"]
        it "are refused as a pair when they describe different registries" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let record = recordOf 2
                    identityFile = directory </> "release-identity.json"
                    recordFile = directory </> "reference-outputs.json"
                    foreign' = recordOf 3
                writeDeploymentFiles identityFile recordFile (identityOf record) foreign'
                    `shouldReturn` Right ()
                readDeploymentFiles identityFile recordFile
                    >>= (`shouldBe` Left (FilesDisagree (recordMismatches (identityOf record) foreign')))
                recordMismatches (identityOf record) foreign' `shouldBe` [NetworkDiffers, ApplicationHashDiffers, StateHashDiffers, CheckpointHashDiffers]
        it "are refused when either is not what it says: an identity file with a field cut names the field" $
            withSystemTempDirectory "registry-files" $ \directory -> do
                let identityFile = directory </> "release-identity.json"
                    recordFile = directory </> "reference-outputs.json"
                BS.writeFile identityFile "{}"
                BS.writeFile recordFile (encodeReferenceRecord (recordOf 1))
                result <- readDeploymentFiles identityFile recordFile
                case result of
                    Left (IdentityFileInvalid path _) -> path `shouldBe` identityFile
                    other -> fail ("expected the identity file refused, got " <> show other)

missingNameFor :: Text -> Text
missingNameFor leaf = leaf
