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
    Seeds (..),
    Vector (..),
    loadSeeds,
    loadVectorNamed,
    signedBy,
 )
import Cardano.KERI.Deployment.LedgerEvaluation (
    Purpose (..),
    accepts,
    evaluated,
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
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, inputsTxBodyL, outputsTxBodyL, referenceInputsTxBodyL, withdrawalsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, coinTxOutL, datumTxOutL, getMinCoinTxOut, mkBasicTxOut, referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (forM_)
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
worldFor registryTerms = do
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
    vector <- loadVectorNamed "two_key"
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
