{- |
Module      : Cardano.KERI.Indexer.Identity
Description : The live identity read of the registry reader (#353)

One read of the registry's holdings for one AID, and the two answers built
from it: the AID's checked live holding or the reason it has none, and the
consumer result of the library over that same holding. The service and the
local command read through the same function, so they cannot differ.

A live holding is a classified holding ('decodeHoldingOutput') of the AID that
is a checkpoint, not a pending termination. An AID that has exactly one is
answered live; any other number, or none, is answered unavailable with a reason
that names no other status: a pending termination, a refused output or another
registry's asset is not this AID's live checkpoint here, and nothing more is
claimed.
-}
module Cardano.KERI.Indexer.Identity (
    LiveHolding (..),
    IdentityRead (..),
    identityTx,
    Unavailable (..),
    unavailableText,
    IdentityAnswer (..),
    answerIdentity,
    Consumer (..),
    consumerOf,
    notEvaluatedReason,
) where

import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Datum (KeyMaterial)
import Cardano.KERI.AID.Consumer (Clause, ObservedOutput, consumableHolding)
import Cardano.KERI.AID.Release (ReleaseIdentity, releaseContext, releaseEnvironment)
import Cardano.KERI.Indexer.Codecs (
    Holding (..),
    HoldingKind (..),
    Observation (..),
    checkpointAddressOf,
    decodeHoldingOutput,
    observeOutput,
 )
import Cardano.KERI.Indexer.Query.Tx (scanAddressTx, watermarkPointTx)
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Types (BlockHash, SlotNo, TxIn)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Database.KV.Transaction (Transaction)

{- | A live holding of the AID: its output reference, sequence number, epoch and
lovelace, the facts and amounts of its checkpoint, and the observed output the
consumer predicate reads.
-}
data LiveHolding = LiveHolding
    { lhTxIn :: !TxIn
    , lhSn :: !Integer
    , lhEpoch :: !Integer
    , lhLovelace :: !Integer
    , lhPoisoned :: !Bool
    , lhFrozen :: !Bool
    , lhBornAt :: !Integer
    , lhRefund :: !ByteString
    , lhToppedUp :: !Bool
    , lhKeys :: !KeyMaterial
    , lhDeposit :: !Integer
    , lhFreezeBond :: !Integer
    , lhPool :: !Integer
    , lhObserved :: !ObservedOutput
    }
    deriving stock (Eq, Show)

{- | What one transaction read for an AID: the store's chain point and every
live checkpoint holding of the AID.
-}
data IdentityRead = IdentityRead
    { irPoint :: !(Maybe (SlotNo, BlockHash))
    , irLive :: ![LiveHolding]
    }
    deriving stock (Eq, Show)

{- | The live holdings of a raw AID under a release identity and the store's chain
point, in one store transaction.
-}
identityTx :: ReleaseIdentity -> ByteString -> Transaction IO cf Cols op IdentityRead
identityTx release raw = do
    entries <- scanAddressTx (checkpointAddressOf release)
    point <- watermarkPointTx
    pure
        IdentityRead
            { irPoint = point
            , irLive =
                [ LiveHolding
                    { lhTxIn = holdingTxIn holding
                    , lhSn = holdingSn holding
                    , lhEpoch = holdingEpoch holding
                    , lhLovelace = holdingLovelace holding
                    , lhPoisoned = hcPoisoned
                    , lhFrozen = hcFrozen
                    , lhBornAt = hcBornAt
                    , lhRefund = hcRefund
                    , lhToppedUp = hcToppedUp
                    , lhKeys = hcKeys
                    , lhDeposit = hcDeposit
                    , lhFreezeBond = hcFreezeBond
                    , lhPool = hcPool
                    , lhObserved = obsOutput observation
                    }
                | (txIn, txOut) <- entries
                , Right holding <- [decodeHoldingOutput release txIn txOut]
                , holdingAid holding == qb64Aid raw
                , HeldCheckpoint{..} <- [holdingKind holding]
                , Right observation <- [observeOutput txOut]
                ]
            }

-- | Why a store ready to be read has no live holding to give for the AID.
data Unavailable
    = NoLiveCheckpoint
    | SeveralLiveCheckpoints
    deriving stock (Eq, Show)

-- | The reason as it is told to a reader.
unavailableText :: Unavailable -> Text
unavailableText = \case
    NoLiveCheckpoint -> "the store holds no live checkpoint of this registry for this AID"
    SeveralLiveCheckpoints -> "the store holds more than one live checkpoint of this registry for this AID"

-- | The checked live holding of an AID, or why there is none.
data IdentityAnswer
    = Live !LiveHolding
    | NotLive !Unavailable
    deriving stock (Eq, Show)

answerIdentity :: IdentityRead -> IdentityAnswer
answerIdentity reading = case irLive reading of
    [one] -> Live one
    [] -> NotLive NoLiveCheckpoint
    _ -> NotLive SeveralLiveCheckpoints

-- | The consumer result, reported beside the holding and never changing its status.
data Consumer
    = NotEvaluated !Text
    | Evaluated ![Clause]
    deriving stock (Eq, Show)

-- | The reason given when the maturity window and the time are not both supplied.
notEvaluatedReason :: Text
notEvaluatedReason =
    "the consumer result is evaluated only when both window_ms and now_ms are given"

{- | The library's verdict over the live holding, for the release's context for
the AID and its environment, at this maturity window and time (both in
milliseconds, the unit of the datum's @born_at@), when both are given.
-}
consumerOf :: ReleaseIdentity -> ByteString -> Maybe (Integer, Integer) -> LiveHolding -> Consumer
consumerOf release raw parameters live = case parameters of
    Nothing -> NotEvaluated notEvaluatedReason
    Just (window, now) ->
        Evaluated
            ( consumableHolding
                window
                now
                (releaseEnvironment release)
                (releaseContext release (qb64Aid raw))
                (lhObserved live)
            )
