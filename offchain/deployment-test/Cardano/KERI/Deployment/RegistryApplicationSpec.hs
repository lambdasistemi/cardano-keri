{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryApplicationSpec
Description : the KERI application, as public Singular's fold drives it, reads a booked request from public data and contributes the spend, the burn, the references and the donation of its batch

A registry deployed by our builders and two identities booked by them. The checks are of the
three things Singular asks of an application: how a request is read from the output at the
application's address, what the batch spends, burns, references and donates, and which output is
the registry's configuration. The expected values come from the booking's own record and from
Singular's own derivations, never from the module under test. This is a component check over an
in-memory chain that runs no script: that the node accepts the batch is the connected journey's.
-}
module Cardano.KERI.Deployment.RegistryApplicationSpec (spec) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    RegistrationData (..),
    SpendAction (..),
    spendActionData,
 )
import Cardano.KERI.Deployment.RecordedHistory
import Cardano.KERI.Deployment.Registry (RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryApplication
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Chain (..), noFaults, pricedParameters)
import Cardano.KERI.Deployment.RegistryTransactions (
    RegistryDeployment (..),
    RegistryReferences (..),
    applicationPolicyId,
 )
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (getPlutusData)
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (inputsTxBodyL, mintTxBodyL, referenceInputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Conway.TxBody (treasuryDonationTxBodyL)
import Cardano.Ledger.Mary.Value (AssetName (..), MultiAsset (..))
import Cardano.Ledger.Plutus.TxInfo (transAddr)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Tx.Build (draft)
import Control.Monad (forM_)
import Data.IORef (readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Lens.Micro ((^.))
import PlutusLedgerApi.V3 qualified as PV3
import Singular.State.Fold (
    Application (..),
    Folded (..),
    PendingRequest (..),
    Registration (..),
    Request (..),
    discoverPending,
 )
import Singular.State.Preimage qualified as Singular
import Test.Hspec

-- | A registry with two identities booked and nothing folded.
data Booked = Booked World [(TxIn, RegistrationData)]

booked :: IO Booked
booked = do
    world <- newWorld 1_000
    single <- loadExport "kli-export-single.cesr"
    multi <- loadExport "kli-export-2-of-5.cesr"
    first' <- bookDirectly world single
    second' <- bookDirectly world multi
    pure (Booked world [first', second'])

-- | What the booking says the fold must read, from the booking's own record and the registry's addresses.
expectedRegistration :: World -> RegistrationData -> Registration
expectedRegistration world record =
    Registration
        { regRegistry = singularIdentityOf (registryOf world)
        , regKey = requestKey record
        , regHolding = checkpointAddressOf world
        , regDatum = requestInitialDatum record
        , regDeposit = Coin (requestDeposit record)
        , regDeadline = requestProcessDeadline record
        }

spec :: Spec
spec = describe "#558 the KERI application read by Singular's fold" $ do
    describe "a booked registration, read from the output at the application's address" $ do
        it "is decoded into the registration the booking recorded: key, holding address, initial datum, deposit and deadline" $ do
            Booked world requests <- booked
            deployment <- worldDeployment world
            references <- worldReferences world
            found <- rtOutputs (runtimeOf noFaults world) (Set.fromList (map fst requests))
            let application = keriApplication deployment references
            Map.size found `shouldBe` 2
            forM_ requests $ \(ref, record) -> do
                out <- maybe (fail ("the booking output " <> show ref <> " is not on the chain")) pure (Map.lookup ref found)
                appDecode application (singularIdentityOf (registryOf world)) [] out
                    `shouldBe` Just (RegistrationRequest (expectedRegistration world record))
        it "reads nothing from outputs that are not requests: the state, the configuration, the published scripts" $ do
            Booked world _ <- booked
            deployment <- worldDeployment world
            references <- worldReferences world
            Just (_, stateOut) <- stateOutputOf world
            let application = keriApplication deployment references
                others =
                    [ ("state output", stateOut)
                    , ("configuration record", snd (referenceConfiguration references))
                    , ("application script", snd (referenceApplication references))
                    ]
            forM_ others $ \(label, out) ->
                (label :: String, appDecode application (singularIdentityOf (registryOf world)) [] out) `shouldBe` (label, Nothing)
        it "names the configuration record as the configuration and no request as one" $ do
            Booked world requests <- booked
            deployment <- worldDeployment world
            references <- worldReferences world
            found <- rtOutputs (runtimeOf noFaults world) (Set.fromList (map fst requests))
            let application = keriApplication deployment references
            appIsConfiguration application (snd (referenceConfiguration references)) `shouldBe` True
            forM_ (Map.elems found) $ \out -> appIsConfiguration application out `shouldBe` False
    describe "Singular's discovery over the outputs the application's policy holds" $ do
        it "finds both bookings with the approvals derived apart, and neither reports nor folds the configuration record" $ do
            Booked world requests <- booked
            deployment <- worldDeployment world
            references <- worldReferences world
            live <- chainOutputsOf world
            let application = keriApplication deployment references
                singular = singularIdentityOf (registryOf world)
            (found', skipped) <- discoverPending (outputsSession live) application singular []
            skipped `shouldBe` []
            map pendingRef found' `shouldMatchList` map fst requests
            forM_ requests $ \(ref, record) -> do
                let expected = expectedRegistration world record
                    derived =
                        Singular.approvalName
                            ( Singular.registrationPreimage
                                (regKey expected)
                                singular
                                (fromJust (transAddr (regHolding expected)))
                                (Singular.initialDatumHash (regDatum expected))
                                (PV3.Lovelace (requestDeposit record))
                            )
                seenPending <- maybe (fail "a booking was not discovered") pure (lookupPending ref found')
                pendingApproval seenPending `shouldBe` derived
                pendingRequest seenPending `shouldBe` RegistrationRequest expected
    describe "what the batch spends, burns, references and donates" $ do
        it "spends each request with the fold action naming its holding, burns each approval, references the application and the configuration, and donates the registration costs" $ do
            Booked world requests <- booked
            deployment <- worldDeployment world
            references <- worldReferences world
            let application = keriApplication deployment references
                singular = singularIdentityOf (registryOf world)
                folds =
                    [ Folded
                        { foldedRequest = ref
                        , foldedApproval = approvalOf world record
                        , foldedRegistry = singular
                        , foldedKey = requestKey record
                        , foldedHolding = Just holding
                        }
                    | (holding, (ref, record)) <- zip [1 ..] requests
                    ]
                batch = draft pricedParameters (appFold application folds)
                inputs = batch ^. bodyTxL . inputsTxBodyL
                Redeemers declared = batch ^. witsTxL . rdmrsTxWitsL
                MultiAsset minted = batch ^. bodyTxL . mintTxBodyL
                policy = applicationPolicyId deployment
                burned = Map.findWithDefault Map.empty policy minted
                spends =
                    Map.fromList
                        [ (index, getPlutusData datum)
                        | (ConwaySpending (AsIx index), (datum, _)) <- Map.toList declared
                        ]
            -- each request is an input and carries the fold action naming the output that holds its key's token
            Set.toList inputs `shouldMatchList` map fst requests
            forM_ (zip [1 ..] requests) $ \(holding, (ref, _)) -> do
                let index = fromIntegral (Set.findIndex ref inputs)
                Map.lookup index spends `shouldBe` Just (spendActionData (FoldRegistration holding))
            -- each approval burned once
            burned `shouldBe` Map.fromList [(approvalOf world record, -1) | (_, record) <- requests]
            -- the application's code and the configuration are read by reference
            batch ^. bodyTxL . referenceInputsTxBodyL
                `shouldSatisfy` \refs -> all (`Set.member` refs) [fst (referenceApplication references), fst (referenceConfiguration references)]
            -- the treasury is paid the registration cost of each folded request
            batch ^. bodyTxL . treasuryDonationTxBodyL `shouldBe` Coin (fromIntegral (length requests) * registrationCostOf deployment)

approvalOf :: World -> RegistrationData -> AssetName
approvalOf world record =
    Singular.approvalName
        ( Singular.registrationPreimage
            (requestKey record)
            (singularIdentityOf (registryOf world))
            (fromJust (transAddr (checkpointAddressOf world)))
            (Singular.initialDatumHash (requestInitialDatum record))
            (PV3.Lovelace (requestDeposit record))
        )

lookupPending :: TxIn -> [PendingRequest] -> Maybe PendingRequest
lookupPending ref found' = case [p | p <- found', pendingRef p == ref] of
    [found] -> Just found
    _ -> Nothing

chainOutputsOf :: World -> IO (Map.Map TxIn (TxOut ConwayEra))
chainOutputsOf world = chainOutputs <$> readIORef (worldChain world)

registrationCostOf :: RegistryDeployment -> Integer
registrationCostOf = registrationCost . registryParameters . deploymentTerms
