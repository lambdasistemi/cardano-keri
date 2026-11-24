{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.KoiosSettlementSpec
Description : a transaction handed over has settled when its first output is visible

Settlement is decided by Singular's confirmation over the Koios ledger provider.
Two layers run it. The first drives Singular's confirmation over a scripted
provider and a scripted clock and sleep, so the polls, the reads and the wait
are observed one by one with no real time. The second runs the Koios
provider itself over an in-memory Koios client, so the exact-reference read and
the refusal of a partial answer are the shipped ones. Nothing reaches the
network. The poll times, the window and the reads allowed are the
producer's own, observed from a run, or an independent oracle written out here;
the one literal is the window of a transaction with a fixed validity end.
-}
module Cardano.KERI.Deployment.KoiosSettlementSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.KoiosSettlement (
    Refusal (..),
    Settlement (..),
    Unsettlement (..),
    koiosSettlement,
    renderUnsettlement,
    settleTransaction,
 )
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx, txIdTx)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, mkBasicTxBody, outputsTxBodyL, vldtTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..), TxIx (..))
import Cardano.Ledger.BaseTypes qualified as Ledger
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Slotting.Slot (SlotNo (..))
import Control.Exception (throwIO)
import Control.Monad (forM_, when)
import Data.Aeson (Value (..), encode, object, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Function ((&))
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Exts (fromList)
import Lens.Micro ((.~), (^.))
import Singular.Provider.Koios.Client qualified as Client
import Singular.Provider.Koios.Wire qualified as Wire
import Singular.Registry.Confirmation (
    ConfirmationFailure (..),
    ConfirmationRuntime (..),
    confirmTransaction,
    confirmationWindow,
 )
import Singular.Registry.Evidence (Evidenced (..), NoWitness, SessionBinding (..), SessionId (..))
import Singular.Registry.LedgerProvider (
    LedgerProvider (..),
    Network (..),
    OutputQuery (..),
    Outputs,
    ReadFailure (..),
    Session (..),
    TipObservation (..),
 )
import Singular.Registry.NetworkTime (NetworkTime, validateNetworkTime)
import Singular.Registry.TimeSource (TimeSource (..), loadPinnedSource)
import Singular.Registry.Wait (WaitFailure (..), WaitStage (..))
import Test.Hspec

spec :: Spec
spec = describe "the Koios instance decides settlement by the transaction's first output" $ do
    scriptedSpec
    koiosSpec

-- ---------------------------------------------------------------------
-- The scripted clock, sleep and provider
-- ---------------------------------------------------------------------

-- | What the provider was asked, in order, with the clock when it was asked.
data Event
    = Acquired Integer
    | OutputsAsked Integer TxIn
    | TipAsked Integer
    deriving stock (Eq, Show)

-- | The state of one scripted run.
data Run = Run
    { runNow :: IORef Integer
    , runEvents :: IORef [Event]
    , runBounds :: IORef [Int]
    , runPauses :: IORef [Int]
    , runTimeReads :: IORef Int
    , runTime :: Integer -> Int -> TimeBehavior
    -- ^ what a read of the time source does, by the clock and by how many reads came before
    }

-- | What a read of the time source does.
data TimeBehavior = TimeOk | TimeFails | TimeStalls
    deriving stock (Eq, Show)

{- | A read of the time source as scripted, by the clock and by how many reads
came before; a stalling read costs the clock a long time.
-}
timeRead :: Run -> IO (Either ReadFailure ())
timeRead run = do
    now <- readIORef (runNow run)
    count <- atomicModifyIORef' (runTimeReads run) (\k -> (k + 1, k + 1))
    case runTime run now count of
        TimeOk -> pure (Right ())
        TimeFails -> pure (Left (BackendReadFailure "the time source cannot be read"))
        TimeStalls -> modifyIORef' (runNow run) (+ 1_000_000) >> pure (Right ())

newRun :: Integer -> IO Run
newRun origin = Run <$> newIORef origin <*> newIORef [] <*> newIORef [] <*> newIORef [] <*> newIORef 0 <*> pure (\_ _ -> TimeOk)

{- | Singular's pure interpretation of its effects: the clock moves only by
what the polling sleeps, a bound is recorded, and a wait whose action ran
past the bound is its failure. @scale@ is how many milliseconds one second of
sleep costs: 1,000 is Singular's own, a smaller one makes a control that polls
faster than Singular does.
-}
scriptedRuntime :: Run -> Integer -> Integer -> ConfirmationRuntime IO
scriptedRuntime run origin scale =
    ConfirmationRuntime
        { currentPosixMs = readIORef (runNow run)
        , attemptWindowRead = fmap Right
        , pausePolling = \seconds -> do
            modifyIORef' (runPauses run) (<> [seconds])
            modifyIORef' (runNow run) (+ toInteger seconds * scale)
        , boundedConfirmation = \tid bound action -> do
            modifyIORef' (runBounds run) (<> [bound])
            started <- readIORef (runNow run)
            outcome <- action
            ended <- readIORef (runNow run)
            let failure = WaitFailure SessionConfirmationWait tid (fromInteger (ended - origin) / 1000) bound
            pure $ case outcome of
                Left deadline -> Left (failure (Just deadline))
                Right answer
                    | ended - started >= toInteger bound * 1000 -> Left (failure Nothing)
                    | otherwise -> Right answer
        }

-- | The provider's answer to an exact-reference read, given the clock.
type Answers = Integer -> TxIn -> Either ReadFailure Outputs

{- | A provider with no read but the exact output and the tip, and no
submission: any other read, and any submission, is an exception that fails the
check that made it.
-}
scriptedProvider :: Run -> NetworkTime -> Answers -> LedgerProvider NoWitness IO
scriptedProvider run time answers =
    LedgerProvider
        { acquire = \_ action -> do
            now <- readIORef (runNow run)
            record (Acquired now)
            Right <$> action session
        , submitTx = \_ _ -> throwIO (userError "a submission on the decision path")
        }
  where
    record event = modifyIORef' (runEvents run) (<> [event])
    nowMs = readIORef (runNow run)
    forbidden what _ = throwIO (userError ("a read on the decision path: " <> what))
    session =
        Session
            { sessionNetwork = Network 1
            , sessionId = SessionId "scripted"
            , sessionBinding = Unbound
            , sessionTracer = mempty
            , sessionEvaluated = \_ -> pure ()
            , servedNetwork = forbidden "served network" ()
            , outputs = \case
                AtTxIn reference -> do
                    now <- nowMs
                    record (OutputsAsked now reference)
                    pure (fmap (`Evidenced` Nothing) (answers now reference))
                _ -> forbidden "outputs by another query" ()
            , protocolParameters = forbidden "protocol parameters" ()
            , tipObservation = do
                now <- nowMs
                record (TipAsked now)
                pure . Right $
                    Evidenced
                        TipObservation
                            { observedSlot = SlotNo 68_774_400
                            , observedHash = BS.replicate 32 0xab
                            , observedHeight = 4_000_000
                            , observedBlockTime = fromInteger (now `div` 1000)
                            }
                        Nothing
            , networkTime = fmap (fmap (\() -> Evidenced time Nothing)) (timeRead run)
            , scriptRegistered = forbidden "script registered"
            , mintRecord = forbidden "mint record"
            , history = \_ _ -> forbidden "history" ()
            , inclusion = forbidden "inclusion"
            }

-- | One run of the settlement over the scripted provider.
data Outcome = Outcome
    { outResult :: Either Refusal Settlement
    , outEvents :: [Event]
    , outBounds :: [Int]
    , outPauses :: [Int]
    , outStarted :: Integer
    , outEnded :: Integer
    }

settleScripted :: Integer -> Integer -> Answers -> ConwayTx -> IO Outcome
settleScripted = settleScriptedWith (\_ _ -> TimeOk)

{- | How many acquisitions Singular's own confirmation makes of the same
transaction under the same script, with nothing of ours around it.
-}
singularAcquisitions :: (Integer -> Int -> TimeBehavior) -> Integer -> Answers -> ConwayTx -> IO Int
singularAcquisitions script origin answers tx = do
    started <- newRun origin
    let run = started{runTime = script}
    time <- preprodTime
    _ <- confirmTransaction (scriptedRuntime run origin 1_000) (scriptedProvider run time answers) (Network 1) tx
    length . filter isAcquired <$> readIORef (runEvents run)
  where
    isAcquired (Acquired _) = True
    isAcquired _ = False

settleScriptedWith :: (Integer -> Int -> TimeBehavior) -> Integer -> Integer -> Answers -> ConwayTx -> IO Outcome
settleScriptedWith script origin scale answers tx = do
    started <- newRun origin
    let run = started{runTime = script}
    time <- preprodTime
    result <- settleTransaction time (scriptedRuntime run origin scale) (scriptedProvider run time answers) (Network 1) tx
    Outcome result <$> readIORef (runEvents run) <*> readIORef (runBounds run) <*> readIORef (runPauses run) <*> pure origin <*> readIORef (runNow run)

{- | Output 0 of the transaction is visible from a time on, and no other
reference is. The answer to a read of another reference is the named absence.
-}
visibleFrom :: ConwayTx -> Maybe Integer -> Answers
visibleFrom tx from now reference = case (from, lookup reference (outputsOf tx)) of
    (Just start, Just output) | now >= start, reference == TxIn (txIdTx tx) (TxIx 0) -> Right [(reference, output)]
    _ -> Left (MissingOutput reference)

-- ---------------------------------------------------------------------
-- The transactions
-- ---------------------------------------------------------------------

{- | The slot a transaction is valid until. The pinned preprod time puts slot
68,774,400 at 1,724,457,600,000 ms and a slot lasts one second there, so this
slot starts 3,600 s later, at 1,724,461,200,000 ms.
-}
validityEnd :: SlotNo
validityEnd = SlotNo (68_774_400 + 3_600)

-- | The window of a transaction valid until 'validityEnd': its start plus two minutes.
windowEnd :: Integer
windowEnd = 1_724_461_320_000

-- | A transaction with two outputs, valid until 'validityEnd'.
transaction :: Integer -> ConwayTx
transaction salt =
    mkBasicTx
        ( mkBasicTxBody
            & outputsTxBodyL .~ fromList [lovelace 5_000_000, lovelace 4_000_000]
            & feeTxBodyL .~ Coin salt
            & vldtTxBodyL .~ ValidityInterval SNothing (SJust validityEnd)
        )

withoutOutputs :: ConwayTx
withoutOutputs =
    mkBasicTx
        ( mkBasicTxBody
            & vldtTxBodyL .~ ValidityInterval SNothing (SJust validityEnd)
        )

-- | A transaction with outputs and no validity upper slot.
withoutValidityEnd :: ConwayTx
withoutValidityEnd =
    mkBasicTx
        ( mkBasicTxBody
            & outputsTxBodyL .~ fromList [lovelace 5_000_000, lovelace 4_000_000]
            & feeTxBodyL .~ Coin 3
        )

outputsOf :: ConwayTx -> [(TxIn, TxOut ConwayEra)]
outputsOf tx =
    [ (TxIn (txIdTx tx) (TxIx index), output)
    | (index, output) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
    ]

main', other :: ConwayTx
main' = transaction 1
other = transaction 2

-- | The clock where a run of 97 s ends at the window's end.
startClock :: Integer
startClock = windowEnd - 97_000

address :: Addr
address = Addr Ledger.Testnet (ScriptHashObj (ScriptHash (fromJust (hashFromBytes (BS.replicate 28 0xa1))))) StakeRefNull

lovelace :: Integer -> TxOut ConwayEra
lovelace n = mkBasicTxOut address (MaryValue (Coin n) (MultiAsset Map.empty))

preprodSource :: IO TimeSource
preprodSource = loadPinnedSource 1 Nothing >>= either (fail . show) pure

preprodTime :: IO NetworkTime
preprodTime = do
    TimeSource manifest genesis eras <- preprodSource
    either (fail . show) pure (validateNetworkTime 1 manifest genesis eras)

-- ---------------------------------------------------------------------
-- The scripted layer
-- ---------------------------------------------------------------------

{- | A wait that the window's close ended: the chain's time reached the end
of the window, under the bound Singular derived, for this transaction.
-}
closedByTip :: ConwayTx -> Int -> ConfirmationFailure -> Bool
closedByTip tx bound = \case
    ConfirmationWaitFailure failure ->
        waitStage failure == SessionConfirmationWait
            && waitTxId failure == txIdTx tx
            && waitBound failure == bound
            && waitClosedAt failure == Just windowEnd
    _ -> False

-- | A read that stopped inside the window, with the failure the provider named.
stoppedBy :: ReadFailure -> ConfirmationFailure -> Bool
stoppedBy expected = \case
    ConfirmationReadFailure failure -> failure == expected
    _ -> False

{- | The one thing a negative case may assert: the result is unsettled, for this
transaction, by this cause, with the deadline of the window (the validity end plus
two minutes) and the bound Singular's own wait failure carries, if it does, and
the wording of the provider that names the deadline as the time to look again
after.
-}
expectUnsettled :: ConwayTx -> Maybe Int -> (ConfirmationFailure -> Bool) -> Either Refusal Settlement -> Expectation
expectUnsettled tx bound causeOk = \case
    Right (NotSettled unsettled) -> do
        unsettledTransaction unsettled `shouldBe` txIdTx tx
        unsettledBy unsettled `shouldSatisfy` causeOk
        unsettledDeadlineMs unsettled `shouldBe` windowEnd
        unsettledBoundSeconds unsettled `shouldBe` bound
        let wording = renderUnsettlement unsettled
        wording `shouldSatisfy` T.isInfixOf (Wire.txIdHex (txIdTx tx))
        wording `shouldSatisfy` T.isInfixOf "may or may not have reached the provider"
        wording `shouldSatisfy` T.isInfixOf ("look again after " <> T.pack (show windowEnd))
        case bound of
            Just seconds -> wording `shouldSatisfy` T.isInfixOf ("bounded at " <> T.pack (show seconds) <> " s")
            Nothing -> wording `shouldNotSatisfy` T.isInfixOf "bounded at"
    other' -> expectationFailure ("not unsettled: " <> describeResult other')

-- | Singular's polling instants from a start: sleeps of 1, 2, 4 and then 5 seconds, written out here.
pollInstants :: Integer -> [Integer]
pollInstants start = [start + offset | offset <- scanl (+) 0 sleeps]
  where
    sleeps = 1_000 : 2_000 : 4_000 : repeat 5_000

{- | The last poll that finds the window open and the poll that finds it
closed: the first whose whole second is at or after the end of the window.
-}
closingPolls :: Integer -> (Integer, Integer)
closingPolls start =
    fromMaybe (0, 0) (find ((>= windowEnd) . snd) (zip instants (drop 1 instants)))
  where
    instants = pollInstants start

-- | The most reads a bound of this many seconds allows at those sleeps.
readsAllowed :: Int -> Int
readsAllowed bound = length (takeWhile (<= toInteger bound * 1_000) (scanl (+) 0 (1_000 : 2_000 : 4_000 : repeat 5_000)))

-- | A start whose closing poll runs 4 s after the deadline.
lateClock :: Integer
lateClock = windowEnd - 98_000

{- | The window Singular derives for the transaction, asked of Singular itself
from a start: its deadline and its bound in seconds.
-}
singularWindow :: Integer -> ConwayTx -> IO (Either ConfirmationFailure (Integer, Int))
singularWindow start tx = do
    run <- newRun start
    time <- preprodTime
    confirmationWindow (scriptedRuntime run start 1_000) (scriptedProvider run time (visibleFrom tx Nothing)) (Network 1) tx

scriptedSpec :: Spec
scriptedSpec = describe "over a scripted provider and a scripted clock" $ do
    describe "settlement by output" $ do
        it "settles when output 0 is visible under its exact reference, asked in its own acquisition" $ do
            outcome <- settleScripted startClock 1_000 (visibleFrom main' (Just startClock)) main'
            isSettled (outResult outcome) `shouldBe` True
            groupAcquisitions (outEvents outcome) `shouldBe` [[], [OutputsAsked startClock (TxIn (txIdTx main') (TxIx 0))]]
            outBounds outcome `shouldBe` [30, 107]
        it "reads nothing about the transaction but its first output and the tip, and submits nothing" $ do
            -- the provider throws on every other read and on a submission
            outcome <- settleScripted startClock 1_000 (visibleFrom main' Nothing) main'
            length [() | OutputsAsked{} <- outEvents outcome] `shouldSatisfy` (> 1)
            all permitted (outEvents outcome) `shouldBe` True
        it "waits in the window Singular derives: the validity end plus two minutes, 1,724,461,320,000 for a validity end of slot 68,777,999" $ do
            outcome <- settleScripted startClock 1_000 (visibleFrom main' Nothing) main'
            expectUnsettled main' (Just 107) (closedByTip main' 107) (outResult outcome)
            singularWindow startClock main' >>= \case
                Right found -> found `shouldBe` (windowEnd, 107)
                Left failure -> expectationFailure ("no window: " <> show failure)
    describe "a window that closes without the output" $ do
        it "ends unsettled, in the window, with the wording of the provider" $ do
            outcome <- settleScripted startClock 1_000 (visibleFrom main' Nothing) main'
            expectUnsettled main' (Just 107) (closedByTip main' 107) (outResult outcome)
        it "settles when the output is visible at the last poll before the deadline" $ do
            let (lastOpen, _) = closingPolls startClock
            outcome <- settleScripted startClock 1_000 (visibleFrom main' (Just lastOpen)) main'
            lastRead outcome `shouldBe` Just lastOpen
            isSettled (outResult outcome) `shouldBe` True
        it "settles when the output is visible at the poll that finds the window closed, which reads before it looks at the tip" $ do
            let (_, closing) = closingPolls startClock
            outcome <- settleScripted startClock 1_000 (visibleFrom main' (Just closing)) main'
            lastRead outcome `shouldBe` Just closing
            isSettled (outResult outcome) `shouldBe` True
        it "ends unsettled when the output is visible only after the last poll" $ do
            let (_, closing) = closingPolls startClock
            outcome <- settleScripted startClock 1_000 (visibleFrom main' (Just (closing + 1))) main'
            lastRead outcome `shouldBe` Just closing
            expectUnsettled main' (Just 107) (closedByTip main' 107) (outResult outcome)
        it "settles an output that becomes visible between the deadline and the closing poll, as Singular does today (pinned edge)" $ do
            let (_, closing) = closingPolls lateClock
            closing `shouldBe` windowEnd + 4_000
            outcome <- settleScripted lateClock 1_000 (visibleFrom main' (Just (windowEnd + 1))) main'
            lastRead outcome `shouldBe` Just closing
            isSettled (outResult outcome) `shouldBe` True
        it "still ends unsettled when the output is visible only after that closing poll" $ do
            let (_, closing) = closingPolls lateClock
            outcome <- settleScripted lateClock 1_000 (visibleFrom main' (Just (closing + 1))) main'
            lastRead outcome `shouldBe` Just closing
            expectUnsettled main' (Just 108) (closedByTip main' 108) (outResult outcome)
    describe "the exact reference" $ do
        it "is not output 0 when only output 1 of the same transaction is visible" $ do
            let sloppy _ _ = Right (take 1 (drop 1 (outputsOf main')))
            outcome <- settleScripted startClock 1_000 sloppy main'
            expectUnsettled main' (Just 107) (closedByTip main' 107) (outResult outcome)
        it "is not output 0 of another transaction" $ do
            let elsewhere _ _ = Right (take 1 (outputsOf other))
            outcome <- settleScripted startClock 1_000 elsewhere main'
            expectUnsettled main' (Just 107) (closedByTip main' 107) (outResult outcome)
        it "is not an answer the provider marks as partial: a named failure inside the window ends unsettled in that window" $ do
            let failure = BackendReadFailure "the answer is partial"
            outcome <- settleScripted startClock 1_000 (\_ _ -> Left failure) main'
            expectUnsettled main' Nothing (stoppedBy failure) (outResult outcome)
            length [() | OutputsAsked{} <- outEvents outcome] `shouldBe` 1
        it "reports the window the confirmation used when a later poll fails, not one counted from the failure" $ do
            let failure = BackendReadFailure "the answer is partial"
                failsAt offset now reference
                    | now < startClock + offset = Left (MissingOutput reference)
                    | otherwise = Left failure
            forM_ [1_000, 12_000, 52_000] $ \offset -> do
                outcome <- settleScripted startClock 1_000 (failsAt offset) main'
                expectUnsettled main' Nothing (stoppedBy failure) (outResult outcome)
                lastRead outcome `shouldBe` Just (startClock + offset)
        it "keeps the deadline when the time source cannot be read after the poll failed" $ do
            let failure = BackendReadFailure "the answer is partial"
                failsAt now reference
                    | now < startClock + 1_000 = Left (MissingOutput reference)
                    | otherwise = Left failure
                unreadableAfterTheFailure now _ = if now >= startClock + 1_000 then TimeFails else TimeOk
            outcome <- settleScriptedWith unreadableAfterTheFailure startClock 1_000 failsAt main'
            expectUnsettled main' Nothing (stoppedBy failure) (outResult outcome)
        it "does not read the time source again after the wait ended, so a read that stalls delays nothing" $ do
            let failure = BackendReadFailure "the answer is partial"
                failsAt now reference
                    | now < startClock + 1_000 = Left (MissingOutput reference)
                    | otherwise = Left failure
                stallsAfterTheFailure now _ = if now >= startClock + 1_000 then TimeStalls else TimeOk
            outcome <- settleScriptedWith stallsAfterTheFailure startClock 1_000 failsAt main'
            expectUnsettled main' Nothing (stoppedBy failure) (outResult outcome)
            outEnded outcome - outStarted outcome `shouldSatisfy` (<= 107_000)
        it "reports the end of the window of the transaction when the first network-time read fails and recovers, and reads as Singular does" $ do
            let failure = BackendReadFailure "the answer is partial"
                partial _ _ = Left failure
                firstUnreadable _ count = if count == 1 then TimeFails else TimeOk
            outcome <- settleScriptedWith firstUnreadable startClock 1_000 partial main'
            expectUnsettled main' Nothing (stoppedBy failure) (outResult outcome)
            singular <- singularAcquisitions firstUnreadable startClock partial main'
            length [() | Acquired _ <- outEvents outcome] `shouldBe` singular
        it "acquires as often as Singular's confirmation does when a later poll fails" $ do
            let failure = BackendReadFailure "the answer is partial"
                failsAt now reference
                    | now < startClock + 1_000 = Left (MissingOutput reference)
                    | otherwise = Left failure
            outcome <- settleScripted startClock 1_000 failsAt main'
            expectUnsettled main' Nothing (stoppedBy failure) (outResult outcome)
            singular <- singularAcquisitions (\_ _ -> TimeOk) startClock failsAt main'
            length [() | Acquired _ <- outEvents outcome] `shouldBe` singular
        it "is not an answer that conflicts: the named failure ends unsettled in that window" $ do
            let conflicting _ reference = Left (ConflictingOutput reference)
                first = TxIn (txIdTx main') (TxIx 0)
            outcome <- settleScripted startClock 1_000 conflicting main'
            expectUnsettled main' Nothing (stoppedBy (ConflictingOutput first)) (outResult outcome)
    describe "the bound" $ do
        it "is Singular's, polls at Singular's instants and waits no longer than it" $ do
            Right (_, bound) <- singularWindow startClock main'
            outcome <- settleScripted startClock 1_000 (visibleFrom main' Nothing) main'
            take 2 (outBounds outcome) `shouldBe` [30, bound]
            let polled = [at | OutputsAsked at _ <- outEvents outcome]
                (_, closing) = closingPolls startClock
            polled `shouldBe` takeWhile (<= closing) (pollInstants startClock)
            take 5 (outPauses outcome) `shouldBe` [1, 2, 4, 5, 5]
            outEnded outcome - outStarted outcome `shouldSatisfy` (<= toInteger bound * 1_000)
            length polled `shouldSatisfy` (<= readsAllowed bound)
        it "is kept at the closing poll after the deadline too" $ do
            Right (_, bound) <- singularWindow lateClock main'
            outcome <- settleScripted lateClock 1_000 (visibleFrom main' Nothing) main'
            lastRead outcome `shouldBe` Just (snd (closingPolls lateClock))
            outEnded outcome - outStarted outcome `shouldSatisfy` (<= toInteger bound * 1_000)
            length [() | OutputsAsked{} <- outEvents outcome] `shouldSatisfy` (<= readsAllowed bound)
        it "catches a control that polls faster than the interval allows" $ do
            Right (_, bound) <- singularWindow startClock main'
            outcome <- settleScripted startClock 100 (visibleFrom main' Nothing) main'
            length [() | OutputsAsked{} <- outEvents outcome] `shouldSatisfy` (> readsAllowed bound)
    describe "a transaction without outputs" $ do
        it "is refused by name and nothing is read" $ do
            outcome <- settleScripted startClock 1_000 (visibleFrom main' (Just startClock)) withoutOutputs
            case outResult outcome of
                Left (TransactionWithoutOutput (ConfirmationNoOutput identity)) -> identity `shouldBe` txIdTx withoutOutputs
                other' -> expectationFailure ("not refused by name: " <> describeEither other')
            outEvents outcome `shouldBe` []
            outBounds outcome `shouldBe` []
            outBounds outcome `shouldBe` []
    describe "a transaction without a validity end" $ do
        it "is refused by name, though its first output is visible, and nothing is read" $ do
            outcome <- settleScripted startClock 1_000 (visibleFrom withoutValidityEnd (Just startClock)) withoutValidityEnd
            case outResult outcome of
                Left (TransactionWithoutValidityEnd identity) -> identity `shouldBe` txIdTx withoutValidityEnd
                other' -> expectationFailure ("not refused by name: " <> describeEither other')
            outEvents outcome `shouldBe` []
            outBounds outcome `shouldBe` []
  where
    permitted event = case event of
        Acquired _ -> True
        OutputsAsked _ reference -> reference == TxIn (txIdTx main') (TxIx 0)
        TipAsked _ -> True

groupAcquisitions :: [Event] -> [[Event]]
groupAcquisitions = go
  where
    go [] = []
    go (Acquired _ : rest) = let (own, later) = break isAcquired rest in own : go later
    go (_ : rest) = go rest
    isAcquired (Acquired _) = True
    isAcquired _ = False

isSettled :: Either Refusal Settlement -> Bool
isSettled (Right Settled) = True
isSettled _ = False

describeResult :: Either Refusal Settlement -> String
describeResult = either show show

describeEither :: Either Refusal Settlement -> String
describeEither = describeResult

-- | The time of the last read of the output, so a settled run is shown to have asked.
lastRead :: Outcome -> Maybe Integer
lastRead outcome = case reverse [at | OutputsAsked at _ <- outEvents outcome] of
    [] -> Nothing
    latest : _ -> Just latest

-- ---------------------------------------------------------------------
-- The Koios layer
-- ---------------------------------------------------------------------

{- | What the in-memory service holds: when each output of each transaction is
there, and what it answers to tx_info.
-}
data Service = Service
    { serviceNow :: IORef Integer
    , serviceCalls :: IORef [Wire.Call]
    , serviceMarked :: IORef Bool
    -- ^ whether an answer marked partial has been sent
    }

koiosSpec :: Spec
koiosSpec = describe "over the Koios provider on an in-memory client" $ do
    it "settles when the service shows output 0 of the transaction, asking only the tip, the transaction and the address" $ do
        (result, calls) <- koiosRun main' (shows' (Just startClock) [0, 1])
        isSettled result `shouldBe` True
        calls `shouldSatisfy` elem Wire.CallTxInfo
        calls `shouldSatisfy` elem Wire.CallAddressUtxos
        all (`elem` [Wire.CallTip, Wire.CallTxInfo, Wire.CallAddressUtxos]) calls `shouldBe` True
    it "ends unsettled, in the window, when the service never shows it" $ do
        (result, _) <- koiosRun main' (shows' Nothing [0, 1])
        expectUnsettled main' (Just 107) (closedByTip main' 107) result
    it "ends unsettled when output 1 is shown at the address and output 0 is not" $ do
        (result, _) <- koiosRun main' (shows' (Just startClock) [1])
        expectUnsettled main' (Just 107) (closedByTip main' 107) result
    it "ends unsettled when only output 0 of another transaction is shown" $ do
        (result, _) <- koiosRun main' (showsOther other)
        expectUnsettled main' (Just 107) (closedByTip main' 107) result
    it "ends unsettled by a read failure, in the window, when the answer for the transaction is marked partial" $ do
        (result, _) <- koiosRunWith (Just 206) main' (shows' (Just startClock) [0, 1])
        expectUnsettled main' Nothing isBackendFailure result
    it "reports the window the confirmation used when a later answer is marked partial, not one counted from the failure" $ do
        (result, calls) <- koiosRunWith (Just 206) main' (shows' (Just (startClock + 1_000)) [0, 1])
        expectUnsettled main' Nothing isBackendFailure result
        length (filter (== Wire.CallTxInfo) calls) `shouldBe` 2
    it "keeps the deadline when the time source cannot be read after the answer marked partial" $ do
        (result, _, reads', _) <- koiosRunTimed (\sent _ -> if sent then TimeFails else TimeOk) (Just 206) main' (shows' (Just (startClock + 1_000)) [0, 1])
        expectUnsettled main' Nothing isBackendFailure result
        reads' `shouldBe` 3
    it "does not read the time source again after the wait ended, so a read that stalls delays nothing" $ do
        (result, _, reads', ended) <- koiosRunTimed (\sent _ -> if sent then TimeStalls else TimeOk) (Just 206) main' (shows' (Just (startClock + 1_000)) [0, 1])
        expectUnsettled main' Nothing isBackendFailure result
        reads' `shouldBe` 3
        ended - startClock `shouldSatisfy` (<= 107_000)
    it "reports the end of the window of the transaction when the first time read fails and recovers" $ do
        let firstUnreadable _ count = if count == 1 then TimeFails else TimeOk
        (result, _, _, _) <- koiosRunTimed firstUnreadable (Just 206) main' (shows' (Just startClock) [0, 1])
        expectUnsettled main' Nothing isBackendFailure result
    it "refuses a transaction without outputs by name and asks the service nothing" $ do
        (result, calls) <- koiosRun withoutOutputs (shows' (Just startClock) [0, 1])
        case result of
            Left (TransactionWithoutOutput (ConfirmationNoOutput identity)) -> identity `shouldBe` txIdTx withoutOutputs
            other' -> expectationFailure ("not refused by name: " <> describeEither other')
        calls `shouldBe` []
    it "refuses a transaction without a validity end by name, though the service shows its output, and asks the service nothing" $ do
        (result, calls) <- koiosRun withoutValidityEnd (Shown withoutValidityEnd (Just startClock) [0, 1])
        case result of
            Left (TransactionWithoutValidityEnd identity) -> identity `shouldBe` txIdTx withoutValidityEnd
            other' -> expectationFailure ("not refused by name: " <> describeEither other')
        calls `shouldBe` []
  where
    isBackendFailure = \case
        ConfirmationReadFailure (BackendReadFailure _) -> True
        _ -> False

-- | Which outputs the service shows, and which transaction it answers for, from a time on.
data Shown = Shown
    { shownTx :: ConwayTx
    , shownFrom :: Maybe Integer
    , shownIndexes :: [Integer]
    }

shows' :: Maybe Integer -> [Integer] -> Shown
shows' = Shown main'

showsOther :: ConwayTx -> Shown
showsOther tx = Shown tx (Just startClock) [0, 1]

koiosRun :: ConwayTx -> Shown -> IO (Either Refusal Settlement, [Wire.Call])
koiosRun = koiosRunWith Nothing

{- | Run the settlement of a transaction against an in-memory service that
shows the given outputs; a status for tx_info other than 200 makes that answer
a partial one.
-}
koiosRunWith :: Maybe Int -> ConwayTx -> Shown -> IO (Either Refusal Settlement, [Wire.Call])
koiosRunWith txInfoStatus tx shown = do
    (result, calls, _, _) <- koiosRunTimed (\_ _ -> TimeOk) txInfoStatus tx shown
    pure (result, calls)

{- | The same, with what a read of the time source does by whether an answer
marked partial has been sent and by how many reads came before; and how many
reads of it were made and where the clock ended.
-}
koiosRunTimed ::
    (Bool -> Int -> TimeBehavior) ->
    Maybe Int ->
    ConwayTx ->
    Shown ->
    IO (Either Refusal Settlement, [Wire.Call], Int, Integer)
koiosRunTimed script txInfoStatus tx shown = do
    run <- newRun startClock
    calls <- newIORef []
    marked <- newIORef False
    source <- preprodSource
    time <- preprodTime
    let service = Service (runNow run) calls marked
        client = Client.Koios Client.defaultClientConfig (Client.Transport (serviceAnswer service txInfoStatus shown))
        loadSource = do
            sent <- readIORef marked
            count <- readIORef (runTimeReads run)
            fmap (fmap (const source)) (timeRead run{runTime = \_ _ -> script sent (count + 1)})
    result <- koiosSettlement client time loadSource (Network 1) (scriptedRuntime run startClock 1_000) tx
    (,,,) result <$> readIORef calls <*> readIORef (runTimeReads run) <*> readIORef (runNow run)

serviceAnswer :: Service -> Maybe Int -> Shown -> Client.RawRequest -> IO Client.Exchange
serviceAnswer service txInfoStatus shown request = do
    now <- readIORef (serviceNow service)
    modifyIORef' (serviceCalls service) (<> [Client.rawCall request])
    let visible = maybe False (now >=) (shownFrom shown)
        produced = shownTx shown
        rows = [pair | pair@(TxIn _ (TxIx index), _) <- outputsOf produced, toInteger index `elem` shownIndexes shown]
    when (Client.rawCall request == Wire.CallTxInfo && visible && isJust txInfoStatus) (writeIORef (serviceMarked service) True)
    pure $ case Client.rawCall request of
        Wire.CallTip ->
            okJson
                200
                []
                ( jsonBytes
                    [ object
                        [ "abs_slot" .= (68_774_400 :: Integer)
                        , "hash" .= T.replicate 32 "ab"
                        , "block_height" .= (1 :: Int)
                        , "epoch_no" .= (0 :: Int)
                        , "block_time" .= (now `div` 1000)
                        ]
                    ]
                )
        Wire.CallTxInfo ->
            okJson
                (if visible then fromMaybe 200 txInfoStatus else 200)
                (if visible then maybe [] (const [("content-range", "0-0/*")]) txInfoStatus else [])
                (jsonBytes [infoRow produced | visible])
        Wire.CallAddressUtxos ->
            pageAnswer [addressRow pair | visible, pair <- rows]
        _ -> Client.singleExchange (Left (Client.NoRecording "unexpected endpoint"))

okJson :: Int -> [(Text, Text)] -> ByteString -> Client.Exchange
okJson status headers body =
    Client.singleExchange . Right $
        Client.Answer
            { Client.answerStatus = status
            , Client.answerHeaders = ("content-type", "application/json") : headers
            , Client.answerBody = body
            }

-- | The honest page of these rows, with the range header the service sends.
pageAnswer :: [Value] -> Client.Exchange
pageAnswer rows =
    okJson
        200
        [("content-range", range)]
        (jsonBytes rows)
  where
    total = T.pack (show (length rows))
    range
        | null rows = "*/0"
        | otherwise = "0-" <> T.pack (show (length rows - 1)) <> "/" <> total

jsonBytes :: [Value] -> ByteString
jsonBytes = LBS.toStrict . encode

infoRow :: ConwayTx -> Value
infoRow tx =
    object
        [ "tx_hash" .= Wire.txIdHex (txIdTx tx)
        , "block_height" .= (20 :: Int)
        , "inputs" .= ([] :: [Value])
        , "reference_inputs" .= ([] :: [Value])
        , "outputs" .= map outputRow (outputsOf tx)
        , "valid_contract" .= True
        ]

outputRow :: (TxIn, TxOut ConwayEra) -> Value
outputRow (TxIn key (TxIx index), output) =
    let MaryValue (Coin amount) _ = output ^. valueTxOutL
     in object
            [ "tx_hash" .= Wire.txIdHex key
            , "tx_index" .= index
            , "payment_addr" .= object ["bech32" .= Wire.renderAddress address]
            , "value" .= show amount
            , "asset_list" .= ([] :: [Value])
            ]

addressRow :: (TxIn, TxOut ConwayEra) -> Value
addressRow pair = case outputRow pair of
    Object fields -> Object (KM.insert "address" (String (Wire.renderAddress address)) fields)
    other' -> other'
