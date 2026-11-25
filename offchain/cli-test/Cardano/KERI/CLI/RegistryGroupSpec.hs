{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.CLI.RegistryGroupSpec
Description : @ckeri registry deploy@ is the one new command, and it takes every term

The production 'Instructions' parser is run with no environment and no
configuration file, unless the example says otherwise. @registry deploy@ is
parsed to the settings it names, each option to its own field; a term left out
is refused; the options of the first deployment's commands that mean a store, a
manifest or a provider are not offered; and the first deployment's @deploy@ is
the command it was.
-}
module Cardano.KERI.CLI.RegistryGroupSpec (spec) where

import Cardano.KERI.CLI (Instructions (..))
import Cardano.KERI.Deployment.RegistryCommand (RegistryDeploySettings (..))
import Cardano.KERI.Deployment.RegistryProvider (ProviderChoice (..))
import Data.Char (toUpper)
import Data.List (isInfixOf)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import OptEnvConf qualified as Opt
import OptEnvConf.Args (parseArgs)
import OptEnvConf.Capability (allCapabilities)
import OptEnvConf.EnvMap qualified as EnvMap
import OptEnvConf.Error (ParseError (..), ParseErrorMessage (..))
import OptEnvConf.Run (runParserOn)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

-- | The options of one deployment, each with a value no other option has.
deployOptions :: [(String, String)]
deployOptions =
    [ ("--network-magic", "42")
    , ("--blueprint", "plutus.json")
    , ("--node-socket", "node.socket")
    , ("--funding-address", "addr_test1qexample")
    , ("--signing-key-file", "payment.skey")
    , ("--timeout-seconds", "77")
    , ("--reference-lovelace", "66000000")
    , ("--release-identity-out", "identity.json")
    , ("--reference-record-out", "references.json")
    , ("--registration-cost", "1000001")
    , ("--minimum-tip", "500002")
    , ("--process-time", "90003")
    , ("--booking-width", "5004")
    , ("--deposit", "1000000005")
    , ("--freeze-bond", "5000006")
    , ("--premium", "2000007")
    , ("--minimum-ada", "2000008")
    , ("--termination-carrier", "1500009")
    ]

-- | The settings those options name.
expectedSettings :: RegistryDeploySettings
expectedSettings =
    RegistryDeploySettings
        { rdNetworkMagic = 42
        , rdBlueprint = "plutus.json"
        , rdProvider = ProviderChoice (Just "node.socket") Nothing Nothing Nothing
        , rdFundingAddress = "addr_test1qexample"
        , rdSigningKeyFile = Just "payment.skey"
        , rdVault = Nothing
        , rdPassphraseFd = Nothing
        , rdTimeoutSeconds = 77
        , rdReferenceLovelace = Just 66_000_000
        , rdReleaseIdentityOut = "identity.json"
        , rdReferenceRecordOut = "references.json"
        , rdRegistrationCost = 1_000_001
        , rdMinimumTip = 500_002
        , rdProcessTime = 90_003
        , rdBookingWidth = 5_004
        , rdDeposit = 1_000_000_005
        , rdFreezeBond = 5_000_006
        , rdPremium = 2_000_007
        , rdMinimumAda = 2_000_008
        , rdTerminationCarrier = 1_500_009
        }

-- | The nine terms of a registry, by option.
termOptions :: [String]
termOptions =
    [ "--registration-cost"
    , "--minimum-tip"
    , "--process-time"
    , "--booking-width"
    , "--deposit"
    , "--freeze-bond"
    , "--premium"
    , "--minimum-ada"
    , "--termination-carrier"
    ]

argumentsOf :: [(String, String)] -> [String]
argumentsOf options = concat [[name, value] | (name, value) <- options]

spec :: Spec
spec = describe "#351 ckeri registry deploy: the command surface" $ do
    it "parses every option to its own setting" $ do
        result <- parseWith [] (["registry", "deploy"] <> argumentsOf deployOptions)
        case result of
            Right (RegistryDeploy settings) -> settings `shouldBe` expectedSettings
            Right _ -> expectationFailure "the arguments were taken for another command"
            Left errors -> expectationFailure ("not parsed: " <> show errors)
    it "takes the provider from options or environment: a node socket, or a Koios URL with an optional token file, as given and not yet checked" $ do
        let others = [o | o@(name, _) <- deployOptions, name /= "--node-socket"]
            koios = [("--koios-url", "https://koios.example/api/v1"), ("--koios-token-file", "koios.token")]
            url = Just "https://koios.example/api/v1"
        mapM_
            ( \(label, options, expected) -> do
                result <- parseWith [] (["registry", "deploy"] <> argumentsOf options)
                case result of
                    Right (RegistryDeploy settings) -> (label, rdProvider settings) `shouldBe` (label, expected)
                    other -> expectationFailure (label <> ": not parsed: " <> showResult other)
            )
            [ ("only a Koios URL", others <> take 1 koios, ProviderChoice Nothing url Nothing Nothing)
            , ("a Koios URL and a token file", others <> koios, ProviderChoice Nothing url (Just "koios.token") Nothing)
            , ("both a node socket and a Koios URL", deployOptions <> take 1 koios, ProviderChoice (Just "node.socket") url Nothing Nothing)
            , ("neither", others, ProviderChoice Nothing Nothing Nothing Nothing)
            ]
        fromEnvironment <-
            parseWith
                [("CKERI_KOIOS_URL", "https://koios.example/api/v1"), ("CKERI_KOIOS_TOKEN_FILE", "koios.token")]
                (["registry", "deploy"] <> argumentsOf others)
        case fromEnvironment of
            Right (RegistryDeploy settings) -> rdProvider settings `shouldBe` ProviderChoice Nothing url (Just "koios.token") Nothing
            other -> expectationFailure ("not parsed: " <> showResult other)
    describe "the directory of the network time" $ do
        let arguments extra = ["registry", "deploy"] <> argumentsOf deployOptions <> extra
            timeOf environment extra = do
                parsed <- parseWith environment (arguments extra)
                pure $ case parsed of
                    Right (RegistryDeploy settings) -> Right (chosenNetworkTime (rdProvider settings))
                    Right _ -> Left "the arguments were taken for another command"
                    Left errors -> Left (show errors)
        it "is none when neither the option nor the variable names one" $
            timeOf [] [] >>= (`shouldBe` Right Nothing)
        it "is the directory the option names, spaced or joined to it" $ do
            timeOf [] ["--network-time", "time-dir"] >>= (`shouldBe` Right (Just "time-dir"))
            timeOf [] ["--network-time=time-dir"] >>= (`shouldBe` Right (Just "time-dir"))
        it "is the directory SINGULAR_NETWORK_TIME names, as public Singular reads it, when no option is given" $
            timeOf [("SINGULAR_NETWORK_TIME", "variable-dir")] [] >>= (`shouldBe` Right (Just "variable-dir"))
        it "is the option's directory when the variable names another: the option first" $
            timeOf [("SINGULAR_NETWORK_TIME", "variable-dir")] ["--network-time", "option-dir"] >>= (`shouldBe` Right (Just "option-dir"))
        it "is refused when the option is given an empty value, even beside a variable that names a directory" $ do
            refused <- timeOf [("SINGULAR_NETWORK_TIME", "variable-dir")] ["--network-time", ""]
            refused `shouldSatisfy` either ("needs a nonempty value" `isInfixOf`) (const False)
        it "is refused when the variable is empty and no option is given" $ do
            refused <- timeOf [("SINGULAR_NETWORK_TIME", "")] []
            refused `shouldSatisfy` either ("needs a nonempty value" `isInfixOf`) (const False)
    it "takes the terms from the environment and the rest from options" $ do
        let environment =
                [ ("CKERI_REGISTRATION_COST", "1000001")
                , ("CKERI_MINIMUM_TIP", "500002")
                , ("CKERI_PROCESS_TIME", "90003")
                , ("CKERI_BOOKING_WIDTH", "5004")
                , ("CKERI_DEPOSIT", "1000000005")
                , ("CKERI_FREEZE_BOND", "5000006")
                , ("CKERI_PREMIUM", "2000007")
                , ("CKERI_MINIMUM_ADA", "2000008")
                , ("CKERI_TERMINATION_CARRIER", "1500009")
                ]
            others = [o | o@(name, _) <- deployOptions, name `notElem` termOptions]
        result <- parseWith environment (["registry", "deploy"] <> argumentsOf others)
        case result of
            Right (RegistryDeploy settings) -> settings `shouldBe` expectedSettings
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "refuses each term that is left out, naming its option: no term has a default" $
        mapM_
            ( \term -> do
                result <-
                    parseWith
                        []
                        ( ["registry", "deploy"]
                            <> argumentsOf [o | o@(name, _) <- deployOptions, name /= term]
                        )
                case result of
                    Left errors -> show errors `shouldSatisfy` (envVarOf term `isInfixOf`)
                    Right _ -> expectationFailure (term <> " was left out and the command was parsed")
            )
            termOptions
    it "offers no option that means a store, a manifest or a token by value" $
        mapM_
            ( \(name, value) -> do
                unrecognisedArgs (["registry", "deploy"] <> argumentsOf deployOptions <> [name, value])
                    >>= (`shouldBe` [name, value])
            )
            [("--store", "store"), ("--manifest", "manifest.json"), ("--koios-token", "token"), ("--cardano-cli", "cli")]
    it "offers the registry group and nothing else new at the top: the group alone is recognised, other spellings are not" $ do
        unrecognisedCmds ["registry"] >>= (`shouldBe` [])
        unrecognisedCmds ["registry-deploy"] >>= (`shouldBe` ["registry-deploy"])
        unrecognisedCmds ["registry", "no-such-verb"] >>= (`shouldBe` ["no-such-verb"])
        unrecognisedCmds ["deploy-registry"] >>= (`shouldBe` ["deploy-registry"])
    it "keeps the first deployment's deploy as it was: its options, and none of the registry's terms" $ do
        unrecognisedCmds ["deploy"] >>= (`shouldBe` [])
        unrecognisedArgs (firstDeploy <> ["--deposit", "1"]) >>= (`shouldBe` ["--deposit", "1"])
        unrecognisedArgs firstDeploy >>= (`shouldBe` [])
  where
    firstDeploy =
        ["deploy", "--blueprint", "b", "--node-socket", "n", "--funding-address", "a", "--signing-key-file", "k", "--store", "s"]
    envVarOf term = "CKERI_" <> map (\c -> if c == '-' then '_' else toUpper c) (drop 2 term)
    showResult = either show (const "parsed to another command")

parseWith :: [(String, String)] -> [String] -> IO (Either (NonEmpty ParseError) Instructions)
parseWith environment args =
    runParserOn
        allCapabilities
        Nothing
        (Opt.settingsParser :: Opt.Parser Instructions)
        (parseArgs args)
        (EnvMap.parse environment)
        Nothing

unrecognisedArgs :: [String] -> IO [String]
unrecognisedArgs args = do
    result <- parseWith [] args
    pure $ either options (const []) result
  where
    options errors =
        concat
            [ NE.toList names
            | ParseError{parseErrorMessage = ParseErrorUnrecognised names} <- NE.toList errors
            ]

unrecognisedCmds :: [String] -> IO [String]
unrecognisedCmds args = do
    result <- parseWith [] args
    pure $ either names (const []) result
  where
    names errors =
        [ name
        | ParseError{parseErrorMessage = ParseErrorUnrecognisedCommand name _} <- NE.toList errors
        ]
