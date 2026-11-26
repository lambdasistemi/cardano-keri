{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryBookingChain
Description : A deployed registry on a chain that keeps its outputs, with a clock

The specs of booking and folding need a registry that @ckeri registry deploy@ created.
This one is made by the deployment itself on the chain of
"Cardano.KERI.Deployment.RegistryDeploySpec": a chain that keeps its unspent
outputs and refuses a transaction that spends what is not there or does not
balance. It runs no script, so what it cannot show (that the registry's scripts
accept a booking or a fold) is shown on the devnet only.

The clock is a slot counter the specs move; a slot starts a fixed span after
the previous one.
-}
module Cardano.KERI.Deployment.RegistryBookingChain (
    World (..),
    newWorld,
    runtimeOf,
    runtimeOfUnder,
    folderAddress,
    folderOutputs,
    originMs,
    slotStart,
    setTip,
    setHorizon,
    observationsMade,
    clockNow,
    loadExport,
    registerRequestOf,
    keyOf,
    registryOf,
    accepted,
    submissionsMade,
    stateOutputOf,
    checkpointHolding,
    holdsToken,
    plantCheckpoint,
    stripApproval,
    reshape,
    advanceClock,
    failStateReadsFrom,
    failingObservation,
    failingObservationBy,
    failingSettlementBy,
    failStateReadsWith,
    StandIn (..),
    newStandIn,
    connectionEnds,
    Call (..),
    handoffsCounted,
    countHandoffsInto,
    endingAt,
    withClient,
    withinOneMinute,
    Ending (..),
    ScriptedClient (..),
    withScriptedClient,
    AcquiredCase (..),
    runAcquiredCase,
    awaitWitness,
    acquiringReads,
    receiptLinesOf,
    bookDirectly,
    worldDeployment,
    worldReferences,
    checkpointAddressOf,
    setRegistryRoot,
    moveRegistryRoot,
    copyChain,
    proofOutputOf,
    removeOutput,
) where

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Application (
    RegistrationData,
    RegistryIdentity (..),
    activeTokenName,
    stateDatumData,
    stateTokenName,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..), liveOfKeyState)
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.KEL (InceptionExport (..), parseInceptionExport)
import Cardano.KERI.Deployment.Registry (deriveRegistryScripts, registryInitialFloor)
import Cardano.KERI.Deployment.RegistryChain (Observation (..), RegistryRuntime (..), ValidityEnd (..), feeOf, txInOfReference, whileConnected)
import Cardano.KERI.Deployment.RegistryDeploy (DeployRequest (..), Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (
    Chain (..),
    Faults,
    chainRuntime,
    deployOn,
    loadTestBlueprint,
    newChain,
    noFaults,
    pricedParameters,
    testTerms,
    walletAddress,
    walletOutputs,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord (..), ScriptReference (..))
import Cardano.KERI.Deployment.RegistryRegister (RegisterRequest (..))
import Cardano.KERI.Deployment.RegistryTransactions (registryRootOf)
import Cardano.KERI.Deployment.RegistryTransactions qualified as Tx
import Cardano.KERI.Deployment.Script (Blueprint)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, coinTxOutL, datumTxOutL, mkBasicTxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.N2C.Connection (newLSQChannel)
import Cardano.Node.Client.N2C.LocalStateQuery (mkLocalStateQueryClient, monitorLocalStateQueryConnection)
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Types (ConnectionLost (..))
import Cardano.Node.Client.Provider (Provider (..), SlotNo (..))
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Control.Concurrent (newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Concurrent.Async (async, pollSTM, uninterruptibleCancel, wait, withAsync)
import Control.Exception (SomeException, throwIO, toException, try)
import Control.Monad (forever, unless, void, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (fromLeft)
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, fromMaybe, listToMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import GHC.Clock (getMonotonicTime)
import GHC.Conc (STM, TVar, atomically, newTVarIO, readTVar, retry, writeTVar)
import Lens.Micro ((&), (.~), (^.))
import Ouroboros.Network.Protocol.LocalStateQuery.Client (
    ClientStAcquired (..),
    ClientStAcquiring (..),
    ClientStIdle (..),
    LocalStateQueryClient (..),
 )
import Paths_cardano_keri (getDataFileName)
import System.Timeout (timeout)
import Test.Hspec (expectationFailure)

-- | A deployed registry, its chain and its clock.
data World = World
    { worldChain :: !(IORef Chain)
    , worldTip :: !(IORef Integer)
    -- ^ the slot of the tip
    , worldSlotMs :: !Integer
    -- ^ how long a slot lasts
    , worldElapsed :: !(IORef Integer)
    -- ^ the milliseconds that have passed since the tip, a half second for each signature
    , worldObservations :: !(IORef Int)
    -- ^ how many times a decision read the tip, the clock and the horizon
    , worldHorizon :: !(IORef Integer)
    -- ^ how many slots past the tip the node can convert
    , worldDeployed :: !Deployed
    , worldBlueprint :: !Blueprint
    }

-- | The wallet of the party that folds: it is not the wallet of the one that books.
folderAddress :: Addr
folderAddress =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromBytes (BS.replicate 28 0x22)))))
        StakeRefNull

folderOutputs :: [(TxIn, TxOut ConwayEra)]
folderOutputs =
    [ (folderIn 0xb1, mkBasicTxOut folderAddress (inject (Coin 50_000_000)))
    , (folderIn 0xb2, mkBasicTxOut folderAddress (inject (Coin 80_000_000)))
    , (folderIn 0xb3, mkBasicTxOut folderAddress (inject (Coin 20_000_000)))
    ]
  where
    folderIn n =
        TxIn
            (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 n)))))
            (TxIx 0)

-- | The instant slot 0 starts.
originMs :: Integer
originMs = 1_800_000_000_000

slotStart :: Integer -> Integer -> Integer
slotStart slotMs slot = originMs + slot * slotMs

-- | A registry deployed on a fresh chain whose slots last the given span.
newWorld :: Integer -> IO World
newWorld slotMs = do
    blueprint <- loadTestBlueprint
    chainRef <- newIORef (newChain (walletOutputs <> folderOutputs))
    outcome <-
        deployOn
            noFaults
            chainRef
            DeployRequest
                { requestTerms = testTerms
                , requestBlueprint = blueprint
                , requestPayer = walletAddress
                , requestReferenceLovelace = Nothing
                }
    deployed <- either (fail . show) pure outcome
    tip <- newIORef 10_000
    horizon <- newIORef 1_000_000
    elapsed <- newIORef 0
    observations <- newIORef 0
    pure (World chainRef tip slotMs elapsed observations horizon deployed blueprint)

setTip :: World -> Integer -> IO ()
setTip world = writeIORef (worldTip world)

-- | The node can convert this many slots past the tip, and no more.
setHorizon :: World -> Integer -> IO ()
setHorizon world = writeIORef (worldHorizon world)

-- | The runtime over the world, with the faults of the chain.
runtimeOf :: Faults -> World -> RegistryRuntime
runtimeOf faults world = runtimeOfUnder faults world (worldChain world)

{- | The runtime reading outputs from one chain reference and submitting to the
world's: a read that is behind the chain is a runtime over an earlier copy.
-}
runtimeOfUnder :: Faults -> World -> IORef Chain -> RegistryRuntime
runtimeOfUnder faults world readRef =
    RegistryRuntime
        { rtNetwork = Testnet
        , rtUtxosAt = \address -> do
            chain <- readIORef readRef
            pure [(ref, out) | (ref, out) <- Map.toList (chainOutputs chain), out ^. addrTxOutL == address]
        , rtOutputs = \wanted -> do
            chain <- readIORef readRef
            pure (Map.restrictKeys (chainOutputs chain) wanted)
        , rtRewardRegistered = \account -> Set.member account . chainRegistered <$> readIORef readRef
        , rtTransactions = transactionsOf faults world
        , rtObserve = do
            modifyIORef' (worldObservations world) (+ 1)
            tip <- readIORef (worldTip world)
            elapsed <- readIORef (worldElapsed world)
            ahead <- readIORef (worldHorizon world)
            pure
                Observation
                    { obsTipSlot = SlotNo (fromInteger tip)
                    , obsTipStartMs = slotStart (worldSlotMs world) tip
                    , obsSlotLengthMs = worldSlotMs world
                    , obsClockMs = slotStart (worldSlotMs world) tip + 100 + elapsed
                    , obsHorizonSlot = SlotNo (fromInteger (tip + ahead))
                    }
        , rtNowMs = clockNow world
        , rtValidityEnd = pure EndNotSet
        }

transactionsOf :: Faults -> World -> TransactionRuntime IO
transactionsOf faults world =
    inner
        { trSign = \tx -> do
            modifyIORef' (worldElapsed world) (+ 500)
            trSign inner tx
        }
  where
    inner = rtTransactions (chainRuntime faults (worldChain world))

-- | The registry the deployment created, as its identity names it.
registryOf :: World -> RegistryIdentity
registryOf world =
    RegistryIdentity
        { registryStatePolicy = rlStatePolicy (riRelease identity)
        , registryName = stateTokenName (riSeed identity)
        }
  where
    identity = deployedIdentity (worldDeployed world)

-- | Whether an output holds one of the token of a policy and name.
holdsToken :: ByteString -> ByteString -> TxOut ConwayEra -> Bool
holdsToken policy name out = case out ^. valueTxOutL of
    MaryValue _ (MultiAsset assets) ->
        any
            ( \(PolicyID (ScriptHash hash), names) ->
                hashToBytes hash == policy
                    && Map.lookup (AssetName (SBS.toShort name)) names == Just 1
            )
            (Map.toList assets)

-- | The registry's state output, as the chain holds it.
stateOutputOf :: World -> IO (Maybe (TxIn, TxOut ConwayEra))
stateOutputOf world = do
    chain <- readIORef (worldChain world)
    let registry = registryOf world
    pure $
        listToMaybe
            [ held
            | held@(_, out) <- Map.toList (chainOutputs chain)
            , holdsToken (registryStatePolicy registry) (registryName registry) out
            ]

-- | The outputs that hold the active token of a key.
checkpointHolding :: World -> ByteString -> IO [(TxIn, TxOut ConwayEra)]
checkpointHolding world key = do
    chain <- readIORef (worldChain world)
    let registry = registryOf world
    pure
        [ held
        | held@(_, out) <- Map.toList (chainOutputs chain)
        , holdsToken (registryStatePolicy registry) (activeTokenName registry key) out
        ]

-- | A request to book an export with the wallet that books.
registerRequestOf :: World -> InceptionExport -> RegisterRequest
registerRequestOf world export =
    RegisterRequest
        { registerBlueprint = worldBlueprint world
        , registerIdentity = deployedIdentity (worldDeployed world)
        , registerRecord = deployedRecord (worldDeployed world)
        , registerExport = export
        , registerPayer = walletAddress
        , registerDeposit = Nothing
        }

-- | The key an export registers under.
keyOf :: InceptionExport -> ByteString
keyOf export = case liveOfKeyState "" 0 (inceptionDatum export) of
    Live{lvAid} -> lvAid
    TerminationPending{} -> error "keyOf: an inception is live"

loadExport :: FilePath -> IO InceptionExport
loadExport name = do
    path <- getDataFileName ("deployment-test/fixtures/" <> name)
    bytes <- BS.readFile path
    either fail pure (parseInceptionExport bytes)

-- | The transactions the chain accepted so far, oldest first.
accepted :: World -> IO [ConwayTx]
accepted world = reverse . chainAccepted <$> readIORef (worldChain world)

-- | How many submissions the chain has seen, accepted or refused.
submissionsMade :: World -> IO Int
submissionsMade world = chainSubmissions <$> readIORef (worldChain world)

-- | The checkpoint validator's address of the registry.
checkpointAddressOf :: World -> Addr
checkpointAddressOf world =
    Addr
        Testnet
        (ScriptHashObj (ScriptHash (fromJust (hashFromBytes (riCheckpointValidator (deployedIdentity (worldDeployed world)))))))
        StakeRefNull

{- | Put an output that holds the active token of a key at the checkpoint
validator's address, as a registration that was folded would have left it.
-}
plantCheckpoint :: World -> ByteString -> IO ()
plantCheckpoint world key = do
    let registry = registryOf world
        PolicyID policy = PolicyID (ScriptHash (fromJust (hashFromBytes (registryStatePolicy registry))))
        value =
            MaryValue
                (Coin 1_009_000_000)
                ( MultiAsset
                    (Map.singleton (PolicyID policy) (Map.singleton (AssetName (SBS.toShort (activeTokenName registry key))) 1))
                )
        planted = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xc7))))) (TxIx 0)
    modifyIORef' (worldChain world) $ \chain ->
        chain{chainOutputs = Map.insert planted (mkBasicTxOut (checkpointAddressOf world) value) (chainOutputs chain)}

-- | Make the chain forget an output, as if it had been spent.
removeOutput :: World -> TxIn -> IO ()
removeOutput world ref =
    modifyIORef' (worldChain world) $ \chain -> chain{chainOutputs = Map.delete ref (chainOutputs chain)}

{- | Book a registration with the library's own builder, as the controller's wallet
would: the setup of a fold that does not depend on the command that books. The
interval is five slots from the tip.
-}
bookDirectly :: World -> InceptionExport -> IO (TxIn, RegistrationData)
bookDirectly world export = do
    deployment <- worldDeployment world
    references <- worldReferences world
    chain <- readIORef (worldChain world)
    tip <- readIORef (worldTip world)
    let wallet = [(ref, out) | (ref, out) <- Map.toList (chainOutputs chain), out ^. addrTxOutL == walletAddress]
        validity =
            Tx.ValidityPlan
                { Tx.lowerSlot = SlotNo (fromInteger tip)
                , Tx.upperSlot = SlotNo (fromInteger tip + 5)
                , Tx.lowerPosixMs = slotStart (worldSlotMs world) tip
                , Tx.upperPosixMs = slotStart (worldSlotMs world) (tip + 5)
                }
        request = Tx.registrationRecord deployment walletAddress (registryInitialFloor testTerms) export validity
    let transactions = rtTransactions (chainRuntime noFaults (worldChain world))
        submit label tx =
            trSubmit transactions tx >>= \case
                Submitted txId -> pure txId
                Rejected reason -> fail (label <> " was refused: " <> show reason)
    -- the proof of the inception is preminted first, as the command does
    premint <-
        either (fail . show) pure $
            Tx.mintHashProof pricedParameters deployment (Tx.Payer walletAddress wallet) export validity
    premintId <- submit "the premint" premint
    chainAfter <- readIORef (worldChain world)
    let proofIn = (TxIn premintId (TxIx 0), fromJust (Map.lookup (TxIn premintId (TxIx 0)) (chainOutputs chainAfter)))
        walletAfter = [(ref, out) | (ref, out) <- Map.toList (chainOutputs chainAfter), out ^. addrTxOutL == walletAddress, ref /= fst proofIn]
    (tx, _) <-
        either (fail . show) pure $
            Tx.bookRegistrations pricedParameters deployment references (Tx.Payer walletAddress walletAfter) [Tx.BookedRequest request export proofIn] validity 0 Map.empty
    txId <- submit "the booking" tx
    pure (TxIn txId (TxIx 0), request)

-- | The output that holds the registry's state: its reference and its value.
stateAt :: World -> Chain -> Maybe (TxIn, TxOut ConwayEra)
stateAt world chain =
    listToMaybe
        [ held
        | held@(_, out) <- Map.toList (chainOutputs chain)
        , holdsToken (registryStatePolicy registry) (registryName registry) out
        ]
  where
    registry = registryOf world

-- | Make the registry's state output hold the root of these keys, in place.
setRegistryRoot :: World -> [ByteString] -> [ByteString] -> IO ()
setRegistryRoot world active terminal =
    modifyIORef' (worldChain world) $ \chain -> case stateAt world chain of
        Just (ref, out) ->
            chain{chainOutputs = Map.insert ref (out & datumTxOutL .~ mkInlineDatum (stateDatumData (registryRootOf active terminal))) (chainOutputs chain)}
        Nothing -> chain

{- | The world as it is after another party's fold: the registry's state is a new
output holding the root of these keys, and the old one is gone.
-}
moveRegistryRoot :: World -> [ByteString] -> Chain -> Chain
moveRegistryRoot world active chain = case stateAt world chain of
    Just (ref, out) ->
        let moved = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xd1))))) (TxIx 0)
         in chain
                { chainOutputs =
                    Map.insert
                        moved
                        (out & datumTxOutL .~ mkInlineDatum (stateDatumData (registryRootOf active [])))
                        (Map.delete ref (chainOutputs chain))
                }
    Nothing -> chain

-- | The chain as it is now, kept: a read of it is behind the world after the world moves.
copyChain :: World -> IO (IORef Chain)
copyChain world = readIORef (worldChain world) >>= newIORef

-- | The output a premint made that holds the hash proof of an export.
proofOutputOf :: World -> ConwayTx -> Maybe TxIn
proofOutputOf world tx =
    listToMaybe
        [ TxIn (transactionId tx) (TxIx ix)
        | (ix, out) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
        , holdsPolicy (scriptHash (recordHashProof (deployedRecord (worldDeployed world)))) out
        ]
  where
    holdsPolicy policy out = case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            any (\(PolicyID (ScriptHash hash)) -> hashToBytes hash == policy) (Map.keys assets)

-- | Change the output the chain holds under a reference.
reshape :: World -> TxIn -> (TxOut ConwayEra -> TxOut ConwayEra) -> IO ()
reshape world ref change =
    modifyIORef' (worldChain world) $ \chain -> chain{chainOutputs = Map.adjust change ref (chainOutputs chain)}

{- | An output that looks like a booked request and is not one: the datum of the
request at the application's address, holding lovelace and no approval token.
-}
stripApproval :: World -> TxIn -> IO TxIn
stripApproval world request = do
    chain <- readIORef (worldChain world)
    let original = fromJust (Map.lookup request (chainOutputs chain))
        TxIn (TxId safeHash) _ = request
        forged = TxIn (TxId safeHash) (TxIx 77)
        bare =
            mkBasicTxOut (original ^. addrTxOutL) (inject (original ^. coinTxOutL))
                & datumTxOutL .~ (original ^. datumTxOutL)
    modifyIORef' (worldChain world) $ \c -> c{chainOutputs = Map.insert forged bare (chainOutputs c)}
    pure forged

-- | Let this many milliseconds pass on the clock without a block.
advanceClock :: World -> Integer -> IO ()
advanceClock world ms = modifyIORef' (worldElapsed world) (+ ms)

{- | A runtime whose reads at an address fail from the n-th on (counting from
one): the node that cannot be read.
-}
failStateReadsFrom :: Int -> Addr -> RegistryRuntime -> IO RegistryRuntime
failStateReadsFrom = failStateReadsWith (ioError (userError "the node cannot be read"))

-- | The same, with the failure delivered by an action.
failStateReadsWith :: IO () -> Int -> Addr -> RegistryRuntime -> IO RegistryRuntime
failStateReadsWith failing nth address runtime = do
    counted <- newIORef (0 :: Int)
    pure
        runtime
            { rtUtxosAt = \asked ->
                if asked == address
                    then do
                        modifyIORef' counted (+ 1)
                        count <- readIORef counted
                        if count >= nth
                            then failing >> rtUtxosAt runtime asked
                            else rtUtxosAt runtime asked
                    else rtUtxosAt runtime asked
            }

-- | How many times a decision has read the tip, the clock and the horizon.
observationsMade :: World -> IO Int
observationsMade world = readIORef (worldObservations world)

-- | The machine's clock of the world: a hundred milliseconds into the tip's slot, and what has passed since.
clockNow :: World -> IO Integer
clockNow world = do
    tip <- readIORef (worldTip world)
    elapsed <- readIORef (worldElapsed world)
    pure (slotStart (worldSlotMs world) tip + 100 + elapsed)

{- | A runtime whose n-th observation (counting from one) fails with an exception: the
node that times out or drops the connection while a decision reads it.
-}
failingObservation :: Int -> SomeException -> RegistryRuntime -> IO RegistryRuntime
failingObservation nth failure = failingObservationBy nth (throwIO failure)

{- | The same, with the failure delivered by an action: the node client dying in the thread
linked to the command, which reaches it as an asynchronous exception.
-}
failingObservationBy :: Int -> IO Observation -> RegistryRuntime -> IO RegistryRuntime
failingObservationBy nth failing runtime = do
    observed <- newIORef (0 :: Int)
    pure
        runtime
            { rtObserve = do
                modifyIORef' observed (+ 1)
                count <- readIORef observed
                if count == nth then failing else rtObserve runtime
            }

{- | A runtime whose n-th settlement observation (counting from one) fails the way a dying
node client does: the transaction was handed to the node and its settlement is not seen.
-}
failingSettlementBy :: Int -> IO () -> RegistryRuntime -> IO RegistryRuntime
failingSettlementBy nth failing runtime = do
    observed <- newIORef (0 :: Int)
    let transactions = rtTransactions runtime
    pure
        runtime
            { rtTransactions =
                transactions
                    { trObserve = \txId -> do
                        modifyIORef' observed (+ 1)
                        count <- readIORef observed
                        if count == nth then failing else trObserve transactions txId
                    }
            }

{- | A node client that is a thread of its own: it runs until it is told to end, and then it
ends, as the live client does when its connection is closed. Its status is what the
runtime's calls wait on.
-}
data StandIn = StandIn
    { standInStatus :: STM (Maybe SomeException)
    -- ^ whether the thread is running, or how it ended
    , standInEnd :: IO ()
    -- ^ let the thread end, and wait until it has
    }

newStandIn :: IO StandIn
newStandIn = do
    gate <- newEmptyMVar
    client <- async (takeMVar gate >> throwIO ConnectionLost)
    let status = fmap (fromLeft (toException ConnectionLost)) <$> pollSTM client
    pure
        StandIn
            { standInStatus = status
            , standInEnd = putMVar gate () >> atomically (status >>= maybe retry (const (pure ())))
            }

{- | The node client ends here, for real, and the reply the caller is waiting for never
comes: the caller waits for ever, as a call the node will not answer does.
-}
connectionEnds :: StandIn -> IO a
connectionEnds client = standInEnd client >> forever (threadDelay 1_000_000)

-- | The kinds of call a runtime makes of the node.
data Call = ReadCall | SubmitCall | ObserveCall
    deriving stock (Eq, Show)

{- | A runtime whose calls are counted from one across every kind, and the node client
ends at the given one: before the call is made, or after the node has done what the call
asked, so that the reply never arrives. Every call after it waits for ever. The kinds of
the calls made are recorded in order.
-}
endingAt :: StandIn -> Int -> Bool -> RegistryRuntime -> IO (RegistryRuntime, IO [Call])
endingAt client nth afterEffect runtime = do
    count <- newIORef (0 :: Int)
    made <- newIORef []
    let counted kind act = do
            modifyIORef' count (+ 1)
            n <- readIORef count
            modifyIORef' made (kind :)
            if n == nth
                then when afterEffect (void act) >> connectionEnds client
                else if n > nth && nth > 0 then connectionEnds client else act
        transactions = rtTransactions runtime
    pure
        ( runtime
            { rtUtxosAt = counted ReadCall . rtUtxosAt runtime
            , rtOutputs = counted ReadCall . rtOutputs runtime
            , rtObserve = counted ReadCall (rtObserve runtime)
            , rtTransactions =
                transactions
                    { trQueryProtocolParams = counted ReadCall (trQueryProtocolParams transactions)
                    , trEvaluate = counted ReadCall . trEvaluate transactions
                    , trSubmit = counted SubmitCall . trSubmit transactions
                    , trObserve = counted ObserveCall . trObserve transactions
                    }
            }
        , reverse <$> readIORef made
        )

{- | A runtime that counts every call the command makes to hand a transaction to the node, at
the boundary the command calls: the call is counted when it is made, whatever becomes of it
(taken, refused, or never begun because the connection had ended). Put it outermost, around
any wrapper of the node client, so that a second call by the command shows as a second.
-}
handoffsCounted :: RegistryRuntime -> IO (RegistryRuntime, IO Int)
handoffsCounted runtime = do
    calls <- newIORef (0 :: Int)
    pure (countHandoffsInto calls runtime, readIORef calls)

-- | The same, counting into a counter the caller holds, for a runtime a command opens itself.
countHandoffsInto :: IORef Int -> RegistryRuntime -> RegistryRuntime
countHandoffsInto calls runtime =
    runtime{rtTransactions = transactions{trSubmit = \tx -> modifyIORef' calls (+ 1) >> trSubmit transactions tx}}
  where
    transactions = rtTransactions runtime

{- | The runtime over a node client that is a thread of its own, changed by what the given
action does with that client: whatever the change does, every call of the result returns
once the client has ended.
-}
withClient :: (StandIn -> RegistryRuntime -> IO RegistryRuntime) -> RegistryRuntime -> IO RegistryRuntime
withClient change runtime = do
    client <- newStandIn
    changed <- change client runtime
    pure (whileConnected (standInStatus client) changed)

{- | An example that does not end within one minute fails: a call that waits for ever is a
failure of the example, not of the run.
-}
withinOneMinute :: IO () -> IO ()
withinOneMinute example =
    timeout 60_000_000 example >>= maybe (expectationFailure "the example did not end within one minute") pure

{- | What a scripted node has been asked by the node's own client: whether it answered an
acquisition of ledger state, and whether it holds a query on that state that it will never answer.
-}
data ScriptedNode = ScriptedNode
    { nodeAcquired :: TVar Bool
    , nodeQueried :: TVar Bool
    }

{- | The node's end of a connection, played in this process against the node's own client
('mkLocalStateQueryClient' over its channel, as the live opener runs it): it answers every
acquisition, and it holds the first query on acquired state without ever answering it.
-}
runScriptedNode :: ScriptedNode -> LocalStateQueryClient block point query IO () -> IO ()
runScriptedNode node (LocalStateQueryClient start) = start >>= idle
  where
    idle = \case
        SendMsgAcquire _ acquiring -> do
            atomically (writeTVar (nodeAcquired node) True)
            recvMsgAcquired acquiring >>= held
        SendMsgDone done -> pure done
    held = \case
        SendMsgQuery _ _ -> do
            atomically (writeTVar (nodeQueried node) True)
            forever (threadDelay 1_000_000)
        SendMsgReAcquire _ acquiring -> recvMsgAcquired acquiring >>= held
        SendMsgRelease next -> next >>= idle

{- | The order in which the end of the connection becomes known to a call that is waiting.

'LivenessFirst': the node client's connection monitor raises its liveness signal as the connection
exits, and the client's thread ends after it, as in the live client.

'ClientStatusFirst': the client's thread is reported as ended while the monitor's liveness signal
has not been raised: the order in which a cancellation reaches a call that holds acquired state
before the call has seen the signal. The library's own cleanup then has nothing to wake it.
-}
data Ending = LivenessFirst | ClientStatusFirst
    deriving stock (Eq, Show)

-- | The node's own client, its provider and a node that is scripted behind it.
data ScriptedClient = ScriptedClient
    { scriptedProvider :: Provider IO
    -- ^ the node's own provider over the client's channel
    , scriptedWitness :: STM (Bool, Bool)
    -- ^ whether the node answered an acquisition, and whether it holds a query on the acquired state
    , scriptedStatus :: STM (Maybe SomeException)
    -- ^ the status of the client's thread the runtime's calls wait on
    , scriptedEnd :: IO ()
    -- ^ end the connection, and return once the end is known as the ordering says
    }

withScriptedClient :: Ending -> (ScriptedClient -> IO a) -> IO a
withScriptedClient ending use = do
    channel <- newLSQChannel 16
    node <- ScriptedNode <$> newTVarIO False <*> newTVarIO False
    standIn <- newStandIn
    withAsync
        (monitorLocalStateQueryConnection channel (runScriptedNode node (mkLocalStateQueryClient channel)))
        $ \connection ->
            use
                ScriptedClient
                    { scriptedProvider = mkN2CProvider channel
                    , scriptedWitness = (,) <$> readTVar (nodeAcquired node) <*> readTVar (nodeQueried node)
                    , scriptedStatus = case ending of
                        LivenessFirst -> fmap (fromLeft (toException ConnectionLost)) <$> pollSTM connection
                        ClientStatusFirst -> standInStatus standIn
                    , scriptedEnd = case ending of
                        LivenessFirst -> uninterruptibleCancel connection
                        ClientStatusFirst -> standInEnd standIn
                    }

-- | Wait up to five seconds until the node has answered an acquisition and holds a query on it, and say what it has seen.
awaitWitness :: ScriptedClient -> IO (Bool, Bool)
awaitWitness client =
    timeout 5_000_000 (atomically held) >>= maybe (atomically (scriptedWitness client)) pure
  where
    held = do
        witness <- scriptedWitness client
        unless (uncurry (&&) witness) retry
        pure witness

-- | A call that was under way when the connection ended.
data AcquiredCase = AcquiredCase
    { caseWitness :: (Bool, Bool)
    -- ^ at the moment the connection ended: the node had answered the acquisition, and held the query
    , caseSeconds :: Double
    -- ^ from the end of the connection until the call returned
    , caseOutcome :: Either SomeException ()
    }

{- | One call through 'whileConnected' that has acquired ledger state and is waiting for the
node's reply when the connection ends; the node's witness is read before it ends.
-}
runAcquiredCase :: RegistryRuntime -> Ending -> Addr -> (Provider IO -> Addr -> IO ()) -> IO AcquiredCase
runAcquiredCase base ending address call = withScriptedClient ending $ \client -> do
    let runtime = whileConnected (scriptedStatus client) base{rtUtxosAt = \at -> call (scriptedProvider client) at >> pure []}
    running <- async (try @SomeException (void (rtUtxosAt runtime address)))
    witness <- awaitWitness client
    scriptedEnd client
    ended <- getMonotonicTime
    outcome <- timeout 10_000_000 (wait running)
    returned <- getMonotonicTime
    pure
        AcquiredCase
            { caseWitness = witness
            , caseSeconds = returned - ended
            , caseOutcome = fromMaybe (Left (toException (userError "no return within ten seconds"))) outcome
            }

{- | A runtime whose every read of the node is a query on acquired ledger state through the node's
own provider, which the scripted node holds without answering; the read the runtime already
had follows it.
-}
acquiringReads :: Provider IO -> Addr -> RegistryRuntime -> RegistryRuntime
acquiringReads provider address runtime =
    runtime
        { rtUtxosAt = \at -> hold >> rtUtxosAt runtime at
        , rtOutputs = \wanted -> hold >> rtOutputs runtime wanted
        , rtObserve = hold >> rtObserve runtime
        , rtTransactions = transactions{trQueryProtocolParams = hold >> trQueryProtocolParams transactions}
        }
  where
    transactions = rtTransactions runtime
    hold = void (queryUTxOs provider address)

-- | The lines of a premint's receipt: its id, what it paid and the proof output it made.
receiptLinesOf :: ConwayTx -> Maybe TxIn -> [String]
receiptLinesOf premintTx proof =
    [ "premint-transaction: " <> T.unpack (renderTransactionId (transactionId premintTx))
    , "proof-output: " <> maybe "" (\(TxIn txId (TxIx ix)) -> T.unpack (renderTransactionId txId) <> "#" <> show ix) proof
    , "premint-fee: " <> show (feeOf premintTx)
    ]

-- | The registry the world deployed, as the builders take it.
worldDeployment :: World -> IO Tx.RegistryDeployment
worldDeployment world = do
    scripts <-
        either fail pure $
            deriveRegistryScripts stateTemplate testTerms (riSeed (deployedIdentity (worldDeployed world))) (worldBlueprint world)
    pure (Tx.RegistryDeployment Testnet testTerms scripts)

-- | The outputs the registry's transactions read by reference, as the chain holds them now.
worldReferences :: World -> IO Tx.RegistryReferences
worldReferences world = do
    chain <- readIORef (worldChain world)
    let record = deployedRecord (worldDeployed world)
        outputAt ref = fromJust (Map.lookup (txInOfReference ref) (chainOutputs chain))
        resolved ref = (txInOfReference ref, outputAt ref)
    pure
        Tx.RegistryReferences
            { Tx.referenceApplication = resolved (scriptOutput (recordApplication record))
            , Tx.referenceState = resolved (scriptOutput (recordState record))
            , Tx.referenceConfiguration = resolved (recordConfiguration record)
            , Tx.referenceAttestation = resolved (scriptOutput (recordAttestation record))
            , Tx.referenceHashProof = resolved (scriptOutput (recordHashProof record))
            }
