{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryKoiosCommandSpec
Description : @ckeri registry deploy@, @register@ and @return@ run through Koios and report as they do on the node

Each command is run whole, over the chain the node journeys run over, with the
Koios instance assembled from parts: its reads are the chain's, its handoff goes
over a live loopback stand-in for the service (so attempts, silence and
refusals are real), and its settlement is scripted. What is observed is the
choice of the one provider, what the commands refuse before reading anything,
what they print as they hand a transaction over and as it settles, and the
words of every stop. The expected lines of a Koios run are the lines of the
same run on the node, with the one noun that names the other end changed where
it appears. Ids and bytes are obtained from the stand-in's log and the ledger,
never typed in.
-}
module Cardano.KERI.Deployment.RegistryKoiosCommandSpec (
    spec,
    Case (..),
    Wired (..),
    Hooks (..),
    plainHooks,
    wire,
    wireWith,
    withDeploy,
    accepting,
    handedOver,
    idText,
    koiosAt,
    nodeChoice,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.KoiosRegistryRuntime (KoiosAccess (..), KoiosParts (..), koiosRegistryRuntime)
import Cardano.KERI.Deployment.KoiosRuntime (KoiosReads (..))
import Cardano.KERI.Deployment.KoiosSettlement (Refusal, Settlement (..), Unsettlement (..))
import Cardano.KERI.Deployment.KoiosStandIn (Script, Seen (..), answering, silent, withStandIn)
import Cardano.KERI.Deployment.KoiosSubmission (Handoff (..), HandoffResult (..), renderHandoff, submitHandoff)
import Cardano.KERI.Deployment.NodeSocketRuntime (KeySource (..), NodeAccess (..))
import Cardano.KERI.Deployment.RegistryBookingChain (
    World (..),
    accepted,
    advanceClock,
    bookDirectly,
    loadExport,
    newWorld,
    runtimeOf,
    setTip,
    withinOneMinute,
 )
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), ValidityEnd (..))
import Cardano.KERI.Deployment.RegistryCommand
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Chain (..), Faults (..), chainRuntime, newChain, noFaults, walletAddress, walletOutputs)
import Cardano.KERI.Deployment.RegistryFiles (writeDeploymentFiles)
import Cardano.KERI.Deployment.RegistryProvider
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (UnknownTxIn))
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Binary (decCBOR, decodeFullAnnotator, serialize')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Exception (IOException, finally, try)
import Control.Monad (forM_, void, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Char (isHexDigit)
import Data.Either (fromLeft)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf, stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.IO.Encoding (getLocaleEncoding, setLocaleEncoding, utf8)
import Paths_cardano_keri (getDataFileName)
import Singular.Provider.Koios.Client (Koios (..), defaultClientConfig)
import Singular.Provider.Koios.Http (HttpConfig (..), defaultHttpConfig, newHttpTransport)
import Singular.Registry.Confirmation (ConfirmationFailure (..))
import Singular.Registry.Signing (signedTx)
import System.Directory (createDirectory, listDirectory, withCurrentDirectory)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hGetEncoding, hPutStrLn, hSetEncoding, mkTextEncoding, stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

-- ---------------------------------------------------------------------
-- The wiring: both openers over one runtime, each noting how it was reached
-- ---------------------------------------------------------------------

data Wired = Wired
    { wiredOpeners :: Openers
    , wiredNode :: IO [NodeAccess]
    , wiredKoios :: IO [KoiosAccess]
    , wiredEvents :: IO [String]
    -- ^ "sign" and "handoff", in the order they happened
    }

{- | What the Koios instance is given besides the runtime's reads and its handoff: how it settles, what
validity end it builds with, what it makes of a transaction not seen to settle, and what the test's world does as a
handoff ends.
-}
data Hooks = Hooks
    { hookSettle :: ConwayTx -> IO (Either Refusal Settlement)
    , hookWindow :: IO ValidityEnd
    , hookAfterHandoff :: Handoff -> IO ()
    , hookPrepare :: ConwayTx -> IO ConwayTx
    -- ^ what is done to a transaction before it is signed
    , hookIncludes :: IO Bool
    -- ^ whether the chain includes a transaction the provider accepted
    }

-- | A settlement as given, no validity end asked for, nothing expired, a world that does not move.
plainHooks :: (ConwayTx -> IO (Either Refusal Settlement)) -> Hooks
plainHooks settlement = Hooks{hookSettle = settlement, hookWindow = pure EndNotSet, hookAfterHandoff = \_ -> pure (), hookIncludes = pure True, hookPrepare = pure}

{- | Both openers over the runtime given. The node opener hands that runtime out
as it is. The Koios opener assembles the instance from parts: the runtime's own
reads, a handoff over a live client of the access's URL, the settlement given.
-}
wire :: Int -> (ConwayTx -> IO (Either Refusal Settlement)) -> RegistryRuntime -> Addr -> IO Wired
wire bound settlement = wireWith (plainHooks settlement) bound

-- | The same, with the hooks given.
wireWith :: Hooks -> Int -> RegistryRuntime -> Addr -> IO Wired
wireWith hooks bound base payer = do
    nodeReached <- newIORef []
    koiosReached <- newIORef []
    events <- newIORef []
    let transactions = rtTransactions base
        koiosOpener access use = do
            modifyIORef' koiosReached (access :)
            client <-
                newHttpTransport (boundedBy bound (koiosUrl access)) >>= \case
                    Right transport -> pure (Koios defaultClientConfig transport)
                    Left failure -> fail ("the transport did not start: " <> show failure)
            runtime <-
                koiosRegistryRuntime
                    KoiosParts
                        { partReads =
                            KoiosReads
                                { readUtxosAt = rtUtxosAt base
                                , readOutputs = rtOutputs base
                                , readProtocolParameters = trQueryProtocolParams transactions
                                , readObservation = rtObserve base
                                , readEvaluation = trEvaluate transactions
                                , readRewardRegistered = rtRewardRegistered base
                                }
                        , partSign = \tx -> modifyIORef' events (<> ["sign"]) >> hookPrepare hooks tx >>= trSign transactions
                        , partHandoff = \signed -> do
                            modifyIORef' events (<> ["handoff"])
                            handoff <- submitHandoff client signed
                            included <- hookIncludes hooks
                            when (handoffResult handoff == Accepted && included) $
                                void (trSubmit transactions (signedTx signed))
                            hookAfterHandoff hooks handoff
                            pure handoff
                        , partSettle = hookSettle hooks
                        , partWindow = hookWindow hooks
                        , partReport = printHandoffReport
                        , partClock = rtNowMs base
                        }
            use (runtime, payer)
        nodeOpener access use = do
            modifyIORef' nodeReached (access :)
            use (base, payer)
    pure
        Wired
            { wiredOpeners = Openers{openersNode = nodeOpener, openersKoios = koiosOpener}
            , wiredNode = reverse <$> readIORef nodeReached
            , wiredKoios = reverse <$> readIORef koiosReached
            , wiredEvents = readIORef events
            }
  where
    boundedBy attempts url =
        (defaultHttpConfig url)
            { httpTimeout = 0.2
            , httpAttempts = attempts
            , httpBaseDelay = 0.01
            , httpMaxDelay = 0.02
            , httpCallCeiling = 30
            }

settles :: ConwayTx -> IO (Either Refusal Settlement)
settles _ = pure (Right Settled)

-- ---------------------------------------------------------------------
-- The stand-in's scripts
-- ---------------------------------------------------------------------

-- | The transaction a request body carries, as the ledger decodes it.
transactionOf :: ByteString -> Maybe ConwayTx
transactionOf body =
    either (const Nothing) Just $
        decodeFullAnnotator (eraProtVerHigh @ConwayEra) "signed transaction" decCBOR (BSL.fromStrict body)

-- | Accept every transaction under its own id.
accepting :: Script
accepting seen _ = case transactionOf (seenBody seen) of
    Just tx -> answering 202 ("\"" <> TE.encodeUtf8 (renderTransactionId (transactionId tx)) <> "\"")
    Nothing -> answering 400 "undecodable"

-- | No answer to the first @n@ requests, then the script.
silentFor :: Int -> Script -> Script
silentFor n next seen earlier
    | earlier < n = silent
    | otherwise = next seen earlier

refusing :: ByteString -> Script
refusing text _ _ = answering 400 text

-- | The transactions the stand-in's requests carried, in order.
handedOver :: [Seen] -> [ConwayTx]
handedOver seen = [tx | request <- seen, Just tx <- [transactionOf (seenBody request)]]

idText :: ConwayTx -> String
idText = T.unpack . renderTransactionId . transactionId

-- ---------------------------------------------------------------------
-- Cases: one command over one chain
-- ---------------------------------------------------------------------

data Case = Case
    { caseRuntime :: RegistryRuntime
    , casePayer :: Addr
    , caseRun :: Openers -> ProviderChoice -> IO (ExitCode, String, String)
    -- ^ the command, run whole in a directory of its own, with its exit, output and error output
    , caseRunAscii :: Openers -> ProviderChoice -> IO (ExitCode, String, String)
    -- ^ the same with both streams able to write ASCII only, as under @LC_ALL=C@, from the moment the command starts
    , caseRunUnreadable :: Openers -> ProviderChoice -> IO (ExitCode, String, String)
    -- ^ the same with a blueprint that cannot be read: whatever reads it first fails by its own name
    , caseLanded :: IO [ConwayTx]
    -- ^ the transactions the chain accepted since the command's world was made
    , caseDirectory :: FilePath
    }

-- | Run an action, and give its exit, what it printed and what it printed as an error.
runCaptured :: IO () -> IO (ExitCode, String, String)
runCaptured action = do
    ((outcome, out), err) <- capturing stderr (capturing stdout (try @ExitCode action))
    pure (fromLeft ExitSuccess outcome, out, err)

-- | A registry with the registration booked by the command: register.
withRegister :: (Case -> IO a) -> IO a
withRegister use = do
    world <- newWorld 1_000
    withFiles world $ \work blueprint identityFile recordFile -> do
        export <- getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
        landedBefore <- length <$> accepted world
        let settings provider =
                RegistryRegisterSettings
                    { rgNetworkMagic = 42
                    , rgBlueprint = blueprint
                    , rgProvider = provider
                    , rgFundingAddress = "addr_test1unused"
                    , rgSigningKeyFile = Just "no-key.skey"
                    , rgVault = Nothing
                    , rgPassphraseFd = Nothing
                    , rgTimeoutSeconds = 5
                    , rgReleaseIdentity = identityFile
                    , rgReferenceRecord = recordFile
                    , rgKliExport = export
                    , rgDeposit = Nothing
                    }
        use
            Case
                { caseRuntime = runtimeOf noFaults world
                , casePayer = walletAddress
                , caseRun = \openers provider ->
                    withCurrentDirectory work (runCaptured (runRegistryRegisterOver (hPutStrLn stderr) openers (settings provider)))
                , caseRunAscii = \openers provider ->
                    withCurrentDirectory work (runCapturedAscii (runRegistryRegisterOver (hPutStrLn stderr) openers (settings provider)))
                , caseRunUnreadable = \openers provider ->
                    withCurrentDirectory work (runCaptured (runRegistryRegisterOver (hPutStrLn stderr) openers (settings provider){rgBlueprint = "/nonexistent/blueprint"}))
                , caseLanded = drop landedBefore <$> accepted world
                , caseDirectory = work
                }

-- | A registry with a request booked and its deadline reached: return.
withReturn :: Bool -> (World -> Case -> IO a) -> IO a
withReturn atDeadline use = do
    world <- newWorld 1_000
    export <- loadExport "kli-export-single.cesr"
    (request, _) <- bookDirectly world export
    setTip world (if atDeadline then 10_095 else 10_094)
    withFiles world $ \work blueprint identityFile recordFile -> do
        landedBefore <- length <$> accepted world
        let settings provider =
                RegistryReturnSettings
                    { rnNetworkMagic = 42
                    , rnBlueprint = blueprint
                    , rnProvider = provider
                    , rnFundingAddress = "addr_test1unused"
                    , rnSigningKeyFile = Just "no-key.skey"
                    , rnVault = Nothing
                    , rnPassphraseFd = Nothing
                    , rnTimeoutSeconds = 5
                    , rnReleaseIdentity = identityFile
                    , rnReferenceRecord = recordFile
                    , rnRequest = T.pack (requestText request)
                    }
        use world $
            Case
                { caseRuntime = runtimeOf noFaults world
                , casePayer = walletAddress
                , caseRun = \openers provider ->
                    withCurrentDirectory work (runCaptured (runRegistryReturnOver (hPutStrLn stderr) openers (settings provider)))
                , caseRunAscii = \openers provider ->
                    withCurrentDirectory work (runCapturedAscii (runRegistryReturnOver (hPutStrLn stderr) openers (settings provider)))
                , caseRunUnreadable = \openers provider ->
                    withCurrentDirectory work (runCaptured (runRegistryReturnOver (hPutStrLn stderr) openers (settings provider){rnBlueprint = "/nonexistent/blueprint"}))
                , caseLanded = drop landedBefore <$> accepted world
                , caseDirectory = work
                }

-- | An empty chain with the wallet funded: deploy.
withDeploy :: (Case -> IO a) -> IO a
withDeploy = withDeployUnder noFaults

-- | The same over a chain with these faults.
withDeployUnder :: Faults -> (Case -> IO a) -> IO a
withDeployUnder faults use = do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    withSystemTempDirectory "registry-koios-deploy" $ \scratch -> do
        let work = scratch </> "cwd"
            out = scratch </> "out"
        createDirectory work
        createDirectory out
        chainRef <- newIORef (newChain walletOutputs)
        let settings provider =
                RegistryDeploySettings
                    { rdNetworkMagic = 42
                    , rdBlueprint = blueprint
                    , rdProvider = provider
                    , rdFundingAddress = "addr_test1unused"
                    , rdSigningKeyFile = Just "no-key.skey"
                    , rdVault = Nothing
                    , rdPassphraseFd = Nothing
                    , rdTimeoutSeconds = 5
                    , rdReferenceLovelace = Nothing
                    , rdReleaseIdentityOut = out </> "release-identity.json"
                    , rdReferenceRecordOut = out </> "reference-outputs.json"
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
        use
            Case
                { caseRuntime = chainRuntime faults chainRef
                , casePayer = walletAddress
                , caseRun = \openers provider ->
                    withCurrentDirectory work (runCaptured (runRegistryDeployOver openers (settings provider)))
                , caseRunAscii = \openers provider ->
                    withCurrentDirectory work (runCapturedAscii (runRegistryDeployOver openers (settings provider)))
                , caseRunUnreadable = \openers provider ->
                    withCurrentDirectory work (runCaptured (runRegistryDeployOver openers (settings provider){rdBlueprint = "/nonexistent/blueprint"}))
                , caseLanded = reverse . chainAccepted <$> readIORef chainRef
                , caseDirectory = out
                }

-- | A working directory with the two deployment files of a world, and where to find the rest.
withFiles :: World -> (FilePath -> FilePath -> FilePath -> FilePath -> IO a) -> IO a
withFiles world action = withSystemTempDirectory "registry-koios-command" $ \scratch -> do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
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
    action work blueprint identityFile recordFile

requestText :: TxIn -> String
requestText (TxIn txId (TxIx ix)) = T.unpack (renderTransactionId txId) <> "#" <> show ix

-- ---------------------------------------------------------------------
-- Choices
-- ---------------------------------------------------------------------

koiosAt :: Text -> ProviderChoice
koiosAt url = ProviderChoice{chosenNodeSocket = Nothing, chosenKoiosUrl = Just url, chosenKoiosTokenFile = Nothing, chosenNetworkTime = Nothing}

nodeChoice :: ProviderChoice
nodeChoice = ProviderChoice{chosenNodeSocket = Just "no-node.socket", chosenKoiosUrl = Nothing, chosenKoiosTokenFile = Nothing, chosenNetworkTime = Nothing}

-- | The same, with the streams made ASCII-only once capture has begun (capture takes the encoding of its file).
runCapturedAscii :: IO () -> IO (ExitCode, String, String)
runCapturedAscii action = runCaptured (mkTextEncoding "ASCII" >>= \ascii -> mapM_ (`hSetEncoding` ascii) [stdout, stderr] >> action)

-- | The three commands, each with a case of its own.
commands :: [(String, Scenario)]
commands =
    [ ("register", Scenario withRegister)
    , ("return", Scenario (\use -> withReturn True (\_ c -> use c)))
    , ("deploy", Scenario withDeploy)
    ]

-- | Something that sets a case up for an action and gives the action's result back.
newtype Scenario = Scenario {withScenario :: forall a. (Case -> IO a) -> IO a}

-- | A stand-in under the script, the wiring over a case, and the run on Koios.
onKoiosRun :: Script -> Int -> (ConwayTx -> IO (Either Refusal Settlement)) -> Case -> IO (Wired, [Seen], (ExitCode, String, String))
onKoiosRun script bound settlement c =
    withStandIn script $ \url seen -> do
        wired <- wire bound settlement (caseRuntime c) (casePayer c)
        result <- caseRun c (wiredOpeners wired) (koiosAt url)
        requests <- seen
        pure (wired, requests, result)

spec :: Spec
spec = describe "#546 the three commands through Koios" $ around_ withinOneMinute $ do
    choiceSpec
    refusalSpec
    reportSpec
    handoffSpec
    settlementSpec
    evaluationSpec
    returnWindowSpec

-- ---------------------------------------------------------------------
-- One provider
-- ---------------------------------------------------------------------

choiceSpec :: Spec
choiceSpec = describe "the one provider a command is given" $
    forM_ commands $ \(name, scenario) -> do
        it (name <> " on Koios reaches the Koios opener once, as told, and never the node's") $
            withScenario scenario $ \c -> do
                (wired, _, (code, _, _)) <- onKoiosRun accepting 3 settles c
                code `shouldBe` ExitSuccess
                wiredNode wired >>= (`shouldBe` [])
                reached <- wiredKoios wired
                map koiosNetworkMagic reached `shouldBe` [42]
                map koiosFundingAddress reached `shouldBe` ["addr_test1unused"]
                map koiosSigningKey reached `shouldBe` [KeyFile "no-key.skey"]
                map koiosTokenFile reached `shouldBe` [Nothing]
        it (name <> " on the node socket reaches the node opener once, as told, and never the Koios opener") $
            withScenario scenario $ \c -> do
                wired <- wire 3 settles (caseRuntime c) (casePayer c)
                (code, _, _) <- caseRun c (wiredOpeners wired) nodeChoice
                code `shouldBe` ExitSuccess
                wiredKoios wired >>= (`shouldBe` [])
                wiredNode wired >>= (`shouldBe` [NodeAccess 42 "no-node.socket" "addr_test1unused" (KeyFile "no-key.skey") 5 Nothing])
        it (name <> " passes the token file the choice names to the Koios opener, unread") $
            withScenario scenario $ \c ->
                withStandIn accepting $ \url _ -> do
                    wired <- wire 3 settles (caseRuntime c) (casePayer c)
                    _ <- caseRun c (wiredOpeners wired) (koiosAt url){chosenKoiosTokenFile = Just "a-token-file"}
                    reached <- wiredKoios wired
                    map koiosTokenFile reached `shouldBe` [Just "a-token-file"]
        it (name <> " passes the network time directory the choice names to the Koios opener, unread") $
            withScenario scenario $ \c ->
                withStandIn accepting $ \url _ -> do
                    wired <- wire 3 settles (caseRuntime c) (casePayer c)
                    _ <- caseRun c (wiredOpeners wired) (koiosAt url){chosenNetworkTime = Just "a-time-directory"}
                    reached <- wiredKoios wired
                    map koiosNetworkTime reached `shouldBe` [Just "a-time-directory"]
        it (name <> " passes the network time directory the choice names to the node opener, unread") $
            withScenario scenario $ \c -> do
                wired <- wire 3 settles (caseRuntime c) (casePayer c)
                _ <- caseRun c (wiredOpeners wired) nodeChoice{chosenNetworkTime = Just "a-time-directory"}
                reached <- wiredNode wired
                map naNetworkTime reached `shouldBe` [Just "a-time-directory"]
        it (name <> " never falls back to the node when Koios cannot be read") $
            withScenario scenario $ \c ->
                withStandIn accepting $ \url _ -> do
                    let broken = (caseRuntime c){rtUtxosAt = \_ -> ioError (userError "provider unreachable")}
                    wired <- wire 3 settles broken (casePayer c)
                    (code, _, err) <- caseRun c (wiredOpeners wired) (koiosAt url)
                    code `shouldBe` ExitFailure 1
                    wiredNode wired >>= (`shouldBe` [])
                    err `shouldSatisfy` ("provider unreachable" `isInfixOf`)
                    err `shouldSatisfy` (not . ("the node" `isInfixOf`))
                    caseLanded c >>= (`shouldBe` []) . map idText

-- ---------------------------------------------------------------------
-- What is refused before anything is read
-- ---------------------------------------------------------------------

refusalSpec :: Spec
refusalSpec = describe "a provider choice that is not exactly one" $ do
    forM_ commands $ \(name, scenario) ->
        forM_
            [ ("both a Koios URL and a node socket", both, "provider-both-given")
            , ("neither", ProviderChoice Nothing Nothing Nothing Nothing, "provider-none-given")
            , ("a token file with no Koios URL", ProviderChoice (Just "no-node.socket") Nothing (Just "t") Nothing, "koios-token-file-without-koios-url")
            , ("a token file with a node socket and a Koios URL", both{chosenKoiosTokenFile = Just "t"}, "provider-both-given")
            ]
            $ \(label, choice, refusal) ->
                it (name <> " given " <> label <> " is refused as " <> refusal <> " before anything is read or opened") $
                    withScenario scenario $ \c -> do
                        wired <- wire 3 settles (caseRuntime c) (casePayer c)
                        (code, _, err) <- caseRunUnreadable c (wiredOpeners wired) choice
                        code `shouldBe` ExitFailure 1
                        err `shouldSatisfy` (("ckeri: " <> refusal <> ":") `isInfixOf`)
                        err `shouldSatisfy` (not . ("nonexistent" `isInfixOf`))
                        wiredNode wired >>= (`shouldBe` [])
                        wiredKoios wired >>= (`shouldBe` [])
                        caseLanded c >>= (`shouldBe` []) . map idText
    forM_ commands $ \(name, scenario) ->
        it (name <> " given one provider and a blueprint that cannot be read stops at the blueprint, so the refusals above are made before it is read") $
            withScenario scenario $ \c -> do
                wired <- wire 3 settles (caseRuntime c) (casePayer c)
                outcome <- try @IOException (caseRunUnreadable c (wiredOpeners wired) nodeChoice)
                either show (const "the command went on") outcome `shouldSatisfy` ("nonexistent" `isInfixOf`)
    forM_ [("a Koios URL", koiosAt "http://koios.invalid/api/v1"), ("a Koios URL and a token file", (koiosAt "http://koios.invalid/api/v1"){chosenKoiosTokenFile = Just "t"})] $ \(label, choice) ->
        it ("fold given " <> label <> " is refused as fold-runs-on-the-node-only, before it reads a file or opens a provider") $ do
            wired <- wire 3 settles (error "no runtime is wanted") walletAddress
            (code, _, err) <- runCaptured (runRegistryFoldOver (hPutStrLn stderr) (wiredOpeners wired) (foldSettings choice))
            code `shouldBe` ExitFailure 1
            err `shouldSatisfy` ("ckeri: fold-runs-on-the-node-only:" `isInfixOf`)
            err `shouldSatisfy` (not . ("invalid" `isInfixOf`))
            wiredNode wired >>= (`shouldBe` [])
            wiredKoios wired >>= (`shouldBe` [])
    it "fold given neither is refused as provider-none-given" $ do
        wired <- wire 3 settles (error "no runtime is wanted") walletAddress
        (code, _, err) <- runCaptured (runRegistryFoldOver (hPutStrLn stderr) (wiredOpeners wired) (foldSettings (ProviderChoice Nothing Nothing Nothing Nothing)))
        code `shouldBe` ExitFailure 1
        err `shouldSatisfy` ("ckeri: provider-none-given:" `isInfixOf`)
  where
    both = ProviderChoice{chosenNodeSocket = Just "no-node.socket", chosenKoiosUrl = Just "http://koios.invalid/api/v1", chosenKoiosTokenFile = Nothing, chosenNetworkTime = Nothing}
    foldSettings choice =
        RegistryFoldSettings
            { rfNetworkMagic = 42
            , rfBlueprint = "/nonexistent/blueprint"
            , rfProvider = choice
            , rfFundingAddress = "addr_test1unused"
            , rfSigningKeyFile = Just "no-key.skey"
            , rfVault = Nothing
            , rfPassphraseFd = Nothing
            , rfTimeoutSeconds = 5
            , rfReleaseIdentity = "/nonexistent/release-identity.json"
            , rfReferenceRecord = "/nonexistent/reference-outputs.json"
            , rfKliExport = "/nonexistent/export.cesr"
            , rfRequest = ""
            , rfSnapshot = "/nonexistent/snapshot.json"
            , rfSnapshotOut = Nothing
            }

-- ---------------------------------------------------------------------
-- Reports: the node's lines with the one noun changed
-- ---------------------------------------------------------------------

-- | A line with the case's own directory named, so that two cases' lines can be compared.
scrubbed :: FilePath -> String -> String
scrubbed directory = go
  where
    go [] = []
    go line@(c : rest)
        | directory `isPrefixOf` line = "<directory>" <> go (drop (length directory) line)
        | otherwise = c : go rest

-- | Stdout has a definitive first-attempt refusal line, and that very line names the transaction.
refusalLineNames :: ConwayTx -> String -> Bool
refusalLineNames tx out =
    case [line | line <- lines out, "provider-handoff: refused by the provider after 1 attempt: " `isPrefixOf` line] of
        [] -> False
        refusals -> all (idText tx `isInfixOf`) refusals

isHandoffReport :: String -> Bool
isHandoffReport line = any (`isPrefixOf` line) ["provider-handoff: ", "provider-handoff-limits: ", "provider-handoff-transaction: "]

{- | What a line of the node's output becomes on Koios: where it says it hands a
transaction to the node, it says the provider.
-}
onTheProvider :: String -> String
onTheProvider line
    | " to the node" `isSuffixOf` line = take (length line - length (" to the node" :: String)) line <> " to the provider"
    | otherwise = line

reportSpec :: Spec
reportSpec = describe "what a command prints on Koios" $
    forM_ commands $ \(name, scenario) -> do
        it (name <> " prints the lines of the same run on the node, with the provider named where the node was, and one handoff report for each transaction it hands over") $ do
            nodeOut <- withScenario scenario $ \c -> do
                wired <- wire 3 settles (caseRuntime c) (casePayer c)
                (code, out, _) <- caseRun c (wiredOpeners wired) nodeChoice
                code `shouldBe` ExitSuccess
                nodeIds <- map idText <$> caseLanded c
                pure (map (scrubbed (caseDirectory c)) (lines out), nodeIds)
            withScenario scenario $ \c -> do
                (_, requests, (code, out, err)) <- onKoiosRun accepting 3 settles c
                code `shouldBe` ExitSuccess
                koiosLanded <- caseLanded c
                let koiosIds = map idText koiosLanded
                -- the same transactions: the ledger's ids, not typed in
                koiosIds `shouldBe` snd nodeOut
                map idText (handedOver requests) `shouldBe` koiosIds
                let outLines = map (scrubbed (caseDirectory c)) (lines out)
                    reports = filter isHandoffReport outLines
                filter (not . isHandoffReport) outLines `shouldBe` map onTheProvider (fst nodeOut)
                [line | line <- reports, "provider-handoff: " `isPrefixOf` line]
                    `shouldBe` ["provider-handoff: " <> T.unpack (renderHandoff (Handoff (transactionId tx) 1 Accepted)) | tx <- koiosLanded]
                forM_ [line | line <- reports, "provider-handoff-limits: " `isPrefixOf` line] $ \line -> do
                    line `shouldSatisfy` ("the attempt count is the transport's" `isInfixOf`)
                    line `shouldSatisfy` ("https://github.com/lambdasistemi/singular/issues/819" `isInfixOf`)
                length [line | line <- reports, "provider-handoff-limits: " `isPrefixOf` line] `shouldBe` length koiosIds
                out `shouldSatisfy` (not . ("the node" `isInfixOf`))
                err `shouldSatisfy` ("ckeri: not for mainnet" `isInfixOf`)
                listDirectoryOf c >>= (`shouldSatisfy` all (`elem` ["release-identity.json", "reference-outputs.json"]))
  where
    listDirectoryOf c = listDirectory (caseDirectory c)

-- ---------------------------------------------------------------------
-- The handoff
-- ---------------------------------------------------------------------

handoffSpec :: Spec
handoffSpec = describe "the handoff of a transaction a command signed" $ do
    it "sends the same bytes again when an attempt got no answer, and builds and signs nothing after the first handoff" $
        withRegister $ \c -> do
            (wired, requests, (code, out, _)) <- onKoiosRun (silentFor 2 accepting) 5 settles c
            code `shouldBe` ExitSuccess
            booking <- last <$> caseLanded c
            map (serialize' (eraProtVerHigh @ConwayEra)) (handedOver requests)
                `shouldBe` replicate 3 (serialize' (eraProtVerHigh @ConwayEra) booking)
            out `shouldSatisfy` (("provider-handoff: " <> T.unpack (renderHandoff (Handoff (transactionId booking) 3 Accepted))) `isInfixOf`)
            events <- wiredEvents wired
            dropWhile (/= "handoff") events `shouldBe` ["handoff"]
    it "ends in the unknown, with the attempts and the provider named, when no attempt was answered" $
        withRegister $ \c -> do
            (wired, requests, (code, out, err)) <- onKoiosRun (\_ _ -> silent) 2 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
                booking = idText signed
            length requests `shouldBe` 2
            err `shouldSatisfy` (("booking " <> booking <> " may or may not have reached the provider; check it before spending again") `isInfixOf`)
            err `shouldSatisfy` (("handoff-unconfirmed: " <> T.unpack (renderHandoff (Handoff (transactionId signed) 2 NoAnswer))) `isInfixOf`)
            err `shouldSatisfy` (not . ("it is not on chain" `isInfixOf`))
            err `shouldSatisfy` (not . ("the node" `isInfixOf`))
            out `shouldSatisfy` (("provider-handoff: " <> T.unpack (renderHandoff (Handoff (transactionId signed) 2 NoAnswer))) `isInfixOf`)
            events <- wiredEvents wired
            dropWhile (/= "handoff") events `shouldBe` ["handoff"]
            caseLanded c >>= (`shouldBe` [])
    it "says a refusal at the first attempt is the provider's, and that the transaction is not on chain" $
        withRegister $ \c -> do
            (_, requests, (code, out, err)) <- onKoiosRun (refusing "BadInputsUTxO") 3 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            length requests `shouldBe` 1
            err `shouldSatisfy` (("booking " <> idText signed <> " was refused by the provider: BadInputsUTxO; it is not on chain") `isInfixOf`)
            err `shouldSatisfy` ("ckeri: registry register stopped, refused by the provider: submission-refused: BadInputsUTxO" `isInfixOf`)
            err `shouldSatisfy` (not . ("the ledger" `isInfixOf`))
            out `shouldSatisfy` (("provider-handoff: " <> T.unpack (renderHandoff (Handoff (transactionId signed) 1 (Refused "BadInputsUTxO")))) `isInfixOf`)
    it "keeps what the provider said of a refusal word for word, whatever it says of itself" $
        withRegister $ \c -> do
            let said = "the node rejected the spending input"
            (_, requests, (code, out, err)) <- onKoiosRun (refusing said) 3 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            err `shouldSatisfy` (("booking " <> idText signed <> " was refused by the provider: " <> T.unpack (TE.decodeUtf8 said) <> "; it is not on chain") `isInfixOf`)
            err `shouldSatisfy` (("submission-refused: " <> T.unpack (TE.decodeUtf8 said)) `isInfixOf`)
            out `shouldSatisfy` (("refused by the provider after 1 attempt: transaction " <> idText signed <> ": " <> T.unpack (TE.decodeUtf8 said)) `isInfixOf`)
            err `shouldSatisfy` (not . ("the provider rejected" `isInfixOf`))
    it "keeps the accents and the marks of what the provider said of a refusal, in the row and the cause, as the handoff report does" $
        utf8Streams . withRegister $ \c -> do
            let said = "d\233p\244t refus\233, the node rejected the input \xE001the node \xE000the node\xE001"
            (_, requests, (code, out, err)) <- onKoiosRun (refusing (TE.encodeUtf8 (T.pack said))) 3 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            err `shouldSatisfy` (("booking " <> idText signed <> " was refused by the provider: " <> said <> "; it is not on chain") `isInfixOf`)
            err `shouldSatisfy` (("submission-refused: " <> said) `isInfixOf`)
            out `shouldSatisfy` (("refused by the provider after 1 attempt: transaction " <> idText signed <> ": " <> said) `isInfixOf`)
    forM_ [("register", Scenario withRegister, "booking"), ("return", Scenario (\use -> withReturn True (\_ c -> use c)), "return"), ("deploy", Scenario withDeploy, "publish-state-template")] $ \(name, scenario, kind) ->
        it ("gives a reader on an ASCII terminal the id and the definite refusal of a first-attempt refusal with accents, " <> name <> ", on both streams") $
            utf8Locale . withScenario scenario $ \c -> do
                let said = "d\233p\244t refus\233"
                (wired, requests, (code, out, err)) <-
                    withStandIn (refusing (TE.encodeUtf8 (T.pack said))) $ \url seen -> do
                        wired <- wire 3 settles (caseRuntime c) (casePayer c)
                        result <- caseRunAscii c (wiredOpeners wired) (koiosAt url)
                        requests <- seen
                        pure (wired, requests, result)
                wiredNode wired >>= (`shouldBe` [])
                code `shouldBe` ExitFailure 1
                let signed = last (handedOver requests)
                err `shouldSatisfy` ((kind <> " " <> idText signed <> " was refused by the provider: d") `isInfixOf`)
                err `shouldSatisfy` ("; it is not on chain" `isInfixOf`)
                err `shouldSatisfy` (not . ("may or may not have reached the provider" `isInfixOf`))
                out `shouldSatisfy` (("refused by the provider after 1 attempt: transaction " <> idText signed <> ": d") `isInfixOf`)
                -- the same transaction the row on stderr names, on the definitive refusal line of stdout itself
                out `shouldSatisfy` refusalLineNames signed
    it "keeps the words of an answer that is neither an acceptance nor a refusal word for word" $
        withRegister $ \c -> do
            (_, _, (code, _, err)) <- onKoiosRun (\_ _ -> answering 403 "the node is down") 3 settles c
            code `shouldBe` ExitFailure 1
            err `shouldSatisfy` ("the node is down" `isInfixOf`)
            err `shouldSatisfy` (not . ("the provider is down" `isInfixOf`))
    it "says a return refused at submission was refused by the provider, in its header and in its row, and not by the ledger" $
        withReturn True $ \_ c -> do
            (_, requests, (code, _, err)) <- onKoiosRun (refusing "BadInputsUTxO") 3 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            err `shouldSatisfy` ("ckeri: registry return stopped, refused by the provider: submission-refused: BadInputsUTxO" `isInfixOf`)
            err `shouldSatisfy` (("return " <> idText signed <> " was refused by the provider: BadInputsUTxO; it is not on chain") `isInfixOf`)
            err `shouldSatisfy` (not . ("the ledger" `isInfixOf`))
    it "binds the id of a deployment's refused publication to its refusal and to its not being on chain, on Koios" $
        withDeploy $ \c -> do
            let said = "the node rejected the spending input"
            (_, requests, (code, out, err)) <- onKoiosRun (refusing said) 3 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            out `shouldSatisfy` refusalLineNames signed
            err `shouldSatisfy` (("publish-state-template " <> idText signed <> " was refused by the provider: " <> T.unpack (TE.decodeUtf8 said) <> "; it is not on chain") `isInfixOf`)
            err `shouldSatisfy` (("submission-refused: " <> T.unpack (TE.decodeUtf8 said)) `isInfixOf`)
    forM_ [("register", Scenario withRegister), ("return", Scenario (\use -> withReturn True (\_ c -> use c))), ("deploy", Scenario withDeploy)] $ \(name, scenario) ->
        forM_ [("no line break", Nothing), ("a line feed", Just "\n"), ("a carriage return and a line feed", Just "\r\n")] $ \(breakName, lineBreak) ->
            it ("puts the id on the definitive refusal line of standard output before the provider's reason, and the whole reason after it, in order: " <> breakName <> ", " <> name) $
                withScenario scenario $ \c -> do
                    let firstLine = "the node rejected the spending input"
                        secondLine = "second line of the reason"
                        reason = maybe firstLine (\separator -> firstLine <> separator <> secondLine) lineBreak
                        said = TE.encodeUtf8 (T.pack reason)
                    (_, requests, (code, out, err)) <- onKoiosRun (refusing said) 3 settles c
                    code `shouldBe` ExitFailure 1
                    let signed = last (handedOver requests)
                        refusalPrefix = "provider-handoff: refused by the provider after 1 attempt: "
                        refusals = [line | line <- lines out, refusalPrefix `isPrefixOf` line]
                        following = drop 1 (dropWhile (not . (refusalPrefix `isPrefixOf`)) (lines out))
                    -- the line that says the transaction was refused names it before any word of the reason
                    refusals `shouldSatisfy` ((== 1) . length)
                    out `shouldSatisfy` refusalLineNames signed
                    let named = refusalPrefix <> "transaction " <> idText signed <> ": "
                    map (filter (/= '\r')) refusals `shouldBe` [named <> firstLine]
                    -- the reason follows the id, whole and in order: one line of it after the id, then the rest
                    case lineBreak of
                        Nothing -> pure ()
                        Just _ -> do
                            take 1 (map (filter (/= '\r')) following) `shouldBe` [secondLine]
                            err `shouldSatisfy` (secondLine `isInfixOf`)
                    err `shouldSatisfy` ((idText signed <> " was refused by the provider: " <> firstLine) `isInfixOf`)
    it "gives a reader on an ASCII terminal the id on the definitive refusal line when the reason spans lines" $
        utf8Locale . withScenario (Scenario withDeploy) $ \c -> do
            let said = "d\233p\244t refus\233\nsecond line"
            (_, requests, (code, out, _)) <-
                withStandIn (refusing (TE.encodeUtf8 (T.pack said))) $ \url seen -> do
                    wired <- wire 3 settles (caseRuntime c) (casePayer c)
                    result <- caseRunAscii c (wiredOpeners wired) (koiosAt url)
                    requests <- seen
                    pure (wired, requests, result)
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            out `shouldSatisfy` refusalLineNames signed
            out `shouldSatisfy` (("transaction " <> idText signed <> ": d") `isInfixOf`)
            out `shouldSatisfy` ("second line" `isInfixOf`)
    it "binds it on the node as well, in the node's words" $
        withDeployUnder noFaults{rejectSubmissionAt = Just 0} $ \c -> do
            wired <- wire 3 settles (caseRuntime c) (casePayer c)
            (code, _, err) <- caseRun c (wiredOpeners wired) nodeChoice
            code `shouldBe` ExitFailure 1
            let rows = [rest | line <- lines err, Just rest <- [stripPrefix "publish-state-template " line]]
            case rows of
                [row] -> do
                    length (takeWhile isHexDigit row) `shouldBe` 64
                    drop 64 row `shouldBe` " was refused by the node: the node refuses this transaction; it is not on chain"
                other -> expectationFailure ("one row was wanted: " <> show other)
    it "does not say a refusal is not on chain when an earlier attempt got no answer: the transaction may have been delivered" $
        withRegister $ \c -> do
            (_, requests, (code, _, err)) <- onKoiosRun (silentFor 1 (refusing "BadInputsUTxO")) 3 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            length requests `shouldBe` 2
            err `shouldSatisfy` (("booking " <> idText signed <> " may or may not have reached the provider; check it before spending again") `isInfixOf`)
            err `shouldSatisfy` (not . ("it is not on chain" `isInfixOf`))
    it "tells a deployment that stops at an unanswered handoff that no other transaction was built or signed, and not that nothing was resubmitted" $
        withDeploy $ \c -> do
            (_, requests, (code, out, err)) <- onKoiosRun (silentFor' 1) 1 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            landed <- caseLanded c
            length landed `shouldBe` 1
            err `shouldSatisfy` (("uncertain: " <> idText signed <> " may still land; no other transaction was built or signed") `isInfixOf`)
            err `shouldSatisfy` (not . ("it was not resubmitted" `isInfixOf`))
            err `shouldSatisfy` (("not-observed: " <> idText signed <> " " <> T.unpack (renderHandoff (Handoff (transactionId signed) 1 NoAnswer))) `isInfixOf`)
            err `shouldSatisfy` (not . ("it is not on chain" `isInfixOf`))
            err `shouldSatisfy` (not . ("refused by the provider" `isInfixOf`))
            length (filter ("provider-handoff: " `isPrefixOf`) (lines out)) `shouldBe` 2
    it "tells a return that stops at an unanswered handoff that no other transaction is built, signed or sent by the command" $
        withReturn True $ \_ c -> do
            (_, requests, (code, _, err)) <- onKoiosRun (\_ _ -> silent) 1 settles c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            err `shouldSatisfy` (("return " <> idText signed <> " may or may not have reached the provider; check it before spending again") `isInfixOf`)
            err `shouldSatisfy` (("handoff-unconfirmed: " <> T.unpack (renderHandoff (Handoff (transactionId signed) 1 NoAnswer))) `isInfixOf`)
            err `shouldSatisfy` (not . ("it is not on chain" `isInfixOf`))
            err `shouldSatisfy` ("not retried: no other transaction is built, signed or sent by this command" `isInfixOf`)
            err `shouldSatisfy` (not . ("no transaction is sent again by this command" `isInfixOf`))
  where
    -- the first transaction is answered, the second never
    silentFor' k seen earlier
        | earlier < k = accepting seen earlier
        | otherwise = silent

-- ---------------------------------------------------------------------
-- The settlement
-- ---------------------------------------------------------------------

settlementSpec :: Spec
settlementSpec = describe "a transaction the provider accepted" $ do
    it "is reported as accepted and not seen to settle, with the K2 wording, the time to look again at and the bound as it is" $
        withRegister $ \c -> do
            let unsettled tx =
                    pure . Right . NotSettled $
                        Unsettlement
                            { unsettledTransaction = transactionId tx
                            , unsettledBy = ConfirmationNoOutput (transactionId tx)
                            , unsettledDeadlineMs = 1_700_000_120_000
                            , unsettledBoundSeconds = Nothing
                            }
            (_, requests, (code, _, err)) <- onKoiosRun accepting 3 unsettled c
            code `shouldBe` ExitFailure 1
            let signed = last (handedOver requests)
            err `shouldSatisfy` (("booking " <> idText signed <> " was accepted by the provider and is not seen on chain; check it before spending again") `isInfixOf`)
            err `shouldSatisfy` ("may or may not have reached the provider; check it before spending again, and look again after 1700000120000 ms since the epoch" `isInfixOf`)
            err `shouldSatisfy` ("may run a few seconds after" `isInfixOf`)
            err `shouldSatisfy` (not . ("the node" `isInfixOf`))

-- ---------------------------------------------------------------------
-- Time: the window rules as on the node
-- ---------------------------------------------------------------------

returnWindowSpec :: Spec
returnWindowSpec = describe "the window of a return on Koios" $
    it "refuses by name when the clock reads the deadline as reached and the chain's tip does not, as on the node, before any transaction" $
        withReturn False $ \world c -> do
            advanceClock world 1_000
            (wired, requests, (code, _, err)) <- onKoiosRun accepting 3 settles c
            code `shouldBe` ExitFailure 1
            wiredNode wired >>= (`shouldBe` [])
            wiredKoios wired >>= (`shouldBe` 1) . length
            err `shouldSatisfy` ("time-evidence-conflicts" `isInfixOf`)
            err `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
            requests `shouldSatisfy` null
            caseLanded c >>= (`shouldBe` []) . map idText

-- ---------------------------------------------------------------------
-- The evaluation
-- ---------------------------------------------------------------------

evaluationSpec :: Spec
evaluationSpec = describe "an evaluation that refuses a booking on Koios" $
    it "is labelled the local evaluation of the transaction, which is where it happened, and nothing is handed over" $
        withRegister $ \c -> do
            let base = caseRuntime c
                missing = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xee))))) (TxIx 0)
                refusing' =
                    base
                        { rtTransactions =
                            (rtTransactions base)
                                { trEvaluate = fmap (Map.map (const (Left (UnknownTxIn missing)))) . trEvaluate (rtTransactions base)
                                }
                        }
            withStandIn accepting $ \url seen -> do
                wired <- wire 3 settles refusing' (casePayer c)
                (code, _, err) <- caseRun c (wiredOpeners wired) (koiosAt url)
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("refused by the local evaluation of the transaction" `isInfixOf`)
                err `shouldSatisfy` ("the local evaluation refused the booking" `isInfixOf`)
                err `shouldSatisfy` (not . ("the provider's evaluation" `isInfixOf`))
                err `shouldSatisfy` (not . ("the node" `isInfixOf`))
                err `shouldSatisfy` ("nothing was submitted; nothing was spent" `isInfixOf`)
                requests <- seen
                requests `shouldSatisfy` null

-- | Run an action with the standard streams and the default text encoding set to UTF-8, and put them back.
utf8Streams :: IO a -> IO a
utf8Streams action = do
    encodings <- mapM hGetEncoding [stdout, stderr]
    locale <- getLocaleEncoding
    setLocaleEncoding utf8
    mapM_ (`hSetEncoding` utf8) [stdout, stderr]
    action `finally` do
        mapM_ (\(handle, old) -> maybe (pure ()) (hSetEncoding handle) old) (zip [stdout, stderr] encodings)
        setLocaleEncoding locale

-- | Run an action with the default text encoding UTF-8, so that what a capture holds can be read back.
utf8Locale :: IO a -> IO a
utf8Locale action = do
    locale <- getLocaleEncoding
    setLocaleEncoding utf8
    action `finally` setLocaleEncoding locale
