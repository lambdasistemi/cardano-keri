{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryTransactionsSpec
Description : the registry's transactions are built from what a caller gives them

The registration record, its approval name, the lovelace of a request and the
holding a fold delivers are checked against the words of the Lean model
(@Application.requestLovelace@, @Application.approval@,
@Application.delivered@): every expected value is spelled out here from the
real keripy export and the terms the registry is derived from, never read back
from a builder. The transactions are built for a chain that is not the devnet,
by a wallet no builder knows, under protocol parameters whose prices are not
zero: each pays the ledger's minimum fee, no output names another network, and
the lovelace of every transaction is conserved.
-}
module Cardano.KERI.Deployment.RegistryTransactionsSpec (
    spec,

    -- * What the specs of the booking share
    terms,
    deployment,
    deposit,
    walletOf,
    afterTx,
    outputAt,
    outputsOf,
    producedBy,
    pricedParameters,
    paysItsWay,
    mintOf,
    datumOf,
    token,
    built,
    interval,
    load,
    txIn,
    ada,
    scriptHashOf,
    feeOf,
    registrySeedIn,
) where

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    Change (..),
    Credential (..),
    HeldDatum (..),
    OutputReference (..),
    RegistrationData (..),
    RegistryIdentity (..),
    activeLeaf,
    activeTokenName,
    configurationTokenName,
    heldDatumData,
    registrationApprovalName,
    stateDatumData,
    stateSpendData,
    stateTokenName,
    unstakedAddress,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    QualifiedIdentity (..),
    keyMaterialOf,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData, bookingAttestationBurnData)
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.AID.E2E.MpfProof (prove)
import Cardano.KERI.AID.E2E.MpfTrie qualified as Trie
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    parseInceptionExport,
 )
import Cardano.KERI.Deployment.ReferenceInception (referenceExport)
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
    registryInitialFloor,
 )
import Cardano.KERI.Deployment.RegistryTransactions
import Cardano.KERI.Deployment.Script (
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    loadBlueprint,
    mkCageScript,
    scriptHashBytes,
 )
import Cardano.KERI.Deployment.SingularFunding (singularFundingRules)
import Cardano.KERI.Deployment.TransactionRuntime.Fixtures (testPParams)
import Cardano.Ledger.Address (
    Addr (..),
    Withdrawals (..),
    serialiseAddr,
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppPricesL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..), Prices (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    binaryDataToData,
 )
import Cardano.Ledger.Api.Tx (bodyTxL, estimateMinFeeTx, txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    treasuryDonationTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
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
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams, TxOut, ppMaxTxSizeL)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash (..),
    extractHash,
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (SlotNo (..))
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.List (stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, listToMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as Text
import Data.Word (Word8)
import Lens.Micro ((&), (.~), (^.))
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data qualified as PLC
import System.Environment (getEnv)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldNotBe, shouldSatisfy)

-- | The registry's terms: a chain that is not the devnet (network nibble 1).
terms :: RegistryTerms
terms =
    RegistryTerms
        { registryCheckpointTerms =
            CheckpointTerms
                { termsNetwork = 1
                , termsDeposit = 1_000_000_000
                , termsFreezeBond = 5_000_000
                , termsPremium = 2_000_000
                }
        , registryParameters =
            ApplicationParameters
                { registrationCost = 2_000_000
                , minimumTip = 1_000_000
                , processTime = 600_000
                , bookingWidth = 100_000
                }
        , registryMinimumAda = 2_000_000
        , registryTerminationCarrier = 1_000_000
        }

seed :: OutputReference
seed = OutputReference (BS.replicate 32 0x77) 3

deployment :: IO RegistryDeployment
deployment = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <- loadBlueprint path >>= either fail pure
    scripts <-
        either fail pure (deriveRegistryScripts stateTemplate terms seed blueprint)
    pure (RegistryDeployment Mainnet terms scripts)

-- | The deposit the request commits: the registry's floor and a pool beyond it.
deposit :: Integer
deposit = registryInitialFloor terms + 1_000_000

walletAddress :: Word8 -> Addr
walletAddress n =
    Addr
        Mainnet
        (KeyHashObj (KeyHash (fromJust (hashFromBytes (BS.replicate 28 n)))))
        StakeRefNull

txIn :: Word8 -> TxIn
txIn n =
    TxIn
        (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 n)))))
        (TxIx 0)

-- | The output the registry of the test is created from: the seed its identity names.
registrySeedIn :: TxIn
registrySeedIn =
    TxIn
        (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (outputTransactionId seed)))))
        (TxIx (fromIntegral (outputIndex seed)))

ada :: Integer -> Coin
ada = Coin . (* 1_000_000)

-- | A wallet of three outputs.
walletOf :: Word8 -> Payer
walletOf n =
    Payer
        { payerAddress = walletAddress n
        , payerRules = singularFundingRules
        , payerFunds =
            [ (txIn (n + k), mkBasicTxOut (walletAddress n) (inject (ada size)))
            | (k, size) <- [(1, 5_000), (2, 4_000), (3, 3_000)]
            ]
        }

{- | The wallet after a transaction: what it did not spend and what the
transaction paid it.
-}
afterTx :: Payer -> ConwayTx -> Payer
afterTx payer tx =
    payer
        { payerFunds =
            [ funds
            | funds@(ref, _) <- payerFunds payer
            , not (Set.member ref (tx ^. bodyTxL . inputsTxBodyL))
            ]
                <> [ outputAt tx ix
                   | (ix, out) <- zip [0 ..] (outputsOf tx)
                   , out ^. addrTxOutL == payerAddress payer
                   ]
        }

outputsOf :: ConwayTx -> [TxOut ConwayEra]
outputsOf tx = toList (tx ^. bodyTxL . outputsTxBodyL)

outputAt :: ConwayTx -> Int -> (TxIn, TxOut ConwayEra)
outputAt tx ix = (TxIn (txIdTx tx) (TxIx (fromIntegral ix)), outputsOf tx !! ix)

firstOutput :: ConwayTx -> TxOut ConwayEra
firstOutput tx = case outputsOf tx of
    out : _ -> out
    [] -> error "firstOutput: a transaction without outputs"

producedBy :: ConwayTx -> [(TxIn, TxOut ConwayEra)]
producedBy tx = [outputAt tx ix | ix <- [0 .. length (outputsOf tx) - 1]]

feeOf :: ConwayTx -> Integer
feeOf tx = let Coin c = tx ^. bodyTxL . feeTxBodyL in c

{- | Protocol parameters whose prices are not zero: a fee follows the units a
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

-- | The ledger's own minimum fee of a transaction signed by one key.
minimumFee :: ConwayTx -> Integer
minimumFee tx = case estimateMinFeeTx pricedParameters tx 1 0 0 of
    Coin c -> c

{- | A transaction pays at least the minimum fee, every output is on the
registry's network, the lovelace the inputs hold is what the outputs, the fee
and the donation take, and every native asset the inputs hold and the
transaction mints is in an output.
-}
paysItsWay :: [(TxIn, TxOut ConwayEra)] -> ConwayTx -> Bool
paysItsWay known tx =
    feeOf tx >= minimumFee tx
        && all ((== Mainnet) . networkOf . (^. addrTxOutL)) (outputsOf tx)
        && resolved
        && inputsCoin == sum (map coinOf (outputsOf tx)) + feeOf tx + donation
        && inputsAssets <> (tx ^. bodyTxL . mintTxBodyL) == foldMap assetsOf (outputsOf tx)
  where
    inputs = toList (tx ^. bodyTxL . inputsTxBodyL)
    resolved = all (`elem` map fst known) inputs
    inputsCoin = sum [coinOf out | ref <- inputs, Just out <- [lookup ref known]]
    inputsAssets = foldMap assetsOf [out | ref <- inputs, Just out <- [lookup ref known]]
    coinOf out = let Coin c = out ^. coinTxOutL in c
    Coin donation = tx ^. bodyTxL . treasuryDonationTxBodyL
    networkOf (Addr network _ _) = network
    networkOf _ = Testnet

assetsOf :: TxOut ConwayEra -> MultiAsset
assetsOf out = let MaryValue _ assets = out ^. valueTxOutL in assets

datumOf :: TxOut ConwayEra -> Maybe PLC.Data
datumOf out = case out ^. datumTxOutL of
    Datum binary -> let Data plc = binaryDataToData binary in Just plc
    _ -> Nothing

mintOf :: ConwayTx -> Map.Map PolicyID (Map.Map AssetName Integer)
mintOf tx = let MultiAsset assets = tx ^. bodyTxL . mintTxBodyL in assets

scriptHashOf :: ByteString -> ScriptHash
scriptHashOf = ScriptHash . fromJust . hashFromBytes

-- | One token of a policy.
token :: ScriptHash -> ByteString -> Integer -> Map.Map PolicyID (Map.Map AssetName Integer)
token policy name quantity =
    Map.singleton (PolicyID policy) (Map.singleton (AssetName (SBS.toShort name)) quantity)

built :: (Show e) => Either e a -> IO a
built = either (fail . ("not built: " <>) . show) pure

interval :: ValidityPlan
interval =
    ValidityPlan
        { lowerSlot = SlotNo 1_000
        , upperSlot = SlotNo 1_025
        , lowerPosixMs = 1_700_000_000_000
        , upperPosixMs = 1_700_000_025_000
        }

{- | An export by fixture file name; a name of the form @reference:ID@ is the
independent reference inception of that id, built through the same decoder.
-}
load :: FilePath -> IO InceptionExport
load name
    | Just reference <- stripPrefix "reference:" name = referenceExport (T.pack reference)
    | otherwise = do
        path <- getDataFileName ("deployment-test/fixtures/" <> name)
        stream <- BS.readFile path
        either fail pure (parseInceptionExport stream)

spec :: Spec
spec = do
    describe "the lovelace of a request" $
        it "is the deposit, the registration cost and the minimum tip" $ do
            let parametersOf cost tip =
                    ApplicationParameters
                        { registrationCost = cost
                        , minimumTip = tip
                        , processTime = 0
                        , bookingWidth = 0
                        }
                request amount =
                    RegistrationData
                        { requestRegistry = RegistryIdentity BS.empty BS.empty
                        , requestKey = BS.empty
                        , requestController = BS.empty
                        , requestRefundAddress = unstakedAddress (KeyCredential BS.empty)
                        , requestHoldingAddress = unstakedAddress (KeyCredential BS.empty)
                        , requestInitialDatum = PLC.I 0
                        , requestDeposit = amount
                        , requestBookedAt = 0
                        , requestProcessDeadline = 0
                        , requestReclaimEnd = 0
                        }
            requestLovelace (parametersOf 7 11) (request 1_000) `shouldBe` 1_018
            requestLovelace (parametersOf 0 0) (request 1_000) `shouldBe` 1_000
            requestLovelace (parametersOf 2_000_000 1_000_000) (request 5)
                `shouldBe` 3_000_005
    describe "a registration read from a real keripy export" $ do
        let refund = walletAddress 0x10
            booked = do
                export <- load "kli-export-single.cesr"
                registry <- deployment
                pure
                    ( export
                    , registry
                    , registrationRecord registry refund deposit export interval
                    )
            checkpointHashOf registry =
                scriptHashBytes
                    (artifactScriptHash (scriptsCheckpoint (deploymentScripts registry)))
        it "names the registry and the key of the identity" $ do
            (export, registry, record) <- booked
            requestRegistry record `shouldBe` scriptsRegistry (deploymentScripts registry)
            requestKey record `shouldBe` Text.encodeUtf8 (inceptionAid export)
        it "commits the checkpoint validator as the holding address" $ do
            (_, registry, record) <- booked
            requestHoldingAddress record
                `shouldBe` unstakedAddress (ScriptCredential (checkpointHashOf registry))
        it "commits the refund address, which is also the controller" $ do
            (_, _, record) <- booked
            requestRefundAddress record
                `shouldBe` unstakedAddress (KeyCredential (BS.replicate 28 0x10))
            requestController record `shouldBe` BS.replicate 28 0x10
        it "commits the initial datum of the identity" $ do
            (export, _, record) <- booked
            requestInitialDatum record
                `shouldBe` asPlcData (V2 (initialFacts export refund))
        it "writes the facts of a new registration: live at sequence number and epoch 0, born at the booking bound" $ do
            (export, _, _) <- booked
            registeredFacts refund export interval
                `shouldBe` initialFacts export refund
        it "commits the deposit and the booking clock" $ do
            (_, _, record) <- booked
            requestDeposit record `shouldBe` deposit
            requestBookedAt record `shouldBe` upperPosixMs interval
            requestProcessDeadline record `shouldBe` upperPosixMs interval + 600_000
            requestReclaimEnd record `shouldBe` upperPosixMs interval + 600_000
        it "names the approval of the request from its registry, key, holding, initial datum and deposit" $ do
            (export, registry, record) <- booked
            approval record
                `shouldBe` registrationApprovalName
                    (scriptsRegistry (deploymentScripts registry))
                    (Text.encodeUtf8 (inceptionAid export))
                    (unstakedAddress (ScriptCredential (checkpointHashOf registry)))
                    (asPlcData (V2 (initialFacts export refund)))
                    deposit
        describe "the holding a fold delivers" $ do
            let holdingOf = do
                    (_, registry, record) <- booked
                    pure (registry, record, deliveredHolding registry record)
            it "is at the checkpoint validator's address" $ do
                (registry, _, holding) <- holdingOf
                holding ^. addrTxOutL
                    `shouldBe` Addr
                        Mainnet
                        ( ScriptHashObj
                            (artifactScriptHash (scriptsCheckpoint (deploymentScripts registry)))
                        )
                        StakeRefNull
            it "holds exactly the committed deposit" $ do
                (_, _, holding) <- holdingOf
                let MaryValue (Coin held) _ = holding ^. valueTxOutL
                held `shouldBe` deposit
            it "holds the one active token of the key and nothing else" $ do
                (registry, record, holding) <- holdingOf
                let MaryValue _ (MultiAsset assets) = holding ^. valueTxOutL
                    scripts = deploymentScripts registry
                    active = activeTokenName (scriptsRegistry scripts) (requestKey record)
                assets
                    `shouldBe` Map.singleton
                        (PolicyID (scriptHashOf (scriptsStateHash scripts)))
                        (Map.singleton (AssetName (SBS.toShort active)) 1)
            it "carries the committed initial datum" $ do
                (_, record, holding) <- holdingOf
                datumOf holding `shouldBe` Just (requestInitialDatum record)
    describe "the transactions of a registry on a chain that is not the devnet" $ do
        it "each pay the ledger's minimum fee and keep every lovelace" $ do
            registry <- deployment
            export <- load "kli-export-single.cesr"
            let scripts = deploymentScripts registry
                owner = walletOf 0x10
                folder = walletOf 0x40
                refund = payerAddress owner
                stateScript = mkCageScript (scriptsStateProgram scripts)
                applicationScript =
                    mkCageScript (artifactProgram (scriptsApplication scripts))
                application = artifactScriptHash (scriptsApplication scripts)
                state = scriptHashOf (scriptsStateHash scripts)
                hashProof = artifactScriptHash (observerHashProof (scriptsObservers scripts))
                attestation = artifactScriptHash (scriptsAttestation scripts)
                observerReferences = [(txIn 0x91, mkBasicTxOut refund (inject (ada 10)))]
                seedOutput = (registrySeedIn, mkBasicTxOut refund (inject (ada 200)))
                known0 = payerFunds owner <> payerFunds folder <> [seedOutput] <> observerReferences
            template <-
                built (publishTemplate Nothing pricedParameters owner (ada 10) (scriptsTemplate scripts))
            let owner1 = afterTx owner template
            applicationTx <-
                built (publishReferenceScript Nothing pricedParameters owner1 (ada 10) applicationScript)
            let owner2 = afterTx owner1 applicationTx
            stateTx <-
                built (publishReferenceScript Nothing pricedParameters owner2 (ada 10) stateScript)
            let owner3 = afterTx owner2 stateTx
            (genesis, genesisPurposes) <-
                built
                    ( createConfiguration
                        Nothing
                        pricedParameters
                        registry
                        [outputAt template 0, outputAt applicationTx 0, outputAt stateTx 0]
                        owner3
                        seedOutput
                        (registryParameters terms)
                        Map.empty
                    )
            let references =
                    RegistryReferences
                        { referenceApplication = outputAt applicationTx 0
                        , referenceState = outputAt stateTx 0
                        , referenceConfiguration = outputAt genesis 1
                        , referenceAttestation = (txIn 0x84, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceHashProof = (txIn 0x85, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        }
                owner4 = afterTx owner3 genesis
                record = registrationRecord registry refund deposit export interval
                knownAfterGenesis =
                    known0
                        <> concatMap producedBy [template, applicationTx, stateTx]
                        <> producedBy genesis
            paysItsWay (known0 <> concatMap producedBy [template, applicationTx, stateTx]) genesis
                `shouldBe` True
            paysItsWay known0 template `shouldBe` True
            paysItsWay (known0 <> producedBy template) applicationTx `shouldBe` True
            paysItsWay (known0 <> producedBy template <> producedBy applicationTx) stateTx
                `shouldBe` True
            Set.size genesisPurposes `shouldBe` 2
            Set.member registrySeedIn (genesis ^. bodyTxL . inputsTxBodyL) `shouldBe` True
            mintOf genesis
                `shouldBe` Map.unionWith
                    (<>)
                    (token state (stateTokenName seed) 1)
                    (token application (configurationTokenName (scriptsRegistry scripts)) 1)
            -- the hash proof of the booking, preminted first, and the booking that burns it
            bookingProofTx <- built (mintHashProof pricedParameters registry owner4 export interval)
            -- valid over the interval it is given, so a booking can follow it within the booking width
            bookingProofTx ^. bodyTxL . vldtTxBodyL
                `shouldBe` ValidityInterval (SJust (lowerSlot interval)) (SJust (upperSlot interval))
            let owner4b = afterTx owner4 bookingProofTx
                knownBeforeBooking = knownAfterGenesis <> producedBy bookingProofTx
                bookingProofName = proofTokenName (reEventBytes (inceptionEvidence export)) (cdCesrAid (inceptionDatum export))
            mintOf bookingProofTx `shouldBe` token hashProof bookingProofName 1
            (booking, _) <-
                built
                    ( bookRegistrations
                        pricedParameters
                        registry
                        references
                        owner4b
                        [BookedRequest record export (outputAt bookingProofTx 0)]
                        interval
                        0
                        Map.empty
                    )
            let requestOut = outputAt booking 0
                owner5 = afterTx owner4b booking
            paysItsWay knownBeforeBooking booking `shouldBe` True
            mintOf booking
                `shouldBe` Map.unionsWith
                    (<>)
                    [ token application (approval record) 1
                    , token attestation (attestationName registry 0 record) 1
                    , token hashProof bookingProofName (-1)
                    ]
            snd requestOut ^. coinTxOutL
                `shouldBe` Coin (requestLovelace (registryParameters terms) record)
            datumOf (snd requestOut) `shouldBe` Just (heldDatumData (Registration record))
            let knownAfterBooking = knownBeforeBooking <> producedBy booking
                folder1 = folder
            -- the fold: no evidence, no proof, no withdrawal
            let key = requestKey record
                foldPlan =
                    FoldPlan
                        { foldRequest = requestOut
                        , foldBooked = record
                        , foldRegistered = []
                        , foldTerminated = []
                        , foldState = outputAt genesis 0
                        , foldValidity = interval
                        , foldPayer = folder1
                        }
                knownForFold = knownAfterBooking
            (foldTx, foldPurposes) <-
                built (foldRegistration pricedParameters registry references foldPlan Map.empty)
            let tree = Trie.build [(key, activeLeaf)]
                newRoot = Trie.rootOf tree
                foldInputs = foldTx ^. bodyTxL . inputsTxBodyL
                stateSpend =
                    ConwaySpending
                        (AsIx (fromIntegral (Set.findIndex (fst (outputAt genesis 0)) foldInputs)))
                Redeemers redeemers = foldTx ^. witsTxL . rdmrsTxWitsL
            paysItsWay knownForFold foldTx `shouldBe` True
            Set.size foldPurposes `shouldBe` 4
            Map.size redeemers `shouldBe` 4
            firstOutput foldTx `shouldBe` deliveredHolding registry record
            datumOf (outputsOf foldTx !! 1) `shouldBe` Just (stateDatumData newRoot)
            (foldTx ^. bodyTxL . treasuryDonationTxBodyL)
                `shouldBe` Coin (registrationCost (registryParameters terms))
            mintOf foldTx
                `shouldBe` Map.unionsWith
                    (<>)
                    [ token application (approval record) (-1)
                    , token state (activeTokenName (scriptsRegistry scripts) key) 1
                    ]
            Map.lookup stateSpend (Map.map fst redeemers)
                `shouldBe` Just
                    ( Data
                        ( stateSpendData
                            seed
                            [ Register
                                { changeRequest = reference (fst requestOut)
                                , changeKey = key
                                , changeHolding = 0
                                , changeDeposit = deposit
                                , changeProof = map asPlcData (prove tree key)
                                }
                            ]
                        )
                    )
            Map.null (let Withdrawals w = foldTx ^. bodyTxL . withdrawalsTxBodyL in w) `shouldBe` True
            -- a second request, booked and returned after its deadline
            secondProofTx <- built (mintHashProof pricedParameters registry owner5 export interval)
            (second, _) <-
                built
                    ( bookRegistrations
                        pricedParameters
                        registry
                        references
                        (afterTx owner5 secondProofTx)
                        [BookedRequest record export (outputAt secondProofTx 0)]
                        interval
                        0
                        Map.empty
                    )
            let secondBooking = Booking (outputAt second 0) record interval
                returnValidity =
                    interval
                        { lowerSlot = SlotNo 1_625
                        , upperSlot = SlotNo 1_650
                        , lowerPosixMs = upperPosixMs interval + 600_000
                        , upperPosixMs = upperPosixMs interval + 625_000
                        }
            (returnTx, _) <-
                built
                    ( returnRequests
                        pricedParameters
                        registry
                        references
                        folder1
                        secondBooking
                        returnValidity
                        refund
                        Map.empty
                    )
            paysItsWay (knownForFold <> producedBy secondProofTx <> producedBy second) returnTx
                `shouldBe` True
            firstOutput returnTx ^. addrTxOutL `shouldBe` refund
            firstOutput returnTx ^. coinTxOutL
                `shouldBe` Coin (requestLovelace (registryParameters terms) record - minimumTip (registryParameters terms))
            mintOf returnTx `shouldBe` token application (approval record) (-1)
            -- the same return, composed with the controller's burn of the attestation its booking left in change
            let holder = afterTx (afterTx owner5 secondProofTx) second
                heldAttestation = outputAt second 1
            (burningTx, burningPurposes) <-
                built (returnRequestsBurning pricedParameters registry references holder secondBooking returnValidity refund [heldAttestation] Map.empty)
            let attested = token attestation (attestationName registry 0 record) (-1)
                mintedBurning = burningTx ^. bodyTxL . mintTxBodyL
                Redeemers burningRedeemers = burningTx ^. witsTxL . rdmrsTxWitsL
                purposeOf policy = ConwayMinting (AsIx (mintingIndex (PolicyID policy) mintedBurning))
            mintOf burningTx `shouldBe` Map.unionsWith (<>) [token application (approval record) (-1), attested]
            Set.size burningPurposes `shouldBe` 3
            Map.size burningRedeemers `shouldBe` 3
            purposeOf application `shouldNotBe` purposeOf attestation
            Map.lookup (purposeOf application) (Map.map fst burningRedeemers) `shouldBe` Just (Data (PLC.List []))
            Map.lookup (purposeOf attestation) (Map.map fst burningRedeemers) `shouldBe` Just (Data bookingAttestationBurnData)
            Set.member (fst heldAttestation) (burningTx ^. bodyTxL . inputsTxBodyL) `shouldBe` True
            Set.member (fst (referenceAttestation references)) (burningTx ^. bodyTxL . referenceInputsTxBodyL) `shouldBe` True
            -- the return itself is as it was: the refund and the tip
            firstOutput burningTx `shouldBe` firstOutput returnTx
            -- control: with nothing to burn the return is the return
            (plainTx, _) <-
                built (returnRequestsBurning pricedParameters registry references folder1 secondBooking returnValidity refund [] Map.empty)
            plainTx `shouldBe` returnTx
            -- control: an output that holds no attestation is no burn
            case returnRequestsBurning pricedParameters registry references holder secondBooking returnValidity refund [outputAt secondProofTx 0] Map.empty of
                Left NothingToBurn -> pure ()
                other -> expectationFailure ("not a refusal to burn nothing: " <> either show (const "a built return") other)
        it "pay a fee that follows the units they declare" $ do
            registry <- deployment
            export <- load "kli-export-single.cesr"
            let owner = walletOf 0x10
                refund = payerAddress owner
                references =
                    RegistryReferences
                        { referenceApplication = (txIn 0x81, mkBasicTxOut refund (inject (ada 10)))
                        , referenceState = (txIn 0x82, mkBasicTxOut refund (inject (ada 10)))
                        , referenceConfiguration = (txIn 0x83, mkBasicTxOut refund (inject (ada 10)))
                        , referenceAttestation = (txIn 0x84, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceHashProof = (txIn 0x85, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        }
                record = registrationRecord registry refund deposit export interval
                bookWith budgets =
                    fst
                        <$> built
                            (bookOne pricedParameters registry references owner record export budgets)
            discovery <- bookWith Map.empty
            measured <- bookWith (Map.fromList [(ConwayMinting (AsIx position), ExUnits 1_000_000 500_000_000) | position <- [0 .. 2]])
            feeOf measured `shouldSatisfy` (< feeOf discovery)
            feeOf measured `shouldSatisfy` (>= minimumFee measured)
            feeOf discovery `shouldSatisfy` (>= minimumFee discovery)
            feeOf measured `shouldSatisfy` (`notElem` [3_000_000, 4_000_000])
    describe "the outputs that fund a transaction" $ do
        let nativeToken =
                MultiAsset
                    (Map.singleton (PolicyID (scriptHashOf (BS.replicate 28 0x42))) (Map.singleton (AssetName "wallet-token") 7))
            walletWith funds =
                Payer
                    { payerAddress = walletAddress 0x50
                    , payerRules = singularFundingRules
                    , payerFunds =
                        [ (txIn (0x50 + n), mkBasicTxOut (walletAddress 0x50) value)
                        | (n, value) <- zip [1 ..] funds
                        ]
                    }
            booking payer = do
                registry <- deployment
                export <- load "kli-export-single.cesr"
                let references =
                        RegistryReferences
                            { referenceApplication = (txIn 0x81, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                            , referenceState = (txIn 0x82, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                            , referenceConfiguration = (txIn 0x83, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                            , referenceAttestation = (txIn 0x84, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                            , referenceHashProof = (txIn 0x85, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                            }
                    record = registrationRecord registry (payerAddress payer) deposit export interval
                (tx, _) <-
                    built (bookOne pricedParameters registry references payer record export Map.empty)
                pure tx
        it "never take an output that carries a reference script or a datum as funding or as collateral" $ do
            registry <- deployment
            let script = mkCageScript (artifactProgram (scriptsApplication (deploymentScripts registry)))
                address = walletAddress 0x50
                carrying =
                    [ (txIn 0x61, mkBasicTxOut address (inject (ada 9_000)) & referenceScriptTxOutL .~ SJust script)
                    , (txIn 0x62, mkBasicTxOut address (inject (ada 8_000)) & datumTxOutL .~ mkInlineDatum (PLC.B "template"))
                    ]
                ordinary =
                    [ (txIn 0x63, mkBasicTxOut address (inject (ada 2_000)))
                    , (txIn 0x64, mkBasicTxOut address (inject (ada 1_900)))
                    , (txIn 0x65, mkBasicTxOut address (inject (ada 15)))
                    ]
                payer = Payer{payerAddress = address, payerFunds = carrying <> ordinary, payerRules = singularFundingRules}
            tx <- booking payer
            let spent = tx ^. bodyTxL . inputsTxBodyL
                collateral = tx ^. bodyTxL . collateralInputsTxBodyL
                carried = Set.fromList (map fst carrying)
            Set.intersection carried spent `shouldBe` Set.empty
            Set.intersection carried collateral `shouldBe` Set.empty
            proof <- proofKnown payer
            paysItsWay (payerFunds payer <> proof) tx `shouldBe` True
            -- a publication takes none of them either
            published <-
                built (publishReferenceScript Nothing pricedParameters payer (Coin 40_000_000) script)
            Set.intersection carried (published ^. bodyTxL . inputsTxBodyL) `shouldBe` Set.empty
        it "carry their native assets into the change" $ do
            let payer =
                    walletWith
                        [ MaryValue (ada 6_000) nativeToken
                        , inject (ada 400)
                        , inject (ada 300)
                        ]
            tx <- booking payer
            proof <- proofKnown payer
            paysItsWay (payerFunds payer <> proof) tx `shouldBe` True
            -- the change holds the token beside the attestation the booking returned to it
            any (holdsAll nativeToken . assetsOf) (outputsOf tx) `shouldBe` True
        it "are several when no one of them covers the payment" $ do
            let payer = walletWith (replicate 6 (inject (ada 300)))
            tx <- booking payer
            proof <- proofKnown payer
            paysItsWay (payerFunds payer <> proof) tx `shouldBe` True
            length (tx ^. bodyTxL . inputsTxBodyL) `shouldSatisfy` (>= 4)
        it "include a collateral without native assets" $ do
            let payer =
                    walletWith
                        [ MaryValue (ada 9_000) nativeToken
                        , MaryValue (ada 8_000) nativeToken
                        , inject (ada 2_000)
                        ]
            tx <- booking payer
            let collateral = toList (tx ^. bodyTxL . collateralInputsTxBodyL)
            proof <- proofKnown payer
            paysItsWay (payerFunds payer <> proof) tx `shouldBe` True
            collateral `shouldBe` [fst (payerFunds payer !! 2)]
        it "have the collateral among them, the largest of lovelace alone, however many are needed" $ do
            let payer =
                    walletWith
                        (map (inject . ada) [300, 290, 280, 270, 10])
            tx <- booking payer
            let largest = fst (fromJust (listToMaybe (payerFunds payer)))
            toList (tx ^. bodyTxL . collateralInputsTxBodyL) `shouldBe` [largest]
            -- the collateral is one of the outputs that pay, never one besides them
            (largest `Set.member` (tx ^. bodyTxL . inputsTxBodyL)) `shouldBe` True
            -- the four of the wallet and the proof the booking spends
            length (tx ^. bodyTxL . inputsTxBodyL) `shouldBe` 5
            proof <- proofKnown payer
            paysItsWay (payerFunds payer <> proof) tx `shouldBe` True
        it "are chosen once: the same outputs fund the transaction whatever units it declares" $ do
            registry <- deployment
            export <- load "kli-export-single.cesr"
            let payer = walletWith (map (inject . Coin) [20_000_000, 1_500_000, 1_500_000, 1_500_000])
                record = registrationRecord registry (payerAddress payer) deposit export interval
                references =
                    RegistryReferences
                        { referenceApplication = (txIn 0x81, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceState = (txIn 0x82, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceConfiguration = (txIn 0x83, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceAttestation = (txIn 0x84, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceHashProof = (txIn 0x85, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        }
                request =
                    Booking
                        ( txIn 0x71
                        , mkBasicTxOut
                            (walletAddress 0x60)
                            (inject (Coin (requestLovelace (registryParameters terms) record)))
                        )
                        record
                        interval
                measured =
                    Map.fromList
                        ( (ConwayMinting (AsIx 0), ExUnits 100_000 50_000_000)
                            : [ (ConwaySpending (AsIx index), ExUnits 100_000 50_000_000)
                              | index <- [0 .. 5]
                              ]
                        )
                returnWith budgets =
                    fst
                        <$> built
                            ( returnRequests
                                pricedParameters
                                registry
                                references
                                payer
                                request
                                interval
                                (walletAddress 0x60)
                                budgets
                            )
            discovery <- returnWith Map.empty
            final <- returnWith measured
            feeOf final `shouldSatisfy` (< feeOf discovery)
            (final ^. bodyTxL . inputsTxBodyL) `shouldBe` (discovery ^. bodyTxL . inputsTxBodyL)
            (final ^. bodyTxL . collateralInputsTxBodyL)
                `shouldBe` (discovery ^. bodyTxL . collateralInputsTxBodyL)
        it "are refused by name when the transaction would exceed the largest size" $ do
            registry <- deployment
            export <- load "kli-export-single.cesr"
            let payer = walletWith (map (inject . ada) [5_000, 4_000, 3_000])
                record = registrationRecord registry (payerAddress payer) deposit export interval
                references =
                    RegistryReferences
                        { referenceApplication = (txIn 0x81, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceState = (txIn 0x82, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceConfiguration = (txIn 0x83, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceAttestation = (txIn 0x84, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        , referenceHashProof = (txIn 0x85, mkBasicTxOut (walletAddress 0x50) (inject (ada 10)))
                        }
            case bookOne (pricedParameters & ppMaxTxSizeL .~ 100) registry references payer record export Map.empty of
                Left (TransactionTooLarge size limit) -> do
                    limit `shouldBe` 100
                    size `shouldSatisfy` (> 100)
                other -> fail ("expected a refusal by name, got " <> show (void other))
    describe "the genesis of a registry" $ do
        let genesisWith spentSeed = do
                registry <- deployment
                let wallet = walletOf 0x10
                    seedOutput =
                        ( spentSeed
                        , mkBasicTxOut
                            (walletAddress 0x10)
                            ( MaryValue
                                (ada 200)
                                (MultiAsset (Map.singleton (PolicyID (scriptHashOf (BS.replicate 28 0x43))) (Map.singleton (AssetName "seed-token") 1)))
                            )
                        )
                pure
                    ( wallet
                    , seedOutput
                    , createConfiguration
                        Nothing
                        pricedParameters
                        registry
                        []
                        wallet
                        seedOutput
                        (registryParameters terms)
                        Map.empty
                    )
        it "spends the seed its registry is derived from and keeps the assets the seed holds" $ do
            (wallet, seedOutput, genesis) <- genesisWith registrySeedIn
            (tx, _) <- built genesis
            paysItsWay (seedOutput : payerFunds wallet) tx `shouldBe` True
            Set.member registrySeedIn (tx ^. bodyTxL . inputsTxBodyL) `shouldBe` True
        it "is refused for a seed other than the one its registry is derived from" $ do
            (_, _, genesis) <- genesisWith (txIn 0x92)
            void genesis `shouldBe` Left SeedIsNotTheRegistrys
  where
    reference (TxIn (TxId safeHash) (TxIx ix)) =
        OutputReference (hashToBytes (extractHash safeHash)) (fromIntegral ix)

-- | The facts a registration writes for an export: live at sequence number and epoch 0, born at the interval's bound.
initialFacts :: InceptionExport -> Addr -> CheckpointDatumV2
initialFacts export refund =
    Live
        { lvAid = Text.encodeUtf8 (inceptionAid export)
        , lvSn = 0
        , lvEpoch = 0
        , lvPoisoned = False
        , lvFrozen = False
        , lvBornAt = upperPosixMs interval
        , lvRefundTo = serialiseAddr refund
        , lvToppedUp = False
        , lvKeys = (keyMaterialOf (inceptionDatum export)){kmCurKeys = qiCurKeys (inceptionQualified export)}
        }

{- | The booking of one request, the hash proof of whose inception an earlier premint
left with the payer.
-}
bookOne ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    Payer ->
    RegistrationData ->
    InceptionExport ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
bookOne parameters registry references payer record export =
    bookRegistrations
        parameters
        registry
        references
        payer
        [BookedRequest record export (proofOutputOf registry export (payerAddress payer) 0x7e)]
        interval
        0

-- | An output of the premint of an inception's hash proof, held at an address.
proofOutputOf :: RegistryDeployment -> InceptionExport -> Addr -> Word8 -> (TxIn, TxOut ConwayEra)
proofOutputOf registry export address n =
    ( txIn n
    , mkBasicTxOut
        address
        ( MaryValue
            (ada 5)
            (MultiAsset (token (artifactScriptHash (observerHashProof (scriptsObservers (deploymentScripts registry)))) (inceptionProofName export) 1))
        )
    )

-- | The proof output 'bookOne' spends, with the outputs a payer holds: what the booking may spend.
proofKnown :: Payer -> IO [(TxIn, TxOut ConwayEra)]
proofKnown payer = do
    registry <- deployment
    export <- load "kli-export-single.cesr"
    pure [proofOutputOf registry export (payerAddress payer) 0x7e]

-- | Whether some assets hold at least every asset of another.
holdsAll :: MultiAsset -> MultiAsset -> Bool
holdsAll (MultiAsset wanted) (MultiAsset held) = Map.isSubmapOfBy Map.isSubmapOf wanted held
