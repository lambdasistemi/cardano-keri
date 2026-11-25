{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.CLI.RegistryBookingGroupSpec
Description : @ckeri registry register@, @fold@ and @return@ take their files and the node, and no registry term

The production 'Instructions' parser is run with no environment and no
configuration file, unless the example says otherwise. Each command is parsed to
the settings it names, each option to its own field; an input left out is
refused by the name of its environment variable; the options that would mean a
store, a manifest, a provider or a registry term are not offered; and the group
keeps its deploy command and its spelling.
-}
module Cardano.KERI.CLI.RegistryBookingGroupSpec (spec) where

import Cardano.KERI.CLI (Instructions (..))
import Cardano.KERI.Deployment.RegistryBookingCommand (
    RegistryFoldSettings (..),
    RegistryRegisterSettings (..),
    RegistryReturnSettings (..),
 )
import Cardano.KERI.Deployment.RegistryProvider (ProviderChoice (..))
import Control.Monad (forM_, unless)
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

nodeOptions :: [(String, String)]
nodeOptions =
    [ ("--network-magic", "42")
    , ("--blueprint", "plutus.json")
    , ("--node-socket", "node.socket")
    , ("--funding-address", "addr_test1qexample")
    , ("--signing-key-file", "payment.skey")
    , ("--timeout-seconds", "77")
    , ("--release-identity", "identity.json")
    , ("--reference-record", "references.json")
    , ("--kli-export", "export.cesr")
    ]

registerOptions :: [(String, String)]
registerOptions = nodeOptions <> [("--request-deposit", "1009000005")]

foldOptions :: [(String, String)]
foldOptions =
    nodeOptions
        <> [ ("--request", "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899#3")
           , ("--snapshot", "snapshot.json")
           , ("--snapshot-out", "next-snapshot.json")
           ]

registerSettings :: RegistryRegisterSettings
registerSettings =
    RegistryRegisterSettings
        { rgNetworkMagic = 42
        , rgBlueprint = "plutus.json"
        , rgProvider = ProviderChoice (Just "node.socket") Nothing Nothing Nothing
        , rgFundingAddress = "addr_test1qexample"
        , rgSigningKeyFile = Just "payment.skey"
        , rgVault = Nothing
        , rgPassphraseFd = Nothing
        , rgTimeoutSeconds = 77
        , rgReleaseIdentity = "identity.json"
        , rgReferenceRecord = "references.json"
        , rgKliExport = "export.cesr"
        , rgDeposit = Just 1_009_000_005
        }

foldSettings :: RegistryFoldSettings
foldSettings =
    RegistryFoldSettings
        { rfNetworkMagic = 42
        , rfBlueprint = "plutus.json"
        , rfProvider = ProviderChoice (Just "node.socket") Nothing Nothing Nothing
        , rfFundingAddress = "addr_test1qexample"
        , rfSigningKeyFile = Just "payment.skey"
        , rfVault = Nothing
        , rfPassphraseFd = Nothing
        , rfTimeoutSeconds = 77
        , rfReleaseIdentity = "identity.json"
        , rfReferenceRecord = "references.json"
        , rfKliExport = "export.cesr"
        , rfRequest = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899#3"
        , rfSnapshot = "snapshot.json"
        , rfSnapshotOut = Just "next-snapshot.json"
        }

returnOptions :: [(String, String)]
returnOptions =
    [ ("--network-magic", "42")
    , ("--blueprint", "plutus.json")
    , ("--node-socket", "node.socket")
    , ("--funding-address", "addr_test1qexample")
    , ("--signing-key-file", "payment.skey")
    , ("--timeout-seconds", "77")
    , ("--release-identity", "identity.json")
    , ("--reference-record", "references.json")
    , ("--request", "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899#3")
    ]

returnSettings :: RegistryReturnSettings
returnSettings =
    RegistryReturnSettings
        { rnNetworkMagic = 42
        , rnBlueprint = "plutus.json"
        , rnProvider = ProviderChoice (Just "node.socket") Nothing Nothing Nothing
        , rnFundingAddress = "addr_test1qexample"
        , rnSigningKeyFile = Just "payment.skey"
        , rnVault = Nothing
        , rnPassphraseFd = Nothing
        , rnTimeoutSeconds = 77
        , rnReleaseIdentity = "identity.json"
        , rnReferenceRecord = "references.json"
        , rnRequest = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899#3"
        }

-- | The options a return cannot run without.
requiredReturn :: [String]
requiredReturn =
    ["--blueprint", "--funding-address", "--release-identity", "--reference-record", "--request"]

argumentsOf :: [(String, String)] -> [String]
argumentsOf options = concat [[name, value] | (name, value) <- options]

-- | The options a command cannot run without.
requiredRegister, requiredFold :: [String]
requiredRegister =
    ["--blueprint", "--funding-address", "--release-identity", "--reference-record", "--kli-export"]
requiredFold = requiredRegister <> ["--request", "--snapshot"]

spec :: Spec
spec = describe "#351 ckeri registry register and ckeri registry fold: the command surface" $ do
    it "takes the provider from options or environment: a node socket, or a Koios URL with an optional token file, as given and not yet checked" $ do
        let without names options = [o | o@(name, _) <- options, name `notElem` names]
            koiosOptions = [("--koios-url", "https://koios.example/api/v1"), ("--koios-token-file", "koios.token")]
            chosen a b c = ProviderChoice a b c Nothing
            url = Just "https://koios.example/api/v1"
        forM_
            [ ("only a Koios URL", without ["--node-socket"] nodeOptions <> take 1 koiosOptions, chosen Nothing url Nothing)
            , ("a Koios URL and a token file", without ["--node-socket"] nodeOptions <> koiosOptions, chosen Nothing url (Just "koios.token"))
            , ("both a node socket and a Koios URL", nodeOptions <> take 1 koiosOptions, chosen (Just "node.socket") url Nothing)
            , ("neither", without ["--node-socket"] nodeOptions, chosen Nothing Nothing Nothing)
            ]
            $ \(label, options, expected) -> do
                registered <- parseWith [] (["registry", "register"] <> argumentsOf (without [] options <> [("--request-deposit", "1009000005")]))
                case registered of
                    Right (RegistryRegister settings) -> (label, rgProvider settings) `shouldBe` (label, expected)
                    other -> expectationFailure (label <> ": not parsed: " <> showResult other)
                returned <- parseWith [] (["registry", "return"] <> argumentsOf (without ["--kli-export"] options <> [("--request", "aa#0")]))
                case returned of
                    Right (RegistryReturn settings) -> (label, rnProvider settings) `shouldBe` (label, expected)
                    other -> expectationFailure (label <> ": not parsed: " <> showResult other)
                folded <- parseWith [] (["registry", "fold"] <> argumentsOf (options <> [("--request", "aa#0"), ("--snapshot", "s.json")]))
                case folded of
                    Right (RegistryFold settings) -> (label, rfProvider settings) `shouldBe` (label, expected)
                    other -> expectationFailure (label <> ": not parsed: " <> showResult other)
        fromEnvironment <-
            parseWith
                [("CKERI_KOIOS_URL", "https://koios.example/api/v1"), ("CKERI_KOIOS_TOKEN_FILE", "koios.token")]
                (["registry", "return"] <> argumentsOf (without ["--node-socket"] returnOptions))
        case fromEnvironment of
            Right (RegistryReturn settings) -> rnProvider settings `shouldBe` chosen Nothing url (Just "koios.token")
            other -> expectationFailure ("not parsed: " <> showResult other)
    forM_ [("register", ["registry", "register"] <> argumentsOf registerOptions), ("return", ["registry", "return"] <> argumentsOf returnOptions)] $ \(name, command) ->
        describe ("the directory of the network time of registry " <> name) $ do
            let timeOf environment extra = do
                    parsed <- parseWith environment (command <> extra)
                    pure $ case parsed of
                        Right (RegistryRegister settings) -> Right (chosenNetworkTime (rgProvider settings))
                        Right (RegistryReturn settings) -> Right (chosenNetworkTime (rnProvider settings))
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
            it "is refused when the option is given an empty value, or the variable is empty and no option is given" $ do
                emptyOption <- timeOf [("SINGULAR_NETWORK_TIME", "variable-dir")] ["--network-time", ""]
                emptyOption `shouldSatisfy` either ("needs a nonempty value" `isInfixOf`) (const False)
                emptyVariable <- timeOf [("SINGULAR_NETWORK_TIME", "")] []
                emptyVariable `shouldSatisfy` either ("needs a nonempty value" `isInfixOf`) (const False)
    describe "registry fold, which reads no network time" $ do
        let command = ["registry", "fold"] <> argumentsOf foldOptions
            timeOf environment extra = do
                parsed <- parseWith environment (command <> extra)
                pure $ case parsed of
                    Right (RegistryFold settings) -> Right (chosenNetworkTime (rfProvider settings))
                    Right _ -> Left "the arguments were taken for another command"
                    Left errors -> Left (show errors)
        it "runs as before beside an empty SINGULAR_NETWORK_TIME: the variable is not read" $
            timeOf [("SINGULAR_NETWORK_TIME", "")] [] >>= (`shouldBe` Right Nothing)
        it "takes no directory from SINGULAR_NETWORK_TIME" $
            timeOf [("SINGULAR_NETWORK_TIME", "variable-dir")] [] >>= (`shouldBe` Right Nothing)
        it "does not know the option: it is not recognised, as before" $
            timeOf [] ["--network-time", "time-dir"] >>= (`shouldSatisfy` either ("--network-time" `isInfixOf`) (const False))
    it "parses every option of register to its own setting" $ do
        result <- parseWith [] (["registry", "register"] <> argumentsOf registerOptions)
        case result of
            Right (RegistryRegister settings) -> settings `shouldBe` registerSettings
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "parses every option of fold to its own setting" $ do
        result <- parseWith [] (["registry", "fold"] <> argumentsOf foldOptions)
        case result of
            Right (RegistryFold settings) -> settings `shouldBe` foldSettings
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "leaves the optional settings out: the request deposit, the next snapshot, the network magic and the timeout take their defaults" $ do
        let without names = [o | o@(name, _) <- nodeOptions, name `notElem` names]
        registered <- parseWith [] (["registry", "register"] <> argumentsOf (without ["--network-magic", "--timeout-seconds"]))
        case registered of
            Right (RegistryRegister settings) -> do
                rgDeposit settings `shouldBe` Nothing
                rgNetworkMagic settings `shouldBe` 1
                rgTimeoutSeconds settings `shouldBe` 600
            other -> expectationFailure ("not parsed: " <> showResult other)
        folded <-
            parseWith
                []
                ( ["registry", "fold"]
                    <> argumentsOf (without [] <> [("--request", "aa#0"), ("--snapshot", "s.json")])
                )
        case folded of
            Right (RegistryFold settings) -> rfSnapshotOut settings `shouldBe` Nothing
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "takes every input from the environment as well as from options" $ do
        let environment = [("CKERI_" <> envName name, value) | (name, value) <- foldOptions]
        result <- parseWith environment ["registry", "fold"]
        case result of
            Right (RegistryFold settings) -> settings `shouldBe` foldSettings
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "refuses each input that is left out, naming its environment variable" $ do
        mapM_
            ( \option -> do
                result <-
                    parseWith [] (["registry", "register"] <> argumentsOf [o | o@(name, _) <- registerOptions, name /= option])
                case result of
                    Left errors -> show errors `shouldSatisfy` (("CKERI_" <> envName option) `isInfixOf`)
                    Right _ -> expectationFailure (option <> " was left out of register and it was parsed")
            )
            requiredRegister
        mapM_
            ( \option -> do
                result <-
                    parseWith [] (["registry", "fold"] <> argumentsOf [o | o@(name, _) <- foldOptions, name /= option])
                case result of
                    Left errors -> show errors `shouldSatisfy` (("CKERI_" <> envName option) `isInfixOf`)
                    Right _ -> expectationFailure (option <> " was left out of fold and it was parsed")
            )
            requiredFold
    it "offers no option that means a store, a manifest, a token by value or a registry term" $
        mapM_
            ( \command ->
                mapM_
                    ( \(name, value) ->
                        unrecognisedArgs (["registry", command] <> argumentsOf (optionsOf command) <> [name, value])
                            >>= (`shouldBe` [name, value])
                    )
                    [ ("--store", "store")
                    , ("--manifest", "manifest.json")
                    , ("--koios-token", "token")
                    , ("--cardano-cli", "cli")
                    , ("--booking-width", "5000")
                    , ("--process-time", "90000")
                    , ("--registration-cost", "1000000")
                    , ("--premium", "2000000")
                    ]
            )
            ["register", "fold"]
    it "offers a deposit to the request of register only, and a snapshot to fold only" $ do
        unrecognisedArgs (["registry", "fold"] <> argumentsOf foldOptions <> ["--request-deposit", "1"])
            >>= (`shouldBe` ["--request-deposit", "1"])
        unrecognisedArgs (["registry", "register"] <> argumentsOf registerOptions <> ["--snapshot", "s.json"])
            >>= (`shouldBe` ["--snapshot", "s.json"])
    it "parses every option of return to its own setting" $ do
        result <- parseWith [] (["registry", "return"] <> argumentsOf returnOptions)
        case result of
            Right (RegistryReturn settings) -> settings `shouldBe` returnSettings
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "takes the inputs of return from the environment, and leaves the network magic and the timeout their defaults" $ do
        let environment = [("CKERI_" <> envName name, value) | (name, value) <- returnOptions]
        fromEnvironment <- parseWith environment ["registry", "return"]
        case fromEnvironment of
            Right (RegistryReturn settings) -> settings `shouldBe` returnSettings
            other -> expectationFailure ("not parsed: " <> showResult other)
        defaults <- parseWith [] (["registry", "return"] <> argumentsOf [o | o@(name, _) <- returnOptions, name `notElem` ["--network-magic", "--timeout-seconds"]])
        case defaults of
            Right (RegistryReturn settings) -> (rnNetworkMagic settings, rnTimeoutSeconds settings) `shouldBe` (1, 600)
            other -> expectationFailure ("not parsed: " <> showResult other)
    it "refuses each input of return that is left out, naming its environment variable" $
        mapM_
            ( \option -> do
                result <- parseWith [] (["registry", "return"] <> argumentsOf [o | o@(name, _) <- returnOptions, name /= option])
                case result of
                    Left errors -> show errors `shouldSatisfy` (("CKERI_" <> envName option) `isInfixOf`)
                    Right _ -> expectationFailure (option <> " was left out of return and it was parsed")
            )
            requiredReturn
    it "offers return nothing that names the refund, the tip, the amounts, a key export, a snapshot, a store or a registry term: the request holds them" $
        mapM_
            ( \(name, value) ->
                unrecognisedArgs (["registry", "return"] <> argumentsOf returnOptions <> [name, value])
                    >>= (`shouldBe` [name, value])
            )
            [ ("--refund-address", "addr_test1qrefund")
            , ("--refund-lovelace", "1")
            , ("--tip", "1")
            , ("--kli-export", "export.cesr")
            , ("--snapshot", "snapshot.json")
            , ("--request-deposit", "1")
            , ("--store", "store")
            , ("--manifest", "manifest.json")
            , ("--booking-width", "5000")
            , ("--process-time", "90000")
            ]
    it "keeps the group to its four commands" $
        unrecognisedCmds ["registry", "return"] >>= (`shouldBe` [])
    it "keeps the group deploy, register and fold, and the spelling the group gives" $ do
        unrecognisedCmds ["registry", "deploy"] >>= (`shouldBe` [])
        unrecognisedCmds ["registry", "register"] >>= (`shouldBe` [])
        unrecognisedCmds ["registry", "fold"] >>= (`shouldBe` [])
        unrecognisedCmds ["register-registry"] >>= (`shouldBe` ["register-registry"])
        unrecognisedCmds ["registry", "book"] >>= (`shouldBe` ["book"])
    it "keeps the first deployment's register and the verbs it has as they were: it parses with its own options, and offers none of the new ones" $ do
        unrecognisedCmds ["register"] >>= (`shouldBe` [])
        firstParsed <- parseWith [] firstRegister
        case firstParsed of
            Right (Register _) -> pure ()
            other -> expectationFailure ("the first deployment's register is not parsed: " <> showResult other)
        unrecognisedArgs (firstRegister <> ["--snapshot", "s.json"]) >>= (`shouldBe` ["--snapshot", "s.json"])
        unrecognisedArgs (firstRegister <> ["--kli-export", "e.cesr"]) >>= (`shouldBe` ["--kli-export", "e.cesr"])
  where
    optionsOf command = if command == "register" then registerOptions else foldOptions
    firstRegister =
        ["register", "--kel", "k.cesr", "--payer", "payer.skey", "--node-socket", "n", "--funding-address", "a", "--store", "s"]
    envName option = map (\c -> if c == '-' then '_' else toUpper c) (drop 2 option)
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

{- | The options the parser did not recognise. Any other parse error fails the
example: an invocation that is wrong for another reason proves nothing.
-}
unrecognisedArgs :: [String] -> IO [String]
unrecognisedArgs args = do
    result <- parseWith [] args
    case result of
        Right _ -> pure []
        Left errors -> do
            let others = [e | e <- NE.toList errors, not (isUnrecognised e)]
            unless (null others) $
                expectationFailure ("the invocation fails for another reason: " <> show others)
            pure
                ( concat
                    [ NE.toList names
                    | ParseError{parseErrorMessage = ParseErrorUnrecognised names} <- NE.toList errors
                    ]
                )
  where
    isUnrecognised ParseError{parseErrorMessage = message} = case message of
        ParseErrorUnrecognised _ -> True
        _ -> False

unrecognisedCmds :: [String] -> IO [String]
unrecognisedCmds args = do
    result <- parseWith [] args
    pure $ either names (const []) result
  where
    names errors =
        [ name
        | ParseError{parseErrorMessage = ParseErrorUnrecognisedCommand name _} <- NE.toList errors
        ]
