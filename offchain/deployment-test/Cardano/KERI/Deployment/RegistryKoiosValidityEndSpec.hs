{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryKoiosValidityEndSpec
Description : Every transaction of @ckeri registry deploy@ carries public Singular's finite validity end, and what is not seen is unconfirmed

The command is run whole, on the node socket and on Koios, with the same window: public
Singular's window from the tip over its usual span, over a network time the test chooses.
On Koios it runs with the production settlement over an in-memory service that shows what
the chain included. The one thing the test moves is the tip: from one handoff to the next,
past a transaction's window, or not at all. What is checked is what the command hands over
(the bodies of the signed transactions, and what the command reports of them), how far it
gets, and what it says where it stops: a transaction that was not seen is unconfirmed, with
its identifier and the possibility that it is included, whatever the chain holds.
-}
module Cardano.KERI.Deployment.RegistryKoiosValidityEndSpec (spec) where

import Cardano.KERI.Deployment.KoiosSettlement (koiosSettlement)
import Cardano.KERI.Deployment.KoiosSettlementSpec (jsonBytes, okJson, pageAnswer)
import Cardano.KERI.Deployment.KoiosStandIn (withStandIn)
import Cardano.KERI.Deployment.RegistryChain (Observation (..), RegistryRuntime (..), ValidityEnd (..))
import Cardano.KERI.Deployment.RegistryKoiosCommandSpec (
    Case (..),
    Hooks (..),
    Wired (..),
    accepting,
    handedOver,
    idText,
    koiosAt,
    nodeChoice,
    wire,
    wireWith,
    withDeploy,
 )
import Cardano.KERI.Deployment.RegistryWindow (installNodeWindow, installNodeWindowWith, koiosValidityEnd, resolveTimeSource)
import Cardano.KERI.Deployment.TestNetworkTime (TestNetwork (..), testNetworkTime, testTimeSource, writeTimeSource)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Api.Tx (bodyTxL, txIdTx)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, outputsTxBodyL, vldtTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, coinTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (SlotNo (..))
import Control.Applicative ((<|>))
import Control.Exception (Exception, SomeException, bracket, throwIO, try)
import Control.Monad (forM_, when)
import Data.Aeson (Value (Object), object, (.=))
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf, isPrefixOf, stripPrefix)
import Data.Maybe (mapMaybe)
import Data.Sequence.Strict qualified as StrictSeq
import Data.Text qualified as T
import Lens.Micro ((%~), (&), (.~), (^.))
import Singular.Provider.Koios.Client qualified as Client
import Singular.Provider.Koios.Wire qualified as Wire
import Singular.Registry.Confirmation (ConfirmationRuntime (..))
import Singular.Registry.LedgerProvider (Network (..))
import Singular.Registry.NetworkTime (NetworkTime, NetworkTimeManifest (..), slotStartMs)
import Singular.Registry.TimeSource (TimeSource (..))
import Singular.Registry.Wait (WaitFailure (..), WaitStage (..))
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

-- ---------------------------------------------------------------------
-- The networks
-- ---------------------------------------------------------------------

-- | A network of the shape of preprod: a slot a second, a horizon far beyond an hour.
longNetwork :: TestNetwork
longNetwork = TestNetwork{slotSeconds = 1, epochLength = 432_000, securityParam = 2_160, activeSlotsCoeff = 0.05, zeroMs = 1_790_000_000_000, laterEra = Nothing}

{- | A network whose horizon is near: the ledger converts only to the end of the epoch that holds the slot
thirty after the tip, and an epoch is five hundred slots.
-}
shortNetwork :: TestNetwork
shortNetwork = longNetwork{epochLength = 500, securityParam = 10, activeSlotsCoeff = 1.0}

-- | A network whose slot is an hour long: an hour from the tip is the next slot, which is not usable.
hourSlotNetwork :: TestNetwork
hourSlotNetwork = longNetwork{slotSeconds = 3_600, zeroMs = 1_000_000_000_000}

{- | A network whose slot length changes inside the hour: slots of a second until the end of the second epoch, slot
two thousand, then slots of two seconds.
-}
changingNetwork :: TestNetwork
changingNetwork = longNetwork{epochLength = 1_000, laterEra = Just (2, 2)}

-- | The block hash the service gives its tip.
tipHash :: T.Text
tipHash = T.replicate 32 "ab"

-- ---------------------------------------------------------------------
-- The service
-- ---------------------------------------------------------------------

data Env = Env
    { envTime :: NetworkTime
    , envTip :: IORef Integer
    -- ^ the slot the provider's tip is at
    , envClock :: IORef Integer
    -- ^ the machine's clock, in POSIX milliseconds
    , envClockStep :: Integer
    -- ^ what one second of polling costs the clock, in milliseconds
    , envJump :: Integer
    -- ^ the slots the tip moves by whenever polling pauses
    , envHidden :: Bool
    -- ^ the provider shows no transaction
    , envTipShape :: (Int, [(T.Text, T.Text)])
    -- ^ the status and the headers of the provider's answer to the tip
    , envAccepted :: IO [ConwayTx]
    -- ^ what the chain included
    }

-- | What the provider shows of the chain.
visible :: Env -> IO [ConwayTx]
visible env = if envHidden env then pure [] else envAccepted env

outputsOf :: ConwayTx -> [(TxIn, TxOut ConwayEra)]
outputsOf tx =
    [ (TxIn (txIdTx tx) (TxIx index), output)
    | (index, output) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
    ]

outputRow :: (TxIn, TxOut ConwayEra) -> Value
outputRow (TxIn key (TxIx index), output) =
    let Coin amount = output ^. coinTxOutL
     in object
            [ "tx_hash" .= Wire.txIdHex key
            , "tx_index" .= index
            , "payment_addr" .= object ["bech32" .= Wire.renderAddress (output ^. addrTxOutL)]
            , "value" .= show amount
            , "asset_list" .= ([] :: [Value])
            ]

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

addressRow :: (TxIn, TxOut ConwayEra) -> Value
addressRow pair@(_, output) = case outputRow pair of
    Object fields -> Object (fields <> addressField)
    other -> other
  where
    addressField = case object ["address" .= Wire.renderAddress (output ^. addrTxOutL)] of
        Object field -> field
        _ -> mempty

{- | The answers of the service: the tip where the test put it, the transactions the chain included, no other, and
no answer to a question the command has no reason to ask, such as whether a transaction is on the chain by its status.
-}
transport :: Env -> Client.RawRequest -> IO Client.Exchange
transport env request = do
    slot <- readIORef (envTip env)
    shown <- visible env
    let asked = show (Client.rawBody request)
        produced = [tx | tx <- shown, T.unpack (Wire.txIdHex (txIdTx tx)) `isInfixOf` asked]
    pure $ case Client.rawCall request of
        Wire.CallTip ->
            case slotStartMs (envTime env) (SlotNo (fromInteger slot)) of
                Right start ->
                    uncurry
                        okJson
                        (envTipShape env)
                        ( jsonBytes
                            [ object
                                [ "abs_slot" .= slot
                                , "hash" .= tipHash
                                , "block_height" .= (1 :: Int)
                                , "epoch_no" .= (0 :: Int)
                                , "block_time" .= (start `div` 1_000)
                                ]
                            ]
                        )
                Left failure -> Client.singleExchange (Left (Client.NoRecording (T.pack (show failure))))
        Wire.CallTxInfo -> okJson 200 [] (jsonBytes (map infoRow produced))
        Wire.CallAddressUtxos ->
            pageAnswer
                [ addressRow pair
                | tx <- shown
                , pair@(_, output) <- outputsOf tx
                , T.unpack (Wire.renderAddress (output ^. addrTxOutL)) `isInfixOf` asked
                ]
        _ -> Client.singleExchange (Left (Client.NoRecording "an endpoint the test does not serve"))

data BoundReached = BoundReached
    deriving stock (Show)

instance Exception BoundReached

{- | Singular's confirmation effects as the test moves them: polling pauses move the clock, and the tip by
the test's jump, and a wait whose clock passes its bound ends as a wait that ran out.
-}
confirmation :: Env -> IO (ConfirmationRuntime IO)
confirmation env = do
    waitStart <- newIORef 0
    waitBound <- newIORef (maxBound :: Int)
    pure
        ConfirmationRuntime
            { currentPosixMs = readIORef (envClock env)
            , attemptWindowRead = fmap Right
            , pausePolling = \seconds -> do
                modifyIORef' (envClock env) (+ toInteger seconds * envClockStep env)
                modifyIORef' (envTip env) (+ envJump env)
                now <- readIORef (envClock env)
                started <- readIORef waitStart
                bound <- readIORef waitBound
                when (now - started >= toInteger bound * 1_000) (throwIO BoundReached)
            , boundedConfirmation = \tid bound action -> do
                started <- readIORef (envClock env)
                writeIORef waitStart started
                writeIORef waitBound bound
                outcome <- try action
                ended <- readIORef (envClock env)
                writeIORef waitBound maxBound
                let failure = WaitFailure SessionConfirmationWait tid (fromInteger (ended - started) / 1_000) bound
                pure $ case outcome of
                    Left BoundReached -> Left (failure Nothing)
                    Right (Left deadline) -> Left (failure (Just deadline))
                    Right (Right answer) -> Right answer
            }

-- ---------------------------------------------------------------------
-- A run
-- ---------------------------------------------------------------------

data Provider = OnNode | OnKoios
    deriving stock (Eq, Show)

data Setup = Setup
    { setNetwork :: TestNetwork
    , setStartSlot :: Integer
    , setStep :: Integer
    -- ^ the slots the tip moves by as each transaction is handed over
    , setJump :: Integer
    , setClockStep :: Integer
    , setHidden :: Bool
    , setTipShape :: (Int, [(T.Text, T.Text)])
    -- ^ the status and the headers of the provider's answer to the tip
    , setIncluded :: Bool
    -- ^ the chain includes what the provider accepted
    , setNoWindowFrom :: Maybe Int
    -- ^ the build from which the window is not usable, whatever the tip
    , setSupplyEnd :: Bool
    {- ^ a transaction the deployment built without an end is given one before it is signed: the report of what is not
    seen is then the subject whatever the deployment builds
    -}
    }

standard :: Setup
standard =
    Setup
        { setNetwork = longNetwork
        , setStartSlot = 100_000
        , setStep = 10
        , setJump = 0
        , setClockStep = 1_000
        , setHidden = False
        , setTipShape = (200, [])
        , setIncluded = True
        , setNoWindowFrom = Nothing
        , setSupplyEnd = False
        }

-- | What a run left.
data Ran = Ran
    { ranCode :: ExitCode
    , ranOut :: String
    , ranErr :: String
    , ranHanded :: [ConwayTx]
    -- ^ what the provider was handed (on the node: what the chain accepted)
    , ranAccepted :: [ConwayTx]
    -- ^ what the chain included
    , ranFiles :: [FilePath]
    -- ^ the deployment files that exist
    }

-- | The upper slot of a transaction's validity, if it has one.
upperOf :: ConwayTx -> Maybe Integer
upperOf tx = case invalidHereafter (tx ^. bodyTxL . vldtTxBodyL) of
    SJust (SlotNo upper) -> Just (toInteger upper)
    SNothing -> Nothing

{- | The transaction with an end an hour after the tip, if it had none: the change pays the few bytes more it
takes.
-}
supplyEnd :: IORef Integer -> ConwayTx -> IO ConwayTx
supplyEnd tip tx = do
    slot <- readIORef tip
    pure $ case upperOf tx of
        Nothing ->
            let outputs = toList (tx ^. bodyTxL . outputsTxBodyL)
                lowered = case reverse outputs of
                    change : earlier -> reverse ((change & coinTxOutL %~ (\(Coin c) -> Coin (c - 400))) : earlier)
                    [] -> []
             in tx
                    & bodyTxL . vldtTxBodyL .~ ValidityInterval SNothing (SJust (SlotNo (fromInteger (slot + 3_600))))
                    & bodyTxL . feeTxBodyL %~ (\(Coin f) -> Coin (f + 400))
                    & bodyTxL . outputsTxBodyL .~ StrictSeq.fromList lowered
        Just _ -> tx

-- | The first transaction handed over.
firstOf :: Ran -> IO ConwayTx
firstOf ran = case ranHanded ran of
    tx : _ -> pure tx
    [] -> fail "the command handed nothing over"

run :: Provider -> Setup -> IO Ran
run OnKoios = runKoios
run OnNode = runNode

-- | The count of the calls so far, then one more.
counted :: IORef Int -> IO Int
counted ref = modifyIORef' ref (+ 1) >> subtract 1 <$> readIORef ref

-- | The window of a build, unusable from the build the setup names.
limited :: Setup -> IORef Int -> IO ValidityEnd -> IO ValidityEnd
limited setup builds window = do
    n <- counted builds
    case setNoWindowFrom setup of
        Just from | n >= from -> pure NoUsableWindow
        _ -> window

filesOf :: Case -> IO [FilePath]
filesOf c = fmap concat . traverse (\path -> (\there -> [path | there]) <$> doesFileExist path) $ [caseDirectory c </> "release-identity.json", caseDirectory c </> "reference-outputs.json"]

runKoios :: Setup -> IO Ran
runKoios setup = withDeploy $ \c -> do
    time <- testNetworkTime (setNetwork setup)
    tip <- newIORef (setStartSlot setup)
    clock <- newIORef (zeroMs (setNetwork setup) + setStartSlot setup * 1_000)
    let env =
            Env
                { envTime = time
                , envTip = tip
                , envClock = clock
                , envClockStep = setClockStep setup
                , envJump = setJump setup
                , envHidden = setHidden setup
                , envTipShape = setTipShape setup
                , envAccepted = caseLanded c
                }
        source = testTimeSource (setNetwork setup)
        client = Client.Koios Client.defaultClientConfig (Client.Transport (transport env))
        network = Network 42
        loaded = pure (Right source)
    runtime <- confirmation env
    builds <- newIORef (0 :: Int)
    let hooks =
            Hooks
                { hookSettle = koiosSettlement client time loaded network runtime
                , hookWindow = limited setup builds (koiosValidityEnd client loaded network)
                , hookAfterHandoff = \_ -> modifyIORef' tip (+ setStep setup)
                , hookIncludes = pure (setIncluded setup)
                , hookPrepare = if setSupplyEnd setup then supplyEnd tip else pure
                }
        base = caseRuntime c
    withStandIn accepting $ \url seen -> do
        wired <- wireWith hooks 3 base (casePayer c)
        (code, out, err) <- caseRun c (wiredOpeners wired) (koiosAt url)
        requests <- seen
        accepted <- caseLanded c
        files <- filesOf c
        pure Ran{ranCode = code, ranOut = out, ranErr = err, ranHanded = handedOver requests, ranAccepted = accepted, ranFiles = files}

{- | The deployment on the node socket: the chain's runtime with the observation the node would give, the production
installation of the window over the node's own tip, and a tip that moves as each transaction is submitted.
-}
runNode :: Setup -> IO Ran
runNode setup = withDeploy $ \c -> do
    tip <- newIORef (setStartSlot setup)
    builds <- newIORef (0 :: Int)
    let zero = zeroMs (setNetwork setup)
        observe = do
            slot <- readIORef tip
            pure
                Observation
                    { obsTipSlot = SlotNo (fromInteger slot)
                    , obsTipStartMs = zero + slot * 1_000
                    , obsSlotLengthMs = 1_000
                    , obsClockMs = zero + slot * 1_000
                    , obsHorizonSlot = SlotNo (fromInteger slot + 1)
                    }
        transactions = rtTransactions (caseRuntime c)
        lookedAt =
            (caseRuntime c)
                { rtObserve = observe
                , rtTransactions = transactions{trSubmit = \tx -> modifyIORef' tip (+ setStep setup) >> trSubmit transactions tx}
                }
        installed = installNodeWindowWith (pure (Right (testTimeSource (setNetwork setup)))) (Network 42) lookedAt
        base = installed{rtValidityEnd = limited setup builds (rtValidityEnd installed)}
    wired <- wire 3 (\_ -> pure (Left (error "no settlement on the node"))) base (casePayer c)
    (code, out, err) <- caseRun c (wiredOpeners wired) nodeChoice
    accepted <- caseLanded c
    files <- filesOf c
    pure Ran{ranCode = code, ranOut = out, ranErr = err, ranHanded = accepted, ranAccepted = accepted, ranFiles = files}

-- | The tip each build saw: the start, and a step further for each transaction handed over before it.
tipOfBuild :: Setup -> Int -> Integer
tipOfBuild setup n = setStartSlot setup + setStep setup * toInteger n

-- | The ends each landed line of the command's report names, in order.
reportedEnds :: String -> [String]
reportedEnds out = mapMaybe (fmap (takeWhile (/= ' ')) . endOf) (lines out)
  where
    endOf = go
      where
        go [] = Nothing
        go candidate@(_ : more) = stripPrefix " valid-until-slot=" candidate <|> go more

-- ---------------------------------------------------------------------
-- The cases
-- ---------------------------------------------------------------------

spec :: Spec
spec = describe "#546 registry deploy: every transaction carries public Singular's finite validity end, and what is not seen is unconfirmed" $ do
    forM_ [("the node socket", OnNode), ("Koios, under the production settlement", OnKoios)] $ \(name, provider) ->
        describe name (endsSpec provider)
    timeSourceSpec
    unconfirmedSpec
    partialTipSpec

endsSpec :: Provider -> Spec
endsSpec provider = do
    it "hands over all seven transactions, each valid until one hour after the tip of its own build, and creates the registry" $ do
        ran <- run provider standard
        ranErr ran `shouldSatisfy` (not . ("stopped" `isInfixOf`))
        ranCode ran `shouldBe` ExitSuccess
        length (ranHanded ran) `shouldBe` 7
        map upperOf (ranHanded ran) `shouldBe` [Just (tipOfBuild standard n + 3_600) | n <- [0 .. 6]]
        length (ranFiles ran) `shouldBe` 2
    it "reports each landed transaction with the end its signed body carries" $ do
        ran <- run provider standard
        ranCode ran `shouldBe` ExitSuccess
        reportedEnds (ranOut ran) `shouldBe` [show (tipOfBuild standard n + 3_600) | n <- [0 .. 6]]
    it "reads the window again at each build: the ends differ as the tip moves, and no two transactions share one" $ do
        ran <- run provider standard{setStep = 25}
        ranCode ran `shouldBe` ExitSuccess
        let ends = map upperOf (ranHanded ran)
        length ends `shouldBe` 7
        length (distinct ends) `shouldBe` 7
    it "is cut by the ledger's horizon where the horizon is near: the last slot the ledger converts, below one hour" $ do
        ran <- run provider standard{setNetwork = shortNetwork, setStartSlot = 100}
        ranCode ran `shouldBe` ExitSuccess
        length (ranHanded ran) `shouldBe` 7
        map upperOf (ranHanded ran) `shouldBe` replicate 7 (Just 499)
    it "converts the instant an hour after the tip through the network's time: a slot that changes its length inside the hour is not extrapolated" $ do
        ran <- run provider standard{setNetwork = changingNetwork, setStartSlot = 1_500}
        ranCode ran `shouldBe` ExitSuccess
        -- the first era ends at slot 2,000, the instant 2,000 s; the instant an hour after the tip's start is 5,100 s,
        -- in the second era, whose slots last two seconds: slot 2,000 + (5,100 - 2,000) / 2
        map upperOf (ranHanded ran) `shouldBe` [Just (3_550 + 5 * toInteger n) | n <- [0 .. 6 :: Int]]
        map upperOf (ranHanded ran) `shouldNotBe` [Just (tipOfBuild standard{setStartSlot = 1_500} n + 3_600) | n <- [0 .. 6]]
    it "refuses the first publication by name, and hands over nothing, when no window from the tip is usable" $ do
        ran <- run provider standard{setNetwork = hourSlotNetwork, setStartSlot = 1_000}
        ranCode ran `shouldBe` ExitFailure 1
        ranErr ran `shouldSatisfy` ("no-usable-window" `isInfixOf`)
        ranErr ran `shouldSatisfy` ("stopped at: publish-state-template" `isInfixOf`)
        length (ranHanded ran) `shouldBe` 0
        length (ranAccepted ran) `shouldBe` 0
    it "refuses a later step by name, before handing it over, and still reports what landed before it" $ do
        ran <- run provider standard{setNoWindowFrom = Just 2}
        ranCode ran `shouldBe` ExitFailure 1
        ranErr ran `shouldSatisfy` ("no-usable-window" `isInfixOf`)
        ranErr ran `shouldSatisfy` ("stopped at: publish-application" `isInfixOf`)
        length (ranHanded ran) `shouldBe` 2
        let landed = [line | line <- lines (ranErr ran), "landed: " `isPrefixOf` line]
        length landed `shouldBe` 2
        mapM_ (\tx -> ranErr ran `shouldSatisfy` (idText tx `isInfixOf`)) (ranHanded ran)
  where
    distinct = foldr (\x seen -> if x `elem` seen then seen else x : seen) []

{- | The network time a command is given: the directory the settings name (the option, else the variable, which the
command line reads), else preprod's pinned package. Below the command line the directory is the only thing given.
-}
timeSourceSpec :: Spec
timeSourceSpec = describe "the network time of a command" $ do
    it "is the directory given, as public Singular reads it, whatever the variable holds" $
        withSystemTempDirectory "network-time" $ \directory -> withSystemTempDirectory "other-time" $ \other -> do
            writeTimeSource directory changingNetwork
            writeTimeSource other hourSlotNetwork
            withTimeVariable (Just other) $ do
                resolved <- resolveTimeSource 42 (Just directory)
                case resolved of
                    Right (TimeSource manifest _ _) -> do
                        timeNetworkMagic manifest `shouldBe` 42
                        timeSystemStartMs manifest `shouldBe` zeroMs changingNetwork
                    Left failure -> expectationFailure ("the source named was not read: " <> show failure)
    it "is preprod's pinned package for preprod when no directory is given, whatever the variable holds" $
        withSystemTempDirectory "other-time" $ \other -> do
            writeTimeSource other hourSlotNetwork
            withTimeVariable (Just other) $ do
                resolved <- resolveTimeSource 1 Nothing
                case resolved of
                    Right (TimeSource manifest _ _) -> timeNetworkMagic manifest `shouldBe` 1
                    Left failure -> expectationFailure ("preprod's package was not read: " <> show failure)
    it "is refused for another network when no directory is given: no time is made up" $
        withTimeVariable Nothing $ do
            resolved <- resolveTimeSource 42 Nothing
            either (const True) (const False) resolved `shouldBe` True
    it "gives the node's window the directory the node command is given" $
        withSystemTempDirectory "network-time" $ \directory -> do
            writeTimeSource directory longNetwork
            withTimeVariable Nothing $ withDeploy $ \c -> do
                let observe =
                        pure
                            Observation
                                { obsTipSlot = SlotNo 100_000
                                , obsTipStartMs = zeroMs longNetwork + 100_000 * 1_000
                                , obsSlotLengthMs = 1_000
                                , obsClockMs = zeroMs longNetwork + 100_000 * 1_000
                                , obsHorizonSlot = SlotNo 100_001
                                }
                    installed = installNodeWindow 42 (Just directory) (caseRuntime c){rtObserve = observe}
                end <- rtValidityEnd installed
                end `shouldBe` EndAt (SlotNo 103_600)

-- | An action with the variable set, or removed, and the variable as it was afterwards.
withTimeVariable :: Maybe FilePath -> IO a -> IO a
withTimeVariable wanted action =
    bracket
        (lookupEnv name <* maybe (unsetEnv name) (setEnv name) wanted)
        (maybe (unsetEnv name) (setEnv name))
        (const action)
  where
    name = "SINGULAR_NETWORK_TIME"

-- | The words a report of a transaction that was not seen may not use: it concludes nothing of the chain or of payment.
concludesNothing :: String -> Bool
concludesNothing err = not (any (`isInfixOf` err) ["unpaid", "not paid", "was not paid", "expired", "not included", "no longer be included"])

-- | The unconfirmed report of a transaction: its identifier, that it was not seen before its deadline, that it may still be included.
unconfirmedFor :: ConwayTx -> String -> Bool
unconfirmedFor tx err =
    all
        (`isInfixOf` err)
        [ "unconfirmed: " <> idText tx
        , "was not seen before its deadline"
        , "may still be included"
        , "by its identifier before anything is built again"
        ]

{- | A transaction that was not seen is unconfirmed whatever the chain holds. The two truths a fixture can build are
a transaction included behind a lagging index and a transaction that was never included, each with the provider's
tip before the end of its window and after it: the command says the same in all four, word for word.
-}
unconfirmedSpec :: Spec
unconfirmedSpec = describe "a transaction the provider did not show" $ do
    let truths = [("included behind a lagging index", True), ("never included", False)]
        timings = [("its window not over", standard{setClockStep = 6_000_000}), ("its window over", standard{setJump = 10_000})]
    forM_ truths $ \(truth, included) ->
        forM_ timings $ \(timing, base) ->
            it ("is unconfirmed, with its identifier and the possibility that it is included, nothing resent and nothing rebuilt: " <> truth <> ", " <> timing) $ do
                ran <- run OnKoios base{setSupplyEnd = True, setHidden = True, setIncluded = included}
                ranCode ran `shouldBe` ExitFailure 1
                first' <- firstOf ran
                length (ranAccepted ran) `shouldBe` (if included then 1 else 0)
                length (ranHanded ran) `shouldBe` 1
                ranErr ran `shouldSatisfy` unconfirmedFor first'
                ranErr ran `shouldSatisfy` ("no other transaction was built or signed" `isInfixOf`)
                ranErr ran `shouldSatisfy` concludesNothing
    forM_ timings $ \(timing, base) ->
        it ("says the same of both truths, word for word: " <> timing) $ do
            included <- run OnKoios base{setSupplyEnd = True, setHidden = True, setIncluded = True}
            absent <- run OnKoios base{setSupplyEnd = True, setHidden = True, setIncluded = False}
            ranErr included `shouldBe` ranErr absent
            ranOut included `shouldBe` ranOut absent

{- | The tip the window reads, when the provider says it is partial: the window is built only from a complete answer,
whatever else the service answers whole.
-}
partialTipSpec :: Spec
partialTipSpec = describe "a tip the provider answers partially" $ do
    forM_ partialTips $ \(name, shape) -> do
        it ("is refused by the window itself, and no end is made of it: " <> name) $ do
            time <- testNetworkTime longNetwork
            tip <- newIORef standardSlot
            clock <- newIORef (zeroMs longNetwork + standardSlot * 1_000)
            let env = Env{envTime = time, envTip = tip, envClock = clock, envClockStep = 1_000, envJump = 0, envHidden = False, envTipShape = shape, envAccepted = pure []}
                client = Client.Koios Client.defaultClientConfig (Client.Transport (transport env))
            outcome <- try (koiosValidityEnd client (pure (Right (testTimeSource longNetwork))) (Network 42))
            case outcome of
                Right end -> expectationFailure ("a window was made of a partial tip: " <> show end)
                Left failure -> show (failure :: SomeException) `shouldSatisfy` (not . null)
        it ("stops the deployment at its first publication by name, before anything is handed over: " <> name) $ do
            ran <- run OnKoios standard{setTipShape = shape}
            ranCode ran `shouldBe` ExitFailure 1
            ranErr ran `shouldSatisfy` ("stopped at: publish-state-template" `isInfixOf`)
            length (ranHanded ran) `shouldBe` 0
            length (ranAccepted ran) `shouldBe` 0
    it "answers a whole tip as it did: the same run with the status 200 hands over its seven transactions" $ do
        ran <- run OnKoios standard
        ranCode ran `shouldBe` ExitSuccess
        length (ranHanded ran) `shouldBe` 7
  where
    standardSlot = setStartSlot standard
    partialTips =
        [ ("the status 206", (206, []))
        , ("a range that starts after the first row", (200, [("content-range", "5-5/10")]))
        ]
