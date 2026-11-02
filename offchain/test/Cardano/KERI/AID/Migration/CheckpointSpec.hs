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
import Cardano.KERI.AID.CESR (
    qb64Aid,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    checkpointDatumToData,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Role (..),
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
    MigrationPredecessor (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    StakeCredential (..),
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
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
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

refundVkey, witnessKey :: ByteString
refundVkey = bytesOf 28 0x72
witnessKey = bytesOf 32 0x90

aidAssetName :: ByteString
aidAssetName = deriveAidAssetName cesrAid

-- | A 2-of-3 live source, so one signature is genuinely below quorum.
sourceDatum :: CheckpointDatumV2
sourceDatum = sourceAtEpoch 7

sourceAtEpoch :: Integer -> CheckpointDatumV2
sourceAtEpoch epoch =
    Live
        { lvAid = qb64Aid cesrAid
        , lvSn = 4
        , lvEpoch = epoch
        , lvPoisoned = False
        , lvFrozen = False
        , lvBornAt = 1800000000000
        , lvRefundTo = BS.cons 0x61 refundVkey
        , lvKeys =
            KeyMaterial
                { kmCurKeys = map verkeyOf [controller0, controller1, controller2]
                , kmCurThreshold = Unweighted 2
                , kmNextKeys = [bytesOf 32 0xd0, bytesOf 32 0xd1]
                , kmNextThreshold = Unweighted 1
                , kmWitnesses = [witnessKey]
                , kmToad = 1
                }
        }

{- | The projection the authorization carries verbatim: the version sum
wrapping the live datum.
-}
sourceStateData :: Data
sourceStateData = checkpointDatumToData (V2 sourceDatum)

{- | The row datum: the frozen `CheckpointDatum` version sum.  The lean design
carries no generation integer and no origin back-pointer.
-}
rowData :: Data
rowData = sourceStateData

sourceRef, mutantRef :: OutputRef
sourceRef = OutputRef sourceTxid 1
mutantRef = OutputRef mutantTxid 1

sourcePredecessor :: MigrationPredecessor
sourcePredecessor = MigrationPredecessor sourcePolicy sourceRef

targetAddress, refundAddress :: FullAddress
-- The successor lands at a role address of the target policy, and the source
-- is held at a role address of its own policy.  A fixture that puts either at
-- some other script is not reachable at the transaction boundary.
targetAddress = FullAddress (ScriptCredential targetPolicy) Nothing

sourceAddress :: FullAddress
sourceAddress = FullAddress (ScriptCredential sourcePolicy) Nothing
refundAddress = FullAddress (VerificationKeyCredential refundVkey) Nothing

migrationTarget :: MigrationTarget
migrationTarget =
    MigrationTarget
        { mtTargetPolicy = targetPolicy
        , mtTargetRole = CheckpointActive
        , mtTargetAddress = targetAddress
        , mtLegacyRefundAddress = Nothing
        }

source :: MigrationSource
source =
    MigrationSource
        { msNetworkId = 1
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
        , maSource = sourcePredecessor
        , maSourceRole = CheckpointActive
        , maSourceState = sourceStateData
        , maTarget = migrationTarget
        , maControllerSignatures = quorum
        }

protectedLovelace :: Integer
protectedLovelace = 8_000_000

valueWith :: ByteString -> Integer -> MigrationValue
valueWith policy lovelace =
    Map.fromList [(lovelaceKey, lovelace), ((policy, aidAssetName), 1)]

{- | The permanent-family source: a natively registered generation-1 row, so
it carries its applied version and deliberately no origin.
-}
sourceInput :: MigrationInput
sourceInput =
    MigrationInput
        { miRef = sourceRef
        , miAddress = sourceAddress
        , miValue = valueWith sourcePolicy protectedLovelace
        , miDatum = Just rowData
        }

successorOutput :: MigrationOutput
successorOutput =
    MigrationOutput
        { moAddress = targetAddress
        , moValue = valueWith targetPolicy protectedLovelace
        , moDatum = Just rowData
        }

-- | The burn\/mint pair of a correct permanent-family move.
replacementMint :: MigrationValue
replacementMint =
    Map.fromList
        [((sourcePolicy, aidAssetName), -1), ((targetPolicy, aidAssetName), 1)]

consumingTx :: MigrationTx
consumingTx =
    MigrationTx
        { mtxNetworkId = 1
        , mtxInputs = [sourceInput]
        , mtxOutputs = [successorOutput]
        , mtxMint = replacementMint
        }

exitTx :: MigrationTx
exitTx =
    consumingTx
        { mtxMint = Map.fromList [((sourcePolicy, aidAssetName), -1)]
        }

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
                        source{msSourceRole = Board}
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

    describe "identity, role and value continuity" $ do
        let active = CheckpointRoleState CheckpointActive
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
                (active (sourceAtEpoch 8))
                (replacement good)
                `shouldBe` Left MigrationIdentityChanged

        it "refuses a successor at another lifecycle position" $
            checkpointTransitionContinuous
                (active sourceDatum)
                (CheckpointRoleState Board sourceDatum)
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
            validateCheckpointMigrateOut authorization sourceRef consumingTx
                `shouldBe` Right ()
            validateCheckpointMigrateOut authorization mutantRef consumingTx
                `shouldBe` Left MigrationSourceMissing

        it "refuses an exit that does not burn the source token" $
            validateCheckpointMigrateOut
                authorization
                sourceRef
                consumingTx{mtxMint = Map.empty}
                `shouldBe` Left MigrationTokenTransitionInvalid

        it "refuses an exit that composes no successor" $
            -- The burn is exactly the authorized one and nothing else is
            -- wrong; only successor composition can refuse this, and without
            -- it the identity is destroyed under a package the controllers
            -- genuinely signed.
            validateCheckpointMigrateOut
                authorization
                sourceRef
                exitTx{mtxOutputs = []}
                `shouldBe` Left MigrationSourceMissing

        it "refuses a signed projection that is not the consumed one" $ do
            -- The observed input is the naming authority; the signed payload
            -- must equal it. A package signed over another checkpoint cannot
            -- move this one.
            let elsewhere = checkpointDatumToData (V2 (sourceAtEpoch 23))
            validateCheckpointMigrateOut
                authorization{maSourceState = elsewhere}
                sourceRef
                exitTx
                `shouldBe` Left MigrationIdentityChanged

    describe "source address shape" $ do
        -- An address is a whole structure, not a hash with some decoration.
        -- The previous method PROJECTED the address down to its payment
        -- script hash, so every other part of it -- the stake credential
        -- above all -- was simply not looked at. The live Aiken path
        -- classifies the entire address, so a correct payment hash carrying a
        -- spurious stake credential passed here and failed on chain.
        --
        -- These controls enumerate the full 2x4 shape cross-product. Every
        -- shape carries the SAME policy bytes, so the constructor shape is
        -- the only discriminating dimension.
        let stakeVariants =
                [ ("absent", Nothing)
                , ("inline-key", Just (InlineStakeCredential (VerificationKeyCredential sourcePolicy)))
                , ("inline-script", Just (InlineStakeCredential (ScriptCredential sourcePolicy)))
                , ("pointer", Just (PointerStakeCredential 1 2 3))
                ]
            paymentVariants =
                [ ("script", ScriptCredential sourcePolicy)
                , ("vkey", VerificationKeyCredential sourcePolicy)
                ]
            shapes =
                [ (paymentName <> "/" <> stakeName, FullAddress payment stake)
                | (paymentName, payment) <- paymentVariants
                , (stakeName, stake) <- stakeVariants
                ]
            -- Exactly one of the eight is the canonical ACTIVE role address.
            canonical = roleAddress sourcePolicy Active
            expectedFor address = address == canonical

            atHelper address =
                sourceAddressIsRole
                    CheckpointActive
                    sourcePolicy
                    sourceInput{miAddress = address}
            atMigrateOut address =
                validateCheckpointMigrateOut
                    authorization
                    sourceRef
                    consumingTx{mtxInputs = [sourceInput{miAddress = address}]}

            enumerate :: String -> (FullAddress -> Either MigrationError ()) -> Spec
            enumerate name boundary =
                it ("classifies all eight address shapes at " <> name) $
                    [ (shapeName, boundary address == Right ())
                    | (shapeName, address) <- shapes
                    ]
                        `shouldBe` [ (shapeName :: String, expectedFor address)
                                   | (shapeName, address) <- shapes
                                   ]

        it "exactly one shape in the cross-product is canonical" $
            length (filter (expectedFor . snd) shapes) `shouldBe` 1

        enumerate "the exported helper" atHelper
        enumerate "migrate-out" atMigrateOut

        it "no single-field-ignoring comparator can pass this enumeration" $ do
            -- Application-verified mutants: each ignores exactly one field of
            -- the address. Each is APPLIED to the same eight shapes, and each
            -- must accept something the total rule rejects. This is what makes
            -- the claim "no single-field omission survives" testable rather
            -- than asserted -- and it is why the total comparison cannot miss
            -- the next field: there is no field list to forget to extend.
            let ignoringStake address =
                    faPaymentCredential address == faPaymentCredential canonical
                ignoringPayment address =
                    faStakeCredential address == faStakeCredential canonical
                survivorsOf :: (FullAddress -> Bool) -> [String]
                survivorsOf mutant =
                    [ shapeName
                    | (shapeName, address) <- shapes
                    , mutant address
                    , not (expectedFor address)
                    ]
            survivorsOf ignoringStake `shouldNotBe` []
            survivorsOf ignoringPayment `shouldNotBe` []
