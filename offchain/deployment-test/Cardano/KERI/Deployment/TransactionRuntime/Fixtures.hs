{- |
Module      : Cardano.KERI.Deployment.TransactionRuntime.Fixtures
Description : Non-degenerate Conway protocol parameters for Slice 2 tests

RULING-002 condition C2: no test in this repository constructs a
'PParams ConwayEra', and a JSON fixture is outside the Slice 2 fence.
'testPParams' is therefore a Haskell record update over 'emptyPParams' —
'Cardano.Ledger.Core.PParams.emptyPParams' is all-zero, which would make
fee, min-UTxO, and 'ppMaxTxExUnits' assertions vacuous (a green that does
not entail the mechanism). Every field this slice's assertions depend on is
set to a real, non-zero, realistic value.

The PlutusV3 cost model is the 251-parameter array published in
@cardano-node-clients@'s own end-to-end devnet genesis,
@e2e-test\/genesis\/conway-genesis.json@ (\@\/home\/paolino\/cardano-node-clients\/e2e-test\/genesis\/conway-genesis.json\@
on this host) — a real Plutus V3 cost model taken from a real Conway
genesis, not fabricated numbers. It is accepted as-is by this repository's
pinned @cardano-ledger-core@ (verified with @mkCostModel PlutusV3@ against
this exact array before this module was written).

/DIRECTION-005 SS2 — what this parameter choice does and does not prove:/
this slice's evaluator is a controlled stand-in; no Plutus script actually
executes against these cost models. So the tests built on 'testPParams' can
prove that the script-integrity hash is computed over the transaction's own
redeemers and datums, is present whenever a program carries redeemers, and
changes when they change. They cannot and do not prove that the resulting
hash, or the transaction it is embedded in, is one a real ledger would
accept -- the same construction-evidence\/validator-evidence boundary
DIRECTION-004 draws for @withDevnet@. Read every assertion built on this
fixture under that boundary.
-}
module Cardano.KERI.Deployment.TransactionRuntime.Fixtures (
    testPParams,

    -- * \#232 bounded-collateral proof oracle
    statedMaximumCollateralLovelace,
    statedRequiredCollateral,
    withCollateralPercentage,
    withFixedFee,
    shouldDeclareBoundedCollateral,
    shouldDeclareNoCollateral,
) where

import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.PParams (
    PParams,
    emptyPParams,
    ppCoinsPerUTxOByteL,
    ppCollateralPercentageL,
    ppCostModelsL,
    ppKeyDepositL,
    ppMaxCollateralInputsL,
    ppMaxTxExUnitsL,
    ppTxFeeFixedL,
    ppTxFeePerByteL,
 )
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    collateralReturnTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    totalCollateralTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    coinTxOutL,
    getMinCoinTxOut,
    valueTxOutL,
 )
import Cardano.Ledger.BaseTypes (StrictMaybe (SJust, SNothing))
import Cardano.Ledger.Coin (Coin (..), CoinPerByte (..), compactCoinOrError)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.CostModels (CostModels, mkCostModel, mkCostModels)
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Word (Word16)
import GHC.Stack (HasCallStack)
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Expectation, expectationFailure, shouldBe)

{- | Real, non-degenerate Conway protocol parameters. Non-zero minimum fee
coefficients, a real @coinsPerUTxOByte@, mainnet-shaped 'ppMaxTxExUnits', a
genuine collateral percentage/input cap, and a real PlutusV3 cost model —
sufficient for 'Cardano.Tx.Build.build'\'s fee estimation, min-UTxO
compensation, balancing, and script-integrity hash to all do real,
non-vacuous work.
-}
testPParams :: PParams ConwayEra
testPParams =
    requireNonZeroKeyDeposit $
        emptyPParams
            & ppTxFeePerByteL .~ CoinPerByte (compactCoinOrError (Coin 44))
            & ppTxFeeFixedL .~ Coin 155_381
            & ppCoinsPerUTxOByteL .~ CoinPerByte (compactCoinOrError (Coin 4_310))
            & ppKeyDepositL .~ Coin 2_000_000
            & ppMaxTxExUnitsL .~ ExUnits 14_000_000 10_000_000_000
            & ppCollateralPercentageL .~ 150
            & ppMaxCollateralInputsL .~ 3
            & ppCostModelsL .~ testCostModels

{- | Fail closed if the fixture's lifecycle-certificate oracle becomes
degenerate. This guard deliberately reads the completed fixture rather than
the literal assigned above, so a future record-update refactor cannot bypass
the invariant accidentally.
-}
requireNonZeroKeyDeposit :: PParams ConwayEra -> PParams ConwayEra
requireNonZeroKeyDeposit pparams =
    case pparams ^. ppKeyDepositL of
        Coin deposit
            | deposit > 0 -> pparams
        deposit ->
            error $
                "Fixtures.testPParams: ppKeyDepositL must be positive, got "
                    <> show deposit

-- ---------------------------------------------------------------------------
-- #232 bounded-collateral proof oracle

{- | The product's absolute phase-2 loss ceiling, stated by the proof itself:
**5,000,000 lovelace**. Deliberately a literal here rather than an import of
'Cardano.KERI.Deployment.TransactionRuntime.maximumCollateralLovelace' — a
proof that reads the constant it exists to police cannot go RED when that
constant drifts (INV-232-LOSS-BOUND).
-}
statedMaximumCollateralLovelace :: Coin
statedMaximumCollateralLovelace = Coin 5_000_000

{- | The exact protocol-required total collateral for a final fee, derived
independently of the implementation under test: @ceiling (fee * p / 100)@ for
the snapshot's collateral percentage @p@ (DATA-INV-232-01).
-}
statedRequiredCollateral :: PParams ConwayEra -> Coin -> Coin
statedRequiredCollateral pparams (Coin fee) =
    Coin ((fee * percent + 99) `div` 100)
  where
    percent = fromIntegral (pparams ^. ppCollateralPercentageL)

{- | Raise a snapshot's flat fee component. This drives a real converged build
past the 5,000,000-lovelace ceiling deterministically, without depending on the
transaction size any particular operation happens to produce — so the
cap-breach negative control cannot silently stop exercising the cap because a
body got smaller.
-}
withFixedFee :: Coin -> PParams ConwayEra -> PParams ConwayEra
withFixedFee fixedFee pparams = pparams & ppTxFeeFixedL .~ fixedFee

{- | Replace the snapshot's collateral percentage.

Every fixture in this repository used to sit at the mainnet default of 150,
which made "reads the protocol parameter" indistinguishable from "happens to
equal the value it would have read": hardcoding 150 in production passed every
example. Varying @p@ is what closes that gap, so this helper exists to be used
across the parameter's legal range — not to add one or two more constants.
-}
withCollateralPercentage :: Word16 -> PParams ConwayEra -> PParams ConwayEra
withCollateralPercentage percentage pparams =
    pparams & ppCollateralPercentageL .~ fromIntegral percentage

{- | Assert every \#232 bounded-collateral property of one converged body
against the snapshot that balanced it and the resolved collateral input:
exact protocol arithmetic, the absolute maximum, exact and disjoint collateral
input identity, and one present ADA-only min-UTxO-valid return to the funding
address that conserves the input exactly
(DATA-INV-232-01 through DATA-INV-232-05).
-}
shouldDeclareBoundedCollateral ::
    (HasCallStack) =>
    PParams ConwayEra ->
    -- | the operation's funding address, which must receive the remainder
    Addr ->
    -- | the resolved collateral input
    (TxIn, TxOut ConwayEra) ->
    ConwayTx ->
    Expectation
shouldDeclareBoundedCollateral
    pparams
    fundingAddress
    (collateralIn, collateralOut)
    tx = do
        adaOnly collateralOut
            `orFail` "#232: the resolved collateral input is not ADA-only"
        body ^. collateralInputsTxBodyL `shouldBe` Set.singleton collateralIn
        not (Set.member collateralIn (body ^. inputsTxBodyL))
            `orFail` "#232: the collateral input is also a regular spending input"
        case (body ^. totalCollateralTxBodyL, body ^. collateralReturnTxBodyL) of
            (SNothing, _) ->
                expectationFailure $
                    "#232: no total_collateral declared; the exact requirement is "
                        <> show required
            (_, SNothing) ->
                expectationFailure $
                    "#232: no collateral_return declared, so the whole "
                        <> show available
                        <> " is exposed to a phase-2 failure"
            (SJust declaredTotal, SJust returnOut) -> do
                declaredTotal `shouldBe` required
                (declaredTotal <= statedMaximumCollateralLovelace)
                    `orFail` ( "#232: declared total collateral "
                                <> show declaredTotal
                                <> " exceeds the stated maximum "
                                <> show statedMaximumCollateralLovelace
                             )
                returnOut ^. addrTxOutL `shouldBe` fundingAddress
                adaOnly returnOut
                    `orFail` "#232: the collateral return is not ADA-only"
                let returned = returnOut ^. coinTxOutL
                    minimumReturn = getMinCoinTxOut pparams returnOut
                (returned >= minimumReturn)
                    `orFail` ( "#232: collateral return "
                                <> show returned
                                <> " is below its min-UTxO requirement "
                                <> show minimumReturn
                             )
                let Coin totalLovelace = declaredTotal
                    Coin returnedLovelace = returned
                Coin (totalLovelace + returnedLovelace) `shouldBe` available
      where
        body = tx ^. bodyTxL
        required = statedRequiredCollateral pparams (body ^. feeTxBodyL)
        available = collateralOut ^. coinTxOutL

{- | Assert that a script-free body invents no collateral commitment at all:
no collateral inputs, and both Conway collateral fields absent
(DATA-INV-232-06).
-}
shouldDeclareNoCollateral :: (HasCallStack) => ConwayTx -> Expectation
shouldDeclareNoCollateral tx = do
    body ^. collateralInputsTxBodyL `shouldBe` Set.empty
    body ^. totalCollateralTxBodyL `shouldBe` SNothing
    body ^. collateralReturnTxBodyL `shouldBe` SNothing
  where
    body = tx ^. bodyTxL

adaOnly :: TxOut ConwayEra -> Bool
adaOnly txOut =
    case txOut ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) -> Map.null assets

orFail :: (HasCallStack) => Bool -> String -> Expectation
orFail True _ = pure ()
orFail False message = expectationFailure message

testCostModels :: CostModels
testCostModels =
    case mkCostModel PlutusV3 plutusV3CostModelParams of
        Left err ->
            error ("Fixtures.testCostModels: real cost model rejected: " <> show err)
        Right costModel -> mkCostModels (Map.singleton PlutusV3 costModel)

{- | Verbatim @plutusV3CostModel@ array from @cardano-node-clients@'s
end-to-end devnet Conway genesis (251 parameters).
-}
plutusV3CostModelParams :: [Int64]
plutusV3CostModelParams =
    [ 100788
    , 420
    , 1
    , 1
    , 1000
    , 173
    , 0
    , 1
    , 1000
    , 59957
    , 4
    , 1
    , 11183
    , 32
    , 201305
    , 8356
    , 4
    , 16000
    , 100
    , 16000
    , 100
    , 16000
    , 100
    , 16000
    , 100
    , 16000
    , 100
    , 16000
    , 100
    , 100
    , 100
    , 16000
    , 100
    , 94375
    , 32
    , 132994
    , 32
    , 61462
    , 4
    , 72010
    , 178
    , 0
    , 1
    , 22151
    , 32
    , 91189
    , 769
    , 4
    , 2
    , 85848
    , 123203
    , 7305
    , -900
    , 1716
    , 549
    , 57
    , 85848
    , 0
    , 1
    , 1
    , 1000
    , 42921
    , 4
    , 2
    , 24548
    , 29498
    , 38
    , 1
    , 898148
    , 27279
    , 1
    , 51775
    , 558
    , 1
    , 39184
    , 1000
    , 60594
    , 1
    , 141895
    , 32
    , 83150
    , 32
    , 15299
    , 32
    , 76049
    , 1
    , 13169
    , 4
    , 22100
    , 10
    , 28999
    , 74
    , 1
    , 28999
    , 74
    , 1
    , 43285
    , 552
    , 1
    , 44749
    , 541
    , 1
    , 33852
    , 32
    , 68246
    , 32
    , 72362
    , 32
    , 7243
    , 32
    , 7391
    , 32
    , 11546
    , 32
    , 85848
    , 123203
    , 7305
    , -900
    , 1716
    , 549
    , 57
    , 85848
    , 0
    , 1
    , 90434
    , 519
    , 0
    , 1
    , 74433
    , 32
    , 85848
    , 123203
    , 7305
    , -900
    , 1716
    , 549
    , 57
    , 85848
    , 0
    , 1
    , 1
    , 85848
    , 123203
    , 7305
    , -900
    , 1716
    , 549
    , 57
    , 85848
    , 0
    , 1
    , 955506
    , 213312
    , 0
    , 2
    , 270652
    , 22588
    , 4
    , 1457325
    , 64566
    , 4
    , 20467
    , 1
    , 4
    , 0
    , 141992
    , 32
    , 100788
    , 420
    , 1
    , 1
    , 81663
    , 32
    , 59498
    , 32
    , 20142
    , 32
    , 24588
    , 32
    , 20744
    , 32
    , 25933
    , 32
    , 24623
    , 32
    , 43053543
    , 10
    , 53384111
    , 14333
    , 10
    , 43574283
    , 26308
    , 10
    , 16000
    , 100
    , 16000
    , 100
    , 962335
    , 18
    , 2780678
    , 6
    , 442008
    , 1
    , 52538055
    , 3756
    , 18
    , 267929
    , 18
    , 76433006
    , 8868
    , 18
    , 52948122
    , 18
    , 1995836
    , 36
    , 3227919
    , 12
    , 901022
    , 1
    , 166917843
    , 4307
    , 36
    , 284546
    , 36
    , 158221314
    , 26549
    , 36
    , 74698472
    , 36
    , 333849714
    , 1
    , 254006273
    , 72
    , 2174038
    , 72
    , 2261318
    , 64571
    , 4
    , 207616
    , 8310
    , 4
    , 1293828
    , 28716
    , 63
    , 0
    , 1
    , 1006041
    , 43623
    , 251
    , 0
    , 1
    ]
