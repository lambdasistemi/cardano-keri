{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryDeploySpec
Description : a registry is deployed in order, from one seed, and reports what landed

A deployment runs against a chain that keeps its unspent outputs and refuses a
transaction that spends what is not there, spends what is already spent, or does
not balance: the lovelace its inputs hold are what its outputs, its fee, its
donation and the deposits it pays take. On it the deployment is observed from
outside: the transactions it submits, the outputs they leave, what it reports
and what it writes. Every expected value is spelled out here or derived again
from the facts the deployment names, never read back from the code that made it.
-}
module Cardano.KERI.Deployment.RegistryDeploySpec (
    spec,

    -- * The chain, for the specs of the command
    Chain (..),
    Faults (..),
    noFaults,
    walletAddress,
    walletOutputs,
    expectedSeedIn,
    lifecycleAccount,
    registrationsOf,
    testTerms,
    newChain,
    chainRuntime,
    deployOn,
    loadTestBlueprint,
    pricedParameters,
) where

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    OutputReference (..),
    RegistryIdentity (..),
    configurationTokenName,
    stateTokenName,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), ValidityEnd (..))
import Cardano.KERI.Deployment.RegistryDeploy
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord (..), ScriptReference (..))
import Cardano.KERI.Deployment.RegistryTransactions (
    outputReferenceOf,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint (..),
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    loadBlueprint,
    mkCageScript,
    scriptHashBytes,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionRuntime (..),
    transactionId,
 )
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (AccountAddress (..), AccountId (..), Addr (..))
import Cardano.Ledger.Alonzo.PParams (ppPricesL)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (UnknownTxIn))
import Cardano.Ledger.Alonzo.Scripts (Prices (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), binaryDataToData)
import Cardano.Ledger.Api.Tx (bodyTxL, estimateMinFeeTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    outputsTxBodyL,
    treasuryDonationTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
    getMinCoinTxOut,
    mkBasicTxOut,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (
    Inject (..),
    Network (..),
    StrictMaybe (SJust),
    TxIx (..),
    boundRational,
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxCert (
    ConwayDelegCert (ConwayRegCert),
    ConwayTxCert (ConwayTxCertDeleg),
 )
import Cardano.Ledger.Core (PParams, Script, ppMaxTxSizeL)
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..), extractHash, unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..), unTxId)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Control.Exception (throwIO)
import Control.Monad (forM_, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (isRight)
import Data.Foldable (toList)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Word (Word8)
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import System.Environment (getEnv)
import Test.Hspec (Spec, beforeAll, describe, expectationFailure, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------
-- A chain that keeps its outputs
-- ---------------------------------------------------------------------

data Chain = Chain
    { chainOutputs :: !(Map TxIn (TxOut ConwayEra))
    , chainAccepted :: ![ConwayTx]
    -- ^ the transactions accepted, newest first
    , chainSubmissions :: !Int
    -- ^ every submission attempted, accepted or not
    , chainEvaluations :: !Int
    , chainObservations :: !Int
    , chainCalls :: !Int
    -- ^ every call the runtime answered
    , chainReported :: ![Landed]
    -- ^ what the deployment reported as it settled, newest first
    , chainReportedAtSubmission :: ![Int]
    -- ^ how many transactions had been reported when each submission arrived, newest first
    , chainRegistered :: !(Set AccountAddress)
    -- ^ the reward accounts the chain holds registered
    }

-- | What goes wrong, and when. Counts start at zero.
data Faults = Faults
    { rejectSubmissionAt :: !(Maybe Int)
    -- ^ the submission with this number is refused by the node
    , failObservationAt :: !(Maybe Int)
    -- ^ the observation with this number never sees the transaction settle
    , afterAccepted :: Int -> Chain -> Chain
    -- ^ what the world does after the n-th accepted transaction
    , distortEvaluation ::
        Int ->
        EvaluateTxResult ConwayEra ->
        EvaluateTxResult ConwayEra
    -- ^ what the node answers to the n-th evaluation, from what it would answer
    }

noFaults :: Faults
noFaults =
    Faults
        { rejectSubmissionAt = Nothing
        , failObservationAt = Nothing
        , afterAccepted = const id
        , distortEvaluation = const id
        }

walletAddress :: Addr
walletAddress =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromBytes (BS.replicate 28 0x11)))))
        StakeRefNull

txInOf :: Word8 -> Integer -> TxIn
txInOf n index =
    TxIn
        (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 n)))))
        (TxIx (fromInteger index))

ada :: Integer -> Coin
ada = Coin . (* 1_000_000)

{- | The wallet before the deployment: a dust output, an output that holds a
token, the output the registry will be created from (the least of those that
hold lovelace alone and at least ten ada), and the outputs that pay for the
rest.
-}
walletOutputs :: [(TxIn, TxOut ConwayEra)]
walletOutputs =
    [ (txInOf 0xa1 0, mkBasicTxOut walletAddress (inject (ada 3)))
    , (txInOf 0xa2 0, mkBasicTxOut walletAddress (MaryValue (ada 15) tokenAsset))
    , (expectedSeedIn, mkBasicTxOut walletAddress (inject (ada 22)))
    , (txInOf 0xa4 0, mkBasicTxOut walletAddress (inject (ada 30)))
    , (txInOf 0xa5 2, mkBasicTxOut walletAddress (inject (ada 5_000)))
    , (txInOf 0xa6 1, mkBasicTxOut walletAddress (inject (ada 4_000)))
    ]
  where
    tokenAsset =
        MultiAsset
            ( Map.singleton
                (PolicyID (scriptHashOf 0x77))
                (Map.singleton (AssetName (SBS.toShort "token")) 1)
            )

-- | The output the registry of these tests is created from.
expectedSeedIn :: TxIn
expectedSeedIn = txInOf 0xa3 4

scriptHashOf :: Word8 -> ScriptHash
scriptHashOf n = ScriptHash (fromJust (hashFromBytes (BS.replicate 28 n)))

newChain :: [(TxIn, TxOut ConwayEra)] -> Chain
newChain outputs = Chain (Map.fromList outputs) [] 0 0 0 0 [] [] Set.empty

{- | Protocol parameters whose prices are not zero, so a fee follows the units a
transaction declares.
-}
pricedParameters :: PParams ConwayEra
pricedParameters =
    testPParams
        & ppMaxTxSizeL .~ 16_384
        & ppPricesL
            .~ Prices
                { prMem = fromJust (boundRational (577 % 10_000))
                , prSteps = fromJust (boundRational (721 % 10_000_000))
                }

-- | Deploy over the chain of 'chainRuntime', recording each transaction as it is reported.
deployOn :: Faults -> IORef Chain -> DeployRequest -> IO (Either DeployFailure Deployed)
deployOn faults chainRef =
    deployRegistry (chainRuntime faults chainRef) $ \landed ->
        modifyIORef' chainRef (\c -> c{chainReported = landed : chainReported c})

{- | The runtime of a deployment over a chain: reads answer from the outputs it
holds, a submission is accepted when it spends what exists and balances, and
the faults say what goes wrong.
-}
chainRuntime :: Faults -> IORef Chain -> RegistryRuntime
chainRuntime faults chainRef =
    RegistryRuntime
        { rtNetwork = Testnet
        , rtUtxosAt = \address -> do
            touch
            chain <- readIORef chainRef
            pure
                [ output
                | output@(_, out) <- Map.toList (chainOutputs chain)
                , out ^. addrTxOutL == address
                ]
        , rtOutputs = \wanted -> do
            touch
            chain <- readIORef chainRef
            pure (Map.restrictKeys (chainOutputs chain) wanted)
        , rtTransactions =
            TransactionRuntime
                { trQueryProtocolParams = touch >> pure pricedParameters
                , trEvaluate = \tx -> do
                    touch
                    n <- atomicModifyIORef' chainRef (\c -> (c{chainEvaluations = chainEvaluations c + 1}, chainEvaluations c))
                    let Redeemers purposes = tx ^. witsTxL . rdmrsTxWitsL
                        honest = Map.map (const (Right (ExUnits 1_000_000 400_000_000))) purposes
                    pure (distortEvaluation faults n honest)
                , trSign = \tx -> touch >> pure (Right tx)
                , trSubmit = \tx -> do
                    touch
                    submit tx
                , trObserve = \txId -> do
                    touch
                    n <- atomicModifyIORef' chainRef (\c -> (c{chainObservations = chainObservations c + 1}, chainObservations c))
                    when (Just n == failObservationAt faults) $
                        throwIO (userError ("transaction not seen settled: " <> show txId))
                }
        , rtRewardRegistered = \account -> do
            touch
            Set.member account . chainRegistered <$> readIORef chainRef
        , rtObserve = fail "a deployment reads no time"
        , rtNowMs = fail "a deployment reads no time"
        , rtValidityEnd = pure EndNotSet
        }
  where
    touch = modifyIORef' chainRef (\c -> c{chainCalls = chainCalls c + 1})
    submit tx = do
        modifyIORef' chainRef (\c -> c{chainReportedAtSubmission = length (chainReported c) : chainReportedAtSubmission c})
        n <- atomicModifyIORef' chainRef (\c -> (c{chainSubmissions = chainSubmissions c + 1}, chainSubmissions c))
        chain <- readIORef chainRef
        if Just n == rejectSubmissionAt faults
            then pure (Rejected "the node refuses this transaction")
            else case refusal chain tx of
                Just reason -> pure (Rejected reason)
                Nothing -> do
                    let txId = transactionId tx
                        spent = tx ^. bodyTxL . inputsTxBodyL
                        made =
                            Map.fromList
                                [ (TxIn txId (TxIx ix), out)
                                | (ix, out) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
                                ]
                        accepted = length (chainAccepted chain)
                        chain' =
                            chain
                                { chainOutputs = Map.union made (Map.withoutKeys (chainOutputs chain) spent)
                                , chainAccepted = tx : chainAccepted chain
                                , chainRegistered = chainRegistered chain <> registrationsOf tx
                                }
                    modifyIORef' chainRef (const (afterAccepted faults accepted chain'))
                    pure (Submitted txId)

-- | A script to put in an output as a reference script: the application's, from the blueprint.
referenceCarrier :: Blueprint -> IO (Script ConwayEra)
referenceCarrier blueprint = do
    scripts <-
        either fail pure $
            deriveRegistryScripts stateTemplate testTerms (outputReferenceOf expectedSeedIn) blueprint
    pure (mkCageScript (artifactProgram (scriptsApplication scripts)))

-- | The reward account of the registration observer, the same for every registry deployed with these terms.
lifecycleAccount :: Blueprint -> IO AccountAddress
lifecycleAccount blueprint = do
    scripts <-
        either fail pure $
            deriveRegistryScripts stateTemplate testTerms (outputReferenceOf expectedSeedIn) blueprint
    pure $
        AccountAddress
            Testnet
            (AccountId (ScriptHashObj (artifactScriptHash (observerLifecycle (scriptsObservers scripts)))))

-- | The reward accounts a transaction registers.
registrationsOf :: ConwayTx -> Set AccountAddress
registrationsOf tx =
    Set.fromList
        [ AccountAddress Testnet (AccountId credential)
        | ConwayTxCertDeleg (ConwayRegCert credential _) <- toList (tx ^. bodyTxL . certsTxBodyL)
        ]

-- | Why the chain refuses a transaction, if it does.
refusal :: Chain -> ConwayTx -> Maybe ByteString
refusal chain tx
    | not (all (`Map.member` chainOutputs chain) inputs) = Just "an input is not unspent"
    | inputsCoin /= outputsCoin + paid + donation + deposits = Just "the transaction does not balance"
    | any (`Set.member` chainRegistered chain) (Set.toList (registrationsOf tx)) = Just "the credential is already registered"
    | paid < minimumFee = Just "the fee is below the minimum"
    | any belowMinimum (tx ^. bodyTxL . outputsTxBodyL) = Just "an output is below its minimum"
    | otherwise = Nothing
  where
    inputs = toList (tx ^. bodyTxL . inputsTxBodyL)
    valueOf out = let Coin c = out ^. coinTxOutL in c
    inputsCoin = sum [valueOf out | ref <- inputs, Just out <- [Map.lookup ref (chainOutputs chain)]]
    outputsCoin = sum (map valueOf (toList (tx ^. bodyTxL . outputsTxBodyL)))
    Coin paid = tx ^. bodyTxL . feeTxBodyL
    Coin donation = tx ^. bodyTxL . treasuryDonationTxBodyL
    deposits =
        sum
            [ d
            | ConwayTxCertDeleg (ConwayRegCert _ (SJust (Coin d))) <- toList (tx ^. bodyTxL . certsTxBodyL)
            ]
    Coin minimumFee = estimateMinFeeTx pricedParameters tx 1 0 0
    belowMinimum out = valueOf out < let Coin least = getMinCoinTxOut pricedParameters out in least

-- ---------------------------------------------------------------------
-- The terms and the blueprint
-- ---------------------------------------------------------------------

-- | The terms the deployments of these tests are given, a test network's.
testTerms :: RegistryTerms
testTerms =
    RegistryTerms
        { registryCheckpointTerms =
            CheckpointTerms
                { termsNetwork = 0
                , termsDeposit = 1_000_000_000
                , termsFreezeBond = 5_000_000
                , termsPremium = 2_000_000
                }
        , registryParameters =
            ApplicationParameters
                { registrationCost = 1_000_000
                , minimumTip = 500_000
                , processTime = 90_000
                , bookingWidth = 5_000
                }
        , registryMinimumAda = 2_000_000
        , registryTerminationCarrier = 1_500_000
        }

loadTestBlueprint :: IO Blueprint
loadTestBlueprint = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    loadBlueprint path >>= either fail pure

requestFor :: Blueprint -> RegistryTerms -> DeployRequest
requestFor blueprint terms =
    DeployRequest
        { requestTerms = terms
        , requestBlueprint = blueprint
        , requestPayer = walletAddress
        , requestReferenceLovelace = Nothing
        }

-- | Run a deployment on a fresh chain.
runOn :: Faults -> Blueprint -> RegistryTerms -> [(TxIn, TxOut ConwayEra)] -> IO (Either DeployFailure Deployed, Chain)
runOn faults blueprint terms outputs = do
    chainRef <- newIORef (newChain outputs)
    outcome <- deployOn faults chainRef (requestFor blueprint terms)
    chain <- readIORef chainRef
    pure (outcome, chain)

-- ---------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------

spec :: Spec
spec = describe "#351 deploying a registry" $ do
    describe "the terms" $ do
        it "are refused by name, every one that applies" $ do
            let at f = testTerms{registryParameters = f (registryParameters testTerms)}
                checkpointAt f = testTerms{registryCheckpointTerms = f (registryCheckpointTerms testTerms)}
            refuseTerms testTerms `shouldBe` []
            refuseTerms (at (\p -> p{registrationCost = -1})) `shouldBe` [NegativeTerm "registration-cost"]
            refuseTerms (at (\p -> p{minimumTip = -1})) `shouldBe` [NegativeTerm "minimum-tip"]
            refuseTerms (at (\p -> p{processTime = -1})) `shouldBe` [NegativeTerm "process-time"]
            refuseTerms (at (\p -> p{bookingWidth = -1})) `shouldBe` [NegativeTerm "booking-width"]
            refuseTerms (checkpointAt (\c -> c{termsPremium = -1})) `shouldBe` [NegativeTerm "premium"]
            refuseTerms (checkpointAt (\c -> c{termsDeposit = 1})) `shouldBe` [DepositBelowFloor]
            refuseTerms (checkpointAt (\c -> c{termsFreezeBond = 1})) `shouldBe` [FreezeBondBelowFloor]
            refuseTerms (checkpointAt (\c -> c{termsNetwork = 2})) `shouldBe` [NetworkDiscriminatorNotZeroOrOne]
            refuseTerms testTerms{registryMinimumAda = 2_000_001} `shouldBe` [MinimumAdaNotTheCheckpoints]
            refuseTerms testTerms{registryTerminationCarrier = 1_500_001}
                `shouldBe` [TerminationCarrierExceedsMinimumAda]
            refuseTerms testTerms{registryTerminationCarrier = -1}
                `shouldBe` [NegativeTerm "termination-carrier"]
        it "are refused only when the scripts could not be derived from them either" $ do
            blueprint <- loadTestBlueprint
            let seed' = OutputReference (BS.replicate 32 0x33) 0
                variants =
                    [ testTerms
                    , testTerms{registryCheckpointTerms = (registryCheckpointTerms testTerms){termsDeposit = 1}}
                    , testTerms{registryCheckpointTerms = (registryCheckpointTerms testTerms){termsFreezeBond = 1}}
                    , testTerms{registryCheckpointTerms = (registryCheckpointTerms testTerms){termsPremium = -1}}
                    , testTerms{registryCheckpointTerms = (registryCheckpointTerms testTerms){termsNetwork = 16}}
                    , testTerms{registryMinimumAda = 3_000_000}
                    , testTerms{registryTerminationCarrier = 2_000_000}
                    , testTerms{registryTerminationCarrier = -5}
                    ]
            forM_ variants $ \terms ->
                null (refuseTerms terms)
                    `shouldBe` isRight (deriveRegistryScripts stateTemplate terms seed' blueprint)

    describe "the seed" $ do
        it "is the output of lovelace alone with the least lovelace of at least ten ada" $ do
            fmap fst (chooseSeed walletOutputs) `shouldBe` Just expectedSeedIn
            fmap fst (chooseSeed (reverse walletOutputs)) `shouldBe` Just expectedSeedIn
        it "does not exist in a wallet of dust and of outputs that hold a token" $
            fmap fst (chooseSeed (take 2 walletOutputs)) `shouldBe` Nothing

    describe "a deployment that completes" $ beforeAll deployed $ do
        it "lands the seven transactions in order, the booking attestation policy published before the application, and reports each as it settles" $ \(outcome, chain) -> do
            result <- expectDeployed outcome
            map landedStep (deployedLanded result) `shouldBe` allSteps
            map landedStep (deployedLanded result)
                `shouldBe` [ PublishTemplate
                           , PublishAttestation
                           , PublishApplication
                           , PublishState
                           , PublishHashProof
                           , PublishCheckpoint
                           , CreateRegistry
                           ]
            map landedTransaction (deployedLanded result)
                `shouldBe` map transactionId (reverse (chainAccepted chain))
            reverse (chainReported chain) `shouldBe` deployedLanded result
            -- each is reported before the next is submitted: at the n-th submission n are reported
            reverse (chainReportedAtSubmission chain) `shouldBe` [0 .. 6]
        it "reports what each transaction paid and what it leaves locked, from the transaction itself" $ \(outcome, chain) -> do
            result <- expectDeployed outcome
            let transactions = reverse (chainAccepted chain)
                outputCoins tx = map coinOf (toList (tx ^. bodyTxL . outputsTxBodyL))
            map landedFee (deployedLanded result) `shouldBe` map fee transactions
            -- a publication locks its one published output; the change is not locked
            forM_ (take 6 (zip (deployedLanded result) transactions)) $ \(landed, tx) ->
                landedLocked landed `shouldBe` sum (take 1 (outputCoins tx))
            -- the genesis locks its state output and its configuration record
            map landedLocked (drop 6 (deployedLanded result))
                `shouldBe` [sum (take 2 (outputCoins (last transactions)))]
            -- the collateral posted is the lovelace of the outputs a transaction names, as they were when it was built
            let created =
                    Map.fromList walletOutputs
                        <> Map.fromList
                            [ (TxIn (transactionId tx) (TxIx ix), out)
                            | tx <- transactions
                            , (ix, out) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
                            ]
                collateralValue tx =
                    sum
                        [ coinOf out
                        | ref <- toList (tx ^. bodyTxL . collateralInputsTxBodyL)
                        , Just out <- [Map.lookup ref created]
                        ]
            map landedCollateral (deployedLanded result) `shouldBe` map collateralValue transactions
            -- the six publications name none; the registration and the genesis name one each
            map landedCollateral (take 6 (deployedLanded result)) `shouldBe` replicate 6 0
            forM_ (drop 6 (deployedLanded result)) $ \landed ->
                landedCollateral landed `shouldSatisfy` (> 0)
        it "chooses the seed before it derives the scripts, and the genesis spends it as its one input of that kind" $ \(outcome, chain) -> do
            result <- expectDeployed outcome
            riSeed (deployedIdentity result) `shouldBe` outputReferenceOf expectedSeedIn
            let transactions = reverse (chainAccepted chain)
                spends tx = tx ^. bodyTxL . inputsTxBodyL
                (beforeGenesis, genesisOnly) = splitAt 6 transactions
            forM_ beforeGenesis $ \tx ->
                Set.member expectedSeedIn (spends tx) `shouldBe` False
            map (Set.member expectedSeedIn . spends) genesisOnly `shouldBe` [True]
            length (filter (Set.member expectedSeedIn . spends) transactions) `shouldBe` 1
        it "writes a release identity whose facts are the deployment's" $ \(outcome, _) -> do
            result <- expectDeployed outcome
            blueprint <- loadTestBlueprint
            let identity = deployedIdentity result
                seedRef = riSeed identity
            -- the scripts are derived again, from the seed the identity names
            scripts <-
                either fail pure $
                    deriveRegistryScripts stateTemplate testTerms seedRef blueprint
            riNetwork identity `shouldBe` 0
            rlApplicationPolicy (riRelease identity)
                `shouldBe` scriptHashBytes (artifactScriptHash (scriptsApplication scripts))
            rlApplicationCredential (riRelease identity) `shouldBe` rlApplicationPolicy (riRelease identity)
            rlStatePolicy (riRelease identity) `shouldBe` scriptsStateHash scripts
            rlStateProgram (riRelease identity) `shouldBe` scriptsStateHash scripts
            riCheckpointValidator identity
                `shouldBe` scriptHashBytes (artifactScriptHash (scriptsCheckpoint scripts))
            riDeposit identity `shouldBe` 1_000_000_000
            riFreezeBond identity `shouldBe` 5_000_000
            riPremium identity `shouldBe` 2_000_000
            riMinimumAda identity `shouldBe` 2_000_000
            riTerminationCarrier identity `shouldBe` 1_500_000
            riApplicationParameters identity `shouldBe` registryParameters testTerms
        it "records where the chain holds what the deployment published and created" $ \(outcome, chain) -> do
            result <- expectDeployed outcome
            blueprint <- loadTestBlueprint
            scripts <-
                either fail pure $
                    deriveRegistryScripts
                        stateTemplate
                        testTerms
                        (riSeed (deployedIdentity result))
                        blueprint
            let record = deployedRecord result
                outputsNow = chainOutputs chain
                outputAt' (OutputReference transaction index) =
                    Map.lookup (TxIn (txIdOf transaction) (TxIx (fromInteger index))) outputsNow
                observers = scriptsObservers scripts
                holdsScript = carriesProgram outputsNow
            recordNetwork record `shouldBe` 0
            holdsScript (recordApplication record) (scriptsApplication scripts) `shouldBe` True
            holdsScript (recordAttestation record) (scriptsAttestation scripts) `shouldBe` True
            -- the new policy is told apart from the historical registration observer
            scriptHash (recordAttestation record) `shouldSatisfy` (/= scriptHashBytes (artifactScriptHash (observerLifecycle observers)))
            holdsScript (recordHashProof record) (observerHashProof observers) `shouldBe` True
            holdsScript (recordCheckpoint record) (scriptsCheckpoint scripts) `shouldBe` True
            fmap (^. referenceScriptTxOutL) (outputAt' (scriptOutput (recordState record)))
                `shouldBe` Just (SJust (mkCageScript (scriptsStateProgram scripts)))
            scriptHash (recordState record) `shouldBe` scriptsStateHash scripts
            fmap datumOf (outputAt' (recordTemplate record)) `shouldBe` Just (Just (PLC.B stateTemplate'))
            -- the state output holds the state token in an empty state
            let registry = scriptsRegistry scripts
                stateOut = outputAt' (recordRegistryState record)
            fmap holdsTokenOf stateOut
                `shouldBe` Just [(statePolicyBytes scripts, stateTokenName (riSeed (deployedIdentity result)), 1)]
            fmap datumOf stateOut `shouldBe` Just (Just (PLC.Constr 0 [PLC.B (BS.replicate 32 0)]))
            registryName registry `shouldBe` stateTokenName (riSeed (deployedIdentity result))
            -- the configuration record carries the terms in the order of the Lean parameters, its retraction window zero
            let configurationDatum =
                    PLC.Constr
                        0
                        [ PLC.Constr 0 [PLC.I 1_000_000, PLC.I 500_000, PLC.I 90_000, PLC.I 0, PLC.I 5_000]
                        , PLC.Constr 1 [PLC.B (scriptHashBytes (artifactScriptHash (scriptsCheckpoint scripts)))]
                        ]
            fmap datumOf (outputAt' (recordConfiguration record)) `shouldBe` Just (Just configurationDatum)
            -- the configuration record holds its token
            let configurationOut = outputAt' (recordConfiguration record)
            fmap holdsTokenOf configurationOut
                `shouldBe` Just [(scriptHashBytes (artifactScriptHash (scriptsApplication scripts)), configurationTokenName registry, 1)]
            -- each transaction the record names is the one that did that step, and no other
            let idOf step =
                    [ transactionIdBytes (landedTransaction landed)
                    | landed <- deployedLanded result
                    , landedStep landed == step
                    ]
                txOf (OutputReference transaction _) = [transaction]
            [recordGenesis record] `shouldBe` idOf CreateRegistry
            txOf (recordTemplate record) `shouldBe` idOf PublishTemplate
            txOf (scriptOutput (recordApplication record)) `shouldBe` idOf PublishApplication
            txOf (scriptOutput (recordState record)) `shouldBe` idOf PublishState
            txOf (scriptOutput (recordAttestation record)) `shouldBe` idOf PublishAttestation
            txOf (scriptOutput (recordHashProof record)) `shouldBe` idOf PublishHashProof
            txOf (scriptOutput (recordCheckpoint record)) `shouldBe` idOf PublishCheckpoint
            txOf (recordConfiguration record) `shouldBe` idOf CreateRegistry
            txOf (recordRegistryState record) `shouldBe` idOf CreateRegistry
            -- every output reference in the record is one the chain holds
            forM_
                [ recordTemplate record
                , scriptOutput (recordApplication record)
                , scriptOutput (recordState record)
                , scriptOutput (recordAttestation record)
                , scriptOutput (recordHashProof record)
                , scriptOutput (recordCheckpoint record)
                , recordConfiguration record
                , recordRegistryState record
                ]
                $ \ref -> outputAt' ref `shouldSatisfy` isJust
        it "tells the right script from a wrong one: the output the record names holds the applied program, and the hash-proof program in the attestation's output fails the same check" $ \(outcome, chain) -> do
            result <- expectDeployed outcome
            blueprint <- loadTestBlueprint
            scripts <-
                either fail pure $
                    deriveRegistryScripts stateTemplate testTerms (riSeed (deployedIdentity result)) blueprint
            let record = deployedRecord result
                outputsNow = chainOutputs chain
                attestation = recordAttestation record
                hashProof = observerHashProof (scriptsObservers scripts)
                attestationAt = txInOfOutputReference (scriptOutput attestation)
                swapped = Map.adjust (referenceScriptTxOutL .~ SJust (mkCageScript (artifactProgram hashProof))) attestationAt outputsNow
            carriesProgram outputsNow attestation (scriptsAttestation scripts) `shouldBe` True
            -- the record's hash is the attestation's, and the output carries another program
            Map.lookup attestationAt swapped `shouldSatisfy` (/= Map.lookup attestationAt outputsNow)
            carriesProgram swapped attestation (scriptsAttestation scripts) `shouldBe` False
            carriesProgram outputsNow attestation hashProof `shouldBe` False
        it "pays everything it holds out of one wallet: nothing but that wallet's outputs fund it" $ \(outcome, chain) -> do
            _ <- expectDeployed outcome
            let walletTotal = sum [coinOf out | (_, out) <- walletOutputs]
                chainTotal = sum [coinOf out | out <- Map.elems (chainOutputs chain)]
                fees = sum [fee tx | tx <- chainAccepted chain]
            chainTotal + fees `shouldBe` walletTotal

    describe "a wallet that already holds the reference outputs of an earlier deployment" $ do
        it "never takes one of them, or an output that carries a datum, as the seed, as funding or as collateral" $ do
            blueprint <- loadTestBlueprint
            carrier <- referenceCarrier blueprint
            let reference :: Word8 -> Coin -> (TxIn, TxOut ConwayEra)
                reference n coin =
                    (txInOf n 0, mkBasicTxOut walletAddress (inject coin) & referenceScriptTxOutL .~ SJust carrier)
                withDatum :: Word8 -> Coin -> (TxIn, TxOut ConwayEra)
                withDatum n coin =
                    (txInOf n 0, mkBasicTxOut walletAddress (inject coin) & datumTxOutL .~ mkInlineDatum (PLC.B "template"))
                carriers =
                    [ reference 0xd1 (Coin 18_150_000)
                    , reference 0xd2 (Coin 35_363_550)
                    , reference 0xd3 (Coin 46_026_490)
                    , reference 0xd4 (Coin 34_462_760)
                    , reference 0xd5 (ada 4_000)
                    , withDatum 0xd6 (ada 12)
                    , withDatum 0xd7 (ada 3_000)
                    ]
            (outcome, chain) <- runOn noFaults blueprint testTerms (walletOutputs <> carriers)
            result <- expectDeployed outcome
            -- the least output of lovelace alone above ten ada that carries nothing is the seed
            riSeed (deployedIdentity result) `shouldBe` outputReferenceOf expectedSeedIn
            let carried = Set.fromList (map fst carriers)
            forM_ (chainAccepted chain) $ \tx -> do
                Set.intersection carried (tx ^. bodyTxL . inputsTxBodyL) `shouldBe` Set.empty
                Set.intersection carried (tx ^. bodyTxL . collateralInputsTxBodyL) `shouldBe` Set.empty
            forM_ (Set.toList carried) $ \ref ->
                Map.member ref (chainOutputs chain) `shouldBe` True
        it "stops by name before any transaction when what is left cannot pay for the publications" $ do
            blueprint <- loadTestBlueprint
            carrier <- referenceCarrier blueprint
            -- the seed, 100 ada that carry nothing, and 5,000 ada in an output that carries a script
            let wallet =
                    [ (expectedSeedIn, mkBasicTxOut walletAddress (inject (ada 22)))
                    , (txInOf 0xe1 0, mkBasicTxOut walletAddress (inject (ada 100)))
                    , (txInOf 0xe2 0, mkBasicTxOut walletAddress (inject (ada 5_000)) & referenceScriptTxOutL .~ SJust carrier)
                    ]
            (outcome, chain) <- runOn noFaults blueprint testTerms wallet
            case outcome of
                Left failure -> case failureCause failure of
                    FundsBelowRequirement needed held -> do
                        held `shouldBe` 100_000_000
                        needed `shouldSatisfy` (> held)
                    other -> fail ("expected the funds named as too low, got " <> show other)
                Right _ -> fail "a deployment went on with funds that cannot pay for it"
            chainSubmissions chain `shouldBe` 0
        it "stops by name before any transaction when one output of lovelace alone is left, less the seed it makes" $ do
            blueprint <- loadTestBlueprint
            carrier <- referenceCarrier blueprint
            let wallet =
                    [ (expectedSeedIn, mkBasicTxOut walletAddress (inject (ada 22)))
                    , (txInOf 0xe2 0, mkBasicTxOut walletAddress (inject (ada 5_000)) & referenceScriptTxOutL .~ SJust carrier)
                    ]
            (outcome, chain) <- runOn noFaults blueprint testTerms wallet
            case outcome of
                Left failure -> case failureCause failure of
                    FundsBelowRequirement needed held -> do
                        -- the one output of lovelace alone makes the seed: what is left of it pays
                        held `shouldBe` 12_000_000
                        needed `shouldSatisfy` (> held)
                    other -> fail ("expected the funds named as too low, got " <> show other)
                Right _ -> fail "a deployment went on with nothing to pay with"
            chainSubmissions chain `shouldBe` 0

    describe "a deployment after another on the same network" $ do
        it "registers no stake credential, before or after another deployment, and lands the same seven steps" $ do
            blueprint <- loadTestBlueprint
            chainRef <- newIORef (newChain (walletOutputs <> moreFunds))
            firstOutcome <- deployOn noFaults chainRef (requestFor blueprint testTerms)
            secondOutcome <- deployOn noFaults chainRef (requestFor blueprint testTerms)
            first <- expectDeployed firstOutcome
            second <- expectDeployed secondOutcome
            map landedStep (deployedLanded first) `shouldBe` allSteps
            map landedStep (deployedLanded second) `shouldBe` allSteps
            riSeed (deployedIdentity first) `shouldSatisfy` (/= riSeed (deployedIdentity second))
            chain <- readIORef chainRef
            length (chainAccepted chain) `shouldBe` 14
            forM_ (chainAccepted chain) $ \tx ->
                registrationsOf tx `shouldBe` Set.empty

    describe "a deployment that does not begin" $ do
        it "refuses the terms before it asks the chain anything" $ do
            blueprint <- loadTestBlueprint
            let bad = testTerms{registryCheckpointTerms = (registryCheckpointTerms testTerms){termsDeposit = 1}}
            (outcome, chain) <- runOn noFaults blueprint bad walletOutputs
            outcome `shouldBe` Left (DeployFailure [] Nothing allSteps (TermsRefused [DepositBelowFloor]))
            chainCalls chain `shouldBe` 0
        it "refuses terms that name another network than the node's" $ do
            blueprint <- loadTestBlueprint
            let other = testTerms{registryCheckpointTerms = (registryCheckpointTerms testTerms){termsNetwork = 1}}
            (outcome, chain) <- runOn noFaults blueprint other walletOutputs
            outcome `shouldBe` Left (DeployFailure [] Nothing allSteps (NetworkDisagrees 1))
            chainSubmissions chain `shouldBe` 0
        it "stops by name when the wallet holds no output to create the registry from" $ do
            blueprint <- loadTestBlueprint
            (outcome, chain) <- runOn noFaults blueprint testTerms (take 2 walletOutputs)
            outcome `shouldBe` Left (DeployFailure [] Nothing allSteps NoSeedOutput)
            chainSubmissions chain `shouldBe` 0
        it "stops by name when the scripts cannot be derived from the blueprint, before any transaction" $ do
            (outcome, chain) <- runOn noFaults (Blueprint []) testTerms walletOutputs
            case outcome of
                Left failure -> do
                    failureLanded failure `shouldBe` []
                    failureStoppedAt failure `shouldBe` Nothing
                    case failureCause failure of
                        ScriptsRefused _ -> pure ()
                        other -> fail ("expected the scripts refused, got " <> show other)
                Right _ -> fail "scripts were derived from an empty blueprint"
            chainSubmissions chain `shouldBe` 0

    describe "a deployment that stops" $ do
        it "names what landed and what did not, when the node refuses the n-th transaction, for every n" $ do
            blueprint <- loadTestBlueprint
            forM_ (zip [0 ..] allSteps) $ \(n, step) -> do
                (outcome, chain) <- runOn noFaults{rejectSubmissionAt = Just n} blueprint testTerms walletOutputs
                case outcome of
                    Right _ -> fail "a refused transaction was not reported"
                    Left failure -> do
                        failureStoppedAt failure `shouldBe` Just step
                        map landedStep (failureLanded failure) `shouldBe` take n allSteps
                        failureNotLanded failure `shouldBe` drop n allSteps
                        case failureCause failure of
                            SubmissionRefused _ reason -> reason `shouldBe` "the node refuses this transaction"
                            other -> expectationFailure ("another cause: " <> show other)
                        map landedTransaction (failureLanded failure)
                            `shouldBe` map transactionId (reverse (chainAccepted chain))
                -- nothing is retried or resubmitted: one submission each, and the refused one
                chainSubmissions chain `shouldBe` n + 1
                length (chainAccepted chain) `shouldBe` n
        it "reports a transaction it cannot see settle as uncertain, and does not submit another" $ do
            blueprint <- loadTestBlueprint
            forM_ (zip [0 ..] allSteps) $ \(n, step) -> do
                (outcome, chain) <- runOn noFaults{failObservationAt = Just n} blueprint testTerms walletOutputs
                case outcome of
                    Right _ -> fail "an unobserved transaction was not reported"
                    Left failure -> do
                        failureStoppedAt failure `shouldBe` Just step
                        map landedStep (failureLanded failure) `shouldBe` take n allSteps
                        uncertainId <- maybe (fail "nothing was accepted") (pure . transactionId) (listToMaybe (chainAccepted chain))
                        case failureCause failure of
                            NotObserved txId _ -> txId `shouldBe` uncertainId
                            other -> fail ("expected the transaction reported as not observed, got " <> show other)
                chainSubmissions chain `shouldBe` n + 1
                length (chainAccepted chain) `shouldBe` n + 1
        it "stops by name, before the genesis, when the seed was spent after the deployment began" $ do
            blueprint <- loadTestBlueprint
            -- after the n-th accepted transaction something else spends the seed
            forM_ [0, 2, 4] $ \n -> do
                let spendSeed accepted chain
                        | accepted == n =
                            chain{chainOutputs = Map.delete expectedSeedIn (chainOutputs chain)}
                        | otherwise = chain
                (outcome, chain) <- runOn noFaults{afterAccepted = spendSeed} blueprint testTerms walletOutputs
                case outcome of
                    Right _ -> fail "a deployment went on without its seed"
                    Left failure -> do
                        failureCause failure `shouldBe` SeedSpent (outputReferenceOf expectedSeedIn)
                        failureStoppedAt failure `shouldBe` Just CreateRegistry
                        map landedStep (failureLanded failure) `shouldBe` take 6 allSteps
                        failureNotLanded failure `shouldBe` [CreateRegistry]
                        map landedTransaction (failureLanded failure)
                            `shouldBe` map transactionId (reverse (chainAccepted chain))
                length (chainAccepted chain) `shouldBe` 6
        it "leaves the seed unspent by every publication even when it is the largest output the wallet holds" $ do
            blueprint <- loadTestBlueprint
            -- the seed is the one output of lovelace alone above ten ada: it is also the first the publications would take
            let token n =
                    MaryValue
                        (ada 100)
                        ( MultiAsset
                            ( Map.singleton
                                (PolicyID (scriptHashOf 0x78))
                                (Map.singleton (AssetName (SBS.toShort "token")) n)
                            )
                        )
                largest =
                    [ (expectedSeedIn, mkBasicTxOut walletAddress (inject (ada 5_000)))
                    , (txInOf 0xb1 0, mkBasicTxOut walletAddress (token 1))
                    , (txInOf 0xb2 0, mkBasicTxOut walletAddress (token 1))
                    , (txInOf 0xb3 0, mkBasicTxOut walletAddress (token 1))
                    , (txInOf 0xb4 0, mkBasicTxOut walletAddress (token 1))
                    , (txInOf 0xb5 0, mkBasicTxOut walletAddress (inject (ada 8)))
                    , (txInOf 0xb6 0, mkBasicTxOut walletAddress (inject (ada 8)))
                    ]
            (outcome, chain) <- runOn noFaults blueprint testTerms largest
            -- whether the deployment completes is not the question: nothing that it submits spends the seed
            fmap landedStep (either failureLanded deployedLanded outcome)
                `shouldSatisfy` ((>= 6) . length)
            Map.member expectedSeedIn (chainOutputs chain) `shouldBe` True
            forM_ (chainAccepted chain) $ \tx ->
                Set.member expectedSeedIn (tx ^. bodyTxL . inputsTxBodyL) `shouldBe` False
        it "refuses an evaluation that does not answer for the purposes it declared, without submitting that transaction" $ do
            blueprint <- loadTestBlueprint
            -- the evaluation of the genesis, the one transaction of the deployment that runs a script
            forM_ [(0 :: Int, CreateRegistry, 6)] $ \(n, step, landedCount) -> do
                (outcome, chain) <- runOn noFaults{distortEvaluation = \k m -> if k == n then Map.empty else m} blueprint testTerms walletOutputs
                case outcome of
                    Right _ -> fail "an evaluation that answered for nothing was accepted"
                    Left failure -> do
                        failureStoppedAt failure `shouldBe` Just step
                        case failureCause failure of
                            PurposesDiffer _ -> pure ()
                            other -> fail ("expected the purposes named as different, got " <> show other)
                length (chainAccepted chain) `shouldBe` landedCount
        it "names the purpose the node's evaluation fails" $ do
            blueprint <- loadTestBlueprint
            (outcome, chain) <-
                runOn
                    noFaults{distortEvaluation = \_ -> Map.map (const (Left (UnknownTxIn (txInOf 0xee 0))))}
                    blueprint
                    testTerms
                    walletOutputs
            case outcome of
                Left failure -> do
                    failureStoppedAt failure `shouldBe` Just CreateRegistry
                    case failureCause failure of
                        EvaluationFailed message -> message `shouldSatisfy` ("UnknownTxIn" `isInfixOf`)
                        other -> fail ("expected an evaluation failure, got " <> show other)
                Right _ -> fail "a failing evaluation was accepted"
            length (chainAccepted chain) `shouldBe` 6
  where
    deployed = do
        blueprint <- loadTestBlueprint
        runOn noFaults blueprint testTerms walletOutputs

moreFunds :: [(TxIn, TxOut ConwayEra)]
moreFunds =
    [ (txInOf 0xc1 0, mkBasicTxOut walletAddress (inject (ada 6_000)))
    , (txInOf 0xc2 0, mkBasicTxOut walletAddress (inject (ada 25)))
    ]

-- ---------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------

expectDeployed :: Either DeployFailure Deployed -> IO Deployed
expectDeployed = either (fail . ("the deployment stopped: " <>) . show) pure

coinOf :: TxOut ConwayEra -> Integer
coinOf out = let Coin c = out ^. coinTxOutL in c

fee :: ConwayTx -> Integer
fee tx = let Coin c = tx ^. bodyTxL . feeTxBodyL in c

datumOf :: TxOut ConwayEra -> Maybe PLC.Data
datumOf out = case out ^. datumTxOutL of
    Datum binary -> let Data plc = binaryDataToData binary in Just plc
    _ -> Nothing

holdsTokenOf :: TxOut ConwayEra -> [(ByteString, ByteString, Integer)]
holdsTokenOf out =
    let MaryValue _ (MultiAsset assets) = out ^. valueTxOutL
     in [ (hashBytesOf policy, nameBytes name, quantity)
        | (policy, names) <- Map.toList assets
        , (name, quantity) <- Map.toList names
        ]

stateTemplate' :: ByteString
stateTemplate' = stateTemplate

statePolicyBytes :: RegistryScripts -> ByteString
statePolicyBytes = scriptsStateHash

txIdOf :: ByteString -> TxId
txIdOf = TxId . unsafeMakeSafeHash . fromJust . hashFromBytes

transactionIdBytes :: TxId -> ByteString
transactionIdBytes = hashToBytes . extractHash . unTxId

hashBytesOf :: PolicyID -> ByteString
hashBytesOf (PolicyID (ScriptHash hash)) = hashToBytes hash

nameBytes :: AssetName -> ByteString
nameBytes (AssetName name) = SBS.fromShort name

{- | Whether the output a script reference names carries exactly the applied program of the artifact, and the
reference names its hash: the hash alone, or some script, is not the program.
-}
carriesProgram :: Map TxIn (TxOut ConwayEra) -> ScriptReference -> ScriptArtifact -> Bool
carriesProgram outputs reference artifact =
    case Map.lookup (txInOfOutputReference (scriptOutput reference)) outputs of
        Just out ->
            out ^. referenceScriptTxOutL == SJust (mkCageScript (artifactProgram artifact))
                && scriptHash reference == scriptHashBytes (artifactScriptHash artifact)
        Nothing -> False

txInOfOutputReference :: OutputReference -> TxIn
txInOfOutputReference (OutputReference transaction index) =
    TxIn (txIdOf transaction) (TxIx (fromInteger index))
