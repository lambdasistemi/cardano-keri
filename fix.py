module LambdaSistemi.CardanoKeri.Epic.Block where

import Data.Text (Text)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Control.Arrow (first, second)
import Control.Monad (liftM2)

type Epoch = Int
type Stake = Text
type ValidatorId = Text

newtype KeriBlock = KeriBlock
    { blockEpochs :: Map Epoch (ValidatorId, Stake)
    } deriving (Eq, Show)

data Board = Board
    { boardId :: ValidatorId
    , boardStake :: Stake
    } deriving (Eq, Show)

data Bounty = Bounty
    { bountyName :: ValidatorId
    , bountyValue :: Epoch
    } deriving (Eq, Show)

class Projectable a where
    project :: a -> KeriBlock

class Migratable a where
    migrateEpoch :: Epoch -> a -> a

class Boarded a where
    bindBoard :: Board -> a -> a

class Authenticated a where
    authBounty :: a -> Bounty -> Bool

instance Projectable KeriBlock where
    project (KeriBlock m) = KeriBlock m

instance Migratable KeriBlock where
    migrateEpoch newEpoch (KeriBlock m) = KeriBlock m

instance Boarded KeriBlock where
    bindBoard (Board i s) (KeriBlock m) = KeriBlock m

instance Authenticated KeriBlock where
    authBounty (KeriBlock m) (Bounty nm v) = Map.member v (Map.fromList m)

type OnChainBlock = KeriBlock
type ValidatorMigration = Migratable OnChainBlock
type BoardBinding = Boarded OnChainBlock
type BountyAuthentication = Authenticated OnChainBlock

-- Core projection law for the on-chain state
instance Projectable Map Epoch (ValidatorId, Stake) where
    project ms = KeriBlock (Map.insert 0 ms)

-- Helper to project a raw validator into the Keri view
instance Projectable (ValidatorId, Stake) where
    project v = KeriBlock (Map.singleton 0 v)

-- Board binding to synchronize validator counts
instance Boarded (ValidatorId, Stake) where
    bindBoard (Board i s) v = (i, s)

-- Bounties for authenticating the epoch weight
instance Authenticated (ValidatorId, Stake) where
    authBounty v (Bounty nm e) = e == 1

-- The complete fixed state type
data BlockState = BlockState
    { stateEpochs :: Map Epoch (ValidatorId, Stake)
    , stateBoard :: Maybe Board
    , stateBounty :: Maybe Bounty
    } deriving (Eq, Show)

instance Projectable BlockState where
    project (BlockState m b bn) = KeriBlock m

instance Migratable BlockState where
    migrateEpoch e (BlockState m b bn) = KeriBlock (Map.insert e m)

instance Boarded BlockState where
    bindBoard board (BlockState m b bn) = KeriBlock m

instance Authenticated BlockState where
    authBounty (BlockState m b bn) (Bounty nm v) = Map.member v m

-- The unified type representing the issue fix
type CardanoBlock = BlockState