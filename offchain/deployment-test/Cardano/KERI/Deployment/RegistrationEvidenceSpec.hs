{- |
Module      : Cardano.KERI.Deployment.RegistrationEvidenceSpec
Description : The offset-free registration evidence, built from signed bytes alone

Three inceptions of an independent structural reference (a key-derived prefix
whose digest differs from its identifier, a self-addressing prefix with a
three-signature quorum, and the two-key positive) and the keripy prefix cases
the model admits go through the production builder, the hash-proof redeemers,
the qualified live datum and the registration predicate. The controls change
one datum field, the spelling of the sequence number or the signed bytes, and
require the named refusal.
-}
module Cardano.KERI.Deployment.RegistrationEvidenceSpec (spec) where

import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    DatumError (..),
    KeyMaterial (..),
    KeyStateView (..),
    QualifiedIdentity (..),
    liveOfInception,
 )
import Cardano.KERI.AID.Checkpoint.InceptionPrefix (PrefixKind (..))
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    InceptionError (..),
    RegistrationError (..),
    RegistrationEvidence (..),
    proofTokenName,
    registrationPredicateOver,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    hashProofBurnData,
    hashProofMintData,
    registrationEvidenceData,
 )
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.ReferenceInception (
    Reference (..),
    exportOf,
    futureCaseExport,
    loadReferences,
    pick,
    prefixCaseExport,
    respell,
 )
import Cardano.KERI.Deployment.RegistryChain (exportKey)
import Control.Monad ((>=>))
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import PlutusCore.Data (Data (..))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "offset-free registration evidence" $ do
    describe "the reference inceptions through the production builder" $ do
        it "builds the three-field evidence, the proof name and the redeemers the reference states" $ do
            refs <- loadReferences
            mapM_ checkReference refs
        it "keeps the identifier and the event's own digest apart for a key-derived prefix" $ do
            refs <- loadReferences
            export <- exportOf (pick "I01" refs)
            inceptionKind export `shouldBe` BasicPrefix True
            BS.length (inceptionDigest export) `shouldBe` 32
            (cdCesrAid (inceptionDatum export) == inceptionDigest export) `shouldBe` False
        it "binds a self-addressing prefix to the digest of its own event" $ do
            refs <- loadReferences
            export <- exportOf (pick "I02" refs)
            inceptionKind export `shouldBe` SelfAddressingPrefix
            cdCesrAid (inceptionDatum export) `shouldBe` inceptionDigest export
        it "accepts each reference inception under the registration predicate" $ do
            refs <- loadReferences
            mapM_ (exportOf >=> accepted) refs
    describe "the request key, the datum identity and the stored keys are the signed qualified spelling" $ do
        let spelled name expectedAid expectedKeys = it name $ do
                refs <- loadReferences
                export <- exportOf (pick (T.pack name) refs)
                exportKey export `shouldBe` TE.encodeUtf8 expectedAid
                case liveOfInception "refund" 7 (inceptionDatum export) (inceptionQualified export) of
                    Live{lvAid, lvKeys} -> do
                        lvAid `shouldBe` TE.encodeUtf8 expectedAid
                        kmCurKeys lvKeys `shouldBe` map TE.encodeUtf8 expectedKeys
                    _ -> fail "a live datum was expected"
        spelled "I01" "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ" ["DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"]
        spelled
            "I02"
            "EEnwnQUz696trMrSNOKKH9b2CKz5xTF-fgCquWHuiLgA"
            [ "DNFWz8AsxHPcZFy7tIswi1cYEG96zmZQVkdz8gQIdzIL"
            , "DCtQH-bOQ4L7ywz_P_uuT_pSKAWce7H6PB_sKuy7b3_R"
            , "DHsjDyW82DiCth5DZhxzn_zJ7PeOPpTFW3zJ-FLXbD09"
            ]
        it "B empty keeps the B code of its key and its identifier, apart from its own SAID" $ do
            export <- prefixCaseExport "B empty"
            let aid = "BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTw"
            exportKey export `shouldBe` aid
            qiCurKeys (inceptionQualified export) `shouldBe` [aid]
            qb64Aid (inceptionDigest export) `shouldBe` "EIgvoqHwq-DpO8FStujY-u5MDe1JjChiQssTtgBG208B"
            inceptionKind export `shouldBe` BasicPrefix False
    describe "the model admits the empty and zero future declarations of the keripy cases" $
        mapM_
            ( \label -> it (T.unpack label <> " is accepted by the predicate") $ do
                export <- prefixCaseExport label
                accepted export
            )
            ["B empty", "D empty", "D next", "D seal", "E digest", "D zero next with digest"]
    describe "the weighted future declarations of draft #600, on keripy's signed inceptions (Q-069)" $ do
        let signed label = do
                export <- futureCaseExport label
                pure (export, reEventBytes (inceptionEvidence export))
        it "admits a signed literal 2/4 + 2/4 clause over two commitments, keeping the signed bytes and both commitments in order" $ do
            (export, bytes) <- signed "D next unreduced"
            accepted export
            ("\"nt\":[\"2/4\",\"2/4\"]" `BS.isInfixOf` bytes) `shouldBe` True
            length (cdNextKeys (inceptionDatum export)) `shouldBe` 2
        it "admits [[1],[1]] over three commitments, keeping all three in order" $ do
            (export, bytes) <- signed "D next partial coverage"
            accepted export
            ("\"nt\":[[\"1\"],[\"1\"]]" `BS.isInfixOf` bytes) `shouldBe` True
            length (cdNextKeys (inceptionDatum export)) `shouldBe` 3
        it "keeps admitting the reduced clause and the numeric zero" $ do
            futureCaseExport "D next exact one" >>= accepted
            prefixCaseExport "D zero next with digest" >>= accepted
        let refusedAtR4 label = it ("refuses " <> T.unpack label <> " at the inception rule") $ do
                export <- futureCaseExport label
                case registrationPredicateOver
                    context
                    (inceptionQualified export)
                    (inceptionDatum export)
                    1_007_000_000
                    (inceptionEvidence export) of
                    Left (R4InceptionInvalid (InceptionIllFormed (NextIllFormed _))) -> pure ()
                    result -> fail ("a refusal of the next declaration was expected: " <> show result)
        mapM_ refusedAtR4 ["D next below one", "D weighted next without commitments", "D next second clause below one"]
    describe "a datum that disagrees with the signed bytes in one field is refused by name" $ do
        let refused name what mutate expected =
                it (name <> ": " <> what) $ do
                    refs <- loadReferences
                    export <- exportOf (pick (T.pack name) refs)
                    registrationPredicateOver
                        context
                        (inceptionQualified export)
                        (mutate (inceptionDatum export))
                        1_007_000_000
                        (inceptionEvidence export)
                        `shouldBe` Left expected
        refused "pos_2key" "identifier" (\d -> d{cdCesrAid = BS.map (+ 1) (cdCesrAid d)}) E2AidMismatch
        refused "pos_2key" "current keys" (\d -> d{cdCurKeys = reverse (cdCurKeys d)}) E4CurKeysMismatch
        refused "pos_2key" "current threshold" (\d -> d{cdCurThreshold = other (cdCurThreshold d)}) E5CurThresholdMismatch
        refused "pos_2key" "next keys" (\d -> d{cdNextKeys = map (BS.map (+ 1)) (cdNextKeys d)}) E6NextKeysMismatch
        refused "pos_2key" "next threshold" (\d -> d{cdNextThreshold = other (cdNextThreshold d)}) E7NextThresholdMismatch
        refused "pos_2key" "witnesses" (\d -> d{cdWitnesses = [BS.replicate 32 7]}) E8WitnessesMismatch
        refused "pos_2key" "witness threshold" (\d -> d{cdToad = 1}) E9ToadMismatch
        it "I01: a key spelled with another code than the signed one is refused as the current keys" $ do
            refs <- loadReferences
            export <- exportOf (pick "I01" refs)
            let q = inceptionQualified export
                bCoded = q{qiCurKeys = map (\k -> "B" <> BS.drop 1 k) (qiCurKeys q)}
            registrationPredicateOver
                context
                bCoded
                (inceptionDatum export)
                1_007_000_000
                (inceptionEvidence export)
                `shouldBe` Left E4CurKeysMismatch
    describe "the sequence number is the canonical spelling" $ do
        -- a key-derived prefix is not a digest of the body, so the spelling is the only difference
        let spelledAs replacement =
                it ("s = " <> show replacement <> " is refused as a sequence mismatch") $ do
                    refs <- loadReferences
                    let r = pick "I01" refs
                    export <- exportOf r
                    let evidence =
                            (inceptionEvidence export)
                                { reEventBytes = respell (refEvent r) "\"s\":\"0\"" ("\"s\":\"" <> replacement <> "\"")
                                }
                    registrationPredicateOver
                        context
                        (inceptionQualified export)
                        (inceptionDatum export)
                        1_007_000_000
                        evidence
                        `shouldBe` Left E3SequenceMismatch
        mapM_ spelledAs ["00", "0x0", "", "1", "A", "\\u0030", "\\u0030\\u0030"]
        it "a respelled body of a self-addressing prefix is refused earlier, as not derived" $ do
            refs <- loadReferences
            let r = pick "pos_2key" refs
            export <- exportOf r
            registrationPredicateOver
                context
                (inceptionQualified export)
                (inceptionDatum export)
                1_007_000_000
                (inceptionEvidence export){reEventBytes = respell (refEvent r) "\"s\":\"0\"" "\"s\":\"00\""}
                `shouldBe` Left E2AidMismatch
    describe "the controller signatures bind the exact signed bytes" $
        it "a grammar-valid body with another own SAID is refused at the quorum, after every binding check" $ do
            refs <- loadReferences
            let r = pick "I01" refs
            export <- exportOf r
            let evidence =
                    (inceptionEvidence export)
                        { reEventBytes = respell (refEvent r) (TE.encodeUtf8 (refSaid r)) (swapSecond (TE.encodeUtf8 (refSaid r)))
                        }
            registrationPredicateOver
                context
                (inceptionQualified export)
                (inceptionDatum export)
                1_007_000_000
                evidence
                `shouldBe` Left R7QuorumUnsatisfied
  where
    context = DeploymentContext{dcMinAda = 2_000_000, dcDReg = 1_000_000_000}
    other (Unweighted n) = Unweighted (n + 1)
    other t = t
    -- another valid E-code digest: the second character of the payload changed
    swapSecond t = BS.take 2 t <> (if BS.index t 2 == 0x41 then "B" else "A") <> BS.drop 3 t

accepted :: InceptionExport -> IO ()
accepted export =
    registrationPredicateOver
        DeploymentContext{dcMinAda = 2_000_000, dcDReg = 1_000_000_000}
        (inceptionQualified export)
        (inceptionDatum export)
        1_007_000_000
        (inceptionEvidence export)
        `shouldBe` Right ()

checkReference :: Reference -> IO ()
checkReference r = do
    export <- exportOf r
    let evidence = inceptionEvidence export
        datum = inceptionDatum export
    reEventBytes evidence `shouldBe` refEvent r
    reCtrlSigs evidence `shouldBe` refCtrlSigs r
    reWitReceipts evidence `shouldBe` []
    inceptionAid export `shouldBe` refIdentifier r
    qb64Aid (inceptionDigest export) `shouldBe` TE.encodeUtf8 (refSaid r)
    proofTokenName (reEventBytes evidence) (cdCesrAid datum) `shouldBe` refProofName r
    hashProofMintData (reEventBytes evidence) (cdCesrAid datum)
        `shouldBe` Constr 0 [B (fst (refMint r)), B (snd (refMint r))]
    hashProofBurnData `shouldBe` Constr 0 [B "", B ""]
    registrationEvidenceData evidence
        `shouldBe` Constr
            0
            [ B (refEvent r)
            , List [List [I (fromIntegral i), B s] | (i, s) <- refCtrlSigs r]
            , List []
            ]
