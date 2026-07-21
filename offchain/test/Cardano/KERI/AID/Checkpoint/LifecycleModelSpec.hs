module Cardano.KERI.AID.Checkpoint.LifecycleModelSpec (
    spec,
    prop_advance_totality,
    prop_no_absorbing_busy_state,
    prop_adversarial_advance_is_progress,
    prop_bounded_churn,
    prop_armed_exclusive_window,
    prop_bond_transfer_only_via_elapsed_window,
    prop_abandonment_pays_exactly_B,
    prop_frozen_implies_true_silence,
    prop_close_lie_always_voidable,
    prop_close_at_tip_unchallengeable,
    prop_current_state_is_quiet,
    prop_value_conservation,
    prop_value_conservation_trace,
    prop_convict_dominance,
    prop_tombstone_terminal_but_no_aid_bar,
    prop_replay_convergence,
    prop_close_cycle_requires_elapsed_window,
) where

import Cardano.KERI.AID.Checkpoint.LifecycleModel
import Data.Either (fromRight, isLeft, isRight)
import Data.List (findIndex)
import Data.Maybe (fromMaybe)
import Test.Hspec (Spec, describe, it)
import Test.QuickCheck (
    Gen,
    Property,
    chooseInteger,
    counterexample,
    elements,
    forAll,
    property,
    vectorOf,
 )
import Test.QuickCheck.Monadic (PropertyM, assert, monadicIO, monitor, pick)

spec :: Spec
spec = describe "T116-R4 Lean lifecycle traceability" $ do
    it "prop_advance_totality [monadic state-machine]" $
        property prop_advance_totality
    it "prop_no_absorbing_busy_state [monadic state-machine]" $
        property prop_no_absorbing_busy_state
    it "prop_adversarial_advance_is_progress [direct]" $
        property prop_adversarial_advance_is_progress
    it "prop_bounded_churn [monadic state-machine]" $
        property prop_bounded_churn
    it "prop_armed_exclusive_window [direct]" $
        property prop_armed_exclusive_window
    it "prop_bond_transfer_only_via_elapsed_window [monadic state-machine]" $
        property prop_bond_transfer_only_via_elapsed_window
    it "prop_abandonment_pays_exactly_B [direct]" $
        property prop_abandonment_pays_exactly_B
    it "prop_frozen_implies_true_silence [monadic state-machine]" $
        property prop_frozen_implies_true_silence
    it "prop_close_lie_always_voidable [direct]" $
        property prop_close_lie_always_voidable
    it "prop_close_at_tip_unchallengeable [direct]" $
        property prop_close_at_tip_unchallengeable
    it "prop_current_state_is_quiet [direct]" $
        property prop_current_state_is_quiet
    it "prop_value_conservation [direct]" $
        property prop_value_conservation
    it "prop_value_conservation_trace [monadic state-machine]" $
        property prop_value_conservation_trace
    it "prop_convict_dominance [direct]" $
        property prop_convict_dominance
    it "prop_tombstone_terminal_but_no_aid_bar [direct]" $
        property prop_tombstone_terminal_but_no_aid_bar
    it "prop_replay_convergence [monadic state-machine]" $
        property prop_replay_convergence
    it "prop_close_cycle_requires_elapsed_window [monadic state-machine]" $
        property prop_close_cycle_requires_elapsed_window

-- Eight trace/reachability goals use QuickCheck's monadic state-machine
-- harness.  Each case is generated without global Arbitrary instances.

prop_advance_totality :: Property
prop_advance_totality = monadicIO $ do
    AdvanceTotalityCase{..} <- pick genAdvanceTotalityCase
    let path = case state atConfig of
            Armed _ _ deadline
                | atSlot >= deadline -> [Tx atSlot Claim, Tx atSlot Advance]
            _ -> [Tx atSlot Advance]
        result = runTrace atParams atEnv atSlot atConfig path
    assertWith "Step.advance_target: reachable behind state advances within two steps" $
        case result of
            Right cfg' ->
                length path <= 2
                    && state cfg' == Active (atSeq + 1)
                    && action (last path) == Advance
            Left _ -> False

prop_no_absorbing_busy_state :: Property
prop_no_absorbing_busy_state = monadicIO $ do
    ReachableLiveCase{..} <- pick genReachableLiveCase
    let candidate = progressTx rlParams rlEnv rlSlot rlConfig
    assertWith "TraceFrom.last_step: every reachable live state has a successor" $
        live (state rlConfig)
            && slot candidate >= rlSlot
            && isRight (dispatch rlParams rlEnv rlConfig candidate)

prop_bounded_churn :: Property
prop_bounded_churn = monadicIO $ do
    TraceCase{..} <- pick genPermissionlessTrace
    let advanceIndices =
            [ index
            | (index, tx) <- zip ([0 ..] :: [Int]) tcTxs
            , action tx == Advance
            ]
        bounded = and (zipWith (\i j -> j <= i + 3) advanceIndices (drop 1 advanceIndices))
    assertWith "fragment_no_three_stalls: adjacent advances enclose at most arm+claim" $
        isRight (runTrace tcParams tcEnv 0 initConfig tcTxs) && bounded

prop_bond_transfer_only_via_elapsed_window :: Property
prop_bond_transfer_only_via_elapsed_window = monadicIO $ do
    BountyTraceCase{..} <- pick genBountyTrace
    let result = runTrace btParams btEnv 0 initConfig btTxs
        noAdvanceBetween =
            all ((/= Advance) . action) (between btArmIndex btClaimIndex btTxs)
    assertWith "TraceFrom.step_at: bounty is paired with an elapsed unanswered window" $
        case result of
            Right cfg' ->
                btArmIndex < btClaimIndex
                    && action (btTxs !! btClaimIndex) == Claim
                    && slot (btTxs !! btArmIndex) + freezeWindow btParams
                        <= slot (btTxs !! btClaimIndex)
                    && noAdvanceBetween
                    && Transfer btHunter (bond btParams) Bounty `elem` outflows (ledger cfg')
            Left _ -> False

prop_frozen_implies_true_silence :: Property
prop_frozen_implies_true_silence = monadicIO $ do
    BountyTraceCase{..} <- pick genBountyTrace
    let result = runTrace btParams btEnv 0 initConfig (take (btClaimIndex + 1) btTxs)
    assertWith "TraceFrom.last_step: Frozen follows a full silent Wf segment" $
        case result of
            Right cfg' ->
                state cfg' == Frozen btSeq
                    && slot (btTxs !! btArmIndex) + freezeWindow btParams
                        <= slot (btTxs !! btClaimIndex)
                    && all
                        ((/= Advance) . action)
                        (between btArmIndex btClaimIndex btTxs)
            Left _ -> False

prop_value_conservation_trace :: Property
prop_value_conservation_trace = monadicIO $ do
    TraceCase{..} <- pick genMixedTrace
    let result = runTraceStates tcParams tcEnv 0 initConfig tcTxs
    assertWith "TraceFrom.preserves_balanced: every generated reachable config balances" $
        case result of
            Right (configs, _) -> all (balanced tcParams) configs
            Left _ -> False

prop_replay_convergence :: Property
prop_replay_convergence = monadicIO $ do
    p <- pick genParams
    eventCount <- pick (chooseInteger (1, 12))
    let env = Env [0 .. eventCount - 1] False []
        txs = Tx 0 Register : [Tx k Advance | k <- [1 .. eventCount - 1]]
        result = runTrace p env 0 initConfig txs
    assertWith "active_advance_chain: replay reaches the KEL tip in N steps" $
        length txs == fromIntegral eventCount
            && case result of
                Right cfg -> state cfg == Active (eventCount - 1)
                Left _ -> False

prop_close_cycle_requires_elapsed_window :: Property
prop_close_cycle_requires_elapsed_window = monadicIO $ do
    CloseTraceCase{..} <- pick genCloseTrace
    let result = runTrace ctParams ctEnv 0 initConfig ctTxs
        finalIndex = fromMaybe (-1) (findIndex ((== FinalizeClose) . action) ctTxs)
        preceding = if finalIndex > 0 then Just (ctTxs !! (finalIndex - 1)) else Nothing
    assertWith "TraceFrom.step_at: finalize is immediately preceded by its elapsed closeIntent" $
        isRight result
            && case preceding of
                Just intent ->
                    action intent == CloseIntent ctRefund
                        && slot intent + closeWindow ctParams <= slot (ctTxs !! finalIndex)
                Nothing -> False

-- Nine per-transition goals use direct QuickCheck properties.

prop_adversarial_advance_is_progress :: Property
prop_adversarial_advance_is_progress = forAll genAdvanceCase $ \AdvanceCase{..} ->
    counterexample "Step.advance_target: any submitter's admitted advance lands at k+1" $
        case dispatch acParams acEnv acConfig acTx of
            Right cfg' ->
                state cfg' == Active (acSeq + 1)
                    && hasEvent acEnv (acSeq + 1)
            Left _ -> False

prop_armed_exclusive_window :: Property
prop_armed_exclusive_window = forAll genArmedWindowCase $ \ArmedWindowCase{..} ->
    let actions = actionUniverse awHunter
        outcomes = [(act, dispatch awParams awEnv awConfig (Tx awSlot act)) | act <- actions]
        admitted = [act | (act, Right _) <- outcomes]
     in counterexample "Armed strictly before deadline admits only advance or convict" $
            Advance `elem` admitted
                && all (\case Advance -> True; Convict _ -> True; _ -> False) admitted

prop_abandonment_pays_exactly_B :: Property
prop_abandonment_pays_exactly_B = forAll genClaimCase $ \ClaimCase{..} ->
    counterexample "claim pays exactly B to the hunter recorded at arm time" $
        case dispatch ccParams ccEnv ccConfig ccTx of
            Right cfg' ->
                state cfg' == Frozen ccSeq
                    && outflows (ledger cfg')
                        == outflows (ledger ccConfig)
                            ++ [Transfer ccHunter (bond ccParams) Bounty]
                    && deposits (ledger cfg') == deposits (ledger ccConfig)
            Left _ -> False

prop_close_lie_always_voidable :: Property
prop_close_lie_always_voidable = forAll genClosingBehindCase $ \ClosingCase{..} ->
    counterexample "behind Closing admits both challengeClose and direct advance" $
        isRight (dispatch clParams clEnv clConfig (Tx clSlot (ChallengeClose clActor)))
            && isRight (dispatch clParams clEnv clConfig (Tx clSlot Advance))

prop_close_at_tip_unchallengeable :: Property
prop_close_at_tip_unchallengeable = forAll genClosingAtTipCase $ \ClosingCase{..} ->
    counterexample "at-tip Closing rejects both voids and finalizes after deadline" $
        isLeft (dispatch clParams clEnv clConfig (Tx clSlot (ChallengeClose clActor)))
            && isLeft (dispatch clParams clEnv clConfig (Tx clSlot Advance))
            && isRight (dispatch clParams clEnv clConfig (Tx clDeadline FinalizeClose))

prop_current_state_is_quiet :: Property
prop_current_state_is_quiet = forAll genCurrentCase $ \CurrentCase{..} ->
    let actions = actionUniverse curRefund
        admitted =
            [ act
            | act <- actions
            , isRight (dispatch curParams curEnv curConfig (Tx curSlot act))
            ]
     in counterexample "at-tip fork-free Active admits only capability closeIntent" $
            admitted == [CloseIntent curRefund]

prop_value_conservation :: Property
prop_value_conservation = forAll genValidStep $ \ValidStep{..} ->
    counterexample "Step.preserves_balanced: every constructor preserves balance" $
        balanced vsParams vsConfig
            && case dispatch vsParams vsEnv vsConfig vsTx of
                Right cfg' -> balanced vsParams cfg'
                Left _ -> False

prop_convict_dominance :: Property
prop_convict_dominance = forAll genConvictCase $ \ConvictCase{..} ->
    counterexample "fork evidence admits convict from every generated live state" $
        live (state cvConfig)
            && isRight (dispatch cvParams cvEnv cvConfig (Tx cvSlot (Convict cvActor)))

prop_tombstone_terminal_but_no_aid_bar :: Property
prop_tombstone_terminal_but_no_aid_bar = forAll genTombstoneSystemCase $ \TombstoneSystemCase{..} ->
    let terminal = all (isLeft . dispatch tsParams tsEnv tsTombstone . Tx tsSlot) (actionUniverse tsActor)
        registered = sysDispatch tsParams tsEnv tsSystem tsFreshId (Tx tsSlot Register)
     in counterexample "tombstone is terminal while a distinct same-AID instance registers" $
            terminal
                && case registered of
                    Right sys' ->
                        lookupInstance tsTombstoneId sys' == Just tsTombstone
                            && fmap state (lookupInstance tsFreshId sys') == Just (Active 0)
                    Left _ -> False

-- Standalone generators and state-machine case builders.

data AdvanceCase = AdvanceCase
    { acParams :: Params
    , acEnv :: Env
    , acConfig :: Config
    , acTx :: Tx
    , acSeq :: Seq
    }
    deriving stock (Show)

genAdvanceCase :: Gen AdvanceCase
genAdvanceCase = do
    p <- genParams
    k <- genSeq
    t <- genSlot
    actor <- genAddr
    source <- elements [Active k, Armed k actor (t + 1), Frozen k, Closing k actor t]
    let env = Env [0 .. k + 1] False [k]
    pure (AdvanceCase p env (balancedConfig p source) (Tx t Advance) k)

data ArmedWindowCase = ArmedWindowCase
    { awParams :: Params
    , awEnv :: Env
    , awConfig :: Config
    , awSlot :: Slot
    , awHunter :: Addr
    }
    deriving stock (Show)

genArmedWindowCase :: Gen ArmedWindowCase
genArmedWindowCase = do
    p <- genParams
    k <- genSeq
    t <- genSlot
    hunter <- genAddr
    fork <- elements [False, True]
    let s = Armed k hunter (t + 1)
    pure (ArmedWindowCase p (Env [0 .. k + 1] fork [k]) (balancedConfig p s) t hunter)

data ClaimCase = ClaimCase
    { ccParams :: Params
    , ccEnv :: Env
    , ccConfig :: Config
    , ccTx :: Tx
    , ccSeq :: Seq
    , ccHunter :: Addr
    }
    deriving stock (Show)

genClaimCase :: Gen ClaimCase
genClaimCase = do
    p <- genParams
    k <- genSeq
    deadline <- genSlot
    delay <- chooseInteger (0, 20)
    hunter <- genAddr
    let s = Armed k hunter deadline
    pure (ClaimCase p (Env [0 .. k + 1] False [k]) (balancedConfig p s) (Tx (deadline + delay) Claim) k hunter)

data ClosingCase = ClosingCase
    { clParams :: Params
    , clEnv :: Env
    , clConfig :: Config
    , clSlot :: Slot
    , clDeadline :: Slot
    , clActor :: Addr
    }
    deriving stock (Show)

genClosingBehindCase :: Gen ClosingCase
genClosingBehindCase = genClosingCase True

genClosingAtTipCase :: Gen ClosingCase
genClosingAtTipCase = genClosingCase False

genClosingCase :: Bool -> Gen ClosingCase
genClosingCase isBehind = do
    p <- genParams
    k <- genSeq
    t <- genSlot
    wait <- chooseInteger (1, 20)
    actor <- genAddr
    let deadline = t + wait
        events = if isBehind then [0 .. k + 1] else [0 .. k]
        s = Closing k actor deadline
    pure (ClosingCase p (Env events False [k]) (balancedConfig p s) t deadline actor)

data CurrentCase = CurrentCase
    { curParams :: Params
    , curEnv :: Env
    , curConfig :: Config
    , curSlot :: Slot
    , curRefund :: Addr
    }
    deriving stock (Show)

genCurrentCase :: Gen CurrentCase
genCurrentCase = do
    p <- genParams
    k <- genSeq
    t <- genSlot
    CurrentCase p (Env [0 .. k] False [k]) (balancedConfig p (Active k)) t
        <$> genAddr

data ValidStep = ValidStep
    { vsParams :: Params
    , vsEnv :: Env
    , vsConfig :: Config
    , vsTx :: Tx
    }
    deriving stock (Show)

genValidStep :: Gen ValidStep
genValidStep = do
    p <- genParams
    k <- genSeq
    t <- genSlot
    actor <- genAddr
    which <- chooseInteger (0, 13)
    let ahead = Env [0 .. k + 1] False [k]
        forked = ahead{forkEvidence = True}
        mk env s act = ValidStep p env (balancedConfig p s) (Tx t act)
    pure $ case which of
        0 -> ValidStep p (Env [0] False []) initConfig (Tx t Register)
        1 -> mk ahead (Active k) Advance
        2 -> mk ahead (Armed k actor (t + 1)) Advance
        3 -> mk ahead (Frozen k) Advance
        4 -> mk ahead (Closing k actor t) Advance
        5 -> mk ahead (Active k) (Arm actor)
        6 -> mk ahead (Armed k actor t) Claim
        7 -> mk ahead (Active k) (CloseIntent actor)
        8 -> mk ahead (Closing k actor t) (ChallengeClose (actor + 1))
        9 -> mk ahead (Closing k actor t) FinalizeClose
        10 -> mk forked (Active k) (Convict actor)
        11 -> mk forked (Armed k (actor + 1) t) (Convict actor)
        12 -> mk forked (Frozen k) (Convict actor)
        _ -> mk forked (Closing k actor t) (Convict actor)

data ConvictCase = ConvictCase
    { cvParams :: Params
    , cvEnv :: Env
    , cvConfig :: Config
    , cvSlot :: Slot
    , cvActor :: Addr
    }
    deriving stock (Show)

genConvictCase :: Gen ConvictCase
genConvictCase = do
    ValidStep{..} <- genValidStep
    actor <- genAddr
    liveState <- elements [Active 0, Armed 0 actor 10, Frozen 0, Closing 0 actor 10]
    pure (ConvictCase vsParams vsEnv{forkEvidence = True} (balancedConfig vsParams liveState) (slot vsTx) actor)

data TombstoneSystemCase = TombstoneSystemCase
    { tsParams :: Params
    , tsEnv :: Env
    , tsTombstone :: Config
    , tsSystem :: Sys
    , tsTombstoneId :: InstanceId
    , tsFreshId :: InstanceId
    , tsSlot :: Slot
    , tsActor :: Addr
    }
    deriving stock (Show)

genTombstoneSystemCase :: Gen TombstoneSystemCase
genTombstoneSystemCase = do
    p <- genParams
    k <- genSeq
    t <- genSlot
    actor <- genAddr
    let tombstoneId = 1
        freshId = 2
        tombstone = balancedConfig p (Tombstone k)
        sys = Sys [(tombstoneId, tombstone), (freshId, initConfig)]
    pure (TombstoneSystemCase p (Env [0 .. k + 1] True [k]) tombstone sys tombstoneId freshId t actor)

data AdvanceTotalityCase = AdvanceTotalityCase
    { atParams :: Params
    , atEnv :: Env
    , atConfig :: Config
    , atSlot :: Slot
    , atSeq :: Seq
    }
    deriving stock (Show)

genAdvanceTotalityCase :: Gen AdvanceTotalityCase
genAdvanceTotalityCase = do
    p <- genParams
    k <- chooseInteger (0, 5)
    start <- genSlot
    actor <- genAddr
    variant <- chooseInteger (0, 4)
    past <- elements [False, True]
    let env = Env [0 .. k + 1] False [0 .. k + 1]
        prefix = Tx start Register : [Tx (start + n) Advance | n <- [1 .. k]]
        activeCfg = fromRight initConfig (runTrace p env start initConfig prefix)
        t = start + k + 1
        staged = case variant of
            0 -> Right activeCfg
            1 -> dispatch p env activeCfg (Tx t (Arm actor))
            2 -> do
                armed <- dispatch p env activeCfg (Tx t (Arm actor))
                dispatch p env armed (Tx (t + freezeWindow p) Claim)
            3 -> dispatch p env activeCfg (Tx t (CloseIntent actor))
            _ -> Right activeCfg
        cfg = fromRight activeCfg staged
        chosenSlot = case state cfg of
            Armed _ _ deadline
                | past -> deadline
                | otherwise -> deadline - 1
            _ -> t
    pure (AdvanceTotalityCase p env cfg chosenSlot k)

data ReachableLiveCase = ReachableLiveCase
    { rlParams :: Params
    , rlEnv :: Env
    , rlConfig :: Config
    , rlSlot :: Slot
    }
    deriving stock (Show)

genReachableLiveCase :: Gen ReachableLiveCase
genReachableLiveCase = do
    AdvanceTotalityCase{..} <- genAdvanceTotalityCase
    pure (ReachableLiveCase atParams atEnv atConfig atSlot)

data TraceCase = TraceCase
    { tcParams :: Params
    , tcEnv :: Env
    , tcTxs :: [Tx]
    }
    deriving stock (Show)

genPermissionlessTrace :: Gen TraceCase
genPermissionlessTrace = do
    p <- genParams
    rounds <- chooseInteger (2, 8)
    choices <- vectorOf (fromIntegral rounds) (elements [False, True])
    actor <- genAddr
    let env = Env [0 .. rounds + 1] False []
        build (t, accumulated) stall =
            if stall
                then
                    ( t + freezeWindow p
                    , accumulated
                        ++ [ Tx t (Arm actor)
                           , Tx (t + freezeWindow p) Claim
                           , Tx (t + freezeWindow p) Advance
                           ]
                    )
                else (t + 1, accumulated ++ [Tx t Advance])
        (_, generatedTxs) = foldl build (1, [Tx 0 Register]) choices
    pure (TraceCase p env generatedTxs)

data BountyTraceCase = BountyTraceCase
    { btParams :: Params
    , btEnv :: Env
    , btTxs :: [Tx]
    , btArmIndex :: Int
    , btClaimIndex :: Int
    , btHunter :: Addr
    , btSeq :: Seq
    }
    deriving stock (Show)

genBountyTrace :: Gen BountyTraceCase
genBountyTrace = do
    p <- genParams
    k <- chooseInteger (0, 5)
    hunter <- genAddr
    viaChallenge <- elements [False, True]
    let env = Env [0 .. k + 1] False [0 .. k]
        prefix = Tx 0 Register : [Tx n Advance | n <- [1 .. k]]
        t = k + 1
        arming =
            if viaChallenge
                then [Tx t (CloseIntent (hunter + 1)), Tx t (ChallengeClose hunter)]
                else [Tx t (Arm hunter)]
        txs = prefix ++ arming ++ [Tx (t + freezeWindow p) Claim]
        armIndex = length prefix + length arming - 1
        claimIndex = length txs - 1
    pure (BountyTraceCase p env txs armIndex claimIndex hunter k)

genMixedTrace :: Gen TraceCase
genMixedTrace = do
    p <- genParams
    actor <- genAddr
    fragment <- chooseInteger (0, 4)
    let env = Env [0 .. 6] True [0 .. 6]
        txs = case fragment of
            0 -> [Tx 0 Register, Tx 1 Advance, Tx 2 (Arm actor), Tx (2 + freezeWindow p) Claim, Tx (2 + freezeWindow p) Advance]
            1 -> [Tx 0 Register, Tx 1 (CloseIntent actor), Tx (1 + closeWindow p) FinalizeClose, Tx (1 + closeWindow p) Register]
            2 -> [Tx 0 Register, Tx 1 (CloseIntent actor), Tx 1 (ChallengeClose (actor + 1)), Tx (1 + freezeWindow p) Claim]
            3 -> [Tx 0 Register, Tx 1 Advance, Tx 2 (Convict actor)]
            _ -> [Tx 0 Register, Tx 1 (Arm actor), Tx 1 (Convict (actor + 1))]
    pure (TraceCase p env txs)

data CloseTraceCase = CloseTraceCase
    { ctParams :: Params
    , ctEnv :: Env
    , ctTxs :: [Tx]
    , ctRefund :: Addr
    }
    deriving stock (Show)

genCloseTrace :: Gen CloseTraceCase
genCloseTrace = do
    p <- genParams
    refund <- genAddr
    t <- chooseInteger (1, 20)
    let env = Env [0] False [0]
        txs = [Tx 0 Register, Tx t (CloseIntent refund), Tx (t + closeWindow p) FinalizeClose]
    pure (CloseTraceCase p env txs refund)

progressTx :: Params -> Env -> Slot -> Config -> Tx
progressTx _p _env t cfg = case state cfg of
    Active k -> Tx t (CloseIntent (k + 100))
    Armed _ _ deadline -> Tx (max t deadline) Claim
    Frozen _ -> Tx t Advance
    Closing _ _ deadline -> Tx (max t deadline) FinalizeClose
    Absent -> Tx t Register
    Tombstone _ -> Tx t Register

actionUniverse :: Addr -> [Action]
actionUniverse actor =
    [ Register
    , Advance
    , Arm actor
    , Claim
    , CloseIntent actor
    , ChallengeClose actor
    , FinalizeClose
    , Convict actor
    ]

between :: Int -> Int -> [a] -> [a]
between i j = take (j - i - 1) . drop (i + 1)

balancedConfig :: Params -> MachState -> Config
balancedConfig p s = Config s (Ledger (carried p s) [])

genParams :: Gen Params
genParams =
    Params
        <$> chooseInteger (1, 20)
        <*> chooseInteger (1, 20)
        <*> chooseInteger (1, 20)
        <*> chooseInteger (1, 20)
        <*> chooseInteger (1, 20)

genSeq :: Gen Seq
genSeq = chooseInteger (0, 10)

genSlot :: Gen Slot
genSlot = chooseInteger (0, 100)

genAddr :: Gen Addr
genAddr = chooseInteger (1, 1_000)

assertWith :: String -> Bool -> PropertyM IO ()
assertWith label verdict = do
    monitor (counterexample label)
    assert verdict
