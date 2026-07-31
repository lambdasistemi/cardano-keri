{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.FollowerSpec (
    spec,
    baseConfig,
    m1Manifest,
) where

import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    SourceInfo (..),
 )
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
 )
import Cardano.KERI.Indexer.Follower (
    mkChainSyncConfig,
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig (..),
    InterestSet (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address (..),
    BlockHash (..),
    SlotNo (..),
 )
import Codec.Binary.Bech32 (
    dataPartFromBytes,
    encodeLenient,
    humanReadablePartFromText,
 )
import Data.ByteString qualified as BS
import Data.Char (
    isDigit,
 )
import Data.List (
    isInfixOf,
 )
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set qualified as Set
import Data.Text (
    Text,
 )
import Data.Text qualified as Text
import OptEnvConf qualified as Opt
import OptEnvConf.Args qualified as OptArgs
import OptEnvConf.Capability qualified as OptCapability
import OptEnvConf.EnvMap qualified as OptEnv
import OptEnvConf.Run qualified as OptRun
import Ouroboros.Network.Magic (
    NetworkMagic (..),
 )
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "Cardano.KERI.Indexer follower configuration" $ do
        it "assembles exactly checkpoint, plural funding, and board addresses" $ do
            let manifestAddress = taggedAddress 0x44
                fullFundingA = taggedAddress 0x55
                fullFundingB = taggedAddress 0x66
                fullBoard = taggedAddress 0x77
                assembled =
                    mkChainSyncConfig
                        baseConfig
                            { icFundingAddrs = [fullFundingA, fullFundingB]
                            , icBoardAddr = Just fullBoard
                            }
                        (manifestWithAddress $ encodeAddress manifestAddress)
            csInterestSet assembled
                `shouldBe` IndexAddressSet
                    ( Set.fromList
                        [ manifestAddress
                        , fullFundingA
                        , fullFundingB
                        , fullBoard
                        ]
                    )

        it "does not invent optional interest addresses" $ do
            let checkpoint = taggedAddress 0x44
                assembled =
                    mkChainSyncConfig
                        baseConfig
                            { icFundingAddrs = []
                            , icBoardAddr = Nothing
                            }
                        (manifestWithAddress $ encodeAddress checkpoint)
            csInterestSet assembled
                `shouldBe` IndexAddressSet (Set.singleton checkpoint)

        it "wires a non-default configured start point" $ do
            csStartPoint wiringConfigAssembled `shouldBe` wiringStart

        it "wires a non-default configured security parameter" $ do
            csSecurityParamK wiringConfigAssembled `shouldBe` 777

        it "wires the mandatory configured Byron epoch size" $ do
            csByronEpochSlots wiringConfigAssembled `shouldBe` 32_000

        it "wires the configured relay socket" $ do
            csRelaySocket wiringConfigAssembled
                `shouldBe` "/tmp/not-an-upstream-default.socket"

        it "wires the configured network magic" $ do
            csNetworkMagic wiringConfigAssembled
                `shouldBe` NetworkMagic 424_242

        it "installs exactly one upstream handler" $ do
            NonEmpty.length (csHandlers wiringConfigAssembled) `shouldBe` 1

        it "preserves an origin start point" $ do
            csStartPoint
                (mkChainSyncConfig baseConfig{icStartPoint = Nothing} m1Manifest)
                `shouldBe` Nothing

        it "decodes the manifest checkpoint bech32 to canonical raw bytes" $ do
            let expected =
                    Address $
                        hexBytes
                            "700c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
            csInterestSet (mkChainSyncConfig baseConfig m1Manifest)
                `shouldBe` IndexAddressSet (Set.singleton expected)

        it "parses every command-line option including plural funding" $ do
            parsed <-
                parseConfig
                    [ "--node-socket"
                    , "/tmp/argv-node.socket"
                    , "--network-magic"
                    , "314159"
                    , "--byron-epoch-slots"
                    , "21600"
                    , "--security-param-k"
                    , "901"
                    , "--start-slot"
                    , "456789"
                    , "--start-block-hash"
                    , replicate 64 'a'
                    , "--store-path"
                    , "/tmp/argv-indexer"
                    , "--funding-address"
                    , addressString fundingA
                    , "--funding-address"
                    , addressString fundingB
                    , "--board-address"
                    , addressString board
                    ]
                    []
            parsed
                `shouldBe` IndexerConfig
                    { icSocketPath = "/tmp/argv-node.socket"
                    , icNetworkMagic = 314_159
                    , icByronEpochSlots = 21_600
                    , icSecurityParamK = 901
                    , icStartPoint =
                        Just
                            ( SlotNo 456_789
                            , BlockHash (BS.replicate 32 0xAA)
                            )
                    , icStorePath = "/tmp/argv-indexer"
                    , icFundingAddrs = [fundingA, fundingB]
                    , icBoardAddr = Just board
                    }

        it "parses every environment field and leaves board absent" $ do
            parsed <-
                parseConfig
                    []
                    [ ("CKERI_NODE_SOCKET", "/tmp/env-node.socket")
                    , ("CKERI_NETWORK_MAGIC", "271828")
                    , ("CKERI_BYRON_EPOCH_SLOTS", "21601")
                    , ("CKERI_SECURITY_PARAM_K", "902")
                    , ("CKERI_START_SLOT", "567890")
                    , ("CKERI_START_BLOCK_HASH", replicate 64 'b')
                    , ("CKERI_STORE_PATH", "/tmp/env-indexer")
                    ,
                        ( "CKERI_FUNDING_ADDRESSES"
                        , addressString fundingA
                            <> ","
                            <> addressString fundingB
                        )
                    ]
            parsed
                `shouldBe` IndexerConfig
                    { icSocketPath = "/tmp/env-node.socket"
                    , icNetworkMagic = 271_828
                    , icByronEpochSlots = 21_601
                    , icSecurityParamK = 902
                    , icStartPoint =
                        Just
                            ( SlotNo 567_890
                            , BlockHash (BS.replicate 32 0xBB)
                            )
                    , icStorePath = "/tmp/env-indexer"
                    , icFundingAddrs = [fundingA, fundingB]
                    , icBoardAddr = Nothing
                    }

        it "rejects config without the mandatory Byron epoch size" $ do
            -- The two successful parses are positive controls over this same
            -- input. They prove both configured routes are live and attribute
            -- the failure specifically to omitting the Byron epoch size.
            result <-
                OptRun.runParserOn
                    OptCapability.allCapabilities
                    Nothing
                    (Opt.settingsParser :: Opt.Parser IndexerConfig)
                    (OptArgs.parseArgs requiredConfigWithoutByronArgs)
                    (OptEnv.parse requiredConfigWithoutByronEnv)
                    Nothing
            case result of
                Left errors ->
                    show errors
                        `shouldSatisfy` \message ->
                            "byron-epoch-slots" `isInfixOf` message
                                || "CKERI_BYRON_EPOCH_SLOTS" `isInfixOf` message
                Right config ->
                    expectationFailure $
                        "expected missing Byron epoch size to fail, parsed: "
                            <> show config

            fromArgv <-
                parseConfig
                    ( requiredConfigWithoutByronArgs
                        <> ["--byron-epoch-slots", "21600"]
                    )
                    requiredConfigWithoutByronEnv
            icByronEpochSlots fromArgv `shouldBe` 21_600

            fromEnv <-
                parseConfig
                    requiredConfigWithoutByronArgs
                    ( ("CKERI_BYRON_EPOCH_SLOTS", "21601")
                        : requiredConfigWithoutByronEnv
                    )
            icByronEpochSlots fromEnv `shouldBe` 21_601

baseConfig :: IndexerConfig
baseConfig =
    IndexerConfig
        { icSocketPath = "/tmp/base-node.socket"
        , icNetworkMagic = 424_242
        , icByronEpochSlots = 32_000
        , icSecurityParamK = 777
        , icStartPoint = Nothing
        , icStorePath = "/tmp/base-indexer"
        , icFundingAddrs = []
        , icBoardAddr = Nothing
        }

wiringStart :: Maybe (SlotNo, BlockHash)
wiringStart =
    Just
        ( SlotNo 987_654
        , BlockHash (BS.replicate 32 0xAB)
        )

wiringConfigAssembled :: ChainSyncConfig
wiringConfigAssembled =
    mkChainSyncConfig
        baseConfig
            { icSocketPath = "/tmp/not-an-upstream-default.socket"
            , icNetworkMagic = 424_242
            , icSecurityParamK = 777
            , icStartPoint = wiringStart
            }
        m1Manifest

fundingA, fundingB, board :: Address
fundingA = taggedAddress 0x21
fundingB = taggedAddress 0x32
board = taggedAddress 0x43

requiredConfigWithoutByronArgs :: [String]
requiredConfigWithoutByronArgs =
    [ "--network-magic"
    , "314159"
    , "--security-param-k"
    , "901"
    , "--store-path"
    , "/tmp/mandatory-byron-indexer"
    ]

requiredConfigWithoutByronEnv :: [(String, String)]
requiredConfigWithoutByronEnv =
    [("CKERI_NODE_SOCKET", "/tmp/mandatory-byron-node.socket")]

taggedAddress :: Word -> Address
taggedAddress tag =
    Address (BS.cons (fromIntegral tag) $ BS.replicate 28 (fromIntegral tag))

encodeAddress :: Address -> Text
encodeAddress (Address bytes) =
    case humanReadablePartFromText "addr_test" of
        Left err -> error $ "FollowerSpec: invalid test HRP: " <> show err
        Right hrp -> encodeLenient hrp (dataPartFromBytes bytes)

addressString :: Address -> String
addressString = Text.unpack . encodeAddress

m1Manifest :: Manifest
m1Manifest =
    manifestWithAddress
        "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"

manifestWithAddress :: Text -> Manifest
manifestWithAddress address =
    Manifest
        { manifestSchemaVersion = "test-schema"
        , manifestNetwork = NetworkInfo "testnet" 42
        , manifestSource = SourceInfo "test-repository" "test-commit"
        , manifestBlueprint = BlueprintInfo "test-blueprint"
        , manifestParameters =
            DeploymentParameters
                { parameterCheckpointVersion = 1
                , parameterNetworkDiscriminator = 0
                , parameterRegistrationBond = 1
                , parameterFreezeBond = 1
                , parameterFreezeWindow = 1
                }
        , manifestCheckpoint =
            CheckpointInfo
                { checkpointAddressBech32 = address
                , checkpointPolicyId = "test-policy"
                }
        , manifestPublishedAt = "2026-07-29T00:00:00Z"
        , manifestScripts = []
        }

parseConfig ::
    [String] ->
    [(String, String)] ->
    IO IndexerConfig
parseConfig args environment = do
    result <-
        OptRun.runParserOn
            OptCapability.allCapabilities
            Nothing
            (Opt.settingsParser :: Opt.Parser IndexerConfig)
            (OptArgs.parseArgs args)
            (OptEnv.parse environment)
            Nothing
    case result of
        Left errors -> do
            expectationFailure (show errors)
            error "FollowerSpec: unreachable after parser failure"
        Right config -> pure config

hexBytes :: String -> BS.ByteString
hexBytes = BS.pack . go
  where
    go [] = []
    go (high : low : rest) =
        fromIntegral (hexDigit high * 16 + hexDigit low) : go rest
    go _ = error "FollowerSpec: odd-length hex"

    hexDigit character
        | isDigit character =
            fromEnum character - fromEnum '0'
        | character >= 'a' && character <= 'f' =
            fromEnum character - fromEnum 'a' + 10
        | otherwise = error "FollowerSpec: invalid hex digit"
