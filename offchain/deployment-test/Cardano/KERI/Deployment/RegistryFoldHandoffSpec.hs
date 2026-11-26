{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFoldHandoffSpec
Description : what a fold says about the fold it signed, read from a working pipe as it happens

A fold that stops at the handoff has signed its one transaction. What the folder
can know of it depends on how far it got: it was signed and never handed to the node,
or the handoff began and the node may or may not have received it. Each case is run
with its lines written to a real pipe and read by another thread line by line while the
writer is still open. At the boundary where the fault is delivered the reader must
already hold the line naming the fold, with the id of the transaction that was signed;
afterwards the complete transcript is checked line by line, and the two transcripts must
differ in the one row the evidence supports.

The checks are functions of transcripts, and are themselves checked on transcripts the
test builds: a correct pair passes, and each fault a transcript can have is refused at
the assertion meant to refuse it.
-}
module Cardano.KERI.Deployment.RegistryFoldHandoffSpec (spec) where

import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand (printFoldEvent, renderFoldStopped)
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), whileConnected)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (noFaults)
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.KERI.Deployment.RegistryTransactions (emptyRoot)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar)
import Control.Exception (SomeException, try)
import Control.Monad (forM_, unless, void, when)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString.Char8 qualified as B8
import Data.Char (isDigit)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isPrefixOf)
import Data.Text qualified as T
import System.IO (BufferMode (..), Handle, hClose, hFlush, hGetLine, hIsEOF, hPutStrLn, hSetBuffering)
import System.Posix.IO (createPipe, fdToHandle)
import Test.Hspec

-- | How far the signed fold got.
data HowFar = NeverHandedOver | NodeMayHaveReceived
    deriving stock (Eq, Show)

-- | The facts a transcript is checked against, each taken from the chain fixture and not from what the command printed.
data Facts = Facts
    { factFold :: String
    -- ^ the id of the transaction the runtime signed last before the fold was handed over
    , factState :: String
    , factRoot :: String
    , factFailure :: String
    -- ^ the failure the node client died of, as the exception shows it, digits masked
    }

idText :: TxId -> String
idText = T.unpack . renderTransactionId

refText :: TxIn -> String
refText (TxIn txId (TxIx index)) = idText txId <> "#" <> show index

-- ---------------------------------------------------------------------
-- The pipe, read while it is open
-- ---------------------------------------------------------------------

-- | A pipe of the operating system: the writer, and the lines a reader thread has seen so far.
data Pipe = Pipe
    { pipeWriter :: Handle
    , pipeSeen :: IORef [String]
    -- ^ newest first
    , pipeEnded :: MVar ()
    }

openPipe :: IO Pipe
openPipe = do
    (readEnd, writeEnd) <- createPipe
    reader <- fdToHandle readEnd
    writer <- fdToHandle writeEnd
    seen <- newIORef []
    ended <- newEmptyMVar
    let loop = do
            done <- hIsEOF reader
            if done
                then putMVar ended ()
                else hGetLine reader >>= \line -> modifyIORef' seen (line :) >> loop
    _ <- forkIO loop
    pure (Pipe writer seen ended)

-- | Whether the reader holds this line, waiting a moment for it to arrive: the writer is still open.
visibleOnPipe :: Pipe -> String -> IO Bool
visibleOnPipe pipe wanted = go (150 :: Int)
  where
    go 0 = pure False
    go n = do
        seen <- readIORef (pipeSeen pipe)
        if wanted `elem` seen then pure True else threadDelay 20_000 >> go (n - 1)

-- | Close the writer and give every line the reader saw, oldest first.
transcriptOf :: Pipe -> IO [String]
transcriptOf pipe = do
    hClose (pipeWriter pipe)
    readMVar (pipeEnded pipe)
    reverse <$> readIORef (pipeSeen pipe)

-- ---------------------------------------------------------------------
-- What a transcript must say
-- ---------------------------------------------------------------------

-- | The row of the evidence: the fold's own line, by how far it got.
rowOf :: HowFar -> Facts -> String
rowOf NeverHandedOver facts = "fold " <> factFold facts <> " was not handed to the node"
rowOf NodeMayHaveReceived facts =
    "fold " <> factFold facts <> " may or may not have reached the node; check it before spending again"

-- | The only words the stage line holds besides the failure the node client died of.
stagePrefix :: String
stagePrefix = "ckeri: registry fold stopped at the handoff of the fold to the node: "

-- | Digit runs replaced by one mark, for what differs between runs (thread numbers).
maskDigits :: String -> String
maskDigits = go
  where
    go [] = []
    go text@(c : rest)
        | isDigit c = '#' : go (dropWhile isDigit text)
        | otherwise = c : go rest

-- | The lines of a transcript, but for the one that carries the failure's own words.
expectedLines :: HowFar -> Facts -> [String]
expectedLines howFar facts =
    ["handing fold " <> factFold facts <> " to the node"]
        <> [stageLine]
        <> [rowOf howFar facts]
        <> ["node-confirmed-state: " <> factState facts <> " root " <> factRoot facts]
        <> ["not retried: no transaction is sent again by this command"]
  where
    stageLine = stagePrefix <> factFailure facts

-- | Why a transcript is not the one the facts call for: line by line, nothing added and nothing missing.
checkTranscript :: HowFar -> Facts -> [String] -> Either String ()
checkTranscript howFar facts actual = do
    let wanted = snapshotLine : expectedLines howFar facts
        snapshotLine = "snapshot-root: " <> factRoot facts
    unless (length actual == length wanted) $
        Left ("the transcript has " <> show (length actual) <> " lines, not " <> show (length wanted) <> ": " <> show actual)
    mapM_ lineOf (zip3 [1 :: Int ..] wanted actual)
  where
    lineOf (n, want, got)
        | stagePrefix `isPrefixOf` want =
            unless (maskDigits got == want) $
                Left ("line " <> show n <> " is not the stage line, prefix and failure only: " <> got)
        | want == got = Right ()
        | otherwise = Left ("line " <> show n <> " is " <> show got <> ", not " <> show want)

-- | The two transcripts, each already right, differ in the one row and in no other.
checkPair :: Facts -> [String] -> Facts -> [String] -> Either String ()
checkPair factsA a factsB b = do
    let masked facts = map (maskFailure . replaceAll (factFold facts) "<fold>")
        differing = [(x, y) | (x, y) <- zip (masked factsA a) (masked factsB b), x /= y]
    unless (length a == length b) $ Left "the transcripts have different lengths"
    case differing of
        [(x, y)] | "was not handed to the node" `isInfixOf` x && "may or may not have reached the node" `isInfixOf` y -> Right ()
        _ -> Left ("the transcripts do not differ in exactly the row of the evidence: " <> show differing)
  where
    maskFailure line =
        if "ckeri: registry fold stopped" `isPrefixOf` line then takeWhile (/= ':') line <> ": <failure>" else line

replaceAll :: String -> String -> String -> String
replaceAll needle replacement = go
  where
    go [] = []
    go text@(c : rest)
        | not (null needle) && needle `isPrefixOf` text = replacement <> go (drop (length needle) text)
        | otherwise = c : go rest

-- ---------------------------------------------------------------------
-- A run
-- ---------------------------------------------------------------------

-- | What a run showed: the facts, what the reader held at the boundary, and the transcript.
data Run = Run
    { runFacts :: Facts
    , runKnownAtBoundary :: Bool
    , runStop :: FoldStopped
    , runAccepted :: Int
    , runBase :: Int
    , runAcceptedLast :: String
    , runTranscript :: [String]
    }

scenario :: HowFar -> IO Run
scenario howFar = do
    world <- newWorld 1_000
    export <- loadExport "kli-export-single.cesr"
    (request, _) <- bookDirectly world export
    base <- length <$> accepted world
    Just (stateRef, _) <- stateOutputOf world
    pipe <- openPipe
    hSetBuffering (pipeWriter pipe) (BlockBuffering Nothing)
    lastSigned <- newIORef ""
    foldId <- newIORef ""
    known <- newIORef True
    submits <- newIORef (0 :: Int)
    client <- newStandIn
    let runtime0 = runtimeOf noFaults world
        transactions = rtTransactions runtime0
        runtime =
            whileConnected (standInStatus client) $
                runtime0
                    { rtTransactions =
                        transactions
                            { trSign = \tx -> do
                                signed <- trSign transactions tx
                                either (const (pure ())) (modifyIORef' lastSigned . const . idText . transactionId) signed
                                pure signed
                            , trSubmit = \tx -> do
                                modifyIORef' submits (+ 1)
                                n <- readIORef submits
                                -- the fold is the one submission: its id is on the pipe, with the writer open, as the handoff begins
                                when (howFar == NodeMayHaveReceived && n == 1) $ do
                                    signedId <- readIORef lastSigned
                                    visible <- visibleOnPipe pipe ("handing fold " <> signedId <> " to the node")
                                    modifyIORef' known (&& visible)
                                outcome <- trSubmit transactions tx
                                -- the node has it; the reply is lost to the dying client
                                when (howFar == NodeMayHaveReceived && n == 1) (void (connectionEnds client))
                                pure outcome
                            }
                    }
        report event = do
            printFoldEvent (pipeWriter pipe) event
            case event of
                FoldHandingOff{eventTransaction = txId} -> do
                    modifyIORef' foldId (const (idText txId))
                    when (howFar == NeverHandedOver) $ do
                        signedId <- readIORef lastSigned
                        -- the id on the pipe, with the writer open, is the id of the transaction signed
                        visible <- visibleOnPipe pipe ("handing fold " <> signedId <> " to the node")
                        modifyIORef' known (&& (visible && idText txId == signedId))
                        -- the client ends before the handoff began
                        standInEnd client
                _ -> pure ()
        input =
            FoldInput
                { foldBlueprint = worldBlueprint world
                , foldIdentity = deployedIdentity (worldDeployed world)
                , foldRecord = deployedRecord (worldDeployed world)
                , foldRequestOutput = request
                , foldSnapshot = Snapshot "the deployer" [] []
                , foldPayerAddress = folderAddress
                }
    outcome <- try @SomeException (foldBookedRequest runtime report input)
    stopped <- case outcome of
        Right (Left stop) -> pure stop
        Right (Right done) -> fail ("the fold was not stopped: " <> show done)
        Left failure -> fail ("no stop record, the failure escaped: " <> show failure)
    -- what a call over the ended connection fails with
    ended <- newStandIn
    standInEnd ended
    failureShown <- either (maskDigits . show) (const "") <$> try @SomeException (rtObserve (whileConnected (standInStatus ended) runtime0))
    mapM_ (hPutStrLn (pipeWriter pipe)) (renderFoldStopped stopped)
    hFlush (pipeWriter pipe)
    transcript <- transcriptOf pipe
    transactions' <- accepted world
    reportedFold <- readIORef foldId
    isKnown <- readIORef known
    pure
        Run
            { runFacts =
                Facts
                    { factFold = reportedFold
                    , factState = refText stateRef
                    , factRoot = B8.unpack (convertToBase Base16 emptyRoot)
                    , factFailure = failureShown
                    }
            , runKnownAtBoundary = isKnown
            , runStop = stopped
            , runAccepted = length transactions'
            , runBase = base
            , runAcceptedLast = idText (transactionId (last transactions'))
            , runTranscript = transcript
            }

-- ---------------------------------------------------------------------
-- The specification
-- ---------------------------------------------------------------------

-- | A transcript the facts call for, with the failure's words in its stage line.
syntheticTranscript :: HowFar -> Facts -> [String]
syntheticTranscript howFar facts =
    ("snapshot-root: " <> factRoot facts) : expectedLines howFar facts

someFacts :: String -> Facts
someFacts foldId =
    Facts
        { factFold = foldId
        , factState = replicate 64 'c' <> "#0"
        , factRoot = replicate 64 '0'
        , factFailure = "the node connection ended: ConnectionLost"
        }

spec :: Spec
spec = describe "#351 what a fold says about the fold it signed" $ around_ withinOneMinute $ do
    describe "the checks, on transcripts the test builds" $ do
        let factsA = someFacts (replicate 64 'f')
            factsB = someFacts (replicate 64 'e')
            goodA = syntheticTranscript NeverHandedOver factsA
            goodB = syntheticTranscript NodeMayHaveReceived factsB
        it "pass a correct pair, each transcript right and the two differing in the one row" $ do
            checkTranscript NeverHandedOver factsA goodA `shouldBe` Right ()
            checkTranscript NodeMayHaveReceived factsB goodB `shouldBe` Right ()
            checkPair factsA goodA factsB goodB `shouldBe` Right ()
        it "refuse, at the line check, a line both transcripts share that claims the fold was submitted" $ do
            let false = "fold " <> replicate 64 'f' <> " was submitted"
                inject at ls = take at ls <> [false] <> drop at ls
            checkTranscript NeverHandedOver factsA (inject 5 goodA) `shouldSatisfy` isLeftWith "the transcript has"
            checkTranscript NodeMayHaveReceived factsB (inject 5 goodB) `shouldSatisfy` isLeftWith "the transcript has"
        it "refuse, at the line check, an uncertain row that names another fold than the one handed over" $ do
            let other = replicate 64 '1'
                wrongRow = map (\line -> if "may or may not" `isInfixOf` line then "fold " <> other <> " may or may not have reached the node; check it before spending again" else line) goodB
            checkTranscript NodeMayHaveReceived factsB wrongRow `shouldSatisfy` isLeftWith "line "
        it "refuse, at the stage line, a false claim embedded in either stage line, and pass the same pair without it" $ do
            let embed how = map (\line -> if stagePrefix `isPrefixOf` line then how line else line)
                atEnd line = line <> "; the fold was submitted"
                inFront line = "the fold was submitted, " <> line
                inside line = take (length stagePrefix) line <> "the fold was submitted: " <> drop (length stagePrefix) line
                refused = isLeftWith "is not the stage line"
            checkTranscript NeverHandedOver factsA goodA `shouldBe` Right ()
            checkTranscript NodeMayHaveReceived factsB goodB `shouldBe` Right ()
            forM_ [atEnd, inFront, inside] $ \how -> do
                checkTranscript NeverHandedOver factsA (embed how goodA) `shouldSatisfy` refused
                checkTranscript NodeMayHaveReceived factsB (embed how goodB) `shouldSatisfy` refused
        it "refuse a pair whose transcripts differ in more than the row of the evidence" $ do
            let extra = map (\line -> if "node-confirmed-state" `isPrefixOf` line then line <> " (stale)" else line) goodB
            checkPair factsA goodA factsB extra `shouldSatisfy` isLeftWith "do not differ"
        it "see a line on the pipe while the writer is open only when it was flushed" $ do
            flushed <- openPipe
            hSetBuffering (pipeWriter flushed) (BlockBuffering Nothing)
            hPutStrLn (pipeWriter flushed) "handing fold X to the node" >> hFlush (pipeWriter flushed)
            visibleOnPipe flushed "handing fold X to the node" >>= (`shouldBe` True)
            _ <- transcriptOf flushed
            unflushed <- openPipe
            hSetBuffering (pipeWriter unflushed) (BlockBuffering Nothing)
            hPutStrLn (pipeWriter unflushed) "handing fold X to the node"
            visibleOnPipe unflushed "handing fold X to the node" >>= (`shouldBe` False)
            -- it arrives when the writer closes, which is too late for the boundary
            transcriptOf unflushed >>= (`shouldBe` ["handing fold X to the node"])
    describe "the fold, run with its lines on a pipe" $
        it "has the fold's id on the pipe at the boundary, whether the handoff never occurred or the node may have received it, and two complete transcripts that differ only in the row of the evidence" $ do
            never <- scenario NeverHandedOver
            maybeThere <- scenario NodeMayHaveReceived
            -- the reader held the line with the signed fold's id while the writer was open, at each boundary
            runKnownAtBoundary never `shouldBe` True
            runKnownAtBoundary maybeThere `shouldBe` True
            -- what the command knows, and what the chain shows
            fmap attemptStatus (stoppedFoldAttempt (runStop never)) `shouldBe` Just NotHandedToNode
            fmap attemptStatus (stoppedFoldAttempt (runStop maybeThere)) `shouldBe` Just HandoffUnknown
            -- the fold never left, or the node has it: the one transaction of the command
            runAccepted never `shouldBe` runBase never
            runAccepted maybeThere `shouldBe` runBase maybeThere + 1
            runAcceptedLast maybeThere `shouldBe` factFold (runFacts maybeThere)
            -- the complete transcripts, line by line, and their difference
            checkTranscript NeverHandedOver (runFacts never) (runTranscript never) `shouldBe` Right ()
            checkTranscript NodeMayHaveReceived (runFacts maybeThere) (runTranscript maybeThere) `shouldBe` Right ()
            checkPair (runFacts never) (runTranscript never) (runFacts maybeThere) (runTranscript maybeThere) `shouldBe` Right ()
  where
    isLeftWith needle = either (needle `isInfixOf`) (const False)
