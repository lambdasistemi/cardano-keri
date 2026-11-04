{- |
Module      : Cardano.KERI.AID.Checkpoint.DepositSpec
Description : The deposit option of Advance (#345) against the Lean deposit intent and corpus

The Haskell side of the deposit rotation: the bond option on the wire, the
intent the new keys sign and its bytes, how their signatures are counted, and
the verdict over the validators' premises. Every byte is the Lean's: the rows
of @lean/checkpoint-deposit-vectors.json@ are generated into
"Cardano.KERI.AID.Checkpoint.DepositVectors" with their signatures, and the
deposit cells of @simulator/checkpoint-simulator-corpus.json@ into
"Cardano.KERI.AID.Checkpoint.DepositCorpus". The rotation evidence is the
committed @adv_wit_2key@ keripy rotation, the same the Aiken tests run over,
so the two layers judge the same transactions. Every amount is arithmetic over
the Lean parameters, never read back from the code under test.
-}
module Cardano.KERI.AID.Checkpoint.DepositSpec (spec) where

import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.AdvanceSpec (AdvCase (..), advCase)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
 )
import Cardano.KERI.AID.Checkpoint.Deposit (
    BondOption (..),
    DepositFacts (..),
    DepositInput (..),
    DepositIntent (..),
    DepositParams (..),
    DepositRefusal (..),
    bondOptionData,
    depositDomain,
    depositIntentPreimage,
    depositSigned,
    depositVerdict,
    requiredIntent,
 )
import Cardano.KERI.AID.Checkpoint.DepositCorpus (
    DepositCell (..),
    depositCells,
 )
import Cardano.KERI.AID.Checkpoint.DepositVectors (
    VectorAuthorization (..),
    VectorFacts (..),
    VectorIntent (..),
    VectorRequirement (..),
    VectorSigned (..),
    VectorSpent (..),
    newKeys,
    vectorAuthorizations,
    vectorCandidateIntents,
    vectorFixture,
    vectorIntents,
    vectorRequirements,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (loadFixture)
import Cardano.KERI.AID.Checkpoint.Message (SpentCheckpoint (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Either (isRight)
import Data.Maybe (fromMaybe)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    beforeAll,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

-- | One Lean unit, in lovelace.
unit :: Integer
unit = 1_000_000

-- | The deployed freeze bond and the bond the Lean vectors use.
deployedBond, leanBond :: Integer
deployedBond = 5 * unit
leanBond = 2_000_000

-- | The Lean parameters as lovelace: @Mc@, @D = 1000@, @B = 5@, @P = 2@; network 1.
params :: DepositParams
params =
    DepositParams
        { dpNetworkId = 1
        , dpMinAda = 2_000_000
        , dpDeposit = 1_000_000_000
        , dpBond = deployedBond
        , dpPremium = 2 * unit
        }

floorUnfrozen, floorFrozen :: Integer
floorUnfrozen = dpMinAda params + dpDeposit params + dpBond params
floorFrozen = dpMinAda params + dpDeposit params

shortPool, coveringPool :: Integer
shortPool = unit
coveringPool = 3 * unit

-- | The spent checkpoint as a live datum, over the fixture's spent key state.
liveOf :: AdvCase -> Bool -> Bool -> Integer -> CheckpointDatumV2
liveOf c poisoned frozen sn =
    Live
        { lvAid = qb64Aid (scCesrAid (acSpent c))
        , lvSn = sn
        , lvEpoch = scSeq (acSpent c)
        , lvPoisoned = poisoned
        , lvFrozen = frozen
        , lvBornAt = birthSlot
        , lvRefundTo = refundAddress
        , lvKeys =
            KeyMaterial
                { kmCurKeys = acIcpKeys c
                , kmCurThreshold = Unweighted 2
                , kmNextKeys = scNextKeys (acSpent c)
                , kmNextThreshold = scNextThreshold (acSpent c)
                , kmWitnesses = scWitnesses (acSpent c)
                , kmToad = 2
                }
        }

-- | The refund address and birth slot of the spent checkpoint.
refundAddress :: ByteString
refundAddress = BS.cons 0x61 (BS.replicate 28 0x53)

birthSlot :: Integer
birthSlot = 1_800_000_000_000

{- | The successor a deposit of the connected rotation writes: the rotated keys
and sequence number, one more epoch, with the given frozen flag, refund
address, birth slot and identifier.
-}
successorWith :: AdvCase -> Bool -> ByteString -> Integer -> ByteString -> CheckpointDatumV2
successorWith c frozen refund born aid =
    Live
        { lvAid = aid
        , lvSn = cdNativeSn created
        , lvEpoch = cdSeq created
        , lvPoisoned = False
        , lvFrozen = frozen
        , lvBornAt = born
        , lvRefundTo = refund
        , lvKeys =
            KeyMaterial
                { kmCurKeys = cdCurKeys created
                , kmCurThreshold = cdCurThreshold created
                , kmNextKeys = cdNextKeys created
                , kmNextThreshold = cdNextThreshold created
                , kmWitnesses = cdWitnesses created
                , kmToad = cdToad created
                }
        }
  where
    created = acCreated c

-- | The honest successor: unfrozen, the spent checkpoint's birth and refund.
successorOf :: AdvCase -> CheckpointDatumV2
successorOf c =
    successorWith c False refundAddress birthSlot (qb64Aid (scCesrAid (acSpent c)))

-- | The signatures of a case of the connected rotation, by name.
signedBy :: String -> [(Int, ByteString)]
signedBy name =
    fromMaybe
        (error ("no fixture case " <> name))
        (lookup name [(vgName v, vgSignatures v) | v <- vectorFixture])

{- | The honest deposit of the connected rotation for a checkpoint with these
flags and this pool, signed as the named case.
-}
depositOf :: AdvCase -> Bool -> Bool -> Integer -> String -> DepositInput
depositOf c poisoned frozen pool intent =
    DepositInput
        { dnPolicy = scPolicyId (acSpent c)
        , dnSpentTxId = scTxid (acSpent c)
        , dnSpentIndex = scIndex (acSpent c)
        , dnSpentDatum = liveOf c poisoned frozen (scNativeSn (acSpent c))
        , dnSpentLovelace = (if frozen then floorFrozen else floorUnfrozen) + pool
        , dnSuccessorDatum = successorOf c
        , dnSuccessorLovelace = floorUnfrozen + afterPremium
        , dnPayeeLovelace = if covers then Just (dpPremium params) else Nothing
        , dnMinted = False
        , dnSignatures = signedBy intent
        , dnRotation = acEvidence c
        }
  where
    covers = pool >= dpPremium params
    afterPremium = if covers then pool - dpPremium params else pool

honest :: AdvCase -> DepositInput
honest c = depositOf c False True shortPool "frozen"

-- ---------------------------------------------------------------------
-- The vector rows
-- ---------------------------------------------------------------------

intentOfRow :: VectorIntent -> DepositIntent
intentOfRow r =
    DepositIntent
        { diDomain = viDomain r
        , diNetworkId = viNetworkId r
        , diCheckpointPolicy = viPolicy r
        , diSpentTxId = viTxId r
        , diSpentIndex = viOutputIndex r
        , diAid = viAid r
        , diNewSn = viNewSn r
        , diNewEpoch = viNewEpoch r
        , diDeposit = viDeposit r
        }

spentOfRow :: VectorSpent -> VectorFacts -> CheckpointDatumV2
spentOfRow s f =
    Live
        { lvAid = vfAid f
        , lvSn = vsSn s
        , lvEpoch = vsEpoch s
        , lvPoisoned = vsPoisoned s
        , lvFrozen = vsFrozen s
        , lvBornAt = vsBornAt s
        , lvRefundTo = vsRefundTo s
        , lvKeys =
            KeyMaterial
                { kmCurKeys = []
                , kmCurThreshold = Unweighted 1
                , kmNextKeys = []
                , kmNextThreshold = Unweighted 1
                , kmWitnesses = []
                , kmToad = 0
                }
        }

factsOfRow :: VectorFacts -> DepositFacts
factsOfRow f =
    DepositFacts
        { dfNetworkId = vfNetworkId f
        , dfPolicy = vfPolicy f
        , dfTxId = vfTxId f
        , dfOutputIndex = vfOutputIndex f
        }

requiredBytes :: Integer -> VectorRequirement -> Maybe ByteString
requiredBytes bond r =
    depositIntentPreimage
        <$> requiredIntent bond (factsOfRow (vrFacts r)) (spentOfRow (vrSpent r) (vrFacts r)) (vrNewSn r)

spec :: Spec
spec = describe "Checkpoint.Deposit (#345, Lean CheckpointDeposit and Step.rotateDeposit*)" $ do
    describe "the bond option on the wire" $ do
        it "Keep is constructor zero with no fields" $
            bondOptionData Keep `shouldBe` Constr 0 []
        it "Deposit is constructor one with the signatures as position and bytes pairs" $
            bondOptionData (Deposit [(0, BS.replicate 64 1), (1, BS.replicate 64 2)])
                `shouldBe` Constr
                    1
                    [ List
                        [ List [I 0, B (BS.replicate 64 1)]
                        , List [I 1, B (BS.replicate 64 2)]
                        ]
                    ]

    describe "the intent bytes are the Lean's" $ do
        it "the domain is the frozen tag" $
            depositDomain `shouldBe` BC.pack "cardano-keri/checkpoint/deposit/v1"
        it "covers the committed intents rows" $
            length vectorIntents `shouldBe` 5
        it "serialises every intents row to the preimage the Lean prints" $
            [ viId r
            | r <- vectorIntents
            , depositIntentPreimage (intentOfRow r) /= viPreimage r
            ]
                `shouldBe` []
        it "covers the candidate of every requirements row" $
            length vectorCandidateIntents `shouldBe` length vectorRequirements
        it "serialises the candidate of every requirements row to the preimage the Lean prints" $
            [ viId r
            | r <- vectorCandidateIntents
            , depositIntentPreimage (intentOfRow r) /= viPreimage r
            ]
                `shouldBe` []
        it "requires, on every requirements row, the intent whose bytes the Lean prints (the Lean's bond)" $
            [vrId r | r <- vectorRequirements, requiredBytes leanBond r /= Just (vrLeanRequired r)]
                `shouldBe` []
        it "requires, on every requirements row, the same intent at the deployed bond" $
            [vrId r | r <- vectorRequirements, requiredBytes deployedBond r /= Just (vrRequired r)]
                `shouldBe` []
        it "accepts a candidate exactly when it is the required intent (bytes of the row)" $
            [ vrId r
            | r <- vectorRequirements
            , (vrCandidate r == vrRequired r) /= vrAccepted r
            ]
                `shouldBe` []

    describe "the signers: the new keys at the new threshold" $ do
        it "counts the signatures of the new keys over the required intent on every requirements row" $
            [ vrId r
            | r <- vectorRequirements
            , depositSigned newKeys (Unweighted 2) (vrCandidateSignatures r) (vrRequired r)
                /= vrAccepted r
            ]
                `shouldBe` []
        it "takes the deposit exactly when the Lean does on every authorizations row" $
            [ vaId a
            | a <- vectorAuthorizations
            , depositSigned newKeys (vaThreshold a) (vaSignatures a) (vaSignedBytes a)
                /= vaAuthorized a
            ]
                `shouldBe` []
        it "covers both verdicts" $ do
            length (filter vaAuthorized vectorAuthorizations) `shouldBe` 5
            length (filter (not . vaAuthorized) vectorAuthorizations) `shouldBe` 10

    describe "depositVerdict: the validators' premises, each by name" $
        beforeAll (loadFixture "advance.json") $ do
            it "accepts the honest deposit of a frozen checkpoint" $ \fx ->
                withCaseIO fx $ \c -> depositVerdict params (honest c) `shouldBe` Right ()
            it "accepts it when the pool covers the premium" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict params (depositOf c False True coveringPool "frozen") `shouldBe` Right ()
            it "accepts it on a poisoned checkpoint" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict params (depositOf c True True shortPool "frozen") `shouldBe` Right ()
            it "accepts a deposit on an unfrozen checkpoint when the intent names zero" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict params (depositOf c False False shortPool "unfrozen") `shouldBe` Right ()
            it "refuses an intent that names zero on a frozen checkpoint" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict params (depositOf c False True shortPool "frozen-names-zero")
                        `shouldBe` Left DepositNotAuthorized
            it "refuses an intent that names the bond on an unfrozen checkpoint" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict params (depositOf c False False shortPool "unfrozen-names-bond")
                        `shouldBe` Left DepositNotAuthorized
            it "refuses an intent for another output, network, sequence number or epoch, or signed by the spent keys" $ \fx ->
                withCaseIO fx $ \c ->
                    [ name
                    | name <- ["other-output", "other-network", "other-sn", "old-epoch", "signed-by-old-keys"] :: [String]
                    , depositVerdict params (depositOf c False True shortPool name)
                        /= Left DepositNotAuthorized
                    ]
                        `shouldBe` []
            it "refuses too few, repeated, out-of-range and swapped signatures" $ \fx ->
                withCaseIO fx $ \c ->
                    case signedBy "frozen" of
                        [(i0, s0), (i1, s1)] ->
                            let with sigs = (honest c){dnSignatures = sigs}
                                cases =
                                    [ ("one", [(i0, s0)])
                                    , ("none", [])
                                    , ("repeated", [(i0, s0), (i0, s0)])
                                    , ("out of range", [(i0, s0), (7, s1)])
                                    , ("swapped", [(i0, s1), (i1, s0)])
                                    ] ::
                                        [(String, [(Int, ByteString)])]
                             in [ name
                                | (name, sigs) <- cases
                                , depositVerdict params (with sigs) /= Left DepositNotAuthorized
                                ]
                                    `shouldBe` []
                        other -> expectationFailure ("fixture case frozen has " <> show (length other) <> " signatures")
            it "refuses a rotation without signatures or receipts" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict
                        params
                        (honest c){dnRotation = (acEvidence c){aeCtrlSigs = [], aeWitReceipts = []}}
                        `shouldSatisfy` isRotationRefused
            it "refuses a successor that stays frozen" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict
                        params
                        (honest c){dnSuccessorDatum = successorWith c True refundAddress birthSlot (qb64Aid (scCesrAid (acSpent c)))}
                        `shouldBe` Left DepositSuccessorStillFrozen
            it "refuses a successor one lovelace short of, or over, the bond" $ \fx ->
                withCaseIO fx $ \c ->
                    [ delta
                    | delta <- [-1, 1, -dpBond params]
                    , depositVerdict
                        params
                        (honest c){dnSuccessorLovelace = floorUnfrozen + shortPool + delta}
                        /= Left DepositSuccessorValueMismatch
                    ]
                        `shouldBe` []
            it "refuses a premium paid one lovelace short" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict
                        params
                        (depositOf c False True coveringPool "frozen"){dnPayeeLovelace = Just (dpPremium params - 1)}
                        `shouldBe` Left DepositPremiumUnpaid
            it "refuses a pool that is not reduced by the premium it covers" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict
                        params
                        (depositOf c False True coveringPool "frozen"){dnSuccessorLovelace = floorUnfrozen + coveringPool}
                        `shouldBe` Left DepositSuccessorValueMismatch
            it "refuses a pool reduced when it does not cover the premium" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict
                        params
                        (honest c){dnSuccessorLovelace = floorUnfrozen + shortPool - 1}
                        `shouldBe` Left DepositSuccessorValueMismatch
            it "refuses a successor that changes the refund address, the birth slot or the identifier" $ \fx ->
                withCaseIO fx $ \c ->
                    let aid = qb64Aid (scCesrAid (acSpent c))
                        moved =
                            [ ("refund", successorWith c False (BS.cons 0x61 (BS.replicate 28 0x52)) birthSlot aid)
                            , ("birth", successorWith c False refundAddress 1 aid)
                            , ("aid", successorWith c False refundAddress birthSlot (BC.pack "E"))
                            ]
                     in [ name
                        | (name, datum) <- moved :: [(String, CheckpointDatumV2)]
                        , depositVerdict params (honest c){dnSuccessorDatum = datum}
                            /= Left DepositSuccessorFrameChanged
                        ]
                            `shouldBe` []
            it "refuses a transaction that mints under the checkpoint policy" $ \fx ->
                withCaseIO fx $ \c ->
                    depositVerdict params (honest c){dnMinted = True} `shouldBe` Left DepositMinted

    describe "the Lean corpus: the Haskell verdict is the Lean's on every deposit cell" $
        beforeAll (loadFixture "advance.json") $ do
            it "covers the grid: both verdicts occur" $ \_ -> do
                length depositCells `shouldBe` 78
                length (filter dcAccepted depositCells) `shouldBe` 12
            it "agrees with the Lean on every cell" $ \fx ->
                withCaseIO fx $ \c ->
                    [ dcName cell
                    | cell <- depositCells
                    , isRight (depositVerdict params (cellInput c cell)) /= dcAccepted cell
                    ]
                        `shouldBe` []
  where
    withCaseIO fx k = case advCase fx "adv_wit_2key" of
        Left err -> expectationFailure err
        Right c -> k c
    isRotationRefused = \case
        Left (DepositRotationRefused _) -> True
        _ -> False

{- | A corpus cell as a deposit: the flags and pool of the cell, the sequence
number relation re-labelling the spent checkpoint, the oracles deciding whether
the evidence carries signatures and whether the new keys signed the required
intent.
-}
cellInput :: AdvCase -> DepositCell -> DepositInput
cellInput c cell =
    base
        { dnSpentDatum = spentDatum
        , dnSpentLovelace = spentLovelace
        , dnSuccessorLovelace = successorLovelace
        , dnPayeeLovelace = payee
        , dnSignatures = signedBy intent
        , dnRotation = rotation
        }
  where
    base = honest c
    pool = dcPool cell * unit
    covers = pool >= dpPremium params
    created = cdNativeSn (acCreated c)
    spentSn = case dcSnRelation cell of
        r
            | r > 0 -> scNativeSn (acSpent c)
            | r == 0 -> created
            | otherwise -> created + 1
    spentDatum
        | dcPending cell =
            TerminationPending (qb64Aid (scCesrAid (acSpent c))) (scNativeSn (acSpent c)) (scSeq (acSpent c))
        | otherwise = liveOf c (dcPoisoned cell) (dcFrozen cell) spentSn
    spentLovelace
        | dcPending cell = dpMinAda params
        | dcFrozen cell = floorFrozen + pool
        | otherwise = floorUnfrozen + pool
    successorLovelace
        | dcPending cell = floorUnfrozen
        | covers = floorUnfrozen + pool - dpPremium params
        | otherwise = floorUnfrozen + pool
    payee
        | not (dcPending cell) && covers = Just (dpPremium params)
        | otherwise = Nothing
    intent
        | not (dcDepositAuthorized cell) = "other-sn"
        | dcFrozen cell || dcPending cell = "frozen"
        | otherwise = "unfrozen"
    rotation
        | dcRotationEvidenced cell = acEvidence c
        | otherwise = (acEvidence c){aeCtrlSigs = [], aeWitReceipts = []}
