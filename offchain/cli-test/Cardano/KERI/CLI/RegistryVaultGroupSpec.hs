{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.CLI.RegistryVaultGroupSpec
Description : The four registry commands take a wallet vault beside the key file

The production 'Instructions' parser is run with no environment and no
configuration file, unless the example says otherwise. Each of @registry deploy@,
@register@, @fold@ and @return@ reads @--vault@ and @--passphrase-fd@ into its settings
beside @--signing-key-file@; which key source is taken is decided when the command
runs, so a settings value may hold both and may hold neither. The descriptor is
given on the command line alone, never by environment variable or configuration file.
-}
module Cardano.KERI.CLI.RegistryVaultGroupSpec (spec) where

import Cardano.KERI.CLI (Instructions (..))
import Cardano.KERI.Deployment.RegistryBookingCommand (
    RegistryFoldSettings (..),
    RegistryRegisterSettings (..),
    RegistryReturnSettings (..),
 )
import Cardano.KERI.Deployment.RegistryCommand (RegistryDeploySettings (..))
import Control.Monad (forM_)
import Data.List.NonEmpty (NonEmpty)
import OptEnvConf qualified as Opt
import OptEnvConf.Args (parseArgs)
import OptEnvConf.Capability (allCapabilities)
import OptEnvConf.EnvMap qualified as EnvMap
import OptEnvConf.Error (ParseError)
import OptEnvConf.Run (runParserOn)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

-- | What a command's settings hold of its key: the key file, the vault and the descriptor.
type KeyFields = (Maybe FilePath, Maybe FilePath, Maybe Int)

data Command = Command
    { commandVerb :: String
    , commandOptions :: [(String, String)]
    -- ^ every option the command needs, none of them a key option
    , commandKey :: Instructions -> Maybe KeyFields
    }

commands :: [Command]
commands =
    [ Command "deploy" (common <> terms) $ \case
        RegistryDeploy s -> Just (rdSigningKeyFile s, rdVault s, rdPassphraseFd s)
        _ -> Nothing
    , Command "register" (common <> files <> [("--kli-export", "export.cesr")]) $ \case
        RegistryRegister s -> Just (rgSigningKeyFile s, rgVault s, rgPassphraseFd s)
        _ -> Nothing
    , Command "fold" (common <> files <> [("--kli-export", "export.cesr"), ("--request", request), ("--snapshot", "snapshot.json")]) $ \case
        RegistryFold s -> Just (rfSigningKeyFile s, rfVault s, rfPassphraseFd s)
        _ -> Nothing
    , Command "return" (common <> files <> [("--request", request)]) $ \case
        RegistryReturn s -> Just (rnSigningKeyFile s, rnVault s, rnPassphraseFd s)
        _ -> Nothing
    ]
  where
    request = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899#3"
    common =
        [ ("--network-magic", "42")
        , ("--blueprint", "plutus.json")
        , ("--node-socket", "node.socket")
        , ("--funding-address", "addr_test1qexample")
        , ("--timeout-seconds", "77")
        ]
    files = [("--release-identity", "identity.json"), ("--reference-record", "references.json")]
    terms =
        [ ("--registration-cost", "1000001")
        , ("--minimum-tip", "500002")
        , ("--process-time", "90003")
        , ("--booking-width", "5004")
        , ("--deposit", "1000000005")
        , ("--freeze-bond", "5000006")
        , ("--premium", "2000007")
        , ("--minimum-ada", "2000008")
        , ("--termination-carrier", "1500009")
        ]

argumentsOf :: [(String, String)] -> [String]
argumentsOf options = concat [[name, value] | (name, value) <- options]

parseWith :: [(String, String)] -> [String] -> IO (Either (NonEmpty ParseError) Instructions)
parseWith environment args =
    runParserOn
        allCapabilities
        Nothing
        (Opt.settingsParser :: Opt.Parser Instructions)
        (parseArgs args)
        (EnvMap.parse environment)
        Nothing

-- | The key fields a command line gives, with the environment given, or the reason it is not parsed.
keyOf :: Command -> [(String, String)] -> [(String, String)] -> IO KeyFields
keyOf command environment keyOptions = do
    result <- parseWith environment (["registry", commandVerb command] <> argumentsOf (commandOptions command <> keyOptions))
    case result of
        Right instructions -> maybe (fail "the arguments were taken for another command") pure (commandKey command instructions)
        Left errors -> fail ("not parsed: " <> show errors)

spec :: Spec
spec = describe "#553 the registry commands take a wallet vault" $
    forM_ commands $ \command -> describe ("registry " <> commandVerb command) $ do
        it "reads --vault and --passphrase-fd into its settings, with no key file" $
            keyOf command [] [("--vault", "wallet.vault"), ("--passphrase-fd", "3")]
                >>= (`shouldBe` (Nothing, Just "wallet.vault", Just 3))
        it "reads --signing-key-file alone as it always did" $
            keyOf command [] [("--signing-key-file", "payment.skey")]
                >>= (`shouldBe` (Just "payment.skey", Nothing, Nothing))
        it "does not decide the key source at parse time: both, or neither, are the settings the command refuses by name" $ do
            keyOf command [] [("--signing-key-file", "payment.skey"), ("--vault", "wallet.vault"), ("--passphrase-fd", "3")]
                >>= (`shouldBe` (Just "payment.skey", Just "wallet.vault", Just 3))
            keyOf command [] [] >>= (`shouldBe` (Nothing, Nothing, Nothing))
        it "sees a key file given by the environment beside a vault given by option as both" $
            keyOf command [("CKERI_SIGNING_KEY_FILE", "payment.skey")] [("--vault", "wallet.vault"), ("--passphrase-fd", "3")]
                >>= (`shouldBe` (Just "payment.skey", Just "wallet.vault", Just 3))
        it "takes the vault from the environment, and the descriptor from no environment variable" $
            keyOf command [("CKERI_VAULT", "wallet.vault"), ("CKERI_PASSPHRASE_FD", "3")] []
                >>= (`shouldBe` (Nothing, Just "wallet.vault", Nothing))
        it "refuses a descriptor that is not a number, where a number is taken" $ do
            keyOf command [] [("--vault", "wallet.vault"), ("--passphrase-fd", "3")]
                >>= (`shouldBe` (Nothing, Just "wallet.vault", Just 3))
            result <- parseWith [] (["registry", commandVerb command] <> argumentsOf (commandOptions command) <> ["--vault", "wallet.vault", "--passphrase-fd", "three"])
            case result of
                Left _ -> pure ()
                Right _ -> expectationFailure "a descriptor that is not a number was parsed"
