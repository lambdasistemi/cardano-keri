{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryAdvanceEvaluationSpec
Description : The advance, the depositing rotation and the freeze the builders write, evaluated by the ledger

The checkpoint's moves of the attested generation ('advanceAttested', 'freezeAttested') are built from the
committed advance vector (its datums, its evidence, and the signed fact the builder derives from them), over the
registry's real applied programs ('deriveAttestedRegistryScripts') published as reference scripts: the checkpoint
validator, the fact policy and the change policy. The transaction is handed to the ledger's own script evaluator
('Cardano.KERI.Deployment.LedgerEvaluation.evaluated'): nothing here writes a script context.

Each accepted transaction stands beside refused neighbours that differ from it by one thing and are refused at the
purpose whose script judges it, by the ledger's typed failure.
-}
module Cardano.KERI.Deployment.RegistryAdvanceEvaluationSpec (spec) where

import Cardano.KERI.AID.Application (OutputReference (..), activeTokenName)
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.AdvanceAttestation (
    advanceAttestationName,
    advanceEnvelopeData,
    changeIssueData,
    factIssueData,
    signedFactForAdvance,
    signedFactForFreeze,
    signedFactName,
 )
import Cardano.KERI.AID.Checkpoint.Deposit (
    BondOption (..),
    DepositIntent (..),
    depositDomain,
    depositIntentPreimage,
 )
import Cardano.KERI.AID.Checkpoint.Wire (advanceAttestedSpendRedeemerData, freezeAttestedSpendRedeemerData)
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum, rawInlineData)
import Cardano.KERI.Deployment.AdvanceAttestationScripts (AdvanceAttestation (..))
import Cardano.KERI.Deployment.AdvanceVectors (
    JanuaryExpectation (..),
    NestedSeal (..),
    Seeds (..),
    Vector (..),
    loadJanuaryExpectation,
    loadJanuaryVector,
    loadNestedSeal,
    loadScalarPair,
    loadSeeds,
    loadTrailingPair,
    loadVectorNamed,
    signedBy,
 )
import Cardano.KERI.Deployment.LedgerEvaluation (
    Purpose (..),
    accepts,
    evaluated,
    measuredBudgets,
    mintOf,
    negative,
    parameters,
    withMint,
 )
import Cardano.KERI.Deployment.LedgerEvaluation qualified as Evaluation
import Cardano.KERI.Deployment.Registry (
    AttestedRegistry (..),
    RegistryScripts (..),
    RegistryTerms (..),
    deriveAttestedRegistryScripts,
 )
import Cardano.KERI.Deployment.RegistryTransactions
import Cardano.KERI.Deployment.RegistryTransactionsSpec (built, terms, txIn, walletAddress, walletOf)
import Cardano.KERI.Deployment.Script (
    CheckpointTerms (..),
    ScriptArtifact (..),
    blueprintIsAttested,
    loadBlueprint,
    mkCageScript,
    scriptHashBytes,
 )
import Cardano.Ledger.Address (Addr, Withdrawals (..))
import Cardano.Ledger.Alonzo.PParams (ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, inputsTxBodyL, outputsTxBodyL, referenceInputsTxBodyL, withdrawalsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, coinTxOutL, datumTxOutL, getMinCoinTxOut, mkBasicTxOut, referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, ppMaxTxSizeL, sizeTxF)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (forM_)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Maybe.Strict (StrictMaybe (SJust))
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Lens.Micro ((%~), (&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import System.Environment (getEnv)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

-- | What the examples build against: the attested registry, its published scripts and the vector.
data World = World
    { worldDeployment :: !RegistryDeployment
    , worldPolicies :: !AdvanceAttestation
    , worldReferences :: !AttestedReferences
    , worldVector :: !Vector
    , worldSeeds :: !Seeds
    , worldParameters :: !(PParams ConwayEra)
    , worldPayer :: !Payer
    }

seedReference :: OutputReference
seedReference = OutputReference (BS.replicate 32 0x77) 3

world :: IO World
world = worldFor terms

-- | The world of a registry derived from other terms (the same programs but for what the terms apply).
worldFor :: RegistryTerms -> IO World
worldFor registryTerms = loadVectorNamed "two_key" >>= \vector -> worldWith vector registryTerms

-- | The world of a registry derived from other terms, for a vector.
worldWith :: Vector -> RegistryTerms -> IO World
worldWith vector registryTerms = do
    blueprint <- getEnv "KERI_ATTESTED_BLUEPRINT" >>= loadBlueprint >>= either fail pure
    blueprintIsAttested blueprint `shouldBe` True
    registry <-
        either fail pure (deriveAttestedRegistryScripts stateTemplate registryTerms seedReference blueprint)
    let scripts = attestedScripts registry
        policies = attestedPolicies registry
        owner = walletOf 0x10
        carrying n program =
            ( txIn n
            , mkBasicTxOut (payerAddress owner) (MaryValue (Coin 20_000_000) mempty)
                & referenceScriptTxOutL .~ SJust (mkCageScript program)
            )
    seeds <- loadSeeds
    params <- parameters
    pure
        World
            { worldDeployment = RegistryDeployment Mainnet registryTerms scripts (Just policies)
            , worldPolicies = policies
            , worldReferences =
                AttestedReferences
                    (carrying 0x91 (artifactProgram (scriptsCheckpoint scripts)))
                    (carrying 0x92 (artifactProgram (attestationFact policies)))
                    (carrying 0x93 (artifactProgram (attestationChange policies)))
            , worldVector = vector
            , worldSeeds = seeds
            , worldParameters = params
            , worldPayer = owner
            }

-- ---------------------------------------------------------------------------
-- The checkpoint, its moves and what the ledger resolves them against
-- ---------------------------------------------------------------------------

checkpointTerms :: CheckpointTerms
checkpointTerms = registryCheckpointTerms terms

-- | The lovelace a checkpoint holds beside its pool.
floorOf :: Bool -> Integer
floorOf frozen =
    registryMinimumAda terms
        + termsDeposit checkpointTerms
        + (if frozen then 0 else termsFreezeBond checkpointTerms)

-- | The checkpoint output of the vector's identifier holding a datum and a pool above the floor of its state.
checkpointOutput :: World -> TxIn -> Bool -> Integer -> PLC.Data -> (TxIn, TxOut ConwayEra)
checkpointOutput w ref frozen pool datum =
    ( ref
    , mkBasicTxOut
        (checkpointAddress deployment)
        (MaryValue (Coin (floorOf frozen + pool)) (tokenValue (statePolicyId deployment) name 1))
        & datumTxOutL .~ mkInlineDatum datum
    )
  where
    deployment = worldDeployment w
    name = activeTokenName (scriptsRegistry (deploymentScripts deployment)) (vectorAid (worldVector w))

-- | The next commitment a live checkpoint datum carries: the committed keys and the integer threshold.
nextCommitment :: PLC.Data -> Maybe ([BS.ByteString], Integer)
nextCommitment = \case
    PLC.Constr 1 [PLC.Constr 0 fields]
        | PLC.Constr 0 [_, _, PLC.List keys, PLC.Constr 0 [PLC.I threshold], _, _] <- last fields ->
            (,) <$> traverse bytesOf keys <*> pure threshold
    _ -> Nothing
  where
    bytesOf = \case
        PLC.B b -> Just b
        _ -> Nothing

-- | A constructor with one field rewritten.
atField :: Int -> (PLC.Data -> PLC.Data) -> PLC.Data -> PLC.Data
atField i f = \case
    PLC.Constr c fields -> PLC.Constr c [if j == i then f x else x | (j, x) <- zip [0 ..] fields]
    other -> other

-- | A constructor with a field replaced by another field of the same constructor.
atFieldFrom :: Int -> Int -> PLC.Data -> PLC.Data
atFieldFrom from to = \case
    PLC.Constr c fields | Just source <- lookup from (zip [0 ..] fields) -> atField to (const source) (PLC.Constr c fields)
    other -> other

-- | The datum with its next commitment replaced: the keys and the integer threshold.
withNextCommitment :: (([BS.ByteString], Integer) -> ([BS.ByteString], Integer)) -> PLC.Data -> PLC.Data
withNextCommitment edit = \case
    PLC.Constr 1 [PLC.Constr 0 fields] ->
        PLC.Constr 1 [PLC.Constr 0 (init fields <> [rewrite (last fields)])]
    other -> other
  where
    rewrite = \case
        PLC.Constr 0 [cur, curT, PLC.List keys, PLC.Constr 0 [PLC.I threshold], wit, toad]
            | Just bytes <- traverse (\case PLC.B b -> Just b; _ -> Nothing) keys ->
                let (keys', threshold') = edit (bytes, threshold)
                 in PLC.Constr 0 [cur, curT, PLC.List (map PLC.B keys'), PLC.Constr 0 [PLC.I threshold'], wit, toad]
        other -> other

withNextKeys :: ([BS.ByteString] -> [BS.ByteString]) -> PLC.Data -> PLC.Data
withNextKeys edit = withNextCommitment (first edit)

-- | A digest that opens nothing: the first byte changed.
flipFirstByte :: BS.ByteString -> BS.ByteString
flipFirstByte bytes = case BS.uncons bytes of
    Just (b, rest) -> BS.cons (b + 1) rest
    Nothing -> bytes

-- | The recipient of what leaves the checkpoint: not the payer.
payeeAddress :: Addr
payeeAddress = walletAddress 0x20

-- | A rotation: the unfrozen checkpoint with a pool that covers the premium, rotated to the vector's successor.
rotationMove :: World -> CheckpointMove
rotationMove w =
    CheckpointMove
        { moveSpent = checkpointOutput w (txIn 0xa1) False 3_000_000 (vectorOld v)
        , moveSuccessor = vectorNew v
        , movePayload = vectorEvidence v
        , movePayee = payeeAddress
        }
  where
    v = worldVector w

-- | The depositing rotation: the frozen checkpoint, rotated to the unfrozen successor, the bond deposited.
depositMove :: World -> CheckpointMove
depositMove w = (rotationMove w){moveSpent = checkpointOutput w (txIn 0xa2) True 3_000_000 (vectorFrozen (worldVector w))}

-- | A freeze: the unfrozen checkpoint whose pool is under the premium, and its frozen copy.
freezeMove :: World -> CheckpointMove
freezeMove w =
    CheckpointMove
        { moveSpent = checkpointOutput w (txIn 0xa3) False 1_000_000 (vectorOld v)
        , moveSuccessor = vectorFrozen v
        , movePayload = vectorFreezePayload v
        , movePayee = payeeAddress
        }
  where
    v = worldVector w

-- | What the ledger resolves a move against: the published scripts, the checkpoint and the payer's outputs.
chainOf :: World -> CheckpointMove -> Map.Map TxIn (TxOut ConwayEra)
chainOf w move =
    Map.fromList $
        [ attestedCheckpointScript references
        , attestedFactScript references
        , attestedChangeScript references
        , moveSpent move
        ]
            <> payerFunds (worldPayer w)
  where
    references = worldReferences w

buildAdvance :: World -> CheckpointMove -> BondOption -> IO ConwayTx
buildAdvance w move bond =
    fst
        <$> built
            ( advanceAttested
                (worldParameters w)
                (worldDeployment w)
                (worldReferences w)
                (worldPayer w)
                move
                bond
                Map.empty
            )

buildFreeze :: World -> CheckpointMove -> IO ConwayTx
buildFreeze w move =
    fst
        <$> built
            ( freezeAttested
                (worldParameters w)
                (worldDeployment w)
                (worldReferences w)
                (worldPayer w)
                move
                Map.empty
            )

-- | What the ledger says of each purpose of a transaction built for a move.
answers :: World -> CheckpointMove -> ConwayTx -> Evaluation.Answers
answers w move = evaluated (worldParameters w) (chainOf w move)

changePolicy, factPolicy :: World -> PolicyID
changePolicy = PolicyID . artifactScriptHash . attestationChange . worldPolicies
factPolicy = PolicyID . artifactScriptHash . attestationFact . worldPolicies

-- | The deposit intent the successor's keys sign, for a move and an amount.
intentFor :: World -> CheckpointMove -> Integer -> DepositIntent
intentFor w move amount =
    DepositIntent
        { diDomain = depositDomain
        , diNetworkId = termsNetwork checkpointTerms
        , diCheckpointPolicy = scriptHashBytes (artifactScriptHash (scriptsCheckpoint (deploymentScripts (worldDeployment w))))
        , diSpentTxId = txid
        , diSpentIndex = index
        , diAid = aid
        , diNewSn = sn
        , diNewEpoch = epoch
        , diDeposit = amount
        }
  where
    OutputReference txid index = outputReferenceOf (fst (moveSpent move))
    (aid, sn, epoch) = case moveSuccessor move of
        PLC.Constr 1 [PLC.Constr 0 (PLC.B a : PLC.I s : PLC.I e : _)] -> (a, s, e)
        _ -> error "the successor is not a live datum"

-- | The signatures of an intent by the rotation's keys, at their positions.
signedBy' :: World -> DepositIntent -> [(Int, BS.ByteString)]
signedBy' w intent =
    [(position, signedBy seed (depositIntentPreimage intent)) | (position, seed) <- zip [0 ..] (rotationSeeds (worldSeeds w))]

spec :: Spec
spec = describe "#576 the checkpoint's moves of the attested generation, evaluated by the ledger" $ do
    it "accepts the rotation the builder writes, minting the change and the fact attestation once and withdrawing nothing" $ do
        w <- world
        let move = rotationMove w
        tx <- buildAdvance w move Keep
        accepts (answers w move tx) `shouldBe` True
        shape w move (advanceAttestedSpendRedeemerData 1 Keep 0) (termsPremium checkpointTerms) tx
    it "accepts the depositing rotation whose successor's keys signed the intent naming the bond, and refuses it without the signatures at the checkpoint alone" $ do
        w <- world
        let move = depositMove w
            intent = intentFor w move (termsFreezeBond checkpointTerms)
        signed <- buildAdvance w move (Deposit (signedBy' w intent))
        accepts (answers w move signed) `shouldBe` True
        shape w move (advanceAttestedSpendRedeemerData 1 (Deposit (signedBy' w intent)) 0) (termsPremium checkpointTerms) signed
        unsigned <- buildAdvance w move (Deposit [])
        let verdict = answers w move unsigned
        Evaluation.refusedAt unsigned verdict (SpendingOf (fst (moveSpent move))) `shouldBe` True
        Evaluation.acceptedAt unsigned verdict (Minting (changePolicy w)) `shouldBe` True
        Evaluation.acceptedAt unsigned verdict (Minting (factPolicy w)) `shouldBe` True
    it "accepts the freeze the builder writes, the bond to the hunter" $ do
        w <- world
        let move = freezeMove w
        tx <- buildFreeze w move
        accepts (answers w move tx) `shouldBe` True
        shape w move (freezeAttestedSpendRedeemerData 1 0) (termsFreezeBond checkpointTerms) tx
    it "refuses the rotation whose change attestation has another name, at the change policy and at the spend" $ do
        w <- world
        let move = rotationMove w
        tx <- buildAdvance w move Keep
        negative
            (worldParameters w)
            (chainOf w move)
            tx
            (withMint (renameChange w))
            mintOf
            [Minting (changePolicy w), SpendingOf (fst (moveSpent move))]
            [Minting (factPolicy w)]
    it "refuses the rotation whose fact attestation is minted twice, at the fact policy and at the change policy that reads it" $ do
        w <- world
        let move = rotationMove w
        tx <- buildAdvance w move Keep
        negative
            (worldParameters w)
            (chainOf w move)
            tx
            (withMint (Map.adjust (Map.map (const 2)) (factPolicy w)))
            mintOf
            [Minting (factPolicy w), Minting (changePolicy w)]
            [SpendingOf (fst (moveSpent move))]
    it "refuses the rotation that mints a surplus name under the change policy, at the change policy alone" $ do
        w <- world
        let move = rotationMove w
        tx <- buildAdvance w move Keep
        negative
            (worldParameters w)
            (chainOf w move)
            tx
            (withMint (Map.adjust (Map.insert (AssetName "surplus") 1) (changePolicy w)))
            mintOf
            [Minting (changePolicy w)]
            [Minting (factPolicy w), SpendingOf (fst (moveSpent move))]
    it "refuses the accepted freeze whose successor datum differs in the frozen flag alone, at the change policy and at the spend" $ do
        w <- world
        let move = freezeMove w
        tx <- buildFreeze w move
        negative
            (worldParameters w)
            (chainOf w move)
            tx
            (\t -> t & bodyTxL . outputsTxBodyL %~ withFirst (\o -> o & datumTxOutL .~ mkInlineDatum (unfrozenFlag (moveSuccessor move))))
            firstDatum
            [Minting (changePolicy w), SpendingOf (fst (moveSpent move))]
            [Minting (factPolicy w)]
    it "refuses, before it mints or balances anything, evidence that does not carry a signed fact of the shape the policy decodes" $ do
        w <- world
        let v = worldVector w
            advanceWith payload = advanceAttested (worldParameters w) (worldDeployment w) (worldReferences w) (worldPayer w) ((rotationMove w){movePayload = payload}) Keep Map.empty
            freezeWith payload = freezeAttested (worldParameters w) (worldDeployment w) (worldReferences w) (worldPayer w) ((freezeMove w){movePayload = payload}) Map.empty
            replaceAt i new = \case
                PLC.Constr c fields -> PLC.Constr c [if j == (i :: Int) then new else f | (j, f) <- zip [0 ..] fields]
                other -> other
            refused = \case
                Left (CheckpointMoveRefused _) -> True
                _ -> False
        -- the honest evidence builds, as the controls
        advanceWith (vectorEvidence v) `shouldSatisfy` isRightResult
        freezeWith (vectorFreezePayload v) `shouldSatisfy` isRightResult
        -- the event bytes of the rotation that are no bytes, and the signatures that are no list of pairs
        advanceWith (replaceAt 0 (PLC.I 0) (vectorEvidence v)) `shouldSatisfy` refused
        advanceWith (replaceAt 13 (PLC.B "") (vectorEvidence v)) `shouldSatisfy` refused
        advanceWith (PLC.I 0) `shouldSatisfy` refused
        freezeWith (replaceAt 2 (replaceAt 0 (PLC.I 0) (vectorEvidence v)) (vectorFreezePayload v)) `shouldSatisfy` refused
        freezeWith (replaceAt 2 (replaceAt 14 (PLC.B "") (vectorEvidence v)) (vectorFreezePayload v)) `shouldSatisfy` refused
    it "pays the recipient exactly the premium, debits the checkpoint that amount and the payer nothing but the fee, at the least premium a deployment admits" $ do
        probe <- world
        let least = premiumOutputMinimum (worldParameters probe)
        least `shouldSatisfy` (> 0)
        w <- worldFor terms{registryCheckpointTerms = checkpointTerms{termsPremium = least}}
        let move = rotationMove w
            payer = worldPayer w
        tx <- buildAdvance w move Keep
        accepts (answers w move tx) `shouldBe` True
        case toList (tx ^. bodyTxL . outputsTxBodyL) of
            successor : payment : _ -> do
                (payment ^. addrTxOutL) `shouldBe` payeeAddress
                unCoinOf (payment ^. coinTxOutL) `shouldBe` least
                unCoinOf (snd (moveSpent move) ^. coinTxOutL) - unCoinOf (successor ^. coinTxOutL) `shouldBe` least
            _ -> fail "the transaction has fewer than two outputs"
        -- what the payer puts in less what comes back to it is the fee and nothing else
        let spentByTx = tx ^. bodyTxL . inputsTxBodyL
            paidIn = sum [unCoinOf (o ^. coinTxOutL) | (ref, o) <- payerFunds payer, Set.member ref spentByTx]
            comesBack = sum [unCoinOf (o ^. coinTxOutL) | o <- toList (tx ^. bodyTxL . outputsTxBodyL), o ^. addrTxOutL == payerAddress payer]
            Coin fee = tx ^. bodyTxL . feeTxBodyL
        paidIn - comesBack `shouldBe` fee
        -- every output is legal under the protocol parameters
        forM_ (toList (tx ^. bodyTxL . outputsTxBodyL)) $ \out ->
            unCoinOf (out ^. coinTxOutL) `shouldSatisfy` (>= unCoinOf (getMinCoinTxOut (worldParameters w) out))
    it "refuses a premium below what the ledger asks of the recipient's output, naming both, instead of making it up from the payer" $ do
        probe <- world
        let settle coin =
                let Coin least = getMinCoinTxOut (worldParameters probe) (mkBasicTxOut payeeAddress (inject (Coin coin)) :: TxOut ConwayEra)
                 in max coin least
            required = settle (settle (settle 0))
            supplied = required - 1
        w <- worldFor terms{registryCheckpointTerms = checkpointTerms{termsPremium = supplied}}
        case advanceAttested (worldParameters w) (worldDeployment w) (worldReferences w) (worldPayer w) (rotationMove w) Keep Map.empty of
            Left (CheckpointMoveRefused message) -> do
                message `shouldSatisfy` isInfixOf (show supplied)
                message `shouldSatisfy` isInfixOf (show required)
            other -> expectationFailure ("a premium of " <> show supplied <> " was built: " <> either show (const "a transaction") other)
    describe "the January advance journeys of #591: a rotation with its own predecessor inception" $ do
        forM_ [("R01", "r01"), ("R17", "r17")] $ \(title, name) ->
            it (title <> ": the signed rotation, with its indexed signatures and no receipts, is accepted at every purpose, and the successor carries the next commitments and threshold the signed event declares") $ do
                v <- loadJanuaryVector name
                expected <- loadJanuaryExpectation name
                w <- worldWith v terms
                let move = rotationMove w
                tx <- buildAdvance w move Keep
                accepts (answers w move tx) `shouldBe` True
                case toList (tx ^. bodyTxL . outputsTxBodyL) of
                    successor : _ -> do
                        rawInlineData successor `shouldBe` Just (vectorNew v)
                        nextCommitment (vectorNew v) `shouldBe` Just (expectedNextKeys expected, expectedNextThreshold expected)
                    [] -> fail "the transaction has no output"
                -- the predecessor's commitments are what the signed inception declared
                fmap fst (nextCommitment (vectorOld v)) `shouldBe` Just (expectedSpentNextKeys expected)
        it "R01: a body that repeats its declaration after its last member is refused at the change policy, a body with a seal inside its last member accepted there" $ do
            v <- loadJanuaryVector "r01"
            seal <- loadNestedSeal
            repeated <- loadTrailingPair
            w <- worldWith v terms
            let honest = rotationMove w
                withBody body = atField 0 (const (PLC.B body))
                framed = honest{movePayload = withBody (sealBody seal) (movePayload honest)}
                unframed = honest{movePayload = withBody repeated (movePayload honest)}
            framedTx <- buildAdvance w framed Keep
            Evaluation.acceptedAt framedTx (answers w framed framedTx) (Minting (changePolicy w)) `shouldBe` True
            tx <- buildAdvance w unframed Keep
            Evaluation.refusedAt tx (answers w unframed tx) (Minting (changePolicy w)) `shouldBe` True
        it "R01: a final value whose number is malformed is refused at the change policy, the one whose numbers are valid accepted there (the other purposes are not what this pair isolates)" $ do
            v <- loadJanuaryVector "r01"
            (valid, malformed) <- loadScalarPair
            w <- worldWith v terms
            let honest = rotationMove w
                withBody body = honest{movePayload = atField 0 (const (PLC.B body)) (movePayload honest)}
                accepted = withBody valid
                refused = withBody malformed
            validTx <- buildAdvance w accepted Keep
            Evaluation.acceptedAt validTx (answers w accepted validTx) (Minting (changePolicy w)) `shouldBe` True
            tx <- buildAdvance w refused Keep
            Evaluation.refusedAt tx (answers w refused tx) (Minting (changePolicy w)) `shouldBe` True
        it "records what each purpose of the R01 and R17 rotations costs, and that the whole fits the limits of the recorded parameters" $
            forM_ [("R01", "r01"), ("R17", "r17")] $ \(title, name) -> do
                v <- loadJanuaryVector name
                w <- worldWith v terms
                let move = rotationMove w
                tx <- buildAdvance w move Keep
                let measured = measuredBudgets (worldParameters w) (chainOf w move) tx
                    units = [(purpose, u) | (purpose, Right u) <- Map.toList measured]
                    limits = worldParameters w ^. ppMaxTxExUnitsL
                    totalMem = sum [m | (_, ExUnits m _) <- units]
                    totalSteps = sum [c | (_, ExUnits _ c) <- units]
                forM_ units $ \(purpose, ExUnits m c) ->
                    putStrLn ("budget " <> title <> " " <> show purpose <> ": memory " <> show m <> ", steps " <> show c)
                putStrLn
                    ( "budget "
                        <> title
                        <> " total: memory "
                        <> show totalMem
                        <> " of "
                        <> show (exUnitsMem' limits)
                        <> ", steps "
                        <> show totalSteps
                        <> " of "
                        <> show (exUnitsSteps' limits)
                        <> "; transaction "
                        <> show (tx ^. sizeTxF)
                        <> " bytes (unsigned) of "
                        <> show (worldParameters w ^. ppMaxTxSizeL)
                        <> "; fee "
                        <> show (let Coin f = tx ^. bodyTxL . feeTxBodyL in f)
                    )
                length units `shouldBe` Map.size measured
                toInteger totalMem `shouldSatisfy` (<= exUnitsMem' limits)
                toInteger totalSteps `shouldSatisfy` (<= exUnitsSteps' limits)
        it "R01: the same rotation judged against a spent state whose commitments are empty is refused at the fact policy, the intact one accepted" $ do
            v <- loadJanuaryVector "r01"
            w <- worldWith v terms
            let honest = rotationMove w
                emptied = honest{moveSpent = checkpointOutput w (txIn 0xa1) False 3_000_000 (withNextCommitment (const ([], 0)) (vectorOld v))}
            honestTx <- buildAdvance w honest Keep
            accepts (answers w honest honestTx) `shouldBe` True
            tx <- buildAdvance w emptied Keep
            let verdict = answers w emptied tx
            Evaluation.refusedAt tx verdict (Minting (factPolicy w)) `shouldBe` True
            Evaluation.acceptedAt tx verdict (Minting (changePolicy w)) `shouldBe` True
        it "R01: an abandonment claimed over a signed event that declares commitments is refused at the change policy, the honest rotation accepted" $ do
            v <- loadJanuaryVector "r01"
            w <- worldWith v terms
            let honest = rotationMove w
                -- the successor claims no next keys and threshold zero, and the offset of the threshold is moved to the
                -- value of `bt`, which spells 0 as well: the body declares two commitments and threshold 2
                steered =
                    honest
                        { moveSuccessor = withNextCommitment (const ([], 0)) (vectorNew v)
                        , movePayload = atField 6 (const (PLC.List [])) (atFieldFrom 10 7 (movePayload honest))
                        }
            honestTx <- buildAdvance w honest Keep
            accepts (answers w honest honestTx) `shouldBe` True
            tx <- buildAdvance w steered Keep
            let verdict = answers w steered tx
            Evaluation.refusedAt tx verdict (Minting (changePolicy w)) `shouldBe` True
            Evaluation.acceptedAt tx verdict (Minting (factPolicy w)) `shouldBe` True
        it "R01: an abandonment spelled by a seal of the body is refused at the change policy, the commitments the body declares accepted there" $ do
            v <- loadJanuaryVector "r01"
            seal <- loadNestedSeal
            w <- worldWith v terms
            let honest = rotationMove w
                -- the signed bytes are replaced by a body whose top level declares R01's two commitments and whose seal
                -- spells `"nt":"0","n":[],"bt":"0"`; the signatures no longer hold, which is the fact policy's concern
                withBody = atField 0 (const (PLC.B (sealBody seal)))
                declared = honest{movePayload = withBody (movePayload honest)}
                spelled =
                    honest
                        { moveSuccessor = withNextCommitment (const ([], 0)) (vectorNew v)
                        , movePayload =
                            atField 10 (const (PLC.I (sealOffBt seal))) $
                                atField 7 (const (PLC.I (sealOffNt seal))) $
                                    atField 6 (const (PLC.List [])) $
                                        withBody (movePayload honest)
                        }
            declaredTx <- buildAdvance w declared Keep
            Evaluation.acceptedAt declaredTx (answers w declared declaredTx) (Minting (changePolicy w)) `shouldBe` True
            tx <- buildAdvance w spelled Keep
            Evaluation.refusedAt tx (answers w spelled tx) (Minting (changePolicy w)) `shouldBe` True
        it "R17: the abandonment rotation is refused at the fact policy with one of its two signatures, and when the revealed keys open no commitment, the intact one accepted" $ do
            v <- loadJanuaryVector "r17"
            w <- worldWith v terms
            let honest = rotationMove w
                signatureIndex = 13
                oneSignature = case movePayload honest of
                    PLC.Constr c fs -> PLC.Constr c [if i == signatureIndex then dropSignature x else x | (i, x) <- zip [0 :: Int ..] fs]
                    other -> other
                dropSignature = \case
                    PLC.List (sig : _) -> PLC.List [sig]
                    other -> other
                unopened = honest{moveSpent = checkpointOutput w (txIn 0xa1) False 3_000_000 (withNextKeys (map flipFirstByte) (vectorOld v))}
            honestTx <- buildAdvance w honest Keep
            accepts (answers w honest honestTx) `shouldBe` True
            partial <- buildAdvance w honest{movePayload = oneSignature} Keep
            Evaluation.refusedAt partial (answers w honest{movePayload = oneSignature} partial) (Minting (factPolicy w)) `shouldBe` True
            tx <- buildAdvance w unopened Keep
            Evaluation.refusedAt tx (answers w unopened tx) (Minting (factPolicy w)) `shouldBe` True
    it "refuses the freeze whose successor is not frozen, built from the move that gives it" $ do
        w <- world
        let honest = freezeMove w
            unfrozen = honest{moveSuccessor = vectorNew (worldVector w)}
        tx <- buildFreeze w unfrozen
        let verdict = answers w unfrozen tx
        Evaluation.refusedAt tx verdict (Minting (changePolicy w)) `shouldBe` True
        Evaluation.refusedAt tx verdict (SpendingOf (fst (moveSpent unfrozen))) `shouldBe` True
        Evaluation.acceptedAt tx verdict (Minting (factPolicy w)) `shouldBe` True
    it "derives, from the datums and the evidence alone, the signed fact the independent generator wrote, for each committed vector" $
        forM_ ["two_key", "unwitnessed", "seven_commitments"] $ \name -> do
            v <- loadVectorNamed name
            signedFactForAdvance (vectorOld v) (vectorNew v) (vectorEvidence v) `shouldBe` Just (vectorFact v)
            signedFactForAdvance (vectorFrozen v) (vectorNew v) (vectorEvidence v) `shouldBe` Just (vectorFact v)
            signedFactForFreeze (vectorOld v) (vectorFreezePayload v) `shouldBe` Just (vectorFact v)
    it "refuses a move of the deployed generation: a deployment without policies builds nothing" $ do
        w <- world
        let deployed = (worldDeployment w){deploymentPolicies = Nothing}
            move = rotationMove w
        advanceAttested (worldParameters w) deployed (worldReferences w) (worldPayer w) move Keep Map.empty
            `shouldSatisfy` isNotAttested
        freezeAttested (worldParameters w) deployed (worldReferences w) (worldPayer w) (freezeMove w) Map.empty
            `shouldSatisfy` isNotAttested
  where
    isRightResult = either (const False) (const True)
    unCoinOf (Coin c) = c
    withFirst f = StrictSeq.fromList . (\case o : rest -> f o : rest; [] -> []) . toList
    firstDatum t = case toList (t ^. bodyTxL . outputsTxBodyL) of
        o : _ -> rawInlineData o
        [] -> Nothing
    unfrozenFlag = \case
        PLC.Constr 1 [PLC.Constr 0 fields] -> PLC.Constr 1 [PLC.Constr 0 [if i == (4 :: Int) then PLC.Constr 0 [] else f | (i, f) <- zip [0 ..] fields]]
        other -> other
    isNotAttested = \case
        Left NotAnAttestedDeployment -> True
        _ -> False

    renameChange w =
        Map.adjust (Map.mapKeys (const (AssetName (SBS.toShort (BS.replicate 32 0x00))))) (changePolicy w)

-- | The shape of a transaction a builder wrote for a move: the mint, the references, the outputs and no withdrawal.
shape :: World -> CheckpointMove -> PLC.Data -> Integer -> ConwayTx -> IO ()
shape w move expectedSpend expectedPayment tx = do
    spentDatum <- maybe (fail "the spent output holds no inline datum") pure (rawInlineData (snd (moveSpent move)))
    let deployment = worldDeployment w
        MultiAsset minted = mintOf tx
        checkpointHashBytes = scriptHashBytes (artifactScriptHash (scriptsCheckpoint (deploymentScripts deployment)))
        OutputReference txid index = outputReferenceOf (fst (moveSpent move))
        isFreeze = movePayload move == vectorFreezePayload (worldVector w)
        action = if isFreeze then 2 else 1 :: Integer
        fact
            | isFreeze = signedFactForFreeze spentDatum (movePayload move)
            | otherwise = signedFactForAdvance spentDatum (moveSuccessor move) (movePayload move)
        nameOf = AssetName . SBS.toShort
        references = worldReferences w
    -- exactly the two policies' attestations, once each, named as the policies name them
    Map.keysSet minted `shouldBe` Set.fromList [changePolicy w, factPolicy w]
    Map.lookup (changePolicy w) minted
        `shouldBe` Just (Map.singleton (nameOf (advanceAttestationName action checkpointHashBytes (txid, index) 0)) 1)
    Map.lookup (factPolicy w) minted
        `shouldBe` Just (Map.singleton (nameOf (fromMaybe BS.empty (fact >>= signedFactName))) 1)
    -- the redeemers: the spend's with the successor index and the bond option, the change policy's claim with its
    -- successor index, the fact policy's facts
    let Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
        carried = [datum | (Ledger.Data datum, _) <- Map.elems redeemers]
    forM_
        [ expectedSpend
        , changeIssueData [(advanceEnvelopeData action checkpointHashBytes (txid, index) (movePayload move), 0)]
        , factIssueData (maybe [] pure fact)
        ]
        $ \expected -> carried `shouldSatisfy` (expected `elem`)
    length carried `shouldBe` 3
    -- the published scripts are read by reference, and nothing is withdrawn
    (tx ^. bodyTxL . referenceInputsTxBodyL)
        `shouldBe` Set.fromList (map fst [attestedCheckpointScript references, attestedFactScript references, attestedChangeScript references])
    (tx ^. bodyTxL . withdrawalsTxBodyL) `shouldBe` Withdrawals mempty
    -- the successor is the first output, at the checkpoint address, with the token and the datum of the move
    case toList (tx ^. bodyTxL . outputsTxBodyL) of
        successor : payment : _ -> do
            (successor ^. addrTxOutL) `shouldBe` checkpointAddress deployment
            rawInlineData successor `shouldBe` Just (moveSuccessor move)
            assetsOfOutput successor `shouldBe` assetsOfOutput (snd (moveSpent move))
            -- the payment is the second output: to the recipient asked for, of the amount asked for, nothing else, and
            -- not to the payer
            (payment ^. addrTxOutL) `shouldBe` movePayee move
            (payment ^. addrTxOutL) `shouldSatisfy` (/= payerAddress (worldPayer w))
            (payment ^. coinTxOutL) `shouldBe` Coin expectedPayment
            assetsOfOutput payment `shouldBe` mempty
        _ -> fail "the transaction has fewer than two outputs"
  where
    assetsOfOutput out = let MaryValue _ assets = out ^. valueTxOutL in assets

-- | The memory and the steps of an execution-unit limit, as numbers.
exUnitsMem', exUnitsSteps' :: ExUnits -> Integer
exUnitsMem' (ExUnits m _) = fromIntegral m
exUnitsSteps' (ExUnits _ c) = fromIntegral c
