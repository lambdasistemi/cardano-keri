{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryDeploy
Description : Create a fresh registry on a network, step by step

A deployment is a fixed sequence of transactions paid by one wallet: publish the
state template and the five scripts a booking reads by reference (the booking
attestation policy, which comes before the application it is a parameter of, the
application, the state script, the hash-proof policy and the checkpoint
validator), then create the registry from a seed. No stake credential is
registered. The seed is a wallet output
chosen before the registry's scripts are derived, because they are derived from
it; no publication spends it, and the genesis spends it as its one input.

Nothing here talks to a node directly: a 'RegistryRuntime' says how to read the
wallet and the outputs the node holds, and how to evaluate, sign, submit and
observe a transaction. The deployment reads chain state only through it.

Every transaction that settles is reported at once. A deployment that stops
names what landed and what did not; it never resubmits a transaction, and a
transaction it cannot see settle is reported as uncertain.
-}
module Cardano.KERI.Deployment.RegistryDeploy (
    -- * What a deployment is given
    DeployRequest (..),

    -- * What it does and what it reports
    Step (..),
    allSteps,
    Landed (..),
    DeployError (..),
    DeployFailure (..),
    Deployed (..),
    deployRegistry,

    -- * The terms a registry is deployed with
    TermRefusal (..),
    refuseTerms,

    -- * What a deployment derives
    releaseIdentityOf,
    seedMinimumLovelace,
    chooseSeed,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    OutputReference (..),
    configurationTokenName,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.FreezeBond (freezeBondValid)
import Cardano.KERI.AID.Checkpoint.Registration (validRegistrationDeposit)
import Cardano.KERI.AID.Checkpoint.Value (checkpointMinAda)
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.RegistryChain (
    RegistryRuntime (..),
    TransactionUnconfirmed (..),
    ValidityEnd (..),
    addUnits,
    withMargin,
    withinUnits,
 )
import Cardano.KERI.Deployment.RegistryFiles (
    ReferenceRecord (..),
    ScriptReference (..),
 )
import Cardano.KERI.Deployment.RegistryTransactions (
    FundingRules,
    Payer (..),
    RegistryDeployment (..),
    RegistryTransactionError (..),
    applicationPolicyId,
    createConfiguration,
    isFundable,
    isPlainFunding,
    outputReferenceOf,
    publishReferenceScript,
    publishTemplate,
    publishTemplateAndSeed,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint,
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    mkCageScript,
    scriptHashBytes,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionRuntime (..),
    transactionId,
 )
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    outputsTxBodyL,
    vldtTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    coinTxOutL,
    datumTxOutL,
    getMinCoinTxOut,
    mkBasicTxOut,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.BaseTypes (
    Inject (..),
    Network (..),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams, Script)
import Cardano.Ledger.Hashes (ScriptHash, extractHash)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..), unTxId)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult, SlotNo (..))
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Control.Exception (Exception, SomeException, fromException, throwIO, try)
import Control.Monad (unless, when)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data (Data (..))

-- | What a deployment is asked to create.
data DeployRequest = DeployRequest
    { requestTerms :: !RegistryTerms
    , requestBlueprint :: !Blueprint
    , requestPayer :: !Addr
    -- ^ the wallet's address: change returns to it
    , requestReferenceLovelace :: !(Maybe Integer)
    -- ^ what each published output holds; the ledger's minimum for it when absent
    }

-- | The transactions of a deployment, in the order they are submitted.
data Step
    = PublishTemplate
    | PublishAttestation
    | PublishApplication
    | PublishState
    | PublishHashProof
    | PublishCheckpoint
    | CreateRegistry
    deriving stock (Eq, Show, Enum, Bounded)

-- | Every step, in order.
allSteps :: [Step]
allSteps = [minBound .. maxBound]

-- | A transaction that settled, with what it cost and what it leaves locked.
data Landed = Landed
    { landedStep :: !Step
    , landedTransaction :: !TxId
    , landedFee :: !Integer
    -- ^ the fee the transaction paid, in lovelace
    , landedLocked :: !Integer
    -- ^ the lovelace it leaves held in outputs and deposits: every output but the change, and the deposits it pays
    , landedCollateral :: !Integer
    -- ^ the lovelace of the outputs the transaction names as collateral: posted, and taken only if a script fails
    , landedValidUntil :: !(Maybe Integer)
    -- ^ the exclusive upper slot of the validity of the transaction that landed, as its signed body carries it
    }
    deriving stock (Eq, Show)

-- | Why a deployment stopped.
data DeployError
    = -- | the terms are refused before any transaction
      TermsRefused ![TermRefusal]
    | -- | the terms name another network than the node's
      NetworkDisagrees !Integer
    | -- | the registry's scripts cannot be derived from the terms
      ScriptsRefused !String
    | -- | the wallet holds no output to create the registry from
      NoSeedOutput
    | -- | the seed the scripts are derived from is spent before the genesis
      SeedSpent !OutputReference
    | -- | the outputs the publications may spend hold less than they cost: what they cost at the least, what is held
      FundsBelowRequirement !Integer !Integer
    | -- | a published output vanished before the genesis read it
      ReferenceVanished !TxIn
    | -- | a builder refused
      BuildRefused !RegistryTransactionError
    | -- | the node's evaluation of a transaction named a failing purpose
      EvaluationFailed !String
    | -- | the node's evaluation did not answer for exactly the purposes the builder declared
      PurposesDiffer !String
    | -- | the budgets measured exceed what a transaction may declare
      BudgetExceeded !String
    | -- | the node or the key refused the signature
      SigningRefused !String
    | -- | the node refused the transaction
      SubmissionRefused !TxId !ByteString
    | -- | the transaction was handed to the node and not seen settled: it may still land
      NotObserved !TxId !String
    | -- | the transaction was handed over and not seen before its deadline: it may still be included
      Unconfirmed !TxId !String
    | -- | the node could not be read
      NodeFailed !String
    | -- | the interval from the tip is too short for a finite validity end: the step was not built or handed over
      NoWindow
    deriving stock (Eq, Show)

-- | A deployment that did not complete: what landed, where it stopped and what did not land.
data DeployFailure = DeployFailure
    { failureLanded :: ![Landed]
    , failureStoppedAt :: !(Maybe Step)
    -- ^ the step that failed; absent when nothing was attempted
    , failureNotLanded :: ![Step]
    -- ^ every step that did not land
    , failureCause :: !DeployError
    }
    deriving stock (Eq, Show)

-- | A deployment that completed.
data Deployed = Deployed
    { deployedIdentity :: !ReleaseIdentity
    , deployedRecord :: !ReferenceRecord
    , deployedLanded :: ![Landed]
    }
    deriving stock (Eq, Show)

-- | A term, or a pair of terms, the registry cannot be deployed with.
data TermRefusal
    = -- | a term that is an amount or a duration is below zero
      NegativeTerm !Text
    | -- | the checkpoint deposit is below its floor
      DepositBelowFloor
    | -- | the freeze bond is below its floor
      FreezeBondBelowFloor
    | -- | the network discriminator is not 0 (a test network) or 1 (the main one)
      NetworkDiscriminatorNotZeroOrOne
    | -- | the application's minimum ADA is not the checkpoint validator's
      MinimumAdaNotTheCheckpoints
    | -- | the termination carrier and the tip exceed the minimum ADA
      TerminationCarrierExceedsMinimumAda
    deriving stock (Eq, Show)

{- | Everything wrong with the terms, before a transaction: each amount or
duration at or above zero, the deposit and the freeze bond at their floors,
the network discriminator one a release identity can name, and the amounts the
application and the checkpoint validator both carry in agreement. The retract
time of the application is not a term: it is zero.
-}
refuseTerms :: RegistryTerms -> [TermRefusal]
refuseTerms terms =
    [NegativeTerm name | (name, value) <- amounts, value < 0]
        <> [DepositBelowFloor | not (validRegistrationDeposit (termsDeposit checkpoint))]
        <> [FreezeBondBelowFloor | not (freezeBondValid (termsFreezeBond checkpoint))]
        <> [NetworkDiscriminatorNotZeroOrOne | termsNetwork checkpoint `notElem` [0, 1]]
        <> [MinimumAdaNotTheCheckpoints | registryMinimumAda terms /= checkpointMinAda]
        <> [ TerminationCarrierExceedsMinimumAda
           | registryTerminationCarrier terms >= 0
           , registryTerminationCarrier terms + minimumTip' > registryMinimumAda terms
           ]
  where
    checkpoint = registryCheckpointTerms terms
    parameters = registryParameters terms
    minimumTip' = minimumTip parameters
    amounts =
        [ ("registration-cost", registrationCost parameters)
        , ("minimum-tip", minimumTip')
        , ("process-time", processTime parameters)
        , ("booking-width", bookingWidth parameters)
        , ("deposit", termsDeposit checkpoint)
        , ("freeze-bond", termsFreezeBond checkpoint)
        , ("premium", termsPremium checkpoint)
        , ("minimum-ada", registryMinimumAda terms)
        , ("termination-carrier", registryTerminationCarrier terms)
        ]

{- | The release identity of a deployed registry: the network, the release of
the application, the seed, the checkpoint validator and the amounts.
-}
releaseIdentityOf :: RegistryTerms -> RegistryScripts -> ReleaseIdentity
releaseIdentityOf terms scripts =
    ReleaseIdentity
        { riNetwork = termsNetwork checkpoint
        , riRelease =
            Release
                { rlApplicationPolicy = application
                , rlApplicationCredential = application
                , rlStateProgram = scriptsStateHash scripts
                , rlStatePolicy = scriptsStateHash scripts
                }
        , riSeed = scriptsSeed scripts
        , riCheckpointValidator =
            scriptHashBytes (artifactScriptHash (scriptsCheckpoint scripts))
        , riDeposit = termsDeposit checkpoint
        , riFreezeBond = termsFreezeBond checkpoint
        , riPremium = termsPremium checkpoint
        , riMinimumAda = registryMinimumAda terms
        , riTerminationCarrier = registryTerminationCarrier terms
        , riApplicationParameters = registryParameters terms
        }
  where
    checkpoint = registryCheckpointTerms terms
    application = scriptHashBytes (artifactScriptHash (scriptsApplication scripts))

{- | What an output must hold to be a seed: the genesis pays two records and a
fee out of it and the outputs that fund it.
-}
seedMinimumLovelace :: Integer
seedMinimumLovelace = 10_000_000

{- | The output the registry is created from: of the wallet's outputs that hold
nothing but lovelace and at least 'seedMinimumLovelace', the one with the
least, so the larger ones remain to pay for the publications.
-}
chooseSeed :: FundingRules -> [(TxIn, TxOut ConwayEra)] -> Maybe (TxIn, TxOut ConwayEra)
chooseSeed rules wallet =
    case sortOn (\(ref, out) -> (coinOf out, ref)) candidates of
        first : _ -> Just first
        [] -> Nothing
  where
    candidates =
        [ output
        | output@(_, out) <- wallet
        , isPlainFunding rules out
        , coinOf out >= seedMinimumLovelace
        ]

-- ---------------------------------------------------------------------
-- The deployment
-- ---------------------------------------------------------------------

newtype Stop = Stop (Maybe Step, DeployError)
    deriving stock (Show)

instance Exception Stop

{- | Create a registry: choose the seed, derive the scripts, publish, register
the observer's credential and create the registry. No transaction is built
before the terms are accepted and the scripts derived, and the genesis is not
built before the seed is read unspent. The wallet is read again before each
transaction, and the seed is never among the outputs a publication may spend.
-}
deployRegistry :: RegistryRuntime -> (Landed -> IO ()) -> DeployRequest -> IO (Either DeployFailure Deployed)
deployRegistry runtime onLanded request = do
    landedRef <- newIORef []
    outcome <- try (run landedRef)
    landed <- reverse <$> readIORef landedRef
    pure $ case outcome of
        Right deployed -> Right deployed{deployedLanded = landed}
        Left (Stop (step, cause)) ->
            Left
                DeployFailure
                    { failureLanded = landed
                    , failureStoppedAt = step
                    , failureNotLanded =
                        [s | s <- allSteps, s `notElem` map landedStep landed]
                    , failureCause = cause
                    }
  where
    terms = requestTerms request
    transactions = rtTransactions runtime
    network = rtNetwork runtime
    payerAddress' = requestPayer request

    -- the upper slot of the transaction a step builds, read once at the start of the step: the discovery and the final
    -- builds of a step share it, and a step that has none usable is not built
    endOf step =
        onNode (Just step) (rtValidityEnd runtime) >>= \case
            EndNotSet -> pure Nothing
            EndAt slot -> pure (Just slot)
            NoUsableWindow -> stop (Just step) NoWindow

    stop :: Maybe Step -> DeployError -> IO a
    stop step cause = throwIO (Stop (step, cause))

    onNode :: Maybe Step -> IO a -> IO a
    onNode step action =
        try @SomeException action >>= either (stop step . NodeFailed . show) pure

    -- the wallet as the node holds it now, without the seed
    spendable step withheld = do
        wallet <- onNode step (rtUtxosAt runtime payerAddress')
        pure [output | output@(ref, out) <- wallet, ref `notElem` withheld, isFundable out]

    -- what is not seen is unconfirmed when the observation says it was not seen before its deadline, and uncertain
    -- otherwise: either way nothing is known of whether it is on the chain
    unobserved txId failure = case fromException failure of
        Just (TransactionUnconfirmed _ _) -> Unconfirmed txId (show failure)
        Nothing -> NotObserved txId (show failure)

    -- sign, submit and observe one transaction, then report it
    settle landedRef step known tx = do
        signedResult <- onNode (Just step) (trSign transactions tx)
        signed <- either (stop (Just step) . SigningRefused . show) pure signedResult
        let txId = transactionId signed
        submitted <- try @SomeException (trSubmit transactions signed)
        case submitted of
            Left failure -> stop (Just step) (NotObserved txId (show failure))
            Right (Rejected reason) -> stop (Just step) (SubmissionRefused txId reason)
            Right (Submitted _) -> pure ()
        observed <- try @SomeException (trObserve transactions txId)
        either (stop (Just step) . unobserved txId) pure observed
        let landed = Landed step txId (feeOf signed) (lockedBy signed) (collateralOf known signed) (validUntilOf signed)
        modifyIORef' landedRef (landed :)
        onLanded landed
        pure signed

    -- a transaction without scripts: built once, from the wallet as it stands
    publication landedRef withheld step build = do
        end <- endOf step
        params <- onNode (Just step) (trQueryProtocolParams transactions)
        wallet <- spendable (Just step) withheld
        tx <-
            either
                (stop (Just step) . BuildRefused)
                pure
                (build params (Payer payerAddress' wallet (rtFunding runtime)) end)
        signed <- settle landedRef step Map.empty tx
        pure (TxIn (transactionId signed) (TxIx 0))

    publishScript landedRef withheld lovelace step script =
        publication landedRef withheld step $ \params payer end ->
            publishReferenceScript
                end
                params
                payer
                ( Coin
                    ( fromMaybe
                        (minimumHolding params (scriptHolder payerAddress' script))
                        lovelace
                    )
                )
                script

    -- a transaction with script purposes: measured, then built under the measured budgets
    budgeted landedRef withheld step build = do
        end <- endOf step
        params <- onNode (Just step) (trQueryProtocolParams transactions)
        wallet <- spendable (Just step) withheld
        let built budgets =
                either (stop (Just step) . BuildRefused) pure (build params wallet budgets end)
        (discovery, expected) <- built Map.empty
        signedDiscovery <-
            onNode (Just step) (trSign transactions discovery)
                >>= either (stop (Just step) . SigningRefused . show) pure
        evaluated <- onNode (Just step) (trEvaluate transactions signedDiscovery)
        measured <- measure step expected evaluated
        let budgets = Map.map withMargin measured
            total = foldr addUnits (ExUnits 0 0) (Map.elems budgets)
        unless (withinUnits total (params ^. ppMaxTxExUnitsL)) $
            stop (Just step) (BudgetExceeded (show total))
        (final, finalExpected) <- built budgets
        when (finalExpected /= expected) $
            stop (Just step) (PurposesDiffer "the purposes changed under the measured budgets")
        settle landedRef step (Map.fromList wallet) final

    run landedRef = do
        let refusals = refuseTerms terms
        unless (null refusals) $ stop Nothing (TermsRefused refusals)
        let discriminator = termsNetwork (registryCheckpointTerms terms)
        when (discriminator /= networkDiscriminator network) $
            stop Nothing (NetworkDisagrees discriminator)
        wallet0 <- onNode Nothing (rtUtxosAt runtime payerAddress')
        (candidate, _) <- maybe (stop Nothing NoSeedOutput) pure (chooseSeed (rtFunding runtime) wallet0)
        -- a wallet whose only output of lovelace alone is the seed candidate has nothing to pay the publications
        -- with once the seed is set aside: the publication of the template then makes the seed, as public
        -- Singular's chained seed does, and the registry is created from it
        let chained = null [ref | (ref, out) <- wallet0, ref /= candidate, isFundable out]
        let derivedFor seed =
                either
                    (stop Nothing . ScriptsRefused)
                    pure
                    (deriveRegistryScripts stateTemplate terms (outputReferenceOf seed) (requestBlueprint request))
        scripts0 <- derivedFor candidate
        let observers0 = scriptsObservers scripts0
            lovelace = requestReferenceLovelace request
        -- the publications are paid from outputs that carry nothing but lovelace and assets: if those hold
        -- less than the six published outputs must hold, nothing is submitted
        checkParams <- onNode Nothing (trQueryProtocolParams transactions)
        let holders =
                templateHolder payerAddress' (scriptsTemplate scripts0)
                    : [ scriptHolder payerAddress' script
                      | script <-
                            [ mkCageScript (artifactProgram (scriptsAttestation scripts0))
                            , mkCageScript (artifactProgram (scriptsApplication scripts0))
                            , mkCageScript (scriptsStateProgram scripts0)
                            , mkCageScript (artifactProgram (observerHashProof observers0))
                            , mkCageScript (artifactProgram (scriptsCheckpoint scripts0))
                            ]
                      ]
            needed = sum [fromMaybe (minimumHolding checkParams holder) lovelace | holder <- holders]
            held
                | chained = sum [coinOf out | (_, out) <- wallet0, isFundable out] - seedMinimumLovelace
                | otherwise = sum [coinOf out | (ref, out) <- wallet0, ref /= candidate, isFundable out]
        when (held < needed) $
            stop Nothing (FundsBelowRequirement needed held)
        let templateLovelace params =
                Coin (fromMaybe (minimumHolding params (templateHolder payerAddress' (scriptsTemplate scripts0))) lovelace)
        (templateIn, seedIn) <-
            if chained
                then do
                    published <-
                        publication landedRef [] PublishTemplate $ \params payer end ->
                            publishTemplateAndSeed end params payer (templateLovelace params) (Coin seedMinimumLovelace) (scriptsTemplate scripts0)
                    pure (published, case published of TxIn created _ -> TxIn created (TxIx 1))
                else do
                    templateIn <-
                        publication landedRef [candidate] PublishTemplate $ \params payer end ->
                            publishTemplate end params payer (templateLovelace params) (scriptsTemplate scripts0)
                    pure (templateIn, candidate)
        scripts <- if chained then derivedFor seedIn else pure scripts0
        unless (seedFreeHashes scripts == seedFreeHashes scripts0) $
            stop (Just PublishTemplate) (ScriptsRefused "the scripts the first publications carry depend on the seed")
        let deployment = RegistryDeployment network terms scripts
            observers = scriptsObservers scripts
            publishedScript = publishScript landedRef [seedIn] lovelace
        attestationIn <-
            publishedScript PublishAttestation $
                mkCageScript (artifactProgram (scriptsAttestation scripts))
        applicationIn <-
            publishedScript PublishApplication $
                mkCageScript (artifactProgram (scriptsApplication scripts))
        stateIn <-
            publishedScript PublishState (mkCageScript (scriptsStateProgram scripts))
        hashProofIn <-
            publishedScript PublishHashProof $
                mkCageScript (artifactProgram (observerHashProof observers))
        checkpointIn <-
            publishedScript PublishCheckpoint $
                mkCageScript (artifactProgram (scriptsCheckpoint scripts))
        -- the genesis: the seed is read unspent, with the outputs the genesis reads by reference
        found <-
            onNode (Just CreateRegistry) $
                rtOutputs
                    runtime
                    (Set.fromList [seedIn, templateIn, applicationIn, stateIn])
        seedOut <-
            maybe
                (stop (Just CreateRegistry) (SeedSpent (outputReferenceOf seedIn)))
                pure
                (Map.lookup seedIn found)
        references <-
            traverse
                ( \ref ->
                    maybe
                        (stop (Just CreateRegistry) (ReferenceVanished ref))
                        (pure . (,) ref)
                        (Map.lookup ref found)
                )
                [templateIn, applicationIn, stateIn]
        genesisTx <-
            budgeted landedRef [seedIn] CreateRegistry $ \params funds budgets end ->
                createConfiguration
                    end
                    params
                    deployment
                    references
                    (Payer payerAddress' funds (rtFunding runtime))
                    (seedIn, seedOut)
                    (registryParameters terms)
                    budgets
        configuration <-
            maybe
                (stop (Just CreateRegistry) (NodeFailed "the genesis holds no configuration record"))
                pure
                (configurationIndex deployment scripts genesisTx)
        let genesisId = transactionId genesisTx
            published ref artifactHash =
                ScriptReference (outputReferenceOf ref) (scriptHashBytes artifactHash)
            record =
                ReferenceRecord
                    { recordNetwork = discriminator
                    , recordTemplate = outputReferenceOf templateIn
                    , recordApplication =
                        published applicationIn (artifactScriptHash (scriptsApplication scripts))
                    , recordState =
                        ScriptReference (outputReferenceOf stateIn) (scriptsStateHash scripts)
                    , recordAttestation =
                        published attestationIn (artifactScriptHash (scriptsAttestation scripts))
                    , recordHashProof =
                        published hashProofIn (artifactScriptHash (observerHashProof observers))
                    , recordCheckpoint =
                        published checkpointIn (artifactScriptHash (scriptsCheckpoint scripts))
                    , recordConfiguration =
                        outputReferenceOf (TxIn genesisId (TxIx (fromInteger configuration)))
                    , recordRegistryState = outputReferenceOf (TxIn genesisId (TxIx 0))
                    , recordGenesis = transactionIdBytes genesisTx
                    }
        pure
            Deployed
                { deployedIdentity = releaseIdentityOf terms scripts
                , deployedRecord = record
                , deployedLanded = []
                }

-- | The index of the configuration record among the genesis' outputs.
configurationIndex :: RegistryDeployment -> RegistryScripts -> ConwayTx -> Maybe Integer
configurationIndex deployment scripts genesis =
    fmap fst . find (holdsConfiguration . snd) $
        zip [0 ..] (toList (genesis ^. bodyTxL . outputsTxBodyL))
  where
    name = AssetName (SBS.toShort (configurationTokenName (scriptsRegistry scripts)))
    holdsConfiguration out = case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            (Map.lookup (applicationPolicyId deployment) assets >>= Map.lookup name)
                == Just 1

-- | The budgets the node measured for exactly the purposes that were declared.
measure ::
    Step ->
    Set (ConwayPlutusPurpose AsIx ConwayEra) ->
    EvaluateTxResult ConwayEra ->
    IO (Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits)
measure step expected evaluated = do
    unless (Map.keysSet evaluated == expected) $
        throwIO (Stop (Just step, PurposesDiffer (show (Map.keysSet evaluated))))
    Map.traverseWithKey
        ( \purpose outcome -> case outcome of
            Right units -> pure units
            Left failure ->
                throwIO
                    (Stop (Just step, EvaluationFailed (show purpose <> ": " <> show failure)))
        )
        evaluated

networkDiscriminator :: Network -> Integer
networkDiscriminator = \case
    Testnet -> 0
    Mainnet -> 1

-- ---------------------------------------------------------------------
-- What an output holds
-- ---------------------------------------------------------------------

coinOf :: TxOut ConwayEra -> Integer
coinOf out = let Coin c = out ^. coinTxOutL in c

-- | The output that holds a published script, before it is given its lovelace.
scriptHolder :: Addr -> Script ConwayEra -> TxOut ConwayEra
scriptHolder address script =
    mkBasicTxOut address (inject (Coin 0)) & referenceScriptTxOutL .~ SJust script

-- | The output that holds the state template as its inline datum.
templateHolder :: Addr -> ByteString -> TxOut ConwayEra
templateHolder address template =
    mkBasicTxOut address (inject (Coin 0)) & datumTxOutL .~ mkInlineDatum (B template)

{- | The least lovelace the ledger lets an output like this one hold: its
minimum, found again for the size the minimum itself makes it.
-}
minimumHolding :: PParams ConwayEra -> TxOut ConwayEra -> Integer
minimumHolding params out = settleAt (settleAt (settleAt 0))
  where
    settleAt coin =
        let Coin least = getMinCoinTxOut params (out & coinTxOutL .~ Coin coin)
         in max coin least

-- | The bytes of a transaction's id.
transactionIdBytes :: ConwayTx -> ByteString
transactionIdBytes = hashToBytes . extractHash . unTxId . transactionId

{- | The lovelace of the outputs a transaction names as collateral, found among
the outputs it was built from.
-}
collateralOf :: Map TxIn (TxOut ConwayEra) -> ConwayTx -> Integer
collateralOf known tx =
    sum
        [ coinOf out
        | ref <- toList (tx ^. bodyTxL . collateralInputsTxBodyL)
        , Just out <- [Map.lookup ref known]
        ]

-- | The exclusive upper slot a transaction is valid until, if its body has one.
validUntilOf :: ConwayTx -> Maybe Integer
validUntilOf tx = case invalidHereafter (tx ^. bodyTxL . vldtTxBodyL) of
    SJust (SlotNo slot) -> Just (toInteger slot)
    SNothing -> Nothing

feeOf :: ConwayTx -> Integer
feeOf tx = let Coin fee = tx ^. bodyTxL . feeTxBodyL in fee

{- | What a transaction leaves locked: the lovelace of every output but the last,
which is the change.
-}
lockedBy :: ConwayTx -> Integer
lockedBy tx =
    sum (map coinOf (dropLast (toList (tx ^. bodyTxL . outputsTxBodyL))))
  where
    dropLast items = take (length items - 1) items

{- | What the scripts published before the seed is known are, by their hashes: the registry the seed names
reaches none of them.
-}
seedFreeHashes :: RegistryScripts -> (ByteString, ScriptHash, ScriptHash, ByteString, ScriptHash)
seedFreeHashes scripts =
    ( scriptsTemplate scripts
    , artifactScriptHash (scriptsAttestation scripts)
    , artifactScriptHash (scriptsApplication scripts)
    , scriptsStateHash scripts
    , artifactScriptHash (observerHashProof (scriptsObservers scripts))
    )
