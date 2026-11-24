{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryVaultSpec
Description : The registry commands sign with a wallet vault, as the @singular@ command line does

A vault is made in these examples by the code of the @singular@ command line, from a fixed
key and a fixed passphrase, and the passphrase is given on a descriptor. The commands are run
whole over scripted openers: what they refuse, before which file is read and before which
transaction exists; and which key reaches the signer, and in what shape.

The words of a refusal that belongs to the vault or to the passphrase are those the
@singular@ modules render, obtained here by calling them; the words of a refusal that belongs
to the choice of a key source are spelled here.
-}
module Cardano.KERI.Deployment.RegistryVaultSpec (spec) where

import Cardano.Crypto.DSIGN (Ed25519DSIGN, SignKeyDSIGN)
import Cardano.Crypto.DSIGN.Class (rawDeserialiseSignKeyDSIGN, rawSerialiseSignKeyDSIGN)
import Cardano.KERI.Deployment.NodeSocketRuntime (KeySource (..), NodeAccess (..), RegistryOpener, keySourceEnvelope)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..))
import Cardano.KERI.Deployment.RegistryCommand
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (noFaults, walletAddress)
import Cardano.KERI.Deployment.RegistryFiles (writeDeploymentFiles)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), signWithPaymentKey)
import Cardano.Ledger.Address (Addr)
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, bracket, finally, try)
import Control.Monad (forM_, unless, void, when)
import Crypto.Random (getRandomBytes)
import Data.Aeson (Value, eitherDecodeFileStrict', encode, object, (.=))
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromLeft, isRight)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Maybe (fromJust)
import Paths_cardano_keri (getDataFileName)
import Singular.CLI.Passphrase (
    PassphraseRefusal (..),
    mkPassphrase,
    passphraseVariable,
    publicNetworks,
    renderPassphraseRefusal,
 )
import Singular.CLI.Vault (
    VaultRefusal (..),
    createVaultFile,
    readVaultFile,
    renderVaultRefusal,
    sealVault,
    vaultWorkFactor,
 )
import System.Directory (createDirectory, listDirectory, removeFile, withCurrentDirectory)
import System.Environment (getEnv, lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.INotify (Event (..), EventVariety (..), addWatch, initINotify, killINotify)
import System.IO (hClose, hPutStrLn, stderr, stdout)
import System.IO.Error (isPermissionError)
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createNamedPipe, setFileMode)
import System.Posix.IO (OpenMode (ReadWrite), closeFd, createPipe, defaultFileFlags, fdToHandle, openFd)
import System.Posix.Types (Fd (..))
import System.Timeout (timeout)
import Test.Hspec

-- ---------------------------------------------------------------------
-- The fixed keys, passphrases and vaults
-- ---------------------------------------------------------------------

keyOf' :: Word -> SignKeyDSIGN Ed25519DSIGN
keyOf' seed = fromJust (rawDeserialiseSignKeyDSIGN (BS.replicate 32 (fromIntegral seed)))

-- | The key of the vault under test, and another key that stands for a wrong one.
keyA, keyB :: SignKeyDSIGN Ed25519DSIGN
keyA = keyOf' 0x41
keyB = keyOf' 0x42

{- | The passphrases carry a marker no output of any command may contain: the right one, and a
wrong one.
-}
rightPassphrase, wrongPassphrase :: ByteString
rightPassphrase = "marker-right-passphrase-7f3a91"
wrongPassphrase = "marker-wrong-passphrase-c20e55"

-- | A key in the shape of a key file, made here and not by the vault code.
envelopeOf :: SignKeyDSIGN Ed25519DSIGN -> Value
envelopeOf key =
    object
        [ "type" .= ("PaymentSigningKeyShelley_ed25519" :: String)
        , "description" .= ("Payment Signing Key" :: String)
        , "cborHex" .= ("5820" <> B8.unpack (convertToBase Base16 (rawSerialiseSignKeyDSIGN key)))
        ]

-- | The bytes of a vault of a key and a passphrase, made by the code of the @singular@ command line.
sealed :: ByteString -> SignKeyDSIGN Ed25519DSIGN -> IO ByteString
sealed passphrase key = case mkPassphrase passphrase of
    Left refusal -> fail (renderPassphraseRefusal refusal)
    Right pass -> sealVault vaultWorkFactor pass key >>= either (fail . renderVaultRefusal) pure

-- | A file of the vault's bytes, created as the code of the @singular@ command line creates one.
vaultFileIn :: FilePath -> ByteString -> IO FilePath
vaultFileIn directory bytes = do
    let path = directory </> "wallet.vault"
    createVaultFile path bytes >>= either (fail . renderVaultRefusal) pure
    pure path

-- | A descriptor of this process that holds one line, as @--passphrase-fd@ is given one.
descriptorHolding :: ByteString -> IO Int
descriptorHolding line = do
    (readEnd, writeEnd) <- createPipe
    handle <- fdToHandle writeEnd
    BS.hPut handle (line <> "\n")
    hClose handle
    pure (fromIntegral readEnd)

-- | What is still on a descriptor, by reading its line: it is closed by the read.
lineOn :: Int -> IO ByteString
lineOn descriptor = do
    handle <- fdToHandle (Fd (fromIntegral descriptor))
    line <- B8.hGetLine handle
    hClose handle
    pure line

-- | Release a descriptor that no command read.
release :: Int -> IO ()
release descriptor = either (\(_ :: IOError) -> ()) id <$> try (void (closeFd (Fd (fromIntegral descriptor))))

{- | An empty working directory for a command, and the directory beside it that holds what the command
is given: for each path a command takes, a named pipe that this process holds open and keeps empty,
so that whoever reads one waits for ever. A refusal before any read ends; a read does not.
-}
inTwoDirectories :: (FilePath -> FilePath -> IO a) -> IO a
inTwoDirectories action =
    withSystemTempDirectory "registry-vault" $ \root -> do
        let directory = root </> "cwd"
        createDirectory directory
        createDirectory (filesOf directory)
        let pipes = [lockedPath directory name | name <- ["blueprint", "identity", "record", "export", "snapshot", "key", "vault"]]
        bracket (mapM held pipes) (mapM_ closeFd) $ \_ -> action directory (filesOf directory)
  where
    held path = createNamedPipe path 0o600 >> openFd path ReadWrite defaultFileFlags

-- | The directory beside a command's working directory that holds the files it is given.
filesOf :: FilePath -> FilePath
filesOf directory = takeDirectory directory </> "files"

-- | A path a command is given, of a file whose reader waits for ever.
lockedPath :: FilePath -> String -> FilePath
lockedPath directory name = filesOf directory </> "unreadable-" <> name

-- | The path of a vault that waits for ever for whoever reads it; the bytes are not used.
unreadableVaultIn :: FilePath -> ByteString -> IO FilePath
unreadableVaultIn directory _ = pure (directory </> "unreadable-vault")

-- | Run an action with an environment variable set or unset, and restore it.
withVariable :: String -> Maybe String -> IO a -> IO a
withVariable name value action =
    bracket
        (lookupEnv name <* set value)
        set
        (const action)
  where
    set = maybe (unsetEnv name) (setEnv name)

-- ---------------------------------------------------------------------
-- The four commands, run whole over an opener that is never used
-- ---------------------------------------------------------------------

-- | What is given to a command about its key.
data Given = Given
    { givenMagic :: Int
    , givenFile :: Maybe FilePath
    , givenVault :: Maybe FilePath
    , givenDescriptor :: Maybe Int
    }

data Outcome = Outcome
    { outcomeCode :: ExitCode
    , outcomeOut :: String
    , outcomeErr :: String
    , outcomeReached :: [NodeAccess]
    , outcomeDirectory :: [FilePath]
    -- ^ the working directory after the command: the command is run in an empty one
    }

data Runner = Runner
    { runnerName :: String
    , runnerRun :: FilePath -> Given -> IO Outcome
    }

-- | An opener that notes the access and never runs the command's use of it.
noting :: IO (RegistryOpener, IO [NodeAccess])
noting = do
    reached <- newIORef []
    pure (\access _ -> modifyIORef' reached (access :), reverse <$> readIORef reached)

runIn :: FilePath -> (RegistryOpener -> IO ()) -> IO Outcome
runIn directory command = do
    (opener, reachedBy) <- noting
    ran <- timeout 10_000_000 (withCurrentDirectory directory (runCaptured (command opener)))
    (code, out, err) <- maybe (fail "the command did not end: it read a file that waits for ever") pure ran
    reached <- reachedBy
    leftBehind <- listDirectory directory
    pure (Outcome code out err reached leftBehind)

runCaptured :: IO () -> IO (ExitCode, String, String)
runCaptured action = do
    ((outcome, out), err) <- capturing stderr (capturing stdout (try @ExitCode action))
    pure (fromLeft ExitSuccess outcome, out, err)

-- | Four commands, none with a file it could read: every path they are given names a named pipe nobody writes to, so a command that reads one before it refuses never ends.
runners :: [Runner]
runners =
    [ Runner "registry deploy" deploy
    , Runner "registry register" register
    , Runner "registry fold" fold
    , Runner "registry return" returned
    ]
  where
    unreadable = lockedPath
    deploy directory given =
        runIn directory $ \opener ->
            runRegistryDeployWith
                opener
                RegistryDeploySettings
                    { rdNetworkMagic = givenMagic given
                    , rdBlueprint = unreadable directory "blueprint"
                    , rdNodeSocket = "no-node.socket"
                    , rdFundingAddress = "addr_test1unused"
                    , rdSigningKeyFile = givenFile given
                    , rdVault = givenVault given
                    , rdPassphraseFd = givenDescriptor given
                    , rdTimeoutSeconds = 5
                    , rdReferenceLovelace = Nothing
                    , rdReleaseIdentityOut = unreadable directory "identity"
                    , rdReferenceRecordOut = unreadable directory "record"
                    , rdRegistrationCost = 1_000_000
                    , rdMinimumTip = 500_000
                    , rdProcessTime = 90_000
                    , rdBookingWidth = 5_000
                    , rdDeposit = 1_000_000_000
                    , rdFreezeBond = 5_000_000
                    , rdPremium = 2_000_000
                    , rdMinimumAda = 2_000_000
                    , rdTerminationCarrier = 1_500_000
                    }
    register directory given =
        runIn directory $ \opener ->
            runRegistryRegisterWith
                opener
                RegistryRegisterSettings
                    { rgNetworkMagic = givenMagic given
                    , rgBlueprint = unreadable directory "blueprint"
                    , rgNodeSocket = "no-node.socket"
                    , rgFundingAddress = "addr_test1unused"
                    , rgSigningKeyFile = givenFile given
                    , rgVault = givenVault given
                    , rgPassphraseFd = givenDescriptor given
                    , rgTimeoutSeconds = 5
                    , rgReleaseIdentity = unreadable directory "identity"
                    , rgReferenceRecord = unreadable directory "record"
                    , rgKliExport = unreadable directory "export"
                    , rgDeposit = Nothing
                    }
    fold directory given =
        runIn directory $ \opener ->
            runRegistryFoldWith
                opener
                RegistryFoldSettings
                    { rfNetworkMagic = givenMagic given
                    , rfBlueprint = unreadable directory "blueprint"
                    , rfNodeSocket = "no-node.socket"
                    , rfFundingAddress = "addr_test1unused"
                    , rfSigningKeyFile = givenFile given
                    , rfVault = givenVault given
                    , rfPassphraseFd = givenDescriptor given
                    , rfTimeoutSeconds = 5
                    , rfReleaseIdentity = unreadable directory "identity"
                    , rfReferenceRecord = unreadable directory "record"
                    , rfKliExport = unreadable directory "export"
                    , rfRequest = ""
                    , rfSnapshot = unreadable directory "snapshot"
                    , rfSnapshotOut = Nothing
                    }
    returned directory given =
        runIn directory $ \opener ->
            runRegistryReturnWith
                opener
                RegistryReturnSettings
                    { rnNetworkMagic = givenMagic given
                    , rnBlueprint = unreadable directory "blueprint"
                    , rnNodeSocket = "no-node.socket"
                    , rnFundingAddress = "addr_test1unused"
                    , rnSigningKeyFile = givenFile given
                    , rnVault = givenVault given
                    , rnPassphraseFd = givenDescriptor given
                    , rnTimeoutSeconds = 5
                    , rnReleaseIdentity = unreadable directory "identity"
                    , rnReferenceRecord = unreadable directory "record"
                    , rnRequest = ""
                    }

-- | A command run with the passphrase variable unset.
runClean :: Runner -> FilePath -> Given -> IO Outcome
runClean runner directory given =
    withVariable passphraseVariable Nothing (runnerRun runner directory given)

-- | A development network's magic, and the one of preprod.
developmentMagic :: Int
developmentMagic = 42

zeroLine, commandBoundary :: String
zeroLine = "nothing was submitted; nothing was spent"
commandBoundary = "refused by the command, before any transaction"

-- | Whether a text holds a passphrase of these examples, or the key of the vault.
printsASecret :: String -> Bool
printsASecret text =
    any ((`isInfixOf` text) . B8.unpack) [rightPassphrase, wrongPassphrase, convertToBase Base16 (rawSerialiseSignKeyDSIGN keyA)]

-- | No marker of any passphrase is in what a command printed.
neverShown :: Outcome -> Expectation
neverShown outcome = do
    forM_ [rightPassphrase, wrongPassphrase] $ \marker ->
        (B8.unpack marker, B8.unpack marker `isInfixOf` (outcomeOut outcome <> outcomeErr outcome)) `shouldBe` (B8.unpack marker, False)
    show (outcomeReached outcome) `shouldSatisfy` (not . ("marker-" `isInfixOf`))

{- | A refusal made by the command before any transaction: it names its cause, it says where it was made
nothing reached the opener, nothing was created in the
working directory, and no passphrase was printed.
-}
refusedWith :: Runner -> String -> Outcome -> Expectation
refusedWith runner cause outcome = do
    (runnerName runner, outcomeCode outcome) `shouldBe` (runnerName runner, ExitFailure 1)
    (runnerName runner, outcomeErr outcome) `shouldSatisfy` (\(_, err) -> cause `isInfixOf` err)
    (runnerName runner, outcomeErr outcome) `shouldSatisfy` (\(_, err) -> commandBoundary `isInfixOf` err)
    (runnerName runner, outcomeErr outcome) `shouldSatisfy` (\(_, err) -> zeroLine `isInfixOf` err)
    (runnerName runner, outcomeReached outcome) `shouldBe` (runnerName runner, [])
    (runnerName runner, outcomeDirectory outcome) `shouldBe` (runnerName runner, [])
    -- every file the command is given is one nobody may read: a read of any would be an error that names it
    forM_ ["unreadable-", "wallet.vault"] $ \mark ->
        (runnerName runner, mark, mark `isInfixOf` outcomeErr outcome) `shouldBe` (runnerName runner, mark, False)
    neverShown outcome

-- ---------------------------------------------------------------------
-- One booking, signed through the command
-- ---------------------------------------------------------------------

-- | A directory with the two files of the deployment, and the settings of a booking that name them.
withBooking :: World -> (FilePath -> RegistryRegisterSettings -> IO a) -> IO a
withBooking world action = withSystemTempDirectory "registry-vault" $ \scratch -> do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    export <- getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
    let work = scratch </> "work"
        identityFile = scratch </> "release-identity.json"
        recordFile = scratch </> "reference-outputs.json"
    createDirectory work
    written <-
        writeDeploymentFiles
            identityFile
            recordFile
            (deployedIdentity (worldDeployed world))
            (deployedRecord (worldDeployed world))
    either (fail . show) pure written
    action
        work
        RegistryRegisterSettings
            { rgNetworkMagic = developmentMagic
            , rgBlueprint = blueprint
            , rgNodeSocket = "no-node.socket"
            , rgFundingAddress = "addr_test1unused"
            , rgSigningKeyFile = Nothing
            , rgVault = Nothing
            , rgPassphraseFd = Nothing
            , rgTimeoutSeconds = 5
            , rgReleaseIdentity = identityFile
            , rgReferenceRecord = recordFile
            , rgKliExport = export
            , rgDeposit = Nothing
            }

{- | What a signer made of the key the command was given produced for one transaction, next to
what the key file of the key we meant produced.
-}
data Probe = Probe
    { probeBothSigned :: Bool
    -- ^ neither signing was refused
    , probeSameWitness :: Bool
    -- ^ the two signed transactions are one
    , probeSigned :: Bool
    -- ^ the transaction the command's key signed is not the transaction it was given
    }

{- | An opener over a world whose signer is the one the command was given, a note of what it
produced for each transaction beside what the key file of the given key produces, and an action
run inside the command before it signs.
-}
signingOpener :: World -> Addr -> FilePath -> IO () -> IO (RegistryOpener, IO [Probe], IO [NodeAccess])
signingOpener world payer keyFile whileRunning = do
    reached <- newIORef []
    produced <- newIORef []
    pure
        ( \access use -> do
            modifyIORef' reached (access :)
            whileRunning
            envelope <- keySourceEnvelope (naSigningKey access) >>= either fail pure
            fileEnvelope <- eitherDecodeFileStrict' keyFile >>= either fail pure
            let runtime = runtimeOf noFaults world
                transactions = rtTransactions runtime
            use
                ( runtime
                    { rtTransactions =
                        transactions
                            { trSign = \tx -> do
                                let viaAccess = signWithPaymentKey envelope tx
                                    viaFile = signWithPaymentKey fileEnvelope tx
                                modifyIORef' produced (Probe (isRight viaAccess && isRight viaFile) (viaAccess == viaFile) (viaAccess /= Right tx) :)
                                -- the world prices a transaction as one a signer has yet to sign: what it receives is unsigned
                                pure (Right tx)
                            }
                    }
                , payer
                )
        , reverse <$> readIORef produced
        , reverse <$> readIORef reached
        )

{- | A booking signed through the command from a vault of the bytes, in a working directory and a
temporary directory nobody may write to while it runs: a write fails the run, whether or not the
file would have been removed before the end. The given action is run inside the command, at the
two directories, as a write of a key would be.
-}
signedReadOnly :: ByteString -> (FilePath -> IO ()) -> IO (Either IOException (ExitCode, String, String), [Probe])
signedReadOnly vaultBytes leak = do
    world <- newWorld 1_000
    withBooking world $ \work settings -> do
        let keyFile = work </> "payment.skey"
            temporary = work </> "tmp"
        BL.writeFile keyFile (encode (envelopeOf keyA))
        createDirectory temporary
        vault <- vaultFileIn work vaultBytes
        descriptor <- descriptorHolding rightPassphrase
        (opener, producedBy, _) <- signingOpener world walletAddress keyFile (leak work >> leak temporary)
        let command = runRegistryRegisterWith opener settings{rgVault = Just vault, rgPassphraseFd = Just descriptor}
        outcome <-
            ( do
                setFileMode temporary 0o555
                setFileMode work 0o555
                try @IOException (withCurrentDirectory work (runCaptured (withVariable "TMPDIR" (Just temporary) command)))
            )
                `finally` (setFileMode work 0o755 >> setFileMode temporary 0o755)
        produced <- producedBy
        pure (outcome, produced)

{- | A booking signed through the command from a vault of the bytes, in a working directory and a temporary
directory that are writable and watched: every file created or moved into either while the command runs is
noted, as its directory and its name, whether or not it is gone by the end and whether or not a failure of
its write was swallowed. The given action is run inside the command, at the two directories, as a write of a
key would be; it is given the name of the barrier.

The barrier is a file of a random name, created after the run in a third watched directory the command is
never given. Events arrive in order, so once it is seen everything the run created has been seen. Only the
barrier's own event, matched by directory and name, is left out of what is given back.
-}
signedWatched :: ByteString -> (String -> FilePath -> IO ()) -> IO (Either IOException (ExitCode, String, String), [Probe], [(String, String)])
signedWatched vaultBytes leak = do
    world <- newWorld 1_000
    barrierName <- ("barrier-" <>) . B8.unpack . convertToBase Base16 <$> getRandomBytes @IO @ByteString 12
    withSystemTempDirectory "registry-vault-barrier" $ \barrierDirectory ->
        withBooking world $ \work settings -> do
            let keyFile = work </> "payment.skey"
                temporary = work </> "tmp"
            BL.writeFile keyFile (encode (envelopeOf keyA))
            createDirectory temporary
            vault <- vaultFileIn work vaultBytes
            descriptor <- descriptorHolding rightPassphrase
            (opener, producedBy, _) <- signingOpener world walletAddress keyFile (leak barrierName work >> leak barrierName temporary)
            let command = runRegistryRegisterWith opener settings{rgVault = Just vault, rgPassphraseFd = Just descriptor}
            notify <- initINotify
            seen <- newIORef []
            let record directory = \case
                    Created{filePath = name} -> modifyIORef' seen ((directory, B8.unpack name) :)
                    MovedIn{filePath = name} -> modifyIORef' seen ((directory, B8.unpack name) :)
                    _ -> pure ()
                watched = [work, temporary, barrierDirectory]
            forM_ watched $ \directory -> addWatch notify [Create, MoveIn] (B8.pack directory) (record directory)
            outcome <- try @IOException (withCurrentDirectory work (runCaptured (withVariable "TMPDIR" (Just temporary) command)))
            produced <- producedBy
            writeFile (barrierDirectory </> barrierName) ""
            waitFor (elem (barrierDirectory, barrierName) <$> readIORef seen)
            killINotify notify
            events <- reverse <$> readIORef seen
            pure
                ( outcome
                , produced
                , [(takeFileName directory, name) | (directory, name) <- events, (directory, name) /= (barrierDirectory, barrierName)]
                )
  where
    waitFor condition = do
        done <- condition
        unless done $ threadDelay 20_000 >> waitFor condition

-- | A file made and removed at once: a key written to a file and gone before the command ends.
createAndRemove :: FilePath -> IO ()
createAndRemove path = writeFile path "leaked" >> removeFile path

-- | A write of a file named like a key, in a directory with the given name.
leakInto :: String -> FilePath -> IO ()
leakInto name directory = when (takeFileName directory == name) (writeFile (directory </> "plaintext-key") "leaked")

spec :: Spec
spec = describe "#553 the registry commands sign with a wallet vault" $ beforeAll ((,) <$> sealed rightPassphrase keyA <*> sealed rightPassphrase keyB) $ do
    describe "the witness" $ do
        let signedThroughPrinting printing vaultBytes = do
                world <- newWorld 1_000
                withBooking world $ \work settings -> do
                    let keyFile = work </> "payment.skey"
                    BL.writeFile keyFile (encode (envelopeOf keyA))
                    vault <- vaultFileIn work vaultBytes
                    descriptor <- descriptorHolding rightPassphrase
                    (opener, producedBy, _) <- signingOpener world walletAddress keyFile printing
                    (code, out, err) <-
                        withCurrentDirectory work $
                            runCaptured (runRegistryRegisterWith opener settings{rgVault = Just vault, rgPassphraseFd = Just descriptor})
                    (code, err) `shouldBe` (ExitSuccess, err)
                    produced <- producedBy
                    not (null produced) `shouldBe` True
                    pure (produced, out, err)
            signedThrough vaultBytes = do
                (produced, out, err) <- signedThroughPrinting (pure ()) vaultBytes
                -- a successful run shows no passphrase and no key either, on either stream
                (out, printsASecret out) `shouldBe` (out, False)
                (err, printsASecret err) `shouldBe` (err, False)
                pure produced
        it "shows no passphrase on a successful run: the check sees one printed on either stream, so it means something" $ \(bytesA, _) -> do
            (_, out, _) <- signedThroughPrinting (putStrLn ("opened with " <> B8.unpack rightPassphrase)) bytesA
            printsASecret out `shouldBe` True
            (_, _, err) <- signedThroughPrinting (hPutStrLn stderr ("opened with " <> B8.unpack rightPassphrase)) bytesA
            printsASecret err `shouldBe` True
            (_, out', _) <- signedThroughPrinting (putStrLn (B8.unpack (convertToBase Base16 (rawSerialiseSignKeyDSIGN keyA)))) bytesA
            printsASecret out' `shouldBe` True
        it "is the witness the key file of the same key gives, for a booking signed through the command" $ \(bytesA, _) -> do
            produced <- signedThrough bytesA
            -- both signings succeeded, to one transaction, which is signed
            forM_ produced $ \probe ->
                (probeBothSigned probe, probeSameWitness probe, probeSigned probe) `shouldBe` (True, True, True)
        it "is another witness, both signings succeeding, when the vault holds another key" $ \(_, bytesB) -> do
            produced <- signedThrough bytesB
            forM_ produced $ \probe ->
                (probeBothSigned probe, probeSameWitness probe, probeSigned probe) `shouldBe` (True, False, True)
    describe "the key reaches the signer as an envelope, never as a path" $ do
        it "gives the opener an opened envelope that shows as a marker" $ \(bytesA, _) -> do
            world <- newWorld 1_000
            withBooking world $ \work settings -> do
                let keyFile = work </> "payment.skey"
                BL.writeFile keyFile (encode (envelopeOf keyA))
                vault <- vaultFileIn work bytesA
                descriptor <- descriptorHolding rightPassphrase
                (opener, _, reachedBy) <- signingOpener world walletAddress keyFile (pure ())
                _ <-
                    withCurrentDirectory work $
                        runCaptured (runRegistryRegisterWith opener settings{rgVault = Just vault, rgPassphraseFd = Just descriptor})
                reached <- reachedBy
                length reached `shouldBe` 1
                forM_ reached $ \access -> do
                    case naSigningKey access of
                        KeyEnvelope _ -> pure ()
                        other -> expectationFailure ("the vault key took the shape of " <> show other)
                    show access `shouldSatisfy` ("KeyEnvelope <signing key>" `isInfixOf`)
                    show access `shouldSatisfy` (not . (B8.unpack (convertToBase Base16 (rawSerialiseSignKeyDSIGN keyA)) `isInfixOf`))
                    show access `shouldSatisfy` (not . (vault `isInfixOf`))
        it "creates no file while it signs, not even one it removes before it ends or whose write fails unheard: the working directory and the temporary directory are watched" $ \(bytesA, _) -> do
            (outcome, produced, created) <- signedWatched bytesA (\_ _ -> pure ())
            case outcome of
                Right (code, _, err) -> (code, err) `shouldBe` (ExitSuccess, err)
                Left failure -> expectationFailure ("the command failed: " <> show failure)
            not (null produced) `shouldBe` True
            created `shouldBe` []
        forM_ ["work", "tmp"] $ \name -> do
            it ("sees a file created in the " <> name <> " directory and removed before the end: the watch works") $ \(bytesA, _) -> do
                (_, _, created) <- signedWatched bytesA (\_ directory -> when (takeFileName directory == name) (createAndRemove (directory </> "plaintext-key")))
                created `shouldBe` [(name, "plaintext-key")]
            it ("sees a file created in the " <> name <> " directory under the name of a file named like the barrier, and removed before the end") $ \(bytesA, _) -> do
                (_, _, created) <- signedWatched bytesA (\barrier directory -> when (takeFileName directory == name) (createAndRemove (directory </> barrier)))
                map fst created `shouldBe` [name]
            it ("sees a file created in the " <> name <> " directory under the name 'sentinel', which a barrier of a fixed name would have hidden") $ \(bytesA, _) -> do
                (_, _, created) <- signedWatched bytesA (\_ directory -> when (takeFileName directory == name) (createAndRemove (directory </> "sentinel")))
                created `shouldBe` [(name, "sentinel")]
        it "writes nothing while it signs: the working directory and the temporary directory are read-only, as a further check" $ \(bytesA, _) -> do
            (outcome, produced) <- signedReadOnly bytesA (const (pure ()))
            case outcome of
                Right (code, _, err) -> (code, err) `shouldBe` (ExitSuccess, err)
                Left failure -> expectationFailure ("a write was attempted: " <> show failure)
            not (null produced) `shouldBe` True
            forM_ produced $ \probe -> (probeBothSigned probe, probeSameWitness probe) `shouldBe` (True, True)
        forM_ ["work", "tmp"] $ \name ->
            it ("catches a write of a file in the " <> name <> " directory that is removed before the end: the same run fails") $ \(bytesA, _) -> do
                (outcome, _) <- signedReadOnly bytesA (leakInto name)
                case outcome of
                    Left failure -> isPermissionError failure `shouldBe` True
                    Right (code, _, _) -> expectationFailure ("the write was not caught, the command ended " <> show code)
        it "has files whose reader waits for ever: the check of a refusal before any read means something here" $ \_ ->
            inTwoDirectories $ \directory _ -> do
                outcome <- timeout 1_000_000 (BS.readFile (lockedPath directory "key"))
                fmap BS.length outcome `shouldBe` Nothing
        it "keeps a key file as a path" $ \_ -> do
            world <- newWorld 1_000
            withBooking world $ \work settings -> do
                let keyFile = work </> "payment.skey"
                BL.writeFile keyFile (encode (envelopeOf keyA))
                (opener, _, reachedBy) <- signingOpener world walletAddress keyFile (pure ())
                _ <- withCurrentDirectory work $ runCaptured (runRegistryRegisterWith opener settings{rgSigningKeyFile = Just keyFile})
                reached <- reachedBy
                map naSigningKey reached `shouldBe` [KeyFile keyFile]
    describe "exactly one key source" $ do
        forM_ runners $ \runner -> describe (runnerName runner) $ do
            let refuse label cause arrange =
                    it ("refuses " <> label <> " by name, before any file is read and before the opener") $ \(bytesA, _) ->
                        inTwoDirectories $ \directory vaults -> do
                            (given, finally') <- arrange vaults bytesA
                            outcome <- runClean runner directory given
                            void finally'
                            refusedWith runner cause outcome
            refuse "a key file and a vault together" "key-source-both" $ \vaults bytesA -> do
                vault <- unreadableVaultIn vaults bytesA
                descriptor <- descriptorHolding rightPassphrase
                pure (Given developmentMagic (Just (vaults </> "unreadable-key")) (Just vault) (Just descriptor), release descriptor)
            refuse "no key source" "key-source-neither" $ \_ _ ->
                pure (Given developmentMagic Nothing Nothing Nothing, pure ())
            refuse "a vault with no passphrase source" "vault-without-passphrase" $ \vaults bytesA -> do
                vault <- unreadableVaultIn vaults bytesA
                pure (Given developmentMagic Nothing (Just vault) Nothing, pure ())
            refuse "a passphrase descriptor beside a key file" "passphrase-fd-without-vault" $ \vaults _ -> do
                descriptor <- descriptorHolding rightPassphrase
                pure (Given developmentMagic (Just (vaults </> "unreadable-key")) Nothing (Just descriptor), release descriptor)
            refuse "a passphrase descriptor alone" "passphrase-fd-without-vault" $ \_ _ -> do
                descriptor <- descriptorHolding rightPassphrase
                pure (Given developmentMagic Nothing Nothing (Just descriptor), release descriptor)
            it "leaves the passphrase on its descriptor when it refuses both sources: nothing was read" $ \(bytesA, _) ->
                inTwoDirectories $ \directory vaults -> do
                    vault <- unreadableVaultIn vaults bytesA
                    descriptor <- descriptorHolding rightPassphrase
                    _ <- runClean runner directory (Given developmentMagic (Just (vaults </> "unreadable-key")) (Just vault) (Just descriptor))
                    lineOn descriptor >>= (`shouldBe` rightPassphrase)
    describe "a wrong passphrase" $ do
        forM_ runners $ \runner ->
            it ("is refused by " <> runnerName runner <> " in Singular's words, with nothing built, signed or handed over") $ \(bytesA, _) ->
                inTwoDirectories $ \directory vaults -> do
                    vault <- vaultFileIn vaults bytesA
                    descriptor <- descriptorHolding wrongPassphrase
                    outcome <- runClean runner directory (Given developmentMagic Nothing (Just vault) (Just descriptor))
                    refusedWith runner (renderVaultRefusal VaultNotOpened) outcome
        it "is refused in the same words however the vault fails to open: a vault that is not there, a descriptor that is not one, an empty line" $ \(bytesA, _) ->
            forM_ runners $ \runner -> inTwoDirectories $ \directory vaults -> do
                let missing = vaults </> "no-such.vault"
                    unreadableDescriptor = 987_654
                held <- descriptorHolding rightPassphrase
                notThereWords <- readVaultFile missing >>= either (pure . renderVaultRefusal) (const (fail "a vault that is not there was read"))
                notThere <- runClean runner directory (Given developmentMagic Nothing (Just missing) (Just held))
                refusedWith runner notThereWords notThere
                vault <- vaultFileIn vaults bytesA
                unreadable <- runClean runner directory (Given developmentMagic Nothing (Just vault) (Just unreadableDescriptor))
                refusedWith runner (renderPassphraseRefusal (PassphraseDescriptorUnreadable unreadableDescriptor)) unreadable
                empty <- descriptorHolding ""
                emptied <- runClean runner directory (Given developmentMagic Nothing (Just vault) (Just empty))
                refusedWith runner (renderPassphraseRefusal PassphraseEmpty) emptied
    describe "the passphrase variable" $ do
        forM_ publicNetworks $ \(network, magic) ->
            forM_ runners $ \runner ->
                it ("is refused on " <> network <> " (network magic " <> show magic <> ") by " <> runnerName runner) $ \(bytesA, _) ->
                    inTwoDirectories $ \directory vaults -> do
                        vault <- vaultFileIn vaults bytesA
                        outcome <-
                            withVariable passphraseVariable (Just (B8.unpack rightPassphrase)) $
                                runnerRun runner directory (Given (fromIntegral magic) Nothing (Just vault) Nothing)
                        refusedWith runner (renderPassphraseRefusal (PassphraseVariablePublic network magic)) outcome
        it "is accepted on a development network, and the opener is given the opened key" $ \(bytesA, _) -> do
            world <- newWorld 1_000
            withBooking world $ \work settings -> do
                vault <- vaultFileIn work bytesA
                (opener, reachedBy) <- noting
                (code, _, err) <-
                    withVariable passphraseVariable (Just (B8.unpack rightPassphrase)) $
                        withCurrentDirectory work $
                            runCaptured (runRegistryRegisterWith opener settings{rgVault = Just vault})
                (code, err) `shouldBe` (ExitSuccess, err)
                reached <- reachedBy
                length reached `shouldBe` 1
                forM_ reached $ \access -> case naSigningKey access of
                    KeyEnvelope _ -> pure ()
                    other -> expectationFailure ("the variable's vault key took the shape of " <> show other)
        it "gives way to a descriptor, also on a public network" $ \(bytesA, _) -> do
            world <- newWorld 1_000
            withBooking world $ \work settings -> do
                vault <- vaultFileIn work bytesA
                descriptor <- descriptorHolding rightPassphrase
                (opener, reachedBy) <- noting
                (code, _, err) <-
                    withVariable passphraseVariable (Just "marker-variable-passphrase-00") $
                        withCurrentDirectory work $
                            runCaptured (runRegistryRegisterWith opener settings{rgNetworkMagic = 1, rgVault = Just vault, rgPassphraseFd = Just descriptor})
                (code, err) `shouldBe` (ExitSuccess, err)
                reachedBy >>= (\reached -> length reached `shouldBe` 1)
                err `shouldSatisfy` (not . ("marker-variable-passphrase-00" `isInfixOf`))
