{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryBookingEvaluationSpec
Description : The booking and the burn the builders write, evaluated by the ledger

"Cardano.KERI.Deployment.RegistryBookingShapeSpec" reads the transactions the
builders write. These examples hand the same transactions to the ledger's own
script evaluator ('evalTxExUnits'), under the protocol parameters and cost
models recorded from the preprod node, over the registry's real applied
programs ('deriveRegistryScripts') published as reference scripts, the
configuration record the genesis builder writes and the hash proofs the premint
builder writes. Nothing here writes a script context: the ledger translates the
transaction.

Each accepted transaction stands beside refused neighbours that differ from it
by one thing, each applied to the transaction the builder wrote:

* an attestation of another name, a second attestation, a quantity of two;
* a hash proof not burned exactly;
* two requests that have changed places;
* the evidence of one key given for the other.
-}
module Cardano.KERI.Deployment.RegistryBookingEvaluationSpec (spec) where

import Cardano.KERI.AID.Application (Action (..), actionData)
import Cardano.KERI.AID.Checkpoint.Wire (bookingAttestationIssueData)
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.RefusalAt (Verdict (..), evaluationRefusedAt, renderEvaluationFailure, requireRefusedAt, verdictAt)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), registryInitialFloor, registryMinimumDeposit)
import Cardano.KERI.Deployment.RegistryBookingShapeSpec (
    Scenario (..),
    applicationBytes,
    claimsOf,
    double,
    foldOf,
    publish,
    redeemerOf,
    scenarioWith,
    single,
 )
import Cardano.KERI.Deployment.RegistryTransactions
import Cardano.KERI.Deployment.RegistryTransactionsSpec (
    afterTx,
    built,
    outputAt,
    pricedParameters,
    producedBy,
    terms,
 )
import Cardano.KERI.Deployment.Script (Observers (..), ScriptArtifact (..))
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (..), evalTxExUnits)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), binaryDataToData)
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (inputsTxBodyL, mintTxBodyL, outputsTxBodyL, referenceInputsTxBodyL, treasuryDonationTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, datumTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (natVersion)
import Cardano.Ledger.Binary (decodeFull')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Mary.Value (AssetName (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.State (UTxO (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Slotting.EpochInfo (fixedEpochInfo)
import Cardano.Slotting.Slot (EpochSize (..))
import Cardano.Slotting.Time (SystemStart (..), mkSlotLength)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (isRight)
import Data.Foldable (toList)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Word (Word32)
import Lens.Micro ((%~), (&), (.~), (^.))
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data qualified as PLC
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldNotBe, shouldSatisfy, shouldThrow)

-- | The preprod protocol parameters of the node the protocol major 11 runs on.
parameters :: IO (PParams ConwayEra)
parameters = do
    path <- getDataFileName "deployment-test/fixtures/koios/preprod-protocol-parameters.cbor"
    bytes <- BS.readFile path
    either (fail . show) pure (decodeFull' (natVersion @11) bytes)

{- | Slot 1,000 is the instant the specs' interval starts at, and a slot is a
second.
-}
systemStart :: SystemStart
systemStart = SystemStart (posixSecondsToUTCTime (fromIntegral ((1_700_000_000 :: Integer) - 1_000)))

-- | Every purpose of the transaction as the ledger answers it: the typed failure it gives, not its text.
evaluated ::
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    Answers
evaluated params utxo tx =
    Map.map
        void
        (evalTxExUnits params tx (UTxO utxo) (fixedEpochInfo (EpochSize 432_000) (mkSlotLength 1)) systemStart)

-- | What the ledger resolves the transaction's inputs and references against.
chainOf :: Scenario -> Map TxIn (TxOut ConwayEra)
chainOf s =
    Map.fromList $
        scKnown s
            <> [ referenceApplication references
               , referenceConfiguration references
               , referenceAttestation references
               , referenceHashProof references
               , referenceState references
               , scState s
               ]
  where
    references = scReferences s

-- | The ledger's answer for each purpose of a transaction: its typed script failure, or acceptance.
type Answers = Map (ConwayPlutusPurpose AsIx ConwayEra) (Either (TransactionScriptFailure ConwayEra) ())

accepts :: Answers -> Bool
accepts answers = not (Map.null answers) && all isRight (Map.elems answers)

-- | A purpose an edit is meant to be refused at, or must leave accepted.
data Purpose = Minting PolicyID | SpendingOf TxIn

purposeOf :: ConwayTx -> Purpose -> ConwayPlutusPurpose AsIx ConwayEra
purposeOf tx = \case
    Minting policy -> ConwayMinting (AsIx (mintingIndex policy (tx ^. bodyTxL . mintTxBodyL)))
    SpendingOf ref -> ConwaySpending (AsIx (fromIntegral (Set.findIndex ref (tx ^. bodyTxL . inputsTxBodyL))))

{- | Whether the script of the purpose ran and failed: the ledger's typed validation failure at that
purpose. A failure of the set-up, of the translation of the transaction, of balancing or of another
purpose is not one.
-}
refusedAt :: ConwayTx -> Answers -> Purpose -> Bool
refusedAt tx answers purpose = verdictAt answers (purposeOf tx purpose) == ExecutedFailure

-- | Whether the ledger failed the purpose without running its script: a failure of the set-up or of the translation.
setUpFailureAt :: ConwayTx -> Answers -> Purpose -> Bool
setUpFailureAt tx answers purpose = verdictAt answers (purposeOf tx purpose) == NotExecuted

acceptedAt :: ConwayTx -> Answers -> Purpose -> Bool
acceptedAt tx answers purpose = Map.lookup (purposeOf tx purpose) answers == Just (Right ())

{- | What a negative control found: the untouched transaction accepted; the edit applied; each purpose
it is meant to be refused at refused by an executed script; each purpose it must leave accepted accepted.
-}
data Judgement = Judgement
    { positiveAccepted :: Bool
    , editApplied :: Bool
    , refusedAsMeant :: Bool
    , keptAsMeant :: Bool
    }
    deriving stock (Eq, Show)

judge ::
    (Eq a) =>
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    -- | the edit
    (ConwayTx -> ConwayTx) ->
    -- | what the edit is meant to change, read from the transaction
    (ConwayTx -> a) ->
    -- | the purposes it is meant to be refused at
    [Purpose] ->
    -- | the purposes that stay accepted
    [Purpose] ->
    Judgement
judge params utxo original edit changed refusedPurposes keptPurposes =
    Judgement
        { positiveAccepted = accepts (evaluated params utxo original)
        , editApplied = changed tampered /= changed original
        , refusedAsMeant = all (refusedAt original answers) refusedPurposes
        , keptAsMeant = all (acceptedAt original answers) keptPurposes
        }
  where
    tampered = edit original
    answers = evaluated params utxo tampered

-- | A negative control that cannot pass for the wrong reason: every part of the judgement holds.
negative ::
    (Eq a) =>
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    (ConwayTx -> ConwayTx) ->
    (ConwayTx -> a) ->
    [Purpose] ->
    [Purpose] ->
    IO ()
negative params utxo original edit changed refusedPurposes keptPurposes =
    judge params utxo original edit changed refusedPurposes keptPurposes
        `shouldBe` Judgement{positiveAccepted = True, editApplied = True, refusedAsMeant = True, keptAsMeant = True}

-- | The mint of a transaction, edited.
withMint :: (Map PolicyID (Map AssetName Integer) -> Map PolicyID (Map AssetName Integer)) -> ConwayTx -> ConwayTx
withMint edit tx = tx & bodyTxL . mintTxBodyL %~ (\(MultiAsset assets) -> MultiAsset (edit assets))

-- | One policy's tokens in a mint, edited.
onPolicy :: PolicyID -> (Map AssetName Integer -> Map AssetName Integer) -> Map PolicyID (Map AssetName Integer) -> Map PolicyID (Map AssetName Integer)
onPolicy policy edit = Map.adjust edit policy

-- | The refund address of a request datum, made an address no checkpoint can record: a pointer stake part.
pointerRefund :: PLC.Data -> PLC.Data
pointerRefund = \case
    PLC.Constr 1 [PLC.Constr 0 fields]
        | (before, PLC.Constr 0 [payment, _] : after) <- splitAt 3 fields ->
            PLC.Constr 1 [PLC.Constr 0 (before <> [PLC.Constr 0 [payment, PLC.Constr 0 [PLC.Constr 1 [PLC.I 1, PLC.I 2, PLC.I 3]]]] <> after)]
    other -> other

mintOf :: ConwayTx -> MultiAsset
mintOf tx = tx ^. bodyTxL . mintTxBodyL

spec :: Spec
spec = describe "#559 the booking transaction, evaluated by the ledger" $ do
    describe "one request" $ do
        it "is accepted by the application's mint, the attestation policy and the hash proof policy" $ do
            params <- parameters
            s <- scenarioWith publish single
            let answers = evaluated params (chainOf s) (scBooking s)
            Map.size answers `shouldBe` 3
            answers `shouldSatisfy` accepts
        it "is refused by the attestation policy and the application when the attestation it mints is named for another claim" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
                policy = attestationPolicyId registry
                flipName (AssetName name) = AssetName (SBS.pack (map (+ 1) (SBS.unpack name)))
            negative
                params
                (chainOf s)
                (scBooking s)
                (withMint (onPolicy policy (Map.mapKeys flipName)))
                mintOf
                [Minting policy, Minting (applicationPolicyId registry)]
                [Minting (hashProofPolicyOf registry)]
        it "is refused by the attestation policy and the application when it mints two units of its attestation" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
                policy = attestationPolicyId registry
            negative
                params
                (chainOf s)
                (scBooking s)
                (withMint (onPolicy policy (Map.map (* 2))))
                mintOf
                [Minting policy, Minting (applicationPolicyId registry)]
                [Minting (hashProofPolicyOf registry)]
        it "is refused by the attestation policy alone when it mints an attestation nobody verified besides its own" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
                policy = attestationPolicyId registry
            negative
                params
                (chainOf s)
                (scBooking s)
                (withMint (onPolicy policy (Map.insert (AssetName "an attestation nobody verified") 1)))
                mintOf
                [Minting policy]
                [Minting (applicationPolicyId registry), Minting (hashProofPolicyOf registry)]
        it "is refused by the attestation policy when its hash proof is not burned exactly" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
            negative
                params
                (chainOf s)
                (scBooking s)
                (withMint (onPolicy (hashProofPolicyOf registry) (Map.map (* 2))))
                mintOf
                [Minting (attestationPolicyId registry)]
                [Minting (applicationPolicyId registry)]

    describe "the booking guards a deposit and a refund address must meet" $ do
        it "is accepted with a deposit that leaves the pool one premium, and refused at the application with one lovelace less" $ do
            params <- parameters
            let initialFloor = registryInitialFloor terms
                book amount = scenarioWith publish [("kli-export-single.cesr", amount)]
            atFloor <- book initialFloor
            short <- book (initialFloor - 1)
            evaluated params (chainOf atFloor) (scBooking atFloor) `shouldSatisfy` accepts
            let answers = evaluated params (chainOf short) (scBooking short)
                registry = scRegistry short
            -- the deposit is what differs
            map (\(_, _, committed) -> committed) (claimsOf registry (scBooking short) (scRecords short))
                `shouldBe` [initialFloor - 1]
            refusedAt (scBooking short) answers (Minting (applicationPolicyId registry)) `shouldBe` True
            acceptedAt (scBooking short) answers (Minting (attestationPolicyId registry)) `shouldBe` True
        it "is refused at the application when its deposit is one lovelace below the registry's minimum" $ do
            params <- parameters
            atFloor <- scenarioWith publish [("kli-export-single.cesr", registryInitialFloor terms)]
            below <- scenarioWith publish [("kli-export-single.cesr", registryMinimumDeposit terms - 1)]
            -- the positive neighbour: the same booking at the floor is accepted
            evaluated params (chainOf atFloor) (scBooking atFloor) `shouldSatisfy` accepts
            let answers = evaluated params (chainOf below) (scBooking below)
            refusedAt (scBooking below) answers (Minting (applicationPolicyId (scRegistry below))) `shouldBe` True
        it "is refused at the application alone when the refund address of the request is one no checkpoint can record" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
            negative
                params
                (chainOf s)
                (scBooking s)
                (\tx -> tx & bodyTxL . outputsTxBodyL %~ onFirst (datumTxOutL %~ retargetDatum pointerRefund))
                (\tx -> map datumOfOutput (toList (tx ^. bodyTxL . outputsTxBodyL)))
                [Minting (applicationPolicyId registry)]
                [Minting (attestationPolicyId registry), Minting (hashProofPolicyOf registry)]

    describe "two requests of other identities and deposits" $ do
        it "is accepted, each attestation named for its own output position" $ do
            params <- parameters
            s <- scenarioWith publish double
            let answers = evaluated params (chainOf s) (scBooking s)
            Map.size answers `shouldBe` 3
            answers `shouldSatisfy` accepts
            map (\(p, _, _) -> p) (claimsOf (scRegistry s) (scBooking s) (scRecords s)) `shouldBe` [0, 1]
        it "is refused by the attestation policy and the application when the two requests have changed places" $ do
            params <- parameters
            s <- scenarioWith publish double
            let registry = scRegistry s
            negative
                params
                (chainOf s)
                (scBooking s)
                (\tx -> tx & bodyTxL . outputsTxBodyL %~ swapFirstTwo)
                (\tx -> map datumOfOutput (toList (tx ^. bodyTxL . outputsTxBodyL)))
                [Minting (attestationPolicyId registry), Minting (applicationPolicyId registry)]
                [Minting (hashProofPolicyOf registry)]
        it "is refused by the attestation policy alone when the evidence of one key is given for the other" $ do
            params <- parameters
            s <- scenarioWith publish double
            let registry = scRegistry s
                policy = attestationPolicyId registry
                position = mintingIndex policy (mintOf (scBooking s))
                swapped =
                    case scExports s of
                        [first', second'] ->
                            bookingAttestationIssueData
                                (applicationBytes registry)
                                [(0, inceptionEvidence second'), (1, inceptionEvidence first')]
                        _ -> error "two exports were built"
            negative
                params
                (chainOf s)
                (scBooking s)
                (\tx -> tx & witsTxL . rdmrsTxWitsL %~ replaceRedeemer position swapped)
                (`redeemerOf` policy)
                [Minting policy]
                [Minting (applicationPolicyId registry)]
        it "is refused by the application and the attestation policy when one of its two attestations is missing" $ do
            params <- parameters
            s <- scenarioWith publish double
            let registry = scRegistry s
                policy = attestationPolicyId registry
            negative
                params
                (chainOf s)
                (scBooking s)
                (withMint (onPolicy policy (Map.take 1)))
                mintOf
                [Minting policy, Minting (applicationPolicyId registry)]
                [Minting (hashProofPolicyOf registry)]

    describe "the fold of a booked request, with no evidence, no proof and no withdrawal" $ do
        -- one wallet books and folds here: the evaluator fixture; the distinct folder and the settled spends belong to the node journey
        it "is accepted by the application's spend and mint and by the state script's spend and mint" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            let answers = evaluated params (foldChain s) tx
            Map.size answers `shouldBe` 4
            answers `shouldSatisfy` accepts
        it "is refused at the application when the holding it pays holds one lovelace more" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            foldNegative params s tx (bodyTxL . outputsTxBodyL %~ onFirst (coinTxOutL %~ (<> Coin 1))) outputsOfTx
        it "is refused at the application when the holding carries another datum" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            foldNegative params s tx (bodyTxL . outputsTxBodyL %~ onFirst (datumTxOutL .~ mkInlineDatum (PLC.B "another datum"))) outputsOfTx
        it "is refused at the application when it donates nothing to the treasury" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            foldNegative params s tx (bodyTxL . treasuryDonationTxBodyL .~ Coin 0) (\t -> t ^. bodyTxL . treasuryDonationTxBodyL)
        it "is refused at the application when the configuration record is not read" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            let record = fst (referenceConfiguration (scReferences s))
            foldNegative params s tx (bodyTxL . referenceInputsTxBodyL %~ Set.delete record) (\t -> t ^. bodyTxL . referenceInputsTxBodyL)

    describe "the controller's burn of the attestations of two bookings" $ do
        it "is accepted by the attestation policy with no evidence at all" $ do
            params <- parameters
            (s, burn, utxo) <- burning
            Map.size (evaluated params utxo burn) `shouldBe` 1
            evaluated params utxo burn `shouldSatisfy` accepts
            Set.size (burn ^. bodyTxL . inputsTxBodyL) `shouldSatisfy` (>= 1)
            scRegistry s `seq` pure ()
        it "is refused by the attestation policy when it also mints an attestation" $ do
            params <- parameters
            (s, burn, utxo) <- burning
            let policy = attestationPolicyId (scRegistry s)
            negative
                params
                utxo
                burn
                (withMint (onPolicy policy (Map.insert (AssetName "a name nobody verified") 1)))
                mintOf
                [Minting policy]
                []
    describe "a refusal counts only when the intended script ran and failed" $ do
        -- one representative control per kind of refusal in this slice: the mint of the booking, the guards of
        -- the deposit and the refund, the application's spend of a fold, the burn. A transaction that fails in
        -- its set-up, or at another purpose, must not satisfy the predicate the negatives above rely on.
        it "a mint refusal: the missing attestation script is a set-up failure, and the proof policy is not where the edit is refused" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
                policy = attestationPolicyId registry
                flipName (AssetName name) = AssetName (SBS.pack (map (+ 1) (SBS.unpack name)))
                edit = withMint (onPolicy policy (Map.mapKeys flipName))
                tampered = edit (scBooking s)
                real = evaluated params (chainOf s) tampered
                setUp = evaluated params (Map.delete (fst (referenceAttestation (scReferences s))) (chainOf s)) tampered
            -- the real refusal is an executed script's
            refusedAt tampered real (Minting policy) `shouldBe` True
            -- without the script the ledger cannot run it: a failure, not the policy's refusal
            setUpFailureAt tampered setUp (Minting policy) `shouldBe` True
            refusedAt tampered setUp (Minting policy) `shouldBe` False
            -- another purpose is not where the edit is refused
            refusedAsMeant (judge params (chainOf s) (scBooking s) edit mintOf [Minting (hashProofPolicyOf registry)] [])
                `shouldBe` False
        it "a guard refusal: the missing application script is a set-up failure, and the attestation policy is not where the pool is refused" $ do
            params <- parameters
            short <- scenarioWith publish [("kli-export-single.cesr", registryInitialFloor terms - 1)]
            let registry = scRegistry short
                tx = scBooking short
                real = evaluated params (chainOf short) tx
                setUp = evaluated params (Map.delete (fst (referenceApplication (scReferences short))) (chainOf short)) tx
            refusedAt tx real (Minting (applicationPolicyId registry)) `shouldBe` True
            setUpFailureAt tx setUp (Minting (applicationPolicyId registry)) `shouldBe` True
            refusedAt tx setUp (Minting (applicationPolicyId registry)) `shouldBe` False
            refusedAt tx real (Minting (attestationPolicyId registry)) `shouldBe` False
        it "a spend refusal: the missing application script is a set-up failure, and the state script is not where a fold is refused" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            let registry = scRegistry s
                request = fst (outputAt (scBooking s) 0)
                tampered = tx & bodyTxL . treasuryDonationTxBodyL .~ Coin 0
                real = evaluated params (foldChain s) tampered
                setUp = evaluated params (Map.delete (fst (referenceApplication (scReferences s))) (foldChain s)) tampered
            refusedAt tampered real (SpendingOf request) `shouldBe` True
            setUpFailureAt tampered setUp (SpendingOf request) `shouldBe` True
            refusedAt tampered setUp (SpendingOf request) `shouldBe` False
            refusedAt tampered real (Minting (statePolicyId registry)) `shouldBe` False
        it "a fold refusal at the application's mint alone does not satisfy a refusal at the request spend" $ do
            params <- parameters
            s <- scenarioWith publish single
            tx <- foldOf s
            let registry = scRegistry s
                request = fst (outputAt (scBooking s) 0)
                application = applicationPolicyId registry
                -- the application's mint is told to book: it judges that, and the spend reads no other script's redeemer
                position = mintingIndex application (mintOf tx)
                tampered = tx & witsTxL . rdmrsTxWitsL %~ replaceRedeemer position (PLC.List [actionData (BookRegistration 0)])
                answers = evaluated params (foldChain s) tampered
            evaluated params (foldChain s) tx `shouldSatisfy` accepts
            redeemerOf tampered application `shouldNotBe` redeemerOf tx application
            refusedAt tx answers (Minting application) `shouldBe` True
            refusedAt tx answers (SpendingOf request) `shouldBe` False
            -- what the earlier assertion (either purpose) would have accepted
            (refusedAt tx answers (SpendingOf request) || refusedAt tx answers (Minting application)) `shouldBe` True

        it "a burn refusal: the missing attestation script is a set-up failure, not the policy's refusal" $ do
            params <- parameters
            (s, burn, utxo) <- burning
            let policy = attestationPolicyId (scRegistry s)
                tampered = withMint (onPolicy policy (Map.insert (AssetName "a name nobody verified") 1)) burn
                real = evaluated params utxo tampered
                setUp = evaluated params (Map.delete (fst (referenceAttestation (scReferences s))) utxo) tampered
            refusedAt tampered real (Minting policy) `shouldBe` True
            setUpFailureAt tampered setUp (Minting policy) `shouldBe` True
            refusedAt tampered setUp (Minting policy) `shouldBe` False
    describe "the refusal assertions of the devnet journeys count only an executed script's failure at the intended purpose" $ do
        it "the verdict is an executed failure for the script that ran, and not for a set-up failure, an acceptance or an uncovered purpose" $ do
            params <- parameters
            short <- scenarioWith publish [("kli-export-single.cesr", registryInitialFloor terms - 1)]
            let registry = scRegistry short
                tx = scBooking short
                real = evaluated params (chainOf short) tx
                setUp = evaluated params (Map.delete (fst (referenceApplication (scReferences short))) (chainOf short)) tx
                intended = purposeOf tx (Minting (applicationPolicyId registry))
                other = purposeOf tx (Minting (attestationPolicyId registry))
                uncovered = ConwayMinting (AsIx 9)
            verdictAt real intended `shouldBe` ExecutedFailure
            -- without the application script the ledger cannot run it: a set-up failure at the very purpose
            verdictAt setUp intended `shouldBe` NotExecuted
            -- the attestation policy accepts this booking: an executed failure elsewhere is not an acceptance here
            verdictAt real other `shouldBe` Accepted
            verdictAt real uncovered `shouldBe` NotCovered
            requireRefusedAt "the control" real intended
            requireRefusedAt "the control" setUp intended `shouldThrow` anyIOException
            requireRefusedAt "the control" real other `shouldThrow` anyIOException
            requireRefusedAt "the control" real uncovered `shouldThrow` anyIOException
        it "an executed failure at another purpose does not satisfy the assertion for the intended one" $ do
            params <- parameters
            s <- scenarioWith publish single
            let registry = scRegistry s
                policy = attestationPolicyId registry
                flipName (AssetName name) = AssetName (SBS.pack (map (+ 1) (SBS.unpack name)))
                tampered = withMint (onPolicy policy (Map.mapKeys flipName)) (scBooking s)
                real = evaluated params (chainOf s) tampered
                attestation = purposeOf tampered (Minting policy)
                proof = purposeOf tampered (Minting (hashProofPolicyOf registry))
            verdictAt real attestation `shouldBe` ExecutedFailure
            -- the proof policy is satisfied by this edit: refused at the attestation, accepted at the proof
            verdictAt real proof `shouldBe` Accepted
            requireRefusedAt "the control" real attestation
            requireRefusedAt "the control" real proof `shouldThrow` anyIOException
        it "the installed command's report counts only the executed failure at the booking application's own purpose" $ do
            params <- parameters
            short <- scenarioWith publish [("kli-export-single.cesr", registryInitialFloor terms - 1)]
            s <- scenarioWith publish single
            let registry = scRegistry short
                tx = scBooking short
                application = purposeOf tx (Minting (applicationPolicyId registry))
                real = evaluated params (chainOf short) tx
                setUp = evaluated params (Map.delete (fst (referenceApplication (scReferences short))) (chainOf short)) tx
                policy = attestationPolicyId (scRegistry s)
                flipName (AssetName name) = AssetName (SBS.pack (map (+ 1) (SBS.unpack name)))
                tampered = withMint (onPolicy policy (Map.mapKeys flipName)) (scBooking s)
                elsewhere = evaluated params (chainOf s) tampered
                attestation = purposeOf tampered (Minting policy)
                reportOf answers purpose = either (renderEvaluationFailure purpose) (const "accepted") (answers Map.! purpose)
            evaluationRefusedAt application (reportOf real application) `shouldBe` True
            -- the same purpose, the script not run
            evaluationRefusedAt application (reportOf setUp application) `shouldBe` False
            -- an executed failure at a different purpose
            evaluationRefusedAt attestation (reportOf elsewhere attestation) `shouldBe` True
            evaluationRefusedAt application (reportOf elsewhere attestation) `shouldBe` False
            -- the index is the whole number, and the kind of purpose is the kind asked for
            evaluationRefusedAt (ConwayMinting (AsIx 2)) "minting purpose 12: ValidationFailure" `shouldBe` False
            evaluationRefusedAt (ConwayMinting (AsIx 2)) "spending purpose 2: ValidationFailure" `shouldBe` False
            evaluationRefusedAt (ConwayMinting (AsIx 2)) "minting purpose 2: ValidationFailure (...)" `shouldBe` True
  where
    hashProofPolicyOf registry =
        PolicyID (artifactScriptHash (observerHashProof (scriptsObservers (deploymentScripts registry))))
    outputsOfTx t = toList (t ^. bodyTxL . outputsTxBodyL)
    datumOfOutput out = out ^. datumTxOutL

    -- the application's spend of the request: where the holding, the donation and the configuration record are judged
    foldNegative params s tx edit changed = do
        let request = fst (outputAt (scBooking s) 0)
            registry = scRegistry s
            tampered = tx & edit
            answers = evaluated params (foldChain s) tampered
        evaluated params (foldChain s) tx `shouldSatisfy` accepts
        changed tampered `shouldNotBe` changed tx
        -- the request spend is the purpose that reads the holding, the donation and the configuration record
        refusedAt tx answers (SpendingOf request) `shouldBe` True
        acceptedAt tx answers (Minting (statePolicyIdOf registry)) `shouldBe` True

    statePolicyIdOf = statePolicyId

    burning = do
        s <- scenarioWith publish double
        let booking = scBooking s
            changeOut = outputAt booking (length (scRecords s))
            holder = afterTx (scPayer s) booking
        (burn, _) <- built (burnAttestations pricedParameters (scRegistry s) (scReferences s) holder [changeOut] Map.empty)
        pure (s, burn, Map.fromList (toList (producedBy booking)) <> chainOf s)

-- | The datum of an output with its nested datum rewritten.
retargetDatum :: (PLC.Data -> PLC.Data) -> Datum ConwayEra -> Datum ConwayEra
retargetDatum edit = \case
    Datum binary -> let Data plc = binaryDataToData binary in mkInlineDatum (edit plc)
    other -> other

swapFirstTwo :: StrictSeq.StrictSeq a -> StrictSeq.StrictSeq a
swapFirstTwo outputs = case toList outputs of
    a : b : rest -> StrictSeq.fromList (b : a : rest)
    other -> StrictSeq.fromList other

replaceRedeemer ::
    Word32 ->
    PLC.Data ->
    Redeemers ConwayEra ->
    Redeemers ConwayEra
replaceRedeemer position new (Redeemers redeemers) =
    Redeemers (Map.adjust (\(_, units) -> (Data new, units)) (ConwayMinting (AsIx position)) redeemers)

-- | What the ledger resolves a fold against: the registry's references and state and the booking's outputs.
foldChain :: Scenario -> Map TxIn (TxOut ConwayEra)
foldChain s = Map.fromList (toList (producedBy (scBooking s))) <> chainOf s

-- | An edit of the first of a sequence.
onFirst :: (a -> a) -> StrictSeq.StrictSeq a -> StrictSeq.StrictSeq a
onFirst edit outputs = case toList outputs of
    first : rest -> StrictSeq.fromList (edit first : rest)
    [] -> outputs
