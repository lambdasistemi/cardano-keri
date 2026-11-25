{- |
Module      : Cardano.KERI.Deployment.KoiosRuntime
Description : The read side of the Koios instance of 'RegistryRuntime'

The reads of a registry runtime over Koios: the outputs at an address, the
outputs under exact references, the protocol parameters, one observation of
the chain's time, and the evaluation of a transaction. Every call goes through
Singular's Koios client, which pages and decodes an answer whole or stops with
one named failure; time and evaluation use Singular's network time and local
evaluation. Nothing here submits, signs or waits for a transaction.
-}
module Cardano.KERI.Deployment.KoiosRuntime (
    KoiosReads (..),
    KoiosFailure (..),
    koiosReads,
    evaluateLocally,
    wholeAnswers,
) where

import Cardano.KERI.Deployment.RegistryChain (Observation (..))
import Cardano.Ledger.Address (AccountAddress, Addr)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL)
import Cardano.Ledger.BaseTypes (ProtVer (..), getVersion)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, ppProtocolVersionL)
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult)
import Control.Exception (Exception, throwIO)
import Control.Monad (forM_, unless, when)
import Data.Aeson (Value (..), decodeStrict')
import Data.Containers.ListUtils (nubOrd)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Lens.Micro ((^.))
import Singular.Provider.Koios.Client (ClientFailure, Koios (..))
import Singular.Provider.Koios.Client qualified as Client
import Singular.Provider.Koios.Wire qualified as Wire
import Singular.Registry.LocalEvaluation (
    EvaluationContext (..),
    EvaluationFailure,
    localEvaluation,
 )
import Singular.Registry.NetworkTime (
    NetworkTime,
    NetworkTimeFailure,
    ledgerHorizon,
    slotStartMs,
    validateProtocolMajor,
 )

-- | The reads of a runtime over Koios.
data KoiosReads = KoiosReads
    { readUtxosAt :: Addr -> IO [(TxIn, TxOut ConwayEra)]
    -- ^ every output Koios holds at an address
    , readOutputs :: Set TxIn -> IO (Map TxIn (TxOut ConwayEra))
    -- ^ the outputs Koios holds unspent under these references
    , readProtocolParameters :: IO (PParams ConwayEra)
    , readObservation :: IO Observation
    -- ^ the tip, the clock and the horizon, each read once
    , readEvaluation :: ConwayTx -> IO (EvaluateTxResult ConwayEra)
    -- ^ the units of every script purpose of a transaction, from facts read here
    , readRewardRegistered :: AccountAddress -> IO Bool
    -- ^ whether Koios holds a reward account registered
    }

-- | Why a read stopped, in Singular's terms where Singular decided it.
data KoiosFailure
    = -- | a call of the client stopped, with its class
      KoiosCallFailed !ClientFailure
    | -- | Koios names an unspent reference and its transaction has no such output
      OutputMissingFromTransaction !TxIn
    | -- | the tip's block time and the start of the tip's slot in the pinned network time, in milliseconds
      TipTimeDisagrees !Integer !Integer
    | -- | an output the answer holds is at another address than the one asked: the output and the address it is at
      OutputAtAnotherAddress !TxIn !Addr
    | -- | the spent-or-not answer states one reference both spent and unspent
      ContradictorySpentStatus !TxIn
    | -- | the spent-or-not answer names a reference that was not asked
      UnaskedReference !TxIn
    | -- | the answer for a transaction holds an output of another one: the transaction asked and the output
      OutputOfAnotherTransaction !TxId !TxIn
    | -- | the pinned network time refuses
      NetworkTimeRefused !NetworkTimeFailure
    | -- | the evaluation cannot start: an input is missing or conflicts
      EvaluationRefused !EvaluationFailure
    deriving stock (Eq, Show)

instance Exception KoiosFailure

{- | The reads over a client, the pinned network time of the network, and a
reading of the machine's clock in POSIX milliseconds.
-}
koiosReads :: Koios IO -> NetworkTime -> IO Integer -> KoiosReads
koiosReads given time clock = reads'
  where
    client = given{Client.koiosTransport = wholeAnswers (Client.koiosTransport given)}
    reads' =
        KoiosReads
            { readUtxosAt = outputsAt client
            , readOutputs = outputsUnder client
            , readProtocolParameters = answered (Client.cliProtocolParams client)
            , readObservation = observe client time clock
            , readEvaluation = evaluateLocally time (readProtocolParameters reads') (readOutputs reads')
            , readRewardRegistered = answered . Client.accountRegistered client
            }

answered :: IO (Either ClientFailure a) -> IO a
answered call = call >>= either (throwIO . KoiosCallFailed) pure

{- | An unpaged answer that signals it is partial is refused. The client checks
the range of every page it asks for and no more, so a partial answer to a call it
does not page would pass as a whole one. Signals: the status 206; a range that
starts after the first row; a range that ends before the rows the answer holds,
or after them; a total the answer states and does not hold. The refusal is the
client's own for an answer cut off. A range that states no total is an ordinary
complete answer.
-}
wholeAnswers :: Client.Transport IO -> Client.Transport IO
wholeAnswers transport = Client.Transport $ \raw -> do
    exchanged <- Client.exchange transport raw
    pure $ case Client.exchangeResult exchanged of
        Right answer
            | not (any ((== "offset") . fst) (Client.rawQuery raw))
            , Just why <- partialBecause answer ->
                exchanged{Client.exchangeResult = Left (Client.BodyCutOff why)}
        _ -> exchanged

partialBecause :: Client.Answer -> Maybe T.Text
partialBecause answer = listToMaybe (status <> start <> end <> total)
  where
    status = ["the service answers 206, partial content" | Client.answerStatus answer == 206]
    (spanText, totalText) =
        maybe ("", "") (fmap (T.drop 1) . T.breakOn "/") (lookup "content-range" (Client.answerHeaders answer))
    bounds = case T.breakOn "-" spanText of
        (from, dash) | not (T.null dash) -> (,) <$> number from <*> number (T.drop 1 dash)
        _ -> Nothing
    held = case decodeStrict' (Client.answerBody answer) of
        Just (Array rows) -> Just (toInteger (length rows))
        _ -> Nothing
    start = ["the range starts at row " <> shown from | Just (from, _) <- [bounds], from /= 0]
    end =
        [ "the range ends at row " <> shown to <> " and the answer holds " <> shown n <> " rows"
        | Just (from, to) <- [bounds]
        , Just n <- [held]
        , to - from + 1 /= n
        ]
    total =
        [ "the answer states " <> shown stated <> " rows and holds " <> shown n
        | Just stated <- [number totalText]
        , Just n <- [held]
        , stated /= n
        ]
    number text = case reads (T.unpack (T.strip text)) of
        [(n, "")] -> Just (n :: Integer)
        _ -> Nothing
    shown = T.pack . show

{- | Every output at an address. An output the answer places at another address
refuses the read: the outputs are the ones the caller will spend from.
-}
outputsAt :: Koios IO -> Addr -> IO [(TxIn, TxOut ConwayEra)]
outputsAt client address = do
    found <- answered (Client.addressUtxos client [address])
    case [(reference, output ^. addrTxOutL) | (reference, output) <- found, output ^. addrTxOutL /= address] of
        (reference, elsewhere) : _ -> throwIO (OutputAtAnotherAddress reference elsewhere)
        [] -> pure found

{- | The outputs under references, whole or refused. One call says which are
unspent, one more gives the outputs of the transactions that made them. A row
for a reference that was not asked, a reference stated both spent and unspent,
an output the answer for a transaction does not place in that transaction and an
unspent reference with no output all refuse the read.
-}
outputsUnder :: Koios IO -> Set TxIn -> IO (Map TxIn (TxOut ConwayEra))
outputsUnder client wanted = case NE.nonEmpty (Set.toAscList wanted) of
    Nothing -> pure Map.empty
    Just references -> do
        rows <- answered (Client.utxoInfo client references)
        forM_ rows $ \row ->
            unless (Wire.utxoInfoReference row `Set.member` wanted) $
                throwIO (UnaskedReference (Wire.utxoInfoReference row))
        let statuses = Map.fromListWith (<>) [(Wire.utxoInfoReference row, [Wire.utxoInfoSpent row]) | row <- rows]
        forM_ (Map.toAscList statuses) $ \(reference, stated) ->
            when (or stated && not (and stated)) $
                throwIO (ContradictorySpentStatus reference)
        let unspent = Map.keys (Map.filter (not . or) statuses)
        case NE.nonEmpty (nubOrd [producer | TxIn producer _ <- unspent]) of
            Nothing -> pure Map.empty
            Just producers -> do
                transactions <- answered (Client.txInfo client (NE.toList producers))
                forM_ transactions $ \transaction ->
                    forM_ (Wire.txInfoOutputs transaction) $ \(reference@(TxIn producer _), _) ->
                        when (producer /= Wire.txInfoId transaction) $
                            throwIO (OutputOfAnotherTransaction (Wire.txInfoId transaction) reference)
                let made = Map.fromList (concatMap Wire.txInfoOutputs transactions)
                Map.fromList
                    <$> traverse
                        ( \reference -> case Map.lookup reference made of
                            Just output -> pure (reference, output)
                            Nothing -> throwIO (OutputMissingFromTransaction reference)
                        )
                        unspent

{- | One observation: the machine's clock is read first and once, the tip is
Koios's, and every slot start and the horizon come from the pinned network
time. The tip's block time, which a provider states in whole seconds, must be the second
the start of its slot falls in there: the slot's start itself where slots last whole seconds, and the whole second
before it where they are shorter. A slot lasts
until the next one starts, so its length is its own at an era boundary too. The
horizon is the last slot the ledger converts: the network time's horizon is the
first it does not.
-}
observe :: Koios IO -> NetworkTime -> IO Integer -> IO Observation
observe client time clock = do
    now <- clock
    tip <- answered (Client.tip client)
    let slot = Wire.tipSlot tip
    start <- timed (slotStartMs time slot)
    next <- timed (slotStartMs time (slot + 1))
    let koiosStart = toInteger (Wire.tipBlockTime tip) * 1_000
    when (koiosStart /= start - start `mod` 1_000) (throwIO (TipTimeDisagrees koiosStart start))
    horizon <- timed (ledgerHorizon time slot)
    pure
        Observation
            { obsTipSlot = slot
            , obsTipStartMs = start
            , obsSlotLengthMs = next - start
            , obsClockMs = now
            , obsHorizonSlot = horizon - 1
            }
  where
    timed = either (throwIO . NetworkTimeRefused) pure

{- | The units of every script purpose of a transaction: the ledger's evaluation
over the transaction, the protocol parameters, the outputs its inputs resolve
to and the pinned network time. The parameters must be of the protocol major
the network time is pinned for.
-}
evaluateLocally ::
    NetworkTime ->
    IO (PParams ConwayEra) ->
    (Set TxIn -> IO (Map TxIn (TxOut ConwayEra))) ->
    ConwayTx ->
    IO (EvaluateTxResult ConwayEra)
evaluateLocally time readParameters resolve tx = do
    parameters <- readParameters
    either (throwIO . NetworkTimeRefused) pure $
        validateProtocolMajor time (getVersion (pvMajor (parameters ^. ppProtocolVersionL)))
    outcome <-
        localEvaluation
            EvaluationContext{evaluationParameters = parameters, evaluationNetworkTime = time}
            (fmap Map.toList . resolve)
            tx
    either (throwIO . EvaluationRefused) pure outcome
