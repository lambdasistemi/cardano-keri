{- |
Module      : Cardano.KERI.Indexer.Shell
Description : Interactive local-store query prompt over one live follower

Consumes 'Cardano.KERI.Indexer.Reads.CheckpointView' and
'Cardano.Node.Client.UTxOIndexer.Follower.FollowerHandle' to build a
'QueryAction' that performs fresh local-store/readiness IO on every
invocation, parses/dispatches the fixed verb set, and drives a Haskeline
prompt over it. Verb-name completion, self-addressing (E-code) AID decoding,
and address decoding reuse 'Cardano.KERI.AID.CESR' and
'Cardano.KERI.Indexer.Config.decodeAddress'.
-}
module Cardano.KERI.Indexer.Shell (
    QueryAction (..),
    StatusView (..),
    Command (..),
    parseCommand,
    handleLine,
    renderStatus,
    renderCheckpoints,
    renderCheckpoint,
    renderPayer,
    helpText,
    verbNames,
    completeVerbs,
    progressLine,
    localQueryAction,
    runShell,
) where

import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.Indexer.Codecs (
    CheckpointDecodeError,
    CheckpointRecord (..),
 )
import Cardano.KERI.Indexer.Config (
    decodeAddress,
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
    checkpointForAid,
    liveCheckpointsWithRejects,
    payerUtxos,
    storePoint,
 )
import Cardano.Node.Client.N2C.Reconnect (
    DisconnectInfo (..),
    UpstreamStatus (..),
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    FollowerHandle (..),
    Readiness (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
    BlockHash (..),
    SlotNo (..),
    TxIn,
    TxOut,
 )
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async qualified as Async
import Control.Concurrent.STM (atomically)
import Control.Monad (forever)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.Char (isSpace)
import Data.List (intercalate, isPrefixOf)
import Data.Text qualified as Text
import System.Console.Haskeline qualified as Haskeline

-- | Everything one prompt sample needs to know about follower progress.
data StatusView = StatusView
    { svReadiness :: !Readiness
    , svStorePoint :: !(Maybe (SlotNo, BlockHash))
    }
    deriving stock (Show)

{- | The local-query seam: every field performs fresh IO on every call. No
field may close over a cached/memoized value. #177 will substitute a
different implementation of this same record; #188 only constructs
'localQueryAction'.
-}
data QueryAction = QueryAction
    { qaStatus :: IO StatusView
    , qaList :: IO ([CheckpointRecord], [(TxIn, CheckpointDecodeError)])
    , qaCheckpoint :: ByteString -> IO (Maybe CheckpointRecord)
    , qaPayer :: Address -> IO [(TxIn, TxOut)]
    }

-- | One fully parsed prompt command.
data Command
    = CmdStatus
    | CmdList
    | CmdCheckpoint !ByteString
    | CmdPayer !Address
    | CmdHelp
    | CmdQuit
    deriving stock (Eq, Show)

verbNames :: [String]
verbNames = ["status", "list", "checkpoint", "payer", "help", "quit"]

helpText :: String
helpText =
    "verbs: "
        <> intercalate ", " verbNames
        <> " -- checkpoint <AID> (44-char E-code), payer <ADDRESS> (bech32)"

-- | Prefix-filter completion candidates for verb names.
completeVerbs :: String -> [String]
completeVerbs prefix = filter (prefix `isPrefixOf`) verbNames

-- | Parse one raw prompt line into a 'Command'. Never performs IO.
parseCommand :: String -> Either String Command
parseCommand raw = case words raw of
    [] -> Left "no command given"
    ["status"] -> Right CmdStatus
    ["list"] -> Right CmdList
    ["help"] -> Right CmdHelp
    ["quit"] -> Right CmdQuit
    ["checkpoint", aidText] -> CmdCheckpoint <$> parseAid aidText
    ["payer", addressText] -> CmdPayer <$> parseAddress addressText
    (verb : _)
        | verb `elem` ["status", "list", "help", "quit"] ->
            Left (verb <> ": takes no arguments")
        | verb `elem` ["checkpoint", "payer"] ->
            Left (verb <> ": expected exactly one argument")
        | otherwise ->
            Left ("unknown verb: " <> verb)

parseAid :: String -> Either String ByteString
parseAid text
    | length text /= 44 =
        Left "checkpoint: AID must be a 44-character E-code identifier"
    | otherwise = case parsePrimitive (BS8.pack text) of
        Right (SelfAddressing raw, rest) | BS8.null rest -> Right raw
        _ -> Left "checkpoint: AID must be a valid E-code (self-addressing) identifier"

parseAddress :: String -> Either String Address
parseAddress text = case decodeAddress (Text.pack text) of
    Left err -> Left ("payer: " <> err)
    Right address -> Right address

{- | Dispatch one non-blank line: 'Nothing' signals a clean quit; 'Just'
carries the text to print. Every branch re-invokes the supplied
'QueryAction' field; nothing here may retain a previous answer.
-}
handleLine :: QueryAction -> String -> IO (Maybe String)
handleLine qa raw = case parseCommand raw of
    Left err -> pure (Just err)
    Right CmdQuit -> pure Nothing
    Right CmdHelp -> pure (Just helpText)
    Right CmdStatus -> Just . renderStatus <$> qaStatus qa
    Right CmdList -> Just . renderCheckpoints <$> qaList qa
    Right (CmdCheckpoint aid) -> Just . renderCheckpoint <$> qaCheckpoint qa aid
    Right (CmdPayer address) -> Just . renderPayer <$> qaPayer qa address

renderStatus :: StatusView -> String
renderStatus (StatusView readiness point) =
    unwords
        [ "processed=" <> maybe "none" showSlot (rProcessedSlot readiness)
        , "tip=" <> maybe "none" showSlot (rTipSlot readiness)
        , "lag=" <> showLag
        , "upstream=" <> showUpstream (rUpstream readiness)
        , "store=" <> showPoint point
        ]
  where
    showSlot (SlotNo slot) = show slot
    showPoint Nothing = "none"
    showPoint (Just (SlotNo slot, BlockHash hash)) = show slot <> "/" <> hexOf hash
    showLag = case (rProcessedSlot readiness, rTipSlot readiness) of
        (Just (SlotNo p), Just (SlotNo t)) -> show (if t >= p then t - p else 0)
        _ -> "unknown"
    showUpstream UpstreamConnected = "connected"
    showUpstream (UpstreamDisconnected info) =
        "disconnected("
            <> Text.unpack (diReason info)
            <> " attempt="
            <> show (diAttempt info)
            <> ")"
    hexOf = BS8.unpack . Base16.encode

renderCheckpoints ::
    ([CheckpointRecord], [(TxIn, CheckpointDecodeError)]) -> String
renderCheckpoints (records, rejects)
    | null records && null rejects = "no live checkpoints, no rejects"
    | otherwise =
        intercalate "\n" (map renderRecordLine records <> map renderRejectLine rejects)
  where
    renderRecordLine record =
        "checkpoint aid="
            <> hexOf (crAid record)
            <> " seq="
            <> show (cdSeq (crDatum record))
    renderRejectLine (txIn, err) =
        "reject txIn=" <> show txIn <> " reason=" <> show err
    hexOf = BS8.unpack . Base16.encode

renderCheckpoint :: Maybe CheckpointRecord -> String
renderCheckpoint Nothing = "checkpoint not found"
renderCheckpoint (Just record) =
    "checkpoint aid="
        <> BS8.unpack (Base16.encode (crAid record))
        <> " seq="
        <> show (cdSeq (crDatum record))

renderPayer :: [(TxIn, TxOut)] -> String
renderPayer [] = "no payer UTxOs"
renderPayer utxos = intercalate "\n" (map renderUtxo utxos)
  where
    renderUtxo (txIn, _txOut) = "utxo " <> show txIn

{- | One live-progress sample. Recomputed from the supplied 'QueryAction' on
every call; holds no state of its own.
-}
progressLine :: QueryAction -> IO String
progressLine qa = do
    status <- qaStatus qa
    (records, rejects) <- qaList qa
    pure $
        renderStatus status
            <> " live="
            <> show (length records)
            <> " rejects="
            <> show (length rejects)

{- | The one local-store implementation of 'QueryAction': every field reads
straight from the shared 'CheckpointView' / 'FollowerHandle' with no
intermediate cache.
-}
localQueryAction :: CheckpointView -> FollowerHandle -> QueryAction
localQueryAction view fh =
    QueryAction
        { qaStatus = StatusView <$> atomically (fhReadiness fh) <*> storePoint view
        , qaList = liveCheckpointsWithRejects view
        , qaCheckpoint = checkpointForAid view
        , qaPayer = payerUtxos (cvHandle view)
        }

{- | Run the interactive Haskeline prompt over one 'QueryAction'. Live
progress goes through Haskeline's external-print facility so background
output never corrupts the prompt; verb completion is wired via
'completeVerbs'; history is Haskeline's default in-process history (recalled
across prompts within this run, never written to disk).
-}
runShell :: QueryAction -> IO ()
runShell qa =
    Haskeline.runInputT settings $ do
        externalPrint <- Haskeline.getExternalPrint
        progressAsync <- liftIO (Async.async (progressLoop externalPrint))
        loop
        liftIO (Async.cancel progressAsync)
  where
    settings =
        Haskeline.setComplete
            ( Haskeline.completeWord Nothing " " $
                pure . map Haskeline.simpleCompletion . completeVerbs
            )
            Haskeline.defaultSettings
    progressLoop externalPrint = forever $ do
        threadDelay progressIntervalMicros
        line <- progressLine qa
        externalPrint line
    loop = do
        minput <- Haskeline.getInputLine "ckeri> "
        case minput of
            Nothing -> pure ()
            Just raw
                | all isSpace raw -> loop
                | otherwise -> do
                    outcome <- liftIO (handleLine qa raw)
                    case outcome of
                        Nothing -> pure ()
                        Just message -> Haskeline.outputStrLn message >> loop

progressIntervalMicros :: Int
progressIntervalMicros = 2_000_000
