{- |
Module      : Cardano.KERI.Indexer.Follower
Description : Assemble the upstream chain-sync follower configuration

Consumes the deployment checkpoint identity from
'Cardano.KERI.Deployment.Manifest'; the reusable configuration and address
types from 'Cardano.Node.Client.UTxOIndexer.Follower' and
'Cardano.Node.Client.UTxOIndexer.Types'; the storage handler from
'Cardano.Node.Client.UTxOIndexer.Indexer'; reconnect and probe defaults from
'Cardano.Node.Client.N2C.Reconnect' and 'Cardano.Node.Client.N2C.Probe'; and
the network wrapper from 'Ouroboros.Network.Magic'.
-}
module Cardano.KERI.Indexer.Follower (
    mkChainSyncConfig,
) where

import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
 )
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
    decodeAddress,
 )
import Cardano.Node.Client.N2C.Probe (
    defaultProbeConfig,
 )
import Cardano.Node.Client.N2C.Reconnect (
    defaultReconnectPolicy,
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig (..),
    InterestSet (..),
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    liveUtxoHandler,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address (..),
 )
import Control.Tracer (
    nullTracer,
 )
import Data.List.NonEmpty (
    NonEmpty (..),
 )
import Data.Maybe (
    maybeToList,
 )
import Data.Set qualified as Set
import Ouroboros.Network.Magic (
    NetworkMagic (..),
 )

-- | Assemble the upstream chain-sync configuration from deployment identity.
mkChainSyncConfig :: IndexerConfig -> Manifest -> ChainSyncConfig
mkChainSyncConfig config manifest =
    let interestSet =
            IndexAddressSet $
                Set.fromList $
                    checkpointAddress manifest
                        : icFundingAddrs config
                            <> maybeToList (icBoardAddr config)
     in ChainSyncConfig
            { csRelaySocket = icSocketPath config
            , csNetworkMagic = NetworkMagic (icNetworkMagic config)
            , csByronEpochSlots = icByronEpochSlots config
            , csStartPoint = icStartPoint config
            , csReadyThresholdSlots = 60
            , csSecurityParamK = icSecurityParamK config
            , csReconnectPolicy = defaultReconnectPolicy
            , csProbeConfig = defaultProbeConfig
            , csInterestSet = interestSet
            , csHandlers = liveUtxoHandler interestSet :| []
            , csBlockTracer = nullTracer
            , csTipTracer = nullTracer
            , csHistory = Nothing
            }

checkpointAddress :: Manifest -> Address
checkpointAddress manifest =
    case decodeAddress (checkpointAddressBech32 $ manifestCheckpoint manifest) of
        Left err ->
            error $
                "mkChainSyncConfig: invalid checkpoint address: "
                    <> err
        Right address -> address
