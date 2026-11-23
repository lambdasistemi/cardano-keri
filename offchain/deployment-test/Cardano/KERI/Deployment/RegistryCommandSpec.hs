{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryCommandSpec
Description : @ckeri registry deploy@ over a chain that keeps its outputs

The command is run whole, over the chain of "Cardano.KERI.Deployment.RegistryDeploySpec",
in a directory of its own: what it prints, what it writes, what it leaves
alone. Every term it deploys with is one of its settings, and a failed
deployment is told in words that name what landed and what did not.
-}
module Cardano.KERI.Deployment.RegistryCommandSpec (spec, capturing, capturingLive) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (ApplicationParameters (..), OutputReference (..))
import Cardano.KERI.ChainQuery.ReleaseIdentity (decodeReleaseIdentity)
import Cardano.KERI.Deployment.Registry (RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryCommand
import Cardano.KERI.Deployment.RegistryDeploy
import Cardano.KERI.Deployment.RegistryDeploySpec (
    Chain (..),
    Faults (..),
    chainRuntime,
    expectedSeedIn,
    lifecycleAccount,
    loadTestBlueprint,
    newChain,
    noFaults,
    testTerms,
    walletAddress,
    walletOutputs,
 )
import Cardano.KERI.Deployment.RegistryFiles (decodeReferenceRecord, readDeploymentFiles)
import Cardano.KERI.Deployment.Script (CheckpointTerms (..))
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..))
import Control.Exception (IOException, bracket, finally, try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.Directory (createDirectory, createDirectoryIfMissing, doesDirectoryExist, listDirectory, withCurrentDirectory)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (BufferMode (..), Handle, hClose, hFlush, hSetBuffering, stderr, stdout)
import System.IO.Error (isEOFError)
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import System.Posix.Files (createSymbolicLink, setFileMode)
import System.Posix.IO.ByteString qualified as Posix
import System.Posix.User (getEffectiveUserID)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldReturn, shouldSatisfy)

settingsIn :: FilePath -> FilePath -> RegistryDeploySettings
settingsIn blueprint directory =
    RegistryDeploySettings
        { rdNetworkMagic = 42
        , rdBlueprint = blueprint
        , rdNodeSocket = "no-node.socket"
        , rdFundingAddress = "addr_test1unused"
        , rdSigningKeyFile = "no-key.skey"
        , rdTimeoutSeconds = 5
        , rdReferenceLovelace = Nothing
        , rdReleaseIdentityOut = directory </> "release-identity.json"
        , rdReferenceRecordOut = directory </> "reference-outputs.json"
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

-- | Run an action with what it prints on a handle, and give both.
capturing :: Handle -> IO a -> IO (a, String)
capturing handle action = capturingLive handle (const action)

-- | Like 'capturing', and the action is given a way to read what has been printed so far.
capturingLive :: Handle -> (IO String -> IO a) -> IO (a, String)
capturingLive handle action =
    withSystemTempFile "captured" $ \path file -> do
        saved <- hDuplicate handle
        outcome <-
            bracket
                (hFlush handle >> hDuplicateTo file handle >> hSetBuffering handle (BlockBuffering Nothing))
                (\_ -> hFlush handle >> hDuplicateTo saved handle >> hClose saved >> hSetBuffering handle LineBuffering)
                (const (action (readRaw path)))
        hClose file
        text <- readFile path
        length text `seq` pure (outcome, text)

spec :: Spec
spec = describe "#351 ckeri registry deploy" $ do
    describe "the terms" $ do
        it "are the settings, each its own: no term is swapped for another or fixed by the command" $ do
            let distinct =
                    (settingsIn "b" "d")
                        { rdRegistrationCost = 11
                        , rdMinimumTip = 12
                        , rdProcessTime = 13
                        , rdBookingWidth = 14
                        , rdDeposit = 15
                        , rdFreezeBond = 16
                        , rdPremium = 17
                        , rdMinimumAda = 18
                        , rdTerminationCarrier = 19
                        }
                terms = registryTermsOf distinct
            registrationCost (registryParameters terms) `shouldBe` 11
            minimumTip (registryParameters terms) `shouldBe` 12
            processTime (registryParameters terms) `shouldBe` 13
            bookingWidth (registryParameters terms) `shouldBe` 14
            termsDeposit (registryCheckpointTerms terms) `shouldBe` 15
            termsFreezeBond (registryCheckpointTerms terms) `shouldBe` 16
            termsPremium (registryCheckpointTerms terms) `shouldBe` 17
            registryMinimumAda terms `shouldBe` 18
            registryTerminationCarrier terms `shouldBe` 19
            registryTermsOf (settingsIn "b" "d") `shouldBe` testTerms

    describe "a deployment that completes" $ do
        it "prints each transaction before the next is submitted, and leaves exactly the two files, which agree" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \scratch -> do
                let directory = scratch </> "out"
                    workDirectory = scratch </> "cwd"
                    decoys = [workDirectory </> "deploy" </> "preprod" </> name | name <- ["m1-manifest.json", "board-manifest.json"]]
                    settings = settingsIn blueprintPath directory
                createDirectory directory
                -- where the first deployment keeps its manifests and its store: here they cannot be read
                createDirectoryIfMissing True workDirectory
                mapM_ (createDirectoryIfMissing True) decoys
                before <- treeOf workDirectory
                chainRef <- newIORef (newChain walletOutputs)
                printedAtSubmission <- newIORef []
                let withObserver readOut opener' settings' use =
                        opener' settings' $ \(runtime, payer) -> do
                            let transactions = runtimeTransactions runtime
                                observed =
                                    transactions
                                        { trSubmit = \tx -> do
                                            printed <- length . filter ("fee=" `isInfixOf`) . lines <$> readOut
                                            modifyIORef' printedAtSubmission (printed :)
                                            trSubmit transactions tx
                                        }
                            use (runtime{runtimeTransactions = observed}, payer)
                    opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                ((ran, out), err) <-
                    capturing stderr $
                        capturingLive stdout $ \readOut ->
                            try @ExitCode $
                                withCurrentDirectory workDirectory $
                                    runRegistryDeployWith (withObserver readOut opener) settings
                ran `shouldBe` Right ()
                chain <- readIORef chainRef
                let landedIds = reverse (map (T.unpack . renderTransactionId . transactionId) (chainAccepted chain))
                    printed = lines out
                -- each landed id is printed, with its step, in the order it landed
                sequence_
                    [ line `shouldSatisfy` ((renderStep step <> ": " <> txid) `isInfixOf`)
                    | (step, txid, line) <- zip3 allSteps landedIds printed
                    ]
                -- and before the next transaction is submitted: at the n-th submission n are already printed
                submissionsSeen <- readIORef printedAtSubmission
                reverse submissionsSeen `shouldBe` [0 .. 7]
                length (filter (": " `isInfixOf`) printed) `shouldSatisfy` (>= 8)
                out `shouldSatisfy` ("registered the registration observer's reward credential" `isInfixOf`)
                out `shouldSatisfy` ("not deployed by this command" `isInfixOf`)
                err `shouldSatisfy` ("not for mainnet" `isInfixOf`)
                -- nothing but the two files appears, and nothing it could have read was touched: no store, no manifest
                filesWritten <- sort <$> listDirectory directory
                filesWritten `shouldBe` ["reference-outputs.json", "release-identity.json"]
                treeOf workDirectory >>= (`shouldBe` before)
                identityBytes <- BS.readFile (rdReleaseIdentityOut settings)
                recordBytes <- BS.readFile (rdReferenceRecordOut settings)
                either (fail . show) (const (pure ())) (decodeReleaseIdentity identityBytes)
                either (fail . show) (const (pure ())) (decodeReferenceRecord recordBytes)
                readDeploymentFiles (rdReleaseIdentityOut settings) (rdReferenceRecordOut settings)
                    >>= either (fail . show) (const (pure ()))

    describe "what a deployment says about the credential" $ do
        it "says it did not register a credential that was registered already, and says it registered one that was not" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            blueprint <- loadTestBlueprint
            account <- lifecycleAccount blueprint
            forM_ [(True, "was already registered and was not registered again"), (False, "registered the registration observer's reward credential;")] $ \(preRegistered, wording) ->
                withSystemTempDirectory "registry-command" $ \directory -> do
                    let settings = settingsIn blueprintPath directory
                        start = newChain walletOutputs
                    chainRef <- newIORef (if preRegistered then start{chainRegistered = Set.singleton account} else start)
                    let opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                    (_, out) <- capturing stdout (runRegistryDeployWith opener settings)
                    out `shouldSatisfy` (wording `isInfixOf`)
                    out `shouldSatisfy` ("not deployed by this command" `isInfixOf`)
                    -- the opposite claim is not made
                    out
                        `shouldSatisfy` ( \o ->
                                            ("registered the registration observer's reward credential;" `isInfixOf` o) /= preRegistered
                                        )

    describe "a deployment that cannot begin" $ do
        it "stops before it asks the node anything when a file it would write is already there" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                chainRef <- newIORef (newChain walletOutputs)
                let settings = settingsIn blueprintPath directory
                    opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                BS.writeFile (rdReleaseIdentityOut settings) "another deployment's"
                (outcome, _) <-
                    capturing stderr (try (runRegistryDeployWith opener settings))
                outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                chain <- readIORef chainRef
                chainCalls chain `shouldBe` 0
                BS.readFile (rdReleaseIdentityOut settings) >>= (`shouldBe` "another deployment's")
        it "stops before it asks the node anything when the directory of a file is missing" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                chainRef <- newIORef (newChain walletOutputs)
                let settings =
                        (settingsIn blueprintPath directory)
                            { rdReferenceRecordOut = directory </> "absent" </> "reference-outputs.json"
                            }
                    opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                (outcome, _) <- capturing stderr (try (runRegistryDeployWith opener settings))
                outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                chain <- readIORef chainRef
                chainCalls chain `shouldBe` 0
        it "stops before it asks the node anything when both files are given one destination, or a directory" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                let one = directory </> "both.json"
                    cases =
                        [ (settingsIn blueprintPath directory){rdReleaseIdentityOut = one, rdReferenceRecordOut = one}
                        , (settingsIn blueprintPath directory){rdReferenceRecordOut = directory}
                        ]
                forM_ cases $ \settings -> do
                    chainRef <- newIORef (newChain walletOutputs)
                    let opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                    (outcome, _) <- capturing stderr (try (runRegistryDeployWith opener settings))
                    outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                    chain <- readIORef chainRef
                    chainCalls chain `shouldBe` 0
        it "stops before it asks the node anything when two names reach one destination" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                let out = directory </> "out"
                    alias = directory </> "alias"
                createDirectory out
                createSymbolicLink out alias
                chainRef <- newIORef (newChain walletOutputs)
                let settings =
                        (settingsIn blueprintPath directory)
                            { rdReleaseIdentityOut = out </> "result.json"
                            , rdReferenceRecordOut = alias </> "result.json"
                            }
                    opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                (outcome, _) <- capturing stderr (try (runRegistryDeployWith opener settings))
                outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                chain <- readIORef chainRef
                chainCalls chain `shouldBe` 0
                listDirectory out `shouldReturn` []
        it "stops before it asks the node anything when the directory of a file cannot be written in" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            root <- (== 0) <$> getEffectiveUserID
            if root
                then pendingWith "a superuser can create files in a read-only directory"
                else withSystemTempDirectory "registry-command" $ \directory -> do
                    let readOnly = directory </> "read-only"
                        settings = (settingsIn blueprintPath directory){rdReferenceRecordOut = readOnly </> "reference-outputs.json"}
                    createDirectory readOnly
                    setFileMode readOnly 0o555
                    chainRef <- newIORef (newChain walletOutputs)
                    let opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                    (outcome, err) <-
                        capturing stderr (try (runRegistryDeployWith opener settings))
                            `finally` setFileMode readOnly 0o755
                    outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                    err `shouldSatisfy` ("directory-not-writable" `isInfixOf`)
                    chain <- readIORef chainRef
                    chainCalls chain `shouldBe` 0
        it "refuses a term the registry cannot be deployed with, by name, before anything is submitted" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                chainRef <- newIORef (newChain walletOutputs)
                let settings = (settingsIn blueprintPath directory){rdDeposit = 1}
                    opener _ use = use (chainRuntime noFaults chainRef, walletAddress)
                ((outcome, _), err) <-
                    capturing stderr (capturing stdout (try (runRegistryDeployWith opener settings)))
                outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                err `shouldSatisfy` ("terms-refused: deposit-below-floor" `isInfixOf`)
                chain <- readIORef chainRef
                chainSubmissions chain `shouldBe` 0
                listDirectory directory `shouldBe'` []

    describe "a deployment that stops" $ do
        it "tells what landed and what did not, writes no file and exits with a failure" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                chainRef <- newIORef (newChain walletOutputs)
                let settings = settingsIn blueprintPath directory
                    faults = noFaults{rejectSubmissionAt = Just 3}
                    opener _ use = use (chainRuntime faults chainRef, walletAddress)
                ((outcome, out), err) <-
                    capturing stderr (capturing stdout (try (runRegistryDeployWith opener settings)))
                outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                chain <- readIORef chainRef
                let landedIds = reverse (map (T.unpack . renderTransactionId . transactionId) (chainAccepted chain))
                length landedIds `shouldBe` 3
                sequence_
                    [ err `shouldSatisfy` (("landed: " <> renderStep step <> " " <> txid) `isInfixOf`)
                    | (step, txid) <- zip allSteps landedIds
                    ]
                err `shouldSatisfy` ("stopped at: publish-registration-observer" `isInfixOf`)
                sequence_
                    [ err `shouldSatisfy` (("not landed: " <> renderStep step) `isInfixOf`)
                    | step <- drop 3 allSteps
                    ]
                -- what landed was printed as it landed, and stays on the output of a failed deployment
                sequence_
                    [ out `shouldSatisfy` ((renderStep step <> ": " <> txid) `isInfixOf`)
                    | (step, txid) <- zip allSteps landedIds
                    ]
                err `shouldSatisfy` ("submission-refused" `isInfixOf`)
                listDirectory directory `shouldBe'` []

    describe "what a stopped deployment tells" $ do
        it "names the seed spent before the genesis and the transactions that landed" $ do
            let seedRef = OutputReference (BS.replicate 32 0xa3) 4
                seedSpent =
                    DeployFailure
                        { failureLanded = [Landed PublishTemplate (transactionIdOf 1) 170_000 5_000_000 0]
                        , failureStoppedAt = Just CreateRegistry
                        , failureNotLanded = drop 1 allSteps
                        , failureSkipped = []
                        , failureCause = SeedSpent seedRef
                        }
                text = unlines (renderFailure seedSpent)
            text `shouldSatisfy` (("landed: publish-state-template " <> hexOf 1) `isInfixOf`)
            text `shouldSatisfy` ("stopped at: create-registry" `isInfixOf`)
            text `shouldSatisfy` ("not landed: create-registry" `isInfixOf`)
            text `shouldSatisfy` (("seed-spent: the registry's seed " <> concat (replicate 32 "a3") <> "#4 was spent") `isInfixOf`)
        it "tells, when the command runs, which seed was spent and what landed before" $ do
            blueprintPath <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            withSystemTempDirectory "registry-command" $ \directory -> do
                chainRef <- newIORef (newChain walletOutputs)
                let spendSeed accepted chain
                        | accepted == 2 = chain{chainOutputs = Map.delete expectedSeedIn (chainOutputs chain)}
                        | otherwise = chain
                    opener _ use = use (chainRuntime noFaults{afterAccepted = spendSeed} chainRef, walletAddress)
                    settings = settingsIn blueprintPath directory
                (outcome, err) <- capturing stderr (try (runRegistryDeployWith opener settings))
                outcome `shouldBe` (Left (ExitFailure 1) :: Either ExitCode ())
                chain <- readIORef chainRef
                let landedIds = reverse (map (T.unpack . renderTransactionId . transactionId) (chainAccepted chain))
                length landedIds `shouldBe` 7
                err `shouldSatisfy` (("seed-spent: the registry's seed " <> concat (replicate 32 "a3") <> "#4 was spent before the genesis") `isInfixOf`)
                sequence_
                    [ err `shouldSatisfy` (("landed: " <> renderStep step <> " " <> txid) `isInfixOf`)
                    | (step, txid) <- zip allSteps landedIds
                    ]
                err `shouldSatisfy` ("not landed: create-registry" `isInfixOf`)
                listDirectory directory `shouldBe'` []
        it "says which step it did not need" $ do
            let skipped =
                    DeployFailure
                        { failureLanded = []
                        , failureStoppedAt = Just PublishTemplate
                        , failureNotLanded = filter (/= RegisterObserverCredential) allSteps
                        , failureSkipped = [RegisterObserverCredential]
                        , failureCause = NodeFailed "x"
                        }
            unlines (renderFailure skipped) `shouldSatisfy` ("skipped: register-observer-credential" `isInfixOf`)
        it "says a transaction it could not see settle may still land, and was not resubmitted" $ do
            let uncertain =
                    DeployFailure
                        { failureLanded = []
                        , failureStoppedAt = Just PublishTemplate
                        , failureNotLanded = allSteps
                        , failureSkipped = []
                        , failureCause = NotObserved (transactionIdOf 2) "timed out"
                        }
                text = unlines (renderFailure uncertain)
            text `shouldSatisfy` (("uncertain: " <> hexOf 2 <> " may still land; it was not resubmitted") `isInfixOf`)
  where
    shouldBe' action expected = action >>= (`shouldBe` expected)
    transactionIdOf n = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 n))))
    hexOf n = T.unpack (renderTransactionId (transactionIdOf n))

-- | Every path under a directory, relative to it.
treeOf :: FilePath -> IO [FilePath]
treeOf root = do
    entries <- sort <$> listDirectory root
    concat
        <$> mapM
            ( \entry -> do
                isDirectory <- doesDirectoryExist (root </> entry)
                below <- if isDirectory then map (entry </>) <$> treeOf (root </> entry) else pure []
                pure (entry : below)
            )
            entries

{- | What a file holds now, read without the file lock a handle writing to it
holds against another handle of this process.
-}
readRaw :: FilePath -> IO String
readRaw path =
    bracket (Posix.openFd (B8.pack path) Posix.ReadOnly Posix.defaultFileFlags) Posix.closeFd $ \fd ->
        let go chunks = do
                chunk <- either (\e -> if isEOFError e then pure BS.empty else ioError e) pure =<< try @IOException (Posix.fdRead fd 65_536)
                if BS.null chunk then pure (BS.concat (reverse chunks)) else go (chunk : chunks)
         in B8.unpack <$> go []
