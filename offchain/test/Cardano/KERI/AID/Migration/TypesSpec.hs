module Cardano.KERI.AID.Migration.TypesSpec (
    spec,
) where

import Cardano.KERI.AID.Migration.Types (
    AddressCredential (..),
    FullAddress (..),
    MigrationAuthorization (..),
    MigrationPredecessor (..),
    MigrationRole (..),
    MigrationTarget (..),
    OutputRef (..),
    StakeCredential (..),
    canonicalCbor,
    migrationDomain,
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.List (
    nub,
 )
import Data.Text.Encoding qualified as TE
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
    ToData (..),
    fromBuiltinData,
    toBuiltinData,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
 )
import Test.QuickCheck (
    Gen,
    elements,
    forAll,
    listOf1,
    oneof,
    vectorOf,
    (===),
 )

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

-- | The canonical Plutus 'Data' tree behind a value.
dataOf :: (ToData a) => a -> Data
dataOf x = let BuiltinData d = toBuiltinData x in d

-- | A strict 'ByteString' from an ASCII hex literal.
hexBs :: ByteString -> ByteString
hexBs s = either error id (convertFromBase Base16 s)

-- | A fixed-width value of a single repeated byte.
bytesOf :: Int -> Word8 -> ByteString
bytesOf = BS.replicate

{- | The opaque state field of an authorization tree, or 'Nothing' if it is
not at the fifth position of the outer record.
-}
stateField :: Data -> Maybe Data
stateField = \case
    Constr 0 [_, _, _, _, state, _, _] -> Just state
    _ -> Nothing

wordBoundary :: Integer
wordBoundary = toInteger (maxBound :: Int) + 1

{- | An authorization __wire tree__ carrying @n@ at every integer position, built
from 'Data' rather than the record types: a value-first round-trip cannot observe
a type too narrow to hold what the wire carries.  Extreme values assert fidelity.
-}
wireWith :: Integer -> Data
wireWith n =
    Constr 0 [B migrationDomain, I n, origin', Constr 1 [], sourceState, target', sigs]
  where
    origin' = Constr 0 [B sourcePolicy, Constr 0 [B sourceTxid, I n]]
    target' = Constr 0 [B targetPolicy, Constr 0 [], address, Constr 1 []]
    address =
        Constr 0 [Constr 1 [B paymentScript], Constr 0 [Constr 1 [I n, I n, I n]]]
    sigs = List [List [I n, B sigA]]

-- | Decode a wire tree and re-encode it; anything but the original tree is loss.
wireRoundTrip :: Data -> Maybe Data
wireRoundTrip tree =
    dataOf <$> (fromBuiltinData (BuiltinData tree) :: Maybe MigrationAuthorization)

-- ---------------------------------------------------------
-- Fixtures (the same material the vector generator uses)
-- ---------------------------------------------------------

sourcePolicy, targetPolicy, sourceTxid, mutantTxid :: ByteString
sourcePolicy = bytesOf 28 0x50
targetPolicy = bytesOf 28 0x51
sourceTxid = bytesOf 32 0x60
mutantTxid = bytesOf 32 0x61

paymentScript, stakeScript, refundVkey :: ByteString
paymentScript = bytesOf 28 0x70
stakeScript = bytesOf 28 0x71
refundVkey = bytesOf 28 0x72

sigA, sigB, mutantDomain :: ByteString
sigA = bytesOf 64 0x80
sigB = bytesOf 64 0x81
mutantDomain = TE.encodeUtf8 "cardano-keri/migration/v0"

{- | The opaque source state: a version-wrapped record the protocol layer
carries verbatim and never interprets.
-}
sourceState, mutantSourceState :: Data
sourceState = stateWith 0
mutantSourceState = stateWith 1

stateWith :: Integer -> Data
stateWith counter =
    Constr
        0
        [ Constr
            0
            [ B (bytesOf 32 0xaa)
            , List [B (bytesOf 32 0x01)]
            , Constr 0 [I 1]
            , I counter
            ]
        ]

sourceRef :: OutputRef
sourceRef = OutputRef{orTransactionId = sourceTxid, orOutputIndex = 3}

predecessor :: MigrationPredecessor
predecessor =
    MigrationPredecessor
        { mpPredecessorPolicy = sourcePolicy
        , mpPredecessorRef = sourceRef
        }

targetAddress, refundAddress :: FullAddress
targetAddress =
    FullAddress
        { faPaymentCredential = ScriptCredential paymentScript
        , faStakeCredential =
            Just (InlineStakeCredential (ScriptCredential stakeScript))
        }
refundAddress =
    FullAddress
        { faPaymentCredential = VerificationKeyCredential refundVkey
        , faStakeCredential = Nothing
        }

migrationTarget :: MigrationTarget
migrationTarget =
    MigrationTarget
        { mtTargetPolicy = targetPolicy
        , mtTargetRole = CheckpointActive
        , mtTargetAddress = targetAddress
        , mtLegacyRefundAddress = Just refundAddress
        }

{- | The golden authorization. Its source role deliberately differs from its
target role so that swapping the two positions is observable; whether they
must be equal is a later validation rule, not a wire-shape rule.
-}
authorization :: MigrationAuthorization
authorization =
    MigrationAuthorization
        { maDomain = migrationDomain
        , maNetworkId = 1
        , maSource = predecessor
        , maSourceRole = CheckpointFrozen
        , maSourceState = sourceState
        , maTarget = migrationTarget
        , maControllerSignatures = [(0, sigA), (2, sigB)]
        }

{- | One mutation per redirectable field, in the same order as the generator
and the Aiken suite.
-}
mutations :: [MigrationAuthorization]
mutations =
    [ authorization{maDomain = mutantDomain}
    , authorization{maNetworkId = 0}
    , withPredecessor predecessor{mpPredecessorPolicy = targetPolicy}
    , withPredecessor predecessor{mpPredecessorRef = sourceRef{orTransactionId = mutantTxid}}
    , withPredecessor predecessor{mpPredecessorRef = sourceRef{orOutputIndex = 4}}
    , authorization{maSourceRole = Board}
    , authorization{maSourceState = mutantSourceState}
    , withTarget migrationTarget{mtTargetPolicy = sourcePolicy}
    , withTarget migrationTarget{mtTargetRole = CheckpointFrozen}
    , withTarget
        migrationTarget{mtTargetAddress = targetAddress{faStakeCredential = Nothing}}
    , withTarget migrationTarget{mtLegacyRefundAddress = Nothing}
    , authorization{maControllerSignatures = [(1, sigA), (2, sigB)]}
    , authorization{maControllerSignatures = [(2, sigB), (0, sigA)]}
    ]
  where
    withPredecessor value = authorization{maSource = value}
    withTarget value = authorization{maTarget = value}

-- ---------------------------------------------------------
-- Generators (standalone, no Arbitrary instances)
-- ---------------------------------------------------------

genBytes :: Int -> Gen ByteString
genBytes width = BS.pack <$> vectorOf width (elements [0x00, 0x01, 0xfe])

-- | Boundaries a machine word would mangle; submission 1 drew only @0..2@.
genWideInteger :: Gen Integer
genWideInteger = elements (small <> wide <> map negate wide)
  where
    small = [0, 1, 2, 7, -1, 2 ^ (127 :: Int)]
    wide = [wordBoundary - 1, wordBoundary, wordBoundary + 1, 2 * wordBoundary]

genRole :: Gen MigrationRole
genRole = elements [CheckpointActive, CheckpointFrozen, CheckpointArmed, Board]

genCredential :: Gen AddressCredential
genCredential =
    oneof
        [ VerificationKeyCredential <$> genBytes 28
        , ScriptCredential <$> genBytes 28
        ]

genAddress :: Gen FullAddress
genAddress =
    FullAddress
        <$> genCredential
        <*> oneof
            [ pure Nothing
            , Just . InlineStakeCredential <$> genCredential
            , Just <$> (PointerStakeCredential <$> wide <*> wide <*> wide)
            ]
  where
    wide = genWideInteger

genPredecessor :: Gen MigrationPredecessor
genPredecessor =
    MigrationPredecessor
        <$> genBytes 28
        <*> (OutputRef <$> genBytes 32 <*> genWideInteger)

genTarget :: Gen MigrationTarget
genTarget =
    MigrationTarget
        <$> genBytes 28
        <*> genRole
        <*> genAddress
        <*> oneof [pure Nothing, Just <$> genAddress]

genAuthorization :: Gen MigrationAuthorization
genAuthorization =
    MigrationAuthorization migrationDomain
        <$> genWideInteger
        <*> genPredecessor
        <*> genRole
        <*> (stateWith <$> genWideInteger)
        <*> genTarget
        <*> listOf1 ((,) <$> genWideInteger <*> genBytes 64)

-- ---------------------------------------------------------
-- Spec
-- ---------------------------------------------------------

spec :: Spec
spec = do
    describe "migration types: frozen domain and primitive wire shapes" $ do
        it "the domain is the exact UTF-8 protocol string" $
            migrationDomain
                `shouldBe` hexBs "63617264616e6f2d6b6572692f6d6967726174696f6e2f7631"
        it "the four migration roles are Constr 0..3 with no fields" $
            map dataOf [CheckpointActive, CheckpointFrozen, CheckpointArmed, Board]
                `shouldBe` [Constr 0 [], Constr 1 [], Constr 2 [], Constr 3 []]
        it "the roles encode to independently derived bytes" $
            map
                canonicalCbor
                [CheckpointActive, CheckpointFrozen, CheckpointArmed, Board]
                `shouldBe` map hexBs ["d87980", "d87a80", "d87b80", "d87c80"]

    describe "migration types: frozen field order" $ do
        it "a predecessor is the policy, then the exact spent reference" $
            -- No generation: release identity is the applied hash, and the
            -- spend itself is the lineage edge.
            dataOf predecessor
                `shouldBe` Constr
                    0
                    [ B sourcePolicy
                    , Constr 0 [B sourceTxid, I 3]
                    ]
        it "a target is policy, role, address, optional refund" $
            dataOf migrationTarget
                `shouldBe` Constr
                    0
                    [ B targetPolicy
                    , Constr 0 []
                    , Constr
                        0
                        [ Constr 1 [B paymentScript]
                        , Constr 0 [Constr 0 [Constr 1 [B stakeScript]]]
                        ]
                    , Constr 0 [dataOf refundAddress]
                    ]
        it "an authorization carries every redirectable field at its own position" $
            dataOf authorization
                `shouldBe` Constr
                    0
                    [ B migrationDomain
                    , I 1
                    , dataOf predecessor
                    , Constr 1 []
                    , sourceState
                    , dataOf migrationTarget
                    , List [List [I 0, B sigA], List [I 2, B sigB]]
                    ]
        it "the source state is embedded verbatim, never re-encoded" $
            stateField (dataOf authorization) `shouldBe` Just sourceState

    describe "migration types: named field mutations stay distinguishable" $ do
        it "no mutation collides with the golden or with another mutation" $
            let encodings = map canonicalCbor (authorization : mutations)
             in (length encodings, length (nub encodings)) `shouldBe` (14, 14)
        it "dropping the legacy refund changes the target bytes" $
            canonicalCbor migrationTarget
                `shouldNotBe` canonicalCbor
                    migrationTarget{mtLegacyRefundAddress = Nothing}

    describe "migration types: nothing is lost on the wire" $ do
        it "the reported counterexample index round-trips to itself" $
            wireRoundTrip (wireWith wordBoundary) `shouldBe` Just (wireWith wordBoundary)
        it "a machine-word alias of that index is a different wire value" $
            wireRoundTrip (wireWith wordBoundary)
                `shouldNotBe` Just (wireWith (negate wordBoundary))
        it "every integer position preserves any wire integer exactly" $
            forAll genWideInteger $ \n ->
                wireRoundTrip (wireWith n) === Just (wireWith n)
        it "an authorization round-trips through Plutus Data" $
            forAll genAuthorization $ \value ->
                fromBuiltinData (toBuiltinData value) === Just value
        it "a target round-trips through Plutus Data" $
            forAll genTarget $ \value ->
                fromBuiltinData (toBuiltinData value) === Just value
        it "an origin round-trips through Plutus Data" $
            forAll genPredecessor $ \value ->
                fromBuiltinData (toBuiltinData value) === Just value
