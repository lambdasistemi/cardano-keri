{-# LANGUAGE ApplicativeDo #-}

{- |
Module      : Cardano.KERI.Indexer.Config
Description : opt-env-conf settings for the KERI follower

Consumes raw address and chain-point types from
'Cardano.Node.Client.UTxOIndexer.Types', decodes addresses with
'Codec.Binary.Bech32', and delegates configuration source precedence and
parsing to 'OptEnvConf'.
-}
module Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
    decodeAddress,
) where

import Cardano.Node.Client.UTxOIndexer.Types (
    Address (..),
    BlockHash (..),
    SlotNo (..),
 )
import Codec.Binary.Bech32 (
    dataPartToBytes,
    decodeLenient,
 )
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.Text qualified as Text
import Data.Word (
    Word32,
    Word64,
 )
import OptEnvConf qualified as Opt

-- | Deployment and storage identity needed by the in-process follower.
data IndexerConfig = IndexerConfig
    { icSocketPath :: !FilePath
    -- ^ Cardano node socket.
    , icNetworkMagic :: !Word32
    , icByronEpochSlots :: !Word64
    -- ^ Byron epoch size required by the node-to-client codec.
    , icSecurityParamK :: !Int
    -- ^ Volatile rollback-window bound.
    , icStartPoint :: !(Maybe (SlotNo, BlockHash))
    -- ^ Deployment point, or origin when absent.
    , icStorePath :: !FilePath
    -- ^ RocksDB directory.
    , icFundingAddrs :: ![Address]
    -- ^ Operator-controlled funding addresses.
    , icBoardAddr :: !(Maybe Address)
    -- ^ Optional endpoint-board address.
    }
    deriving stock (Eq, Show)

instance Opt.HasParser IndexerConfig where
    settingsParser = do
        icSocketPath <-
            stringSetting
                "node-socket"
                "CKERI_NODE_SOCKET"
                "Cardano node socket"
        icNetworkMagic <-
            autoSetting
                "network-magic"
                "CKERI_NETWORK_MAGIC"
                "Cardano network magic"
        icByronEpochSlots <-
            autoSetting
                "byron-epoch-slots"
                "CKERI_BYRON_EPOCH_SLOTS"
                "Byron epoch size for the node-to-client codec"
        icSecurityParamK <-
            autoSetting
                "security-param-k"
                "CKERI_SECURITY_PARAM_K"
                "Cardano security parameter k"
        icStartPoint <-
            Opt.optional $
                (,) . SlotNo
                    <$> autoSetting
                        "start-slot"
                        "CKERI_START_SLOT"
                        "Follower start slot"
                    <*> customSetting
                        blockHashReader
                        "start-block-hash"
                        "CKERI_START_BLOCK_HASH"
                        "Follower start block hash"
        icStorePath <-
            stringSetting
                "store-path"
                "CKERI_STORE_PATH"
                "Indexer store directory"
        icFundingAddrs <- fundingAddressesParser
        icBoardAddr <-
            Opt.optional $
                customSetting
                    addressReader
                    "board-address"
                    "CKERI_BOARD_ADDRESS"
                    "Optional endpoint-board address"
        pure IndexerConfig{..}

fundingAddressesParser :: Opt.Parser [Address]
fundingAddressesParser =
    Opt.some
        ( Opt.setting
            [ Opt.reader addressReader
            , Opt.option
            , Opt.long "funding-address"
            , Opt.metavar "ADDRESS"
            , Opt.help "Funding address (repeat for multiple addresses)"
            ]
        )
        Opt.<|> Opt.setting
            [ Opt.reader (Opt.commaSeparatedList addressReader)
            , Opt.env "CKERI_FUNDING_ADDRESSES"
            , Opt.metavar "ADDRESSES"
            , Opt.help "Comma-separated funding addresses"
            ]
        Opt.<|> pure []

stringSetting :: String -> String -> String -> Opt.Parser String
stringSetting = customSetting Opt.str

autoSetting :: (Read a) => String -> String -> String -> Opt.Parser a
autoSetting = customSetting Opt.auto

customSetting ::
    Opt.Reader a ->
    String ->
    String ->
    String ->
    Opt.Parser a
customSetting valueReader optionName environmentName description =
    Opt.setting
        [ Opt.reader valueReader
        , Opt.option
        , Opt.long optionName
        , Opt.env environmentName
        , Opt.metavar "VALUE"
        , Opt.help description
        ]

addressReader :: Opt.Reader Address
addressReader = Opt.eitherReader (decodeAddress . Text.pack)

-- | Decode the canonical bytes carried by a bech32 Cardano address.
decodeAddress :: Text.Text -> Either String Address
decodeAddress encoded = do
    (_, dataPart) <-
        firstShow "Invalid bech32 address" $
            decodeLenient encoded
    bytes <-
        maybe
            (Left "Invalid bech32 address payload")
            Right
            (dataPartToBytes dataPart)
    pure (Address bytes)

blockHashReader :: Opt.Reader BlockHash
blockHashReader =
    Opt.eitherReader $ \raw -> do
        bytes <-
            firstShow "Invalid hexadecimal block hash" $
                Base16.decode (BS8.pack raw)
        if BS8.length bytes == 32
            then Right (BlockHash bytes)
            else Left "Block hash must contain exactly 32 bytes"

firstShow :: (Show err) => String -> Either err value -> Either String value
firstShow context =
    either (Left . ((context <> ": ") <>) . show) Right
