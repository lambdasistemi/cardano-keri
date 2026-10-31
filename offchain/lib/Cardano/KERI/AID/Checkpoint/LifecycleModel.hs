{- |
Module      : Cardano.KERI.AID.Checkpoint.LifecycleModel
Description : Pure executable mirror skeleton for the #116 Lean lifecycle

Every Lean 'Step' constructor has a separately named entry point and the total
dispatcher delegates to it.  This model is deliberately ledger-abstract: it
mirrors the Lean state, guards, deposits, and cumulative transfers without
opening any live validator branch.
-}
module Cardano.KERI.AID.Checkpoint.LifecycleModel (
    Slot,
    Seq,
    Addr,
    InstanceId,
    Params (..),
    Env (..),
    MachState (..),
    TransferKind (..),
    Transfer (..),
    Ledger (..),
    Config (..),
    Action (..),
    Tx (..),
    Rejection (..),
    Sys (..),
    initConfig,
    hasEvent,
    behind,
    carried,
    balanced,
    live,
    stateSeq,
    register,
    advanceActive,
    advanceArmed,
    advanceFrozen,
    arm,
    claim,
    convictActive,
    convictArmed,
    convictFrozen,
    dispatch,
    runTrace,
    runTraceStates,
    lookupInstance,
    sysDispatch,
) where

type Slot = Integer

type Seq = Integer

type Addr = Integer

type InstanceId = Integer

data Params = Params
    { minAda :: !Integer
    , deposit :: !Integer
    , bond :: !Integer
    , freezeWindow :: !Integer
    }
    deriving stock (Show, Eq)

data Env = Env
    { kelEvents :: ![Seq]
    , forkEvidence :: !Bool
    }
    deriving stock (Show, Eq)

data MachState
    = Absent
    | Active !Seq
    | Armed !Seq !Addr !Slot
    | Frozen !Seq
    | Tombstone !Seq
    deriving stock (Show, Eq)

data TransferKind = Bounty | Forfeiture
    deriving stock (Show, Eq)

data Transfer = Transfer
    { destination :: !Addr
    , amount :: !Integer
    , transferKind :: !TransferKind
    }
    deriving stock (Show, Eq)

data Ledger = Ledger
    { deposits :: !Integer
    , outflows :: ![Transfer]
    }
    deriving stock (Show, Eq)

data Config = Config
    { state :: !MachState
    , ledger :: !Ledger
    }
    deriving stock (Show, Eq)

data Action
    = Register
    | Advance
    | Arm !Addr
    | Claim
    | Convict !Addr
    deriving stock (Show, Eq)

data Tx = Tx
    { slot :: !Slot
    , action :: !Action
    }
    deriving stock (Show, Eq)

data Rejection = StepRejected
    deriving stock (Show, Eq)

newtype Sys = Sys [(InstanceId, Config)]
    deriving stock (Show, Eq)

initConfig :: Config
initConfig = Config Absent (Ledger 0 [])

hasEvent :: Env -> Seq -> Bool
hasEvent env k = k `elem` kelEvents env

behind :: Env -> Seq -> Bool
behind env k = hasEvent env (k + 1)

carried :: Params -> MachState -> Integer
carried p = \case
    Absent -> 0
    Active _ -> minAda p + deposit p + bond p
    Armed{} -> minAda p + deposit p + bond p
    Frozen _ -> minAda p + deposit p
    Tombstone _ -> minAda p

balanced :: Params -> Config -> Bool
balanced p cfg =
    carried p (state cfg) + sum (map amount (outflows (ledger cfg)))
        == deposits (ledger cfg)

live :: MachState -> Bool
live = \case
    Active _ -> True
    Armed{} -> True
    Frozen _ -> True
    Absent -> False
    Tombstone _ -> False

stateSeq :: MachState -> Maybe Seq
stateSeq = \case
    Active k -> Just k
    Armed k _ _ -> Just k
    Frozen k -> Just k
    Tombstone k -> Just k
    Absent -> Nothing

register :: Params -> Env -> Config -> Tx -> Either Rejection Config
register p env (Config Absent led) (Tx _ Register)
    | hasEvent env 0 =
        Right $
            Config
                (Active 0)
                led{deposits = deposits led + minAda p + deposit p + bond p}
register _ _ _ _ = Left StepRejected

advanceActive :: Params -> Env -> Config -> Tx -> Either Rejection Config
advanceActive _ env (Config (Active k) led) (Tx _ Advance)
    | behind env k = Right (Config (Active (k + 1)) led)
advanceActive _ _ _ _ = Left StepRejected

advanceArmed :: Params -> Env -> Config -> Tx -> Either Rejection Config
advanceArmed _ env (Config (Armed k _ deadline) led) (Tx t Advance)
    | behind env k && t < deadline = Right (Config (Active (k + 1)) led)
advanceArmed _ _ _ _ = Left StepRejected

advanceFrozen :: Params -> Env -> Config -> Tx -> Either Rejection Config
advanceFrozen p env (Config (Frozen k) led) (Tx _ Advance)
    | behind env k =
        Right $
            Config
                (Active (k + 1))
                led{deposits = deposits led + bond p}
advanceFrozen _ _ _ _ = Left StepRejected

arm :: Params -> Env -> Config -> Tx -> Either Rejection Config
arm p env (Config (Active k) led) (Tx t (Arm hunter))
    | behind env k = Right (Config (Armed k hunter (t + freezeWindow p)) led)
arm _ _ _ _ = Left StepRejected

claim :: Params -> Env -> Config -> Tx -> Either Rejection Config
claim p _ (Config (Armed k hunter deadline) led) (Tx t Claim)
    | deadline <= t =
        Right $
            Config
                (Frozen k)
                led{outflows = outflows led ++ [Transfer hunter (bond p) Bounty]}
claim _ _ _ _ = Left StepRejected

convictActive :: Params -> Env -> Config -> Tx -> Either Rejection Config
convictActive p env (Config (Active k) led) (Tx _ (Convict c))
    | forkEvidence env =
        Right $
            Config
                (Tombstone k)
                led
                    { outflows =
                        outflows led
                            ++ [ Transfer c (deposit p) Forfeiture
                               , Transfer c (bond p) Forfeiture
                               ]
                    }
convictActive _ _ _ _ = Left StepRejected

convictArmed :: Params -> Env -> Config -> Tx -> Either Rejection Config
convictArmed p env (Config (Armed k hunter _) led) (Tx _ (Convict c))
    | forkEvidence env =
        Right $
            Config
                (Tombstone k)
                led
                    { outflows =
                        outflows led
                            ++ [ Transfer c (deposit p) Forfeiture
                               , Transfer hunter (bond p) Bounty
                               ]
                    }
convictArmed _ _ _ _ = Left StepRejected

convictFrozen :: Params -> Env -> Config -> Tx -> Either Rejection Config
convictFrozen p env (Config (Frozen k) led) (Tx _ (Convict c))
    | forkEvidence env =
        Right $
            Config
                (Tombstone k)
                led{outflows = outflows led ++ [Transfer c (deposit p) Forfeiture]}
convictFrozen _ _ _ _ = Left StepRejected

dispatch :: Params -> Env -> Config -> Tx -> Either Rejection Config
dispatch p env cfg tx = case (state cfg, action tx) of
    (Absent, Register) -> register p env cfg tx
    (Active _, Advance) -> advanceActive p env cfg tx
    (Armed{}, Advance) -> advanceArmed p env cfg tx
    (Frozen _, Advance) -> advanceFrozen p env cfg tx
    (Active _, Arm _) -> arm p env cfg tx
    (Armed{}, Claim) -> claim p env cfg tx
    (Active _, Convict _) -> convictActive p env cfg tx
    (Armed{}, Convict _) -> convictArmed p env cfg tx
    (Frozen _, Convict _) -> convictFrozen p env cfg tx
    _ -> Left StepRejected

runTrace :: Params -> Env -> Slot -> Config -> [Tx] -> Either Rejection Config
runTrace p env start cfg txs = snd <$> runTraceStates p env start cfg txs

runTraceStates ::
    Params ->
    Env ->
    Slot ->
    Config ->
    [Tx] ->
    Either Rejection ([Config], Config)
runTraceStates p env start cfg0 = go start cfg0 [cfg0]
  where
    go _ cfg states [] = Right (states, cfg)
    go lower cfg states (tx : txs)
        | lower <= slot tx = do
            cfg' <- dispatch p env cfg tx
            go (slot tx) cfg' (states ++ [cfg']) txs
        | otherwise = Left StepRejected

lookupInstance :: InstanceId -> Sys -> Maybe Config
lookupInstance instanceId (Sys instances) = lookup instanceId instances

sysDispatch ::
    Params ->
    Env ->
    Sys ->
    InstanceId ->
    Tx ->
    Either Rejection Sys
sysDispatch p env (Sys instances) instanceId tx = do
    cfg <- maybe (Left StepRejected) Right (lookup instanceId instances)
    cfg' <- dispatch p env cfg tx
    Right $
        Sys
            [ if key == instanceId then (key, cfg') else (key, value)
            | (key, value) <- instances
            ]
