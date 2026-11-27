{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryBookingShapeSpec
Description : The booking transaction of interface v3, as the builders write it

A booking spends the hash proofs an earlier premint left with the controller,
mints the application's approval and the booking attestation of every request,
burns each proof, and returns the attestations in the ordinary change. The
claim an attestation is named by (the application policy, the zero-based index
of the request's output, the exact initial datum it holds and the deposit it
commits) is read back from the transaction the builder wrote, never from the
request it was given: an index, a datum or a deposit the builder got wrong is a
name no policy would accept.

One request and two are built, of different identities and deposits, so that a
position, a quantity and a name each differ between the two requests. The
ledger's own evaluation of the same transactions is in
"Cardano.KERI.Deployment.RegistryBookingEvaluationSpec".
-}
module Cardano.KERI.Deployment.RegistryBookingShapeSpec (
    spec,
    Scenario (..),
    Setup,
    publish,
    scenarioWith,
    scenarioOf,
    single,
    double,
    claimsOf,
    applicationBytes,
    attestationPolicyBytes,
    redeemerOf,
    foldOf,
    foldAt,
    firstRecord,
) where

import Cardano.KERI.AID.Application (
    Action (..),
    ApplicationParameters (..),
    RegistrationData (..),
    actionData,
    activeTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Datum (KeyStateView (..), checkpointDatumFromData)
import Cardano.KERI.AID.Checkpoint.Wire (
    bookingAttestationBurnData,
    bookingAttestationIssueData,
    bookingAttestationName,
 )
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryTransactions
import Cardano.KERI.Deployment.RegistryTransactionsSpec (
    ada,
    afterTx,
    built,
    datumOf,
    deployment,
    deposit,
    interval,
    load,
    mintOf,
    outputAt,
    outputsOf,
    paysItsWay,
    pricedParameters,
    producedBy,
    registrySeedIn,
    scriptHashOf,
    terms,
    token,
    txIn,
    walletOf,
 )
import Cardano.KERI.Deployment.Script (Observers (..), ScriptArtifact (..), mkCageScript, scriptHashBytes)
import Cardano.Ledger.Address (Withdrawals (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    referenceInputsTxBodyL,
    treasuryDonationTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, datumTxOutL, mkBasicTxOut, referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (Inject (..), StrictMaybe (SJust))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (foldM, void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

-- | The shapes of the requests a scenario books: an export and the deposit its request commits.
single, double, keyDerived :: [(FilePath, Integer)]
single = [("kli-export-single.cesr", deposit)]
keyDerived = [("reference:I01", deposit)]
double = [("kli-export-single.cesr", deposit), ("kli-export-2-of-5.cesr", deposit + 7_000_000)]

-- | A booking built by the builders, with everything it was built from.
data Scenario = Scenario
    { scRegistry :: !RegistryDeployment
    , scReferences :: !RegistryReferences
    , scExports :: ![InceptionExport]
    , scRecords :: ![RegistrationData]
    , scRequests :: ![BookedRequest]
    , scState :: !(TxIn, TxOut ConwayEra)
    -- ^ the registry's state output, as its genesis wrote it
    , scPayer :: !Payer
    -- ^ the wallet after the premints, which pays the booking
    , scKnown :: ![(TxIn, TxOut ConwayEra)]
    -- ^ every output the booking may spend
    , scBooking :: !ConwayTx
    }

-- | What a scenario reads by reference, the wallet that pays and the registry's state output: given the registry and the first wallet.
type Setup = RegistryDeployment -> Payer -> IO (RegistryReferences, Payer, (TxIn, TxOut ConwayEra))

-- | A scenario over the registry's real published scripts and the genesis the builder writes.
scenarioOf :: [(FilePath, Integer)] -> IO Scenario
scenarioOf = scenarioWith publish

-- | The registry's scripts as published outputs, and the configuration record and the state its genesis writes.
publish :: Setup
publish registry owner = do
    let scripts = deploymentScripts registry
        holder = payerAddress owner
        carrying n program =
            ( txIn n
            , mkBasicTxOut holder (inject (ada 20)) & referenceScriptTxOutL .~ SJust (mkCageScript program)
            )
        template =
            ( txIn 0xa1
            , mkBasicTxOut holder (inject (ada 20)) & datumTxOutL .~ mkInlineDatum (PLC.B (scriptsTemplate scripts))
            )
        application = carrying 0x81 (artifactProgram (scriptsApplication scripts))
        state = carrying 0x82 (scriptsStateProgram scripts)
        attestation = carrying 0x84 (artifactProgram (scriptsAttestation scripts))
        hashProof = carrying 0x85 (artifactProgram (observerHashProof (scriptsObservers scripts)))
    (genesis, _) <-
        built
            ( createConfiguration
                Nothing
                pricedParameters
                registry
                [template, application, state]
                owner
                (registrySeedIn, mkBasicTxOut holder (inject (ada 200)))
                (registryParameters terms)
                Map.empty
            )
    pure
        ( RegistryReferences
            { referenceApplication = application
            , referenceState = state
            , referenceConfiguration = outputAt genesis 1
            , referenceAttestation = attestation
            , referenceHashProof = hashProof
            }
        , afterTx owner genesis
        , outputAt genesis 0
        )

scenarioWith :: Setup -> [(FilePath, Integer)] -> IO Scenario
scenarioWith setup shapes = do
    registry <- deployment
    exports <- traverse (load . fst) shapes
    let owner0 = walletOf 0x10
        refund = payerAddress owner0
    (references, owner, stateOut) <- setup registry owner0
    let premint (wallet, premints) export = do
            tx <- built (mintHashProof pricedParameters registry wallet export interval)
            pure (afterTx wallet tx, premints <> [tx])
    (payer, premints) <- foldM premint (owner, []) exports
    let records =
            [ registrationRecord registry refund amount export interval
            | ((_, amount), export) <- zip shapes exports
            ]
        requests = [BookedRequest record export (outputAt tx 0) | (record, export, tx) <- zip3 records exports premints]
    (booking, _) <-
        built (bookRegistrations pricedParameters registry references payer requests interval 0 Map.empty)
    pure
        Scenario
            { scRegistry = registry
            , scReferences = references
            , scExports = exports
            , scRecords = records
            , scRequests = requests
            , scState = stateOut
            , scPayer = payer
            , scKnown = payerFunds owner <> concatMap producedBy premints
            , scBooking = booking
            }

-- | The application's policy, the 28 bytes the claim of an attestation names.
applicationBytes :: RegistryDeployment -> ByteString
applicationBytes = scriptHashBytes . artifactScriptHash . scriptsApplication . deploymentScripts

attestationPolicyBytes :: RegistryDeployment -> ByteString
attestationPolicyBytes = scriptHashBytes . artifactScriptHash . scriptsAttestation . deploymentScripts

{- | What each request's output of the transaction holds, read from the
transaction: the zero-based position of the output, the initial datum and the
deposit its datum commits. The output is found by the approval it holds.
-}
claimsOf :: RegistryDeployment -> ConwayTx -> [RegistrationData] -> [(Integer, PLC.Data, Integer)]
claimsOf registry tx records =
    [ (fromIntegral position, initial, committed)
    | record <- records
    , (position, out) <- zip [0 :: Int ..] (outputsOf tx)
    , holdsExactlyApproval registry record out
    , Just (PLC.Constr 1 [PLC.Constr 0 fields]) <- [datumOf out]
    , length fields == 10
    , let initial = fields !! 5
    , PLC.I committed <- [fields !! 6]
    ]

-- | The redeemer a transaction gives the minting policy.
redeemerOf :: ConwayTx -> PolicyID -> Maybe PLC.Data
redeemerOf tx policy =
    let Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
        position = mintingIndex policy (tx ^. bodyTxL . mintTxBodyL)
     in (\(Data plc, _) -> plc) <$> Map.lookup (ConwayMinting (AsIx position)) redeemers

spec :: Spec
spec = describe "#559 the booking transaction of interface v3" $ do
    mapM_
        (\(label, shapes) -> describe label (shapeTests shapes))
        [ ("one request", single)
        , ("two requests of other identities and deposits", double)
        , ("one request of a key-derived identifier (D code, own SAID apart)", keyDerived)
        ]

    describe "a weighted future declaration is booked with a datum the codec reads back" $
        mapM_
            ( \name -> it name $ do
                s <- scenarioOf [(name, deposit)]
                case map requestInitialDatum (scRecords s) of
                    [PLC.Constr 1 [live]] -> void (checkpointDatumFromData (PLC.Constr 1 [live])) `shouldBe` Just ()
                    other -> fail ("the initial datum is not a version 2 checkpoint: " <> show other)
            )
            ["future:D next unreduced", "future:D next partial coverage"]
    describe "a key-derived inception is booked under its signed qualified identifier" $ do
        it "keys the request, the initial datum and the stored current keys by the exact signed spelling" $ do
            s <- scenarioOf keyDerived
            let aid = "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            map requestKey (scRecords s) `shouldBe` [aid]
            case map requestInitialDatum (scRecords s) of
                [PLC.Constr 1 [PLC.Constr 0 (PLC.B stored : _ : _ : _ : _ : _ : _ : _ : PLC.Constr 0 (PLC.List keys : _) : _)]] -> do
                    stored `shouldBe` aid
                    keys `shouldBe` [PLC.B aid]
                other -> fail ("the initial datum is not the live checkpoint: " <> show other)
        it "names the hash proof over the raw payload of the signed identifier, not its qualified text" $ do
            s <- scenarioOf keyDerived
            case scExports s of
                [export] -> do
                    inceptionProofName export `shouldNotBe` inceptionProofName export{inceptionDatum = (inceptionDatum export){cdCesrAid = BS.replicate 32 0}}
                    BS.length (cdCesrAid (inceptionDatum export)) `shouldBe` 32
                _ -> fail "one export was expected"

    describe "the fold of a booked request: it supplies no evidence, no proof and no withdrawal" $ do
        it "burns the approval, mints the one active token of the key and nothing else" $ do
            s <- scenarioOf single
            tx <- foldOf s
            let scripts = deploymentScripts (scRegistry s)
                record = firstRecord s
            mintOf tx
                `shouldBe` Map.unionsWith
                    (<>)
                    [ token (artifactScriptHash (scriptsApplication scripts)) (approval record) (-1)
                    , token (scriptHashOf (scriptsStateHash scripts)) (activeTokenName (scriptsRegistry scripts) (requestKey record)) 1
                    ]
        it "carries four purposes, none of them a withdrawal, and no hash proof, certificate or script witness" $ do
            s <- scenarioOf single
            tx <- foldOf s
            let Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
                Withdrawals withdrawals = tx ^. bodyTxL . withdrawalsTxBodyL
            Map.size redeemers `shouldBe` 4
            [() | ConwayRewarding _ <- Map.keys redeemers] `shouldBe` []
            Map.null withdrawals `shouldBe` True
            toList (tx ^. bodyTxL . certsTxBodyL) `shouldBe` []
            Map.null (tx ^. witsTxL . scriptTxWitsL) `shouldBe` True
        it "pays the committed holding first, donates the registration cost, reads the configuration by reference and keeps every lovelace" $ do
            s <- scenarioOf single
            tx <- foldOf s
            let record = firstRecord s
                references = scReferences s
            take 1 (outputsOf tx) `shouldBe` [deliveredHolding (scRegistry s) record]
            tx ^. bodyTxL . treasuryDonationTxBodyL `shouldBe` Coin (registrationCost (registryParameters terms))
            map fst [referenceConfiguration references, referenceApplication references, referenceState references]
                `shouldSatisfy` all (`Set.member` (tx ^. bodyTxL . referenceInputsTxBodyL))
            paysItsWay (scKnown s <> producedBy (scBooking s) <> [scState s]) tx `shouldBe` True

    describe "builder refusals: typed errors of the builder before it builds anything, no script runs" $ do
        it "a booking of no request" $ do
            s <- scenarioOf single
            void (bookRegistrations pricedParameters (scRegistry s) (scReferences s) (scPayer s) [] interval 0 Map.empty)
                `shouldBe` Left NothingToBook
        it "a proof output that holds another inception's proof" $ do
            s <- scenarioOf double
            case scRequests s of
                [first', second'] -> do
                    let swapped = [first'{bookedProof = bookedProof second'}]
                    void (bookRegistrations pricedParameters (scRegistry s) (scReferences s) (scPayer s) swapped interval 0 Map.empty)
                        `shouldBe` Left (ProofIsNotTheInceptions (fst (bookedProof second')))
                _ -> fail "two requests were built"
        it "a proof output that holds no proof at all" $ do
            s <- scenarioOf single
            case scRequests s of
                [request] -> do
                    let bare = (txIn 0x7a, mkBasicTxOut (payerAddress (scPayer s)) (inject (ada 5)))
                    void
                        ( bookRegistrations
                            pricedParameters
                            (scRegistry s)
                            (scReferences s)
                            (scPayer s)
                            [request{bookedProof = bare}]
                            interval
                            0
                            Map.empty
                        )
                        `shouldBe` Left (ProofIsNotTheInceptions (fst bare))
                _ -> fail "one request was built"
        it "two requests that name the exact same output as their proof: it is spent once" $ do
            s <- scenarioOf single
            case scRequests s of
                [request] ->
                    void (bookRegistrations pricedParameters (scRegistry s) (scReferences s) (scPayer s) [request, request] interval 0 Map.empty)
                        `shouldBe` Left (ProofOutputReused (fst (bookedProof request)))
                _ -> fail "one request was built"

    describe "the controller's burn of attestations" $ do
        it "burns each attestation the given outputs hold with the Burn redeemer, mints nothing, shows no evidence and spends no proof" $ do
            s <- scenarioOf double
            let registry = scRegistry s
                booking = scBooking s
                changeOut = outputAt booking (length (scRecords s))
                holder = afterTx (scPayer s) booking
                scripts = deploymentScripts registry
                attestation = artifactScriptHash (scriptsAttestation scripts)
            (burn, _) <- built (burnAttestations pricedParameters registry (scReferences s) holder [changeOut] Map.empty)
            mintOf burn
                `shouldBe` Map.unionsWith
                    (<>)
                    [token attestation name (-1) | name <- attestationNames registry s]
            redeemerOf burn (attestationPolicyId registry) `shouldBe` Just bookingAttestationBurnData
            let Redeemers redeemers = burn ^. witsTxL . rdmrsTxWitsL
            Map.size redeemers `shouldBe` 1
            Set.member (fst changeOut) (burn ^. bodyTxL . inputsTxBodyL) `shouldBe` True
            map (attestationsOf registry) (outputsOf burn) `shouldBe` [Map.empty]
            paysItsWay (scKnown s <> producedBy booking) burn `shouldBe` True
        it "refuses a burn of outputs that hold no attestation" $ do
            s <- scenarioOf single
            let registry = scRegistry s
                holder = afterTx (scPayer s) (scBooking s)
                plain = (txIn 0x7b, mkBasicTxOut (payerAddress holder) (inject (ada 5)))
            void (burnAttestations pricedParameters registry (scReferences s) holder [plain] Map.empty)
                `shouldBe` Left NothingToBurn
            void (burnAttestations pricedParameters registry (scReferences s) holder [] Map.empty)
                `shouldBe` Left NothingToBurn

-- | What one booking of the given requests is, whatever their number.
shapeTests :: [(FilePath, Integer)] -> Spec
shapeTests shapes = do
    it "mints one approval and one attestation per request and burns each hash proof, and mints nothing else" $ do
        s <- scenarioOf shapes
        let registry = scRegistry s
            scripts = deploymentScripts registry
            application = artifactScriptHash (scriptsApplication scripts)
            attestation = artifactScriptHash (scriptsAttestation scripts)
            hashProof = artifactScriptHash (observerHashProof (scriptsObservers scripts))
            claims = claimsOf registry (scBooking s) (scRecords s)
        length claims `shouldBe` length shapes
        mintOf (scBooking s)
            `shouldBe` Map.unionsWith
                (<>)
                ( [token application (approval record) 1 | record <- scRecords s]
                    <> [ token attestation (bookingAttestationName (applicationBytes registry) position initial committed) 1
                       | (position, initial, committed) <- claims
                       ]
                    <> [token hashProof (inceptionProofName export) (-1) | export <- scExports s]
                )
    it "names each attestation by the claim of the output the request is really in" $ do
        s <- scenarioOf shapes
        let registry = scRegistry s
            claims = claimsOf registry (scBooking s) (scRecords s)
            names = [bookingAttestationName (applicationBytes registry) p i d | (p, i, d) <- claims]
        length (Set.fromList names) `shouldBe` length shapes
        Map.keysSet (attestationsMinted registry (scBooking s)) `shouldBe` Set.fromList names
        -- the positions are the outputs' own: each request is at the next output, change is last
        [position | (position, _, _) <- claims] `shouldBe` map fromIntegral [0 .. length shapes - 1]
        -- a name made with another position is not one the transaction mints
        [bookingAttestationName (applicationBytes registry) 0 i d | (_, i, d) <- claims]
            `shouldSatisfy` (\other -> length shapes == 1 || other /= names)
    it "writes the Issue redeemer with the evidence of each request at its output position, and burns each proof with the proof policy's burn" $ do
        s <- scenarioOf shapes
        let registry = scRegistry s
            claims = claimsOf registry (scBooking s) (scRecords s)
            scripts = deploymentScripts registry
            hashProofPolicy = PolicyID (artifactScriptHash (observerHashProof (scriptsObservers scripts)))
        redeemerOf (scBooking s) (attestationPolicyId registry)
            `shouldBe` Just
                ( bookingAttestationIssueData
                    (applicationBytes registry)
                    [(position, inceptionEvidence export) | ((position, _, _), export) <- zip claims (scExports s)]
                )
        redeemerOf (scBooking s) (applicationPolicyId registry)
            `shouldBe` Just (PLC.List [actionData (BookRegistration position) | (position, _, _) <- claims])
        redeemerOf (scBooking s) hashProofPolicy
            `shouldBe` Just (PLC.Constr 0 [PLC.B "", PLC.B ""])
    it "pays the approvals with the requests, the attestations to an output of their own and the rest to change that holds lovelace alone, and no output holds a hash proof" $ do
        s <- scenarioOf shapes
        let registry = scRegistry s
            outputs = outputsOf (scBooking s)
            requests = take (length shapes) outputs
            change = drop (length shapes) outputs
            holds policy out = let MaryValue _ (MultiAsset assets) = out ^. valueTxOutL in Map.member policy assets
            hashProofPolicy = PolicyID (artifactScriptHash (observerHashProof (scriptsObservers (deploymentScripts registry))))
            payerAddress' = payerAddress (scPayer s)
        length change `shouldBe` 2
        all (uncurry (holdsExactlyApproval registry)) (zip (scRecords s) requests) `shouldBe` True
        any (holds (attestationPolicyId registry)) requests `shouldBe` False
        map (^. addrTxOutL) change `shouldBe` [payerAddress', payerAddress']
        map (attestationsOf registry) change `shouldBe` [Map.fromList [(name, 1) | name <- attestationNames registry s], Map.empty]
        any (holds hashProofPolicy) outputs `shouldBe` False
    it "spends the proof of each inception, reads the registry's scripts by reference, and registers, withdraws and certifies nothing" $ do
        s <- scenarioOf shapes
        let tx = scBooking s
            references = scReferences s
        [fst (bookedProof request) | request <- scRequests s]
            `shouldSatisfy` all (`Set.member` (tx ^. bodyTxL . inputsTxBodyL))
        map fst [referenceApplication references, referenceConfiguration references, referenceAttestation references, referenceHashProof references]
            `shouldSatisfy` all (`Set.member` (tx ^. bodyTxL . referenceInputsTxBodyL))
        let Withdrawals withdrawals = tx ^. bodyTxL . withdrawalsTxBodyL
        Map.null withdrawals `shouldBe` True
        toList (tx ^. bodyTxL . certsTxBodyL) `shouldBe` []
        Map.null (tx ^. witsTxL . scriptTxWitsL) `shouldBe` True
    it "pays the ledger's minimum fee and keeps every lovelace and every asset" $ do
        s <- scenarioOf shapes
        paysItsWay (scKnown s) (scBooking s) `shouldBe` True

-- | The attestations a transaction mints, by name.
attestationsMinted :: RegistryDeployment -> ConwayTx -> Map.Map ByteString Integer
attestationsMinted registry tx =
    let MultiAsset minted = tx ^. bodyTxL . mintTxBodyL
     in Map.fromList
            [ (SBS.fromShort (assetNameBytes name), quantity)
            | (name, quantity) <- maybe [] Map.toList (Map.lookup (attestationPolicyId registry) minted)
            ]

-- | The attestations an output holds, by name.
attestationsOf :: RegistryDeployment -> TxOut ConwayEra -> Map.Map ByteString Integer
attestationsOf registry out =
    let MaryValue _ (MultiAsset assets) = out ^. valueTxOutL
     in Map.fromList
            [ (SBS.fromShort (assetNameBytes name), quantity)
            | (name, quantity) <- maybe [] Map.toList (Map.lookup (attestationPolicyId registry) assets)
            ]

-- | The names of the attestations a scenario's booking mints.
attestationNames :: RegistryDeployment -> Scenario -> [ByteString]
attestationNames registry s =
    [ bookingAttestationName (applicationBytes registry) position initial committed
    | (position, initial, committed) <- claimsOf registry (scBooking s) (scRecords s)
    ]

-- | The fold of the first request of a scenario, by the wallet that booked it, before its deadline.
foldOf :: Scenario -> IO ConwayTx
foldOf s = foldAt s 0

-- | The fold of the request at an output position of the booking.
foldAt :: Scenario -> Int -> IO ConwayTx
foldAt s position = do
    let booking = scBooking s
        plan =
            FoldPlan
                { foldRequest = outputAt booking position
                , foldBooked = scRecords s !! position
                , foldRegistered = []
                , foldTerminated = []
                , foldState = scState s
                , foldValidity = interval
                , foldPayer = afterTx (scPayer s) booking
                }
    fst <$> built (foldRegistration pricedParameters (scRegistry s) (scReferences s) plan Map.empty)

-- | The record of the first request of a scenario.
firstRecord :: Scenario -> RegistrationData
firstRecord s = case scRecords s of
    record : _ -> record
    [] -> error "firstRecord: a scenario of no request"
