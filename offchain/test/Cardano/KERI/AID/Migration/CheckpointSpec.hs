{- |
Module      : Cardano.KERI.AID.Migration.CheckpointSpec
Description : Checkpoint-family migration oracle controls, #254 S254-1B

Every example here is two-sided: it asserts the accepting transition and a
named mutant of it in the same expectation.  A one-sided rejection example
passes just as happily against a rule that rejects everything, which is the
exact failure mode a fail-closed body would hide — so the accepting case is
carried everywhere as the live negative control.

The transaction-shaped arms are exercised through the 'MigrationTx' mirror,
which is deliberately the smallest set of facts a migration rule may read.  It
carries no signatory list at all, so no example here can accidentally
demonstrate a transaction-signer fallback: the only thing that authorizes a
move is controller signature data.
-}
module Cardano.KERI.AID.Migration.CheckpointSpec (spec) where

import Cardano.Crypto.DSIGN (
    Ed25519DSIGN,
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.Seed (
    mkSeedFromBytes,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Cardano.KERI.AID.Migration.Checkpoint
import Cardano.KERI.AID.Migration.Types (
    AddressCredential (..),
    FullAddress (..),
    MigrationAuthorization (..),
    MigrationOrigin (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    StakeCredential (..),
    ValidatorVersion (..),
    migrationDomain,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Word (
    Word8,
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    toBuiltinData,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
    shouldSatisfy,
 )

-- ---------------------------------------------------------
-- Fixture material
-- ---------------------------------------------------------

signerOf :: Word8 -> SignKeyDSIGN Ed25519DSIGN
signerOf byte = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 byte))

verkeyOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
verkeyOf = rawSerialiseVerKeyDSIGN . deriveVerKeyDSIGN

signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver signer message = rawSerialiseSigDSIGN (signDSIGN () message signer)

controller0, controller1, controller2, foreigner :: SignKeyDSIGN Ed25519DSIGN
controller0 = signerOf 0xc0
controller1 = signerOf 0xc1
controller2 = signerOf 0xc2
foreigner = signerOf 0xf0

bytesOf :: Int -> Word8 -> ByteString
bytesOf = BS.replicate

cesrAid, sourcePolicy, targetPolicy, sourceTxid, mutantTxid :: ByteString
cesrAid = bytesOf 32 0xaa
sourcePolicy = bytesOf 28 0x50
targetPolicy = bytesOf 28 0x51
sourceTxid = bytesOf 32 0x60
mutantTxid = bytesOf 32 0x61

targetScript, refundVkey, witnessKey :: ByteString
targetScript = bytesOf 28 0x70
refundVkey = bytesOf 28 0x72
witnessKey = bytesOf 32 0x90

aidAssetName :: ByteString
aidAssetName = deriveAidAssetName cesrAid

-- | A 2-of-3 source, so one signature is genuinely below quorum.
sourceDatum :: CheckpointDatumV1
sourceDatum =
    CheckpointDatumV1
        { cdCesrAid = cesrAid
        , cdCurKeys = map verkeyOf [controller0, controller1, controller2]
        , cdCurThreshold = Unweighted 2
        , cdNextKeys = [bytesOf 32 0xd0, bytesOf 32 0xd1]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = [witnessKey]
        , cdToad = 1
        , cdSeq = 7
        , cdNativeSn = 4
        }

sourceStateData :: Data
sourceStateData = let BuiltinData d = toBuiltinData (V1 sourceDatum) in d

sourceRef, mutantRef :: OutputRef
sourceRef = OutputRef sourceTxid 1
mutantRef = OutputRef mutantTxid 1

sourceOrigin :: MigrationOrigin
sourceOrigin = MigrationOrigin (ValidatorVersion 1) sourcePolicy sourceRef

targetAddress, refundAddress :: FullAddress
targetAddress =
    FullAddress
        (ScriptCredential targetScript)
        (Just (InlineStakeCredential (ScriptCredential targetScript)))
refundAddress = FullAddress (VerificationKeyCredential refundVkey) Nothing

migrationTarget :: MigrationTarget
migrationTarget =
    MigrationTarget
        { mtTargetVersion = ValidatorVersion 2
        , mtTargetPolicy = targetPolicy
        , mtTargetRole = CheckpointActive
        , mtTargetAddress = targetAddress
        , mtLegacyRefundAddress = Nothing
        }

source :: MigrationSource
source =
    MigrationSource
        { msNetworkId = 1
        , msSourceVersion = ValidatorVersion 1
        , msSourcePolicy = sourcePolicy
        , msSourceRef = sourceRef
        , msSourceRole = CheckpointActive
        , msSourceState = sourceStateData
        }

goldenBytes :: ByteString
goldenBytes = encodeMigrationMessage source migrationTarget

sig0Pair, sig1Pair :: (Integer, ByteString)
sig0Pair = (0, signOver controller0 goldenBytes)
sig1Pair = (1, signOver controller1 goldenBytes)

quorum :: [(Integer, ByteString)]
quorum = [sig0Pair, sig1Pair]

authorization :: MigrationAuthorization
authorization =
    MigrationAuthorization
        { maDomain = migrationDomain
        , maNetworkId = 1
        , maSourceOrigin = sourceOrigin
        , maSourceRole = CheckpointActive
        , maSourceState = sourceStateData
        , maTarget = migrationTarget
        , maControllerSignatures = quorum
        }

pinned :: Predecessor
pinned = Predecessor (ValidatorVersion 1) sourcePolicy

-- | The successor record, in the exact wire layout the decoder reads.
successorData :: Integer -> Maybe MigrationOrigin -> Data
successorData version origin =
    Constr
        0
        [ Constr 0 [I version]
        , maybe (Constr 1 []) (\o -> Constr 0 [originTree o]) origin
        , sourceStateData
        ]
  where
    originTree MigrationOrigin{..} =
        Constr
            0
            [ Constr 0 [I (vvValue moSourceVersion)]
            , B moSourcePolicy
            , Constr
                0
                [B (orTransactionId moSourceRef), I (orOutputIndex moSourceRef)]
            ]

protectedLovelace :: Integer
protectedLovelace = 8_000_000

valueWith :: ByteString -> Integer -> MigrationValue
valueWith policy lovelace =
    Map.fromList [(lovelaceKey, lovelace), ((policy, aidAssetName), 1)]

sourceInput :: MigrationInput
sourceInput =
    MigrationInput
        { miRef = sourceRef
        , miAddress = targetAddress
        , miValue = valueWith sourcePolicy protectedLovelace
        , miDatum = Just sourceStateData
        }

successorOutput :: MigrationOutput
successorOutput =
    MigrationOutput
        { moAddress = targetAddress
        , moValue = valueWith targetPolicy protectedLovelace
        , moDatum = Just (successorData 2 (Just sourceOrigin))
        }

-- | The burn\/mint pair of a correct permanent-family move.
replacementMint :: MigrationValue
replacementMint =
    Map.fromList
        [((sourcePolicy, aidAssetName), -1), ((targetPolicy, aidAssetName), 1)]

migrateInTx :: MigrationTx
migrateInTx =
    MigrationTx
        { mtxNetworkId = 1
        , mtxInputs = [sourceInput]
        , mtxOutputs = [successorOutput]
        , mtxMint = replacementMint
        }

migrateOutTx :: MigrationTx
migrateOutTx =
    migrateInTx
        { mtxMint = Map.fromList [((sourcePolicy, aidAssetName), -1)]
        }

accepted :: MigrationVerdict -> Bool
accepted = (== Right ())

-- ---------------------------------------------------------
-- Legacy bridge fixtures
-- ---------------------------------------------------------

legacyPolicy :: ByteString
legacyPolicy = lcPolicy preprodV0

legacyTarget :: MigrationTarget
legacyTarget =
    migrationTarget
        { mtTargetVersion = ValidatorVersion 1
        , mtLegacyRefundAddress = Just refundAddress
        }

legacySource :: MigrationSource
legacySource =
    source
        { msNetworkId = lcNetworkId preprodV0
        , msSourceVersion = lcVersion preprodV0
        , msSourcePolicy = legacyPolicy
        }

legacyOrigin :: MigrationOrigin
legacyOrigin = MigrationOrigin (ValidatorVersion 0) legacyPolicy sourceRef

legacyAuthorization :: MigrationAuthorization
legacyAuthorization =
    authorization
        { maNetworkId = lcNetworkId preprodV0
        , maSourceOrigin = legacyOrigin
        , maTarget = legacyTarget
        , maControllerSignatures =
            [ (0, signOver controller0 legacyBytes)
            , (1, signOver controller1 legacyBytes)
            ]
        }
  where
    legacyBytes = encodeMigrationMessage legacySource legacyTarget

legacyClose :: LegacyCloseEvidence
legacyClose =
    LegacyCloseEvidence
        { lceRefundAddress = refundAddress
        , lceRefundLovelace = protectedLovelace
        , lceBurnedAssetName = aidAssetName
        }

{- | The legacy transaction.  The refunded value leaves to the refund address
and the successor is capitalized __independently__ with equal protected
lovelace — a recapitalization, not a transfer of the refunded ada.
-}
legacySuccessorOutput, legacyRefundOutput :: MigrationOutput
legacySuccessorOutput =
    successorOutput{moDatum = Just (successorData 1 (Just legacyOrigin))}
legacyRefundOutput =
    MigrationOutput
        { moAddress = refundAddress
        , moValue = Map.fromList [(lovelaceKey, protectedLovelace)]
        , moDatum = Nothing
        }

legacyTx :: MigrationTx
legacyTx =
    MigrationTx
        { mtxNetworkId = lcNetworkId preprodV0
        , mtxInputs =
            [sourceInput{miValue = valueWith legacyPolicy protectedLovelace}]
        , mtxOutputs = [legacySuccessorOutput, legacyRefundOutput]
        , mtxMint =
            Map.fromList
                [ ((legacyPolicy, aidAssetName), -1)
                , ((targetPolicy, aidAssetName), 1)
                ]
        }

runLegacy :: MigrationAuthorization -> MigrationTx -> MigrationVerdict
runLegacy auth =
    validateLegacyCheckpointMigrateIn preprodV0 sourceRef legacyClose auth targetPolicy

-- ---------------------------------------------------------
-- Spec
-- ---------------------------------------------------------

spec :: Spec
spec = describe "checkpoint migration" $ do
    describe "canonical message" $ do
        it "carries the frozen domain separator" $
            mmDomain (migrationMessage source migrationTarget)
                `shouldBe` migrationDomain

        it "binds every redirectable field" $ do
            let redirections =
                    [ encodeMigrationMessage source{msNetworkId = 0} migrationTarget
                    , encodeMigrationMessage source{msSourceRef = mutantRef} migrationTarget
                    , encodeMigrationMessage
                        source{msSourceRole = CheckpointFrozen}
                        migrationTarget
                    , encodeMigrationMessage
                        source
                        migrationTarget{mtTargetPolicy = sourcePolicy}
                    , encodeMigrationMessage
                        source
                        migrationTarget{mtLegacyRefundAddress = Just refundAddress}
                    ]
            mapM_ (`shouldNotBe` goldenBytes) redirections

    describe "controller authority" $ do
        it "accepts the source's own current quorum" $
            checkpointMigrationAuthorized
                sourceDatum
                (migrationMessage source migrationTarget)
                quorum
                `shouldBe` Right ()

        it "refuses every named authority shortfall" $ do
            let message = migrationMessage source migrationTarget
                refuse signatures =
                    checkpointMigrationAuthorized sourceDatum message signatures
                        `shouldBe` Left MigrationQuorumUnsatisfied
            refuse []
            refuse [sig0Pair]
            refuse [sig0Pair, (1, signOver foreigner goldenBytes)]
            refuse [sig0Pair, sig0Pair]
            refuse [sig0Pair, (9, signOver controller2 goldenBytes)]

        it "refuses a real signature made over a redirected message" $ do
            let elsewhere =
                    encodeMigrationMessage source{msSourceRef = mutantRef} migrationTarget
                replayed =
                    [(0, signOver controller0 elsewhere), (1, signOver controller1 goldenBytes)]
            checkpointMigrationAuthorized
                sourceDatum
                (migrationMessage source migrationTarget)
                replayed
                `shouldBe` Left MigrationQuorumUnsatisfied

    describe "family edge" $ do
        it "accepts exactly the successor generation and refuses a skip" $ do
            let edge v =
                    validMigrationEdge
                        source
                        (MigrationSuccessor (ValidatorVersion v) targetPolicy (Just sourceOrigin) CheckpointActive)
                        pinned
            edge 2 `shouldBe` Right ()
            edge 3 `shouldBe` Left MigrationVersionNotSuccessor

        it "refuses a foreign predecessor and a wrong or absent origin" $ do
            let successorWith origin =
                    MigrationSuccessor (ValidatorVersion 2) targetPolicy origin CheckpointActive
            validMigrationEdge source (successorWith (Just sourceOrigin)) pinned
                `shouldBe` Right ()
            validMigrationEdge
                source
                (successorWith (Just sourceOrigin))
                pinned{pdPredecessorPolicy = legacyPolicy}
                `shouldBe` Left MigrationForeignPredecessor
            validMigrationEdge
                source
                (successorWith (Just sourceOrigin{moSourceRef = mutantRef}))
                pinned
                `shouldBe` Left MigrationOriginMismatch
            validMigrationEdge source (successorWith Nothing) pinned
                `shouldBe` Left MigrationOriginMismatch

    describe "identity, role and value continuity" $ do
        let active d = CheckpointRoleState CheckpointActive d Nothing Nothing
            replacement successorValue =
                PolicyReplacement
                    { prSourcePolicy = sourcePolicy
                    , prTargetPolicy = targetPolicy
                    , prAssetName = aidAssetName
                    , prSourceValue = valueWith sourcePolicy protectedLovelace
                    , prSuccessorValue = successorValue
                    }
            good = valueWith targetPolicy protectedLovelace

        it "preserves the KEL projection exactly" $ do
            checkpointTransitionContinuous
                (active sourceDatum)
                (active sourceDatum)
                (replacement good)
                `shouldBe` Right ()
            checkpointTransitionContinuous
                (active sourceDatum)
                (active sourceDatum{cdSeq = 8})
                (replacement good)
                `shouldBe` Left MigrationIdentityChanged

        it "refuses an invented role payload" $
            checkpointTransitionContinuous
                (active sourceDatum)
                (CheckpointRoleState CheckpointActive sourceDatum (Just refundVkey) (Just 99))
                (replacement good)
                `shouldBe` Left MigrationRoleChanged

        it "admits only the one policy-token replacement" $ do
            let skimmed = valueWith targetPolicy (protectedLovelace - 1_000_000)
                retained = Map.insert (sourcePolicy, aidAssetName) 1 good
            checkpointTransitionContinuous (active sourceDatum) (active sourceDatum) (replacement good)
                `shouldBe` Right ()
            checkpointTransitionContinuous (active sourceDatum) (active sourceDatum) (replacement skimmed)
                `shouldBe` Left MigrationValueChanged
            checkpointTransitionContinuous (active sourceDatum) (active sourceDatum) (replacement retained)
                `shouldBe` Left MigrationValueChanged

    describe "migrate-out arm" $ do
        it "accepts a controller-authorized exit and refuses a missing source" $ do
            validateCheckpointMigrateOut 1 authorization sourceRef migrateOutTx
                `shouldBe` Right ()
            validateCheckpointMigrateOut 1 authorization mutantRef migrateOutTx
                `shouldBe` Left MigrationSourceMissing

        it "refuses an applied version that is not the source generation" $
            validateCheckpointMigrateOut 2 authorization sourceRef migrateOutTx
                `shouldBe` Left MigrationAppliedVersionMismatch

        it "refuses an exit that does not burn the source token" $
            validateCheckpointMigrateOut
                1
                authorization
                sourceRef
                migrateOutTx{mtxMint = Map.empty}
                `shouldBe` Left MigrationTokenTransitionInvalid

    describe "migrate-in arm" $ do
        it "accepts the pinned-predecessor entry" $
            validateCheckpointMigrateIn 2 pinned sourceRef authorization targetPolicy migrateInTx
                `shouldBe` Right ()

        it "stays accepted whoever relays it" $ do
            -- Authorization is data: there is no submitter field to vary, so
            -- the standing proof is that acceptance depends on nothing but
            -- the package and the observed transaction.
            let relayed = migrateInTx{mtxInputs = mtxInputs migrateInTx}
            validateCheckpointMigrateIn 2 pinned sourceRef authorization targetPolicy relayed
                `shouldSatisfy` accepted

        it "refuses a foreign predecessor pin" $
            validateCheckpointMigrateIn
                2
                pinned{pdPredecessorPolicy = legacyPolicy}
                sourceRef
                authorization
                targetPolicy
                migrateInTx
                `shouldBe` Left MigrationForeignPredecessor

        it "refuses a duplicated successor" $
            validateCheckpointMigrateIn
                2
                pinned
                sourceRef
                authorization
                targetPolicy
                migrateInTx{mtxOutputs = [successorOutput, successorOutput]}
                `shouldBe` Left MigrationAmbiguousSuccessor

        it "refuses a successor whose applied version disagrees with its datum" $
            validateCheckpointMigrateIn 3 pinned sourceRef authorization targetPolicy migrateInTx
                `shouldBe` Left MigrationAppliedVersionMismatch

        it "refuses a mint that is not the one-for-one replacement" $
            validateCheckpointMigrateIn
                2
                pinned
                sourceRef
                authorization
                targetPolicy
                migrateInTx
                    { mtxMint = Map.insert (targetPolicy, aidAssetName) 2 replacementMint
                    }
                `shouldBe` Left MigrationTokenTransitionInvalid

    describe "legacy preprod v0 bridge" $ do
        it "accepts the exact committed v0 ACTIVE source" $
            runLegacy legacyAuthorization legacyTx `shouldBe` Right ()

        it "refuses a v0 row that is not ACTIVE" $ do
            -- v0 ARMED and FROZEN have no authorized exit at all, so they
            -- block the cutover rather than being rewritten.
            let armed = legacyAuthorization{maSourceRole = CheckpointArmed}
                frozen = legacyAuthorization{maSourceRole = CheckpointFrozen}
            runLegacy armed legacyTx `shouldBe` Left MigrationLegacyRoleUnsupported
            runLegacy frozen legacyTx `shouldBe` Left MigrationLegacyRoleUnsupported

        it "refuses a source that is not the committed v0 family" $
            runLegacy
                legacyAuthorization
                    { maSourceOrigin = legacyOrigin{moSourcePolicy = sourcePolicy}
                    }
                legacyTx
                `shouldBe` Left MigrationLegacyIdentityMismatch

        it "requires the legacy refund to be exact" $
            runLegacy
                legacyAuthorization
                legacyTx
                    { mtxOutputs =
                        [ legacySuccessorOutput
                        , MigrationOutput
                            refundAddress
                            (Map.fromList [(lovelaceKey, protectedLovelace - 1)])
                            Nothing
                        ]
                    }
                `shouldBe` Left MigrationLegacyRefundMismatch

        it "capitalizes the successor with equal protected lovelace" $ do
            -- The successor is funded independently; short-funding it is not
            -- excused by the refund having been paid.
            let short =
                    legacyTx
                        { mtxOutputs =
                            [ legacySuccessorOutput
                                { moValue =
                                    valueWith targetPolicy (protectedLovelace - 1_000_000)
                                }
                            , legacyRefundOutput
                            ]
                        }
            runLegacy legacyAuthorization short `shouldBe` Left MigrationValueChanged
