{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryProvider
Description : The one provider a registry command runs on

A registry command runs on exactly one provider: a node's socket, or a Koios
service (a URL and an optional token file). Both, or neither, is refused by
name before anything is read. This module holds the choice as given, the choice
as resolved, the two openers a command may be run over, and the noun the
reports use for the other end of the chain.
-}
module Cardano.KERI.Deployment.RegistryProvider (
    ProviderChoice (..),
    Provider (..),
    ProviderRefusal (..),
    resolveProvider,
    resolveNodeProvider,
    renderProviderRefusal,
    providerChoiceParser,
    providerChoiceWithoutTimeParser,
    Counterpart (..),
    counterpartOf,
    forCounterpart,
    evidence,
    reasonText,
    KoiosOpener,
    Openers (..),
    nodeOnly,
    withProvider,
    printHandoffReport,
    transliterateReports,
) where

import Cardano.KERI.Deployment.KoiosRegistryRuntime (KoiosAccess (..))
import Cardano.KERI.Deployment.KoiosSubmission (Handoff, renderHandoff)
import Cardano.KERI.Deployment.NodeSocketRuntime (KeySource, NodeAccess (..), RegistryOpener)
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime)
import Cardano.Ledger.Address (Addr)
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.List (isInfixOf, stripPrefix)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error (lenientDecode)
import OptEnvConf qualified as Opt
import System.IO (hFlush, hGetEncoding, hSetEncoding, mkTextEncoding, stderr, stdout)

-- | What the settings name, as given: a node socket, a Koios URL, a token file.
data ProviderChoice = ProviderChoice
    { chosenNodeSocket :: !(Maybe FilePath)
    , chosenKoiosUrl :: !(Maybe Text)
    , chosenKoiosTokenFile :: !(Maybe FilePath)
    , chosenNetworkTime :: !(Maybe FilePath)
    }
    deriving stock (Show, Eq)

-- | The provider a choice resolves to.
data Provider
    = OnNode !FilePath
    | OnKoios !Text !(Maybe FilePath)
    deriving stock (Show, Eq)

-- | Why a choice is not exactly one provider.
data ProviderRefusal
    = BothProviders
    | NoProvider
    | TokenFileWithoutKoios
    | FoldRunsOnTheNodeOnly
    deriving stock (Show, Eq)

{- | Exactly one provider: a node socket alone, or a Koios URL with an optional
token file. A token file needs the URL.
-}
resolveProvider :: ProviderChoice -> Either ProviderRefusal Provider
resolveProvider ProviderChoice{..} = case (chosenNodeSocket, chosenKoiosUrl) of
    (Just _, Just _) -> Left BothProviders
    (Nothing, Nothing) -> Left NoProvider
    (Just socket, Nothing) -> maybe (Right (OnNode socket)) (const (Left TokenFileWithoutKoios)) chosenKoiosTokenFile
    (Nothing, Just url) -> Right (OnKoios url chosenKoiosTokenFile)

-- | The node socket a command that runs on the node only is given; anything that names Koios is refused.
resolveNodeProvider :: ProviderChoice -> Either ProviderRefusal FilePath
resolveNodeProvider ProviderChoice{..} = case (chosenKoiosUrl, chosenKoiosTokenFile) of
    (Nothing, Nothing) -> maybe (Left NoProvider) Right chosenNodeSocket
    _ -> Left FoldRunsOnTheNodeOnly

-- | The refusal, beginning with its name.
renderProviderRefusal :: ProviderRefusal -> String
renderProviderRefusal = \case
    BothProviders -> "provider-both-given: give --koios-url (with an optional --koios-token-file) or --node-socket, not both"
    NoProvider -> "provider-none-given: give --koios-url (with an optional --koios-token-file) or --node-socket"
    TokenFileWithoutKoios -> "koios-token-file-without-koios-url: --koios-token-file goes with --koios-url"
    FoldRunsOnTheNodeOnly -> "fold-runs-on-the-node-only: registry fold runs on the node socket only; give --node-socket and no Koios option"

-- | A directory that is named: an empty value is refused, as public Singular refuses it.
nonEmptyDirectory :: String -> Either String FilePath
nonEmptyDirectory "" = Left "--network-time needs a nonempty value"
nonEmptyDirectory directory = Right directory

{- | The provider options of a command that reads no network time: the node socket, or a Koios URL with its token
file. The fold is one; its settings hold no directory of the network time, and neither its help nor its environment
mention one.
-}
providerChoiceWithoutTimeParser :: Opt.Parser ProviderChoice
providerChoiceWithoutTimeParser = do
    chosenNodeSocket <-
        Opt.optional $
            Opt.setting
                [ Opt.reader Opt.str
                , Opt.option
                , Opt.long "node-socket"
                , Opt.env "CKERI_NODE_SOCKET"
                , Opt.conf "node-socket"
                , Opt.metavar "VALUE"
                , Opt.help "Cardano node socket (give this or --koios-url, not both)"
                ]
    chosenKoiosUrl <-
        Opt.optional $
            Opt.setting
                [ Opt.reader (T.pack <$> Opt.str)
                , Opt.option
                , Opt.long "koios-url"
                , Opt.env "CKERI_KOIOS_URL"
                , Opt.conf "koios-url"
                , Opt.metavar "URL"
                , Opt.help "Koios API base URL (give this or --node-socket, not both; registry fold runs on the node socket only)"
                ]
    chosenKoiosTokenFile <-
        Opt.optional $
            Opt.setting
                [ Opt.reader Opt.str
                , Opt.option
                , Opt.long "koios-token-file"
                , Opt.env "CKERI_KOIOS_TOKEN_FILE"
                , Opt.conf "koios-token-file"
                , Opt.metavar "FILE"
                , Opt.help "File holding the Koios bearer token, read by the transport (with --koios-url)"
                ]
    let chosenNetworkTime = Nothing
    pure ProviderChoice{..}

{- | The provider options of a command that reads a network time: those of 'providerChoiceWithoutTimeParser' and the directory
of the network time, as public Singular selects it.
-}
providerChoiceParser :: Opt.Parser ProviderChoice
providerChoiceParser = do
    choice <- providerChoiceWithoutTimeParser
    chosenNetworkTime <-
        Opt.optional $
            Opt.setting
                [ Opt.reader (Opt.eitherReader nonEmptyDirectory)
                , Opt.option
                , Opt.long "network-time"
                , Opt.env "SINGULAR_NETWORK_TIME"
                , Opt.metavar "DIR"
                , Opt.help "Directory of the network time, as public Singular reads it (the option first, then the variable; preprod's pinned package without either); read by registry deploy and by the commands on Koios"
                ]
    pure choice{chosenNetworkTime}

-- | What a report calls the other end of the chain.
data Counterpart = TheNode | TheProvider
    deriving stock (Show, Eq)

counterpartOf :: Provider -> Counterpart
counterpartOf = \case
    OnNode _ -> TheNode
    OnKoios _ _ -> TheProvider

{- | A report line as it reads for the other end: the node's words, with the provider named
where the node was, the local evaluation where the node's evaluation was, and the provider
where the ledger refused a submission. What the provider said (marked by 'evidence') is kept
word for word, and the marks are taken off.
-}
forCounterpart :: Counterpart -> String -> String
forCounterpart counterpart = outside
  where
    outside [] = []
    outside ('\xE000' : rest) = inside rest
    outside line@(c : rest)
        | TheProvider <- counterpart
        , Just after <- stripPrefix "the node's evaluation" line =
            "the local evaluation" <> outside after
        | TheProvider <- counterpart
        , Just after <- stripPrefix "refused by the ledger" line =
            "refused by the provider" <> outside after
        | TheProvider <- counterpart
        , Just after <- stripPrefix "the node" line =
            "the provider" <> outside after
        | otherwise = c : outside rest
    -- what was marked: a mark inside it is doubled, so only a single closing mark ends it
    inside [] = []
    inside ('\xE001' : '\xE001' : rest) = '\xE001' : inside rest
    inside ('\xE000' : '\xE000' : rest) = '\xE000' : inside rest
    inside ('\xE001' : rest) = outside rest
    inside (c : rest) = c : inside rest

{- | Text the provider or the chain supplied, which a report quotes: it is not changed when the
report is worded for the other end.
-}
evidence :: String -> String
evidence text = "\xE000" <> concatMap doubled text <> "\xE001"
  where
    doubled c
        | c == '\xE000' || c == '\xE001' = [c, c]
        | otherwise = [c]

-- | The words of a refusal the provider or the node gave as bytes: text in UTF-8, as the submission result says.
reasonText :: ByteString -> String
reasonText = T.unpack . TE.decodeUtf8With lenientDecode

{- | Make what the command prints unable to fail on a character the terminal's encoding lacks: it is
written as the nearest the encoding has. A report that failed to be written would otherwise hide what the
command knew, the identifier of a transaction and the refusal that came with it.
-}
transliterateReports :: IO ()
transliterateReports = forM_ [stdout, stderr] $ \handle ->
    hGetEncoding handle >>= \case
        Just encoding | not ("//" `isInfixOf` show encoding) -> mkTextEncoding (show encoding <> "//TRANSLIT") >>= hSetEncoding handle
        _ -> pure ()

-- | How a command reaches Koios: the runtime and the paying address.
type KoiosOpener = KoiosAccess -> ((RegistryRuntime, Addr) -> IO ()) -> IO ()

-- | The two ways a command may be opened; it uses the one its settings choose.
data Openers = Openers
    { openersNode :: RegistryOpener
    , openersKoios :: KoiosOpener
    }

-- | Openers of which only the node's is meant to be reached.
nodeOnly :: RegistryOpener -> Openers
nodeOnly open = Openers{openersNode = open, openersKoios = \_ _ -> fail "no Koios opener was given"}

-- | Open the provider chosen, with what every command is given besides it.
withProvider ::
    Openers ->
    Provider ->
    Maybe FilePath ->
    Int ->
    Text ->
    KeySource ->
    Int ->
    ((RegistryRuntime, Addr) -> IO ()) ->
    IO ()
withProvider openers provider time magic funding key timeout use = case provider of
    OnNode socket -> openersNode openers (NodeAccess magic socket funding key timeout time) use
    OnKoios url token ->
        openersKoios
            openers
            KoiosAccess
                { koiosUrl = url
                , koiosTokenFile = token
                , koiosNetworkMagic = magic
                , koiosFundingAddress = funding
                , koiosSigningKey = key
                , koiosNetworkTime = time
                }
            use

{- | What a handoff came to, and what its attempt count is: printed, flushed,
as the handoff ends, whatever it came to.
-}
printHandoffReport :: Handoff -> IO ()
printHandoffReport handoff = do
    putStrLn ("provider-handoff: " <> T.unpack (renderHandoff handoff))
    putStrLn
        "provider-handoff-limits: the attempt count is the transport's; a redirect the provider answers is followed inside one attempt and is not detected (https://github.com/lambdasistemi/singular/issues/819)"
    hFlush stdout
