{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.AdvanceAttestationBoundarySpec
Description : the two-policy advance, as the ledger evaluates it

The Aiken tests run the validators' source through the Aiken evaluator over
transactions written in Aiken. These examples run the /applied programs of the
production derivation/ (the fact policy, the change policy applied to it, and the
checkpoint applied to the change policy) through the Plutus ledger evaluator, over
a version 3 script context written as Plutus Data by "Cardano.KERI.Deployment.LedgerContext",
which shares nothing with the Aiken fixtures. The datums, the evidence and the signed
fact are the Plutus Data trees of the committed advance vectors
(@advance-split-cases.json@, the input of the independent generator
@scripts/advance-split-vectors.mjs@); the names and the redeemers are built with
the library's encoders ("Cardano.KERI.AID.Checkpoint.AdvanceAttestation").

Each story is an accepted transaction beside refused neighbours that differ by one
thing, for each of the three programs:

* the fact policy: the signed fact minted once, against a surplus, empty or doubled
  name, a damaged signature, a missing signature and a Burn that mints;
* the change policy: the claim of a rotation or of a freeze, with its fact asset,
  against a missing fact asset, a wrong successor index, a successor of the wrong
  datum and a claim naming an input that is not spent;
* the checkpoint spend: the advance and the freeze with their change asset minted,
  against the same transaction whose change asset is held by an input and not minted,
  and against a successor index that the attestation does not name.
-}
module Cardano.KERI.Deployment.AdvanceAttestationBoundarySpec (spec) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    Credential (..),
    OutputReference (..),
    RegistryIdentity (..),
    activeTokenName,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.AdvanceAttestation (
    advanceAttestationName,
    changeBurnData,
    changeIssueData,
    factBurnData,
    factIssueData,
    serialisedData,
    signedFactName,
 )
import Cardano.KERI.AID.Checkpoint.Deposit (BondOption (..), DepositIntent (..), depositDomain, depositIntentPreimage)
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceAttestedSpendRedeemerData,
    freezeAttestedSpendRedeemerData,
 )
import Cardano.KERI.Deployment.AdvanceAttestationScripts (
    AdvanceAttestation (..),
    deriveAdvanceAttestation,
    deriveAttestedCheckpoint,
 )
import Cardano.KERI.Deployment.AdvanceVectors (
    Seeds (..),
    Vector (..),
    asText,
    field,
    hexBytes,
    loadSeeds,
    loadVector,
    loadVectorNamed,
    signedBy,
 )
import Cardano.KERI.Deployment.LedgerContext (
    accepted,
    ada,
    input,
    inputAt,
    just,
    mintingContext,
    output,
    spendingContext,
    value,
 )
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.RegistryFixture (fixtureApplicationPolicy, fixtureRegistry)
import Cardano.KERI.Deployment.Script (
    CheckpointTerms (..),
    ScriptArtifact (..),
    attestedBlueprintRefusal,
    blueprintIsAttested,
    deriveV1Scripts,
    loadBlueprint,
    scriptHashBytes,
 )
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (isRight)
import Data.Foldable (for_, toList)
import Data.List (sort)
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import System.Environment (getEnv)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- The registry, the two policies and the checkpoint the derivation produces
-- ---------------------------------------------------------------------------

terms :: RegistryTerms
terms =
    RegistryTerms
        { registryCheckpointTerms =
            CheckpointTerms
                { termsNetwork = 0
                , termsDeposit = 1_000_000_000
                , termsFreezeBond = 5_000_000
                , termsPremium = 2_000_000
                }
        , registryParameters =
            ApplicationParameters
                { registrationCost = 2
                , minimumTip = 1
                , processTime = 5
                , bookingWidth = 1
                }
        , registryMinimumAda = 2_000_000
        , registryTerminationCarrier = 1_000_000
        }

data World = World
    { worldVector :: Vector
    , worldRegistry :: RegistryIdentity
    , worldFact :: ScriptArtifact
    , worldChange :: ScriptArtifact
    , worldCheckpoint :: ScriptArtifact
    }

{- | The registry, its application and the observers come from the deployed
generation's blueprint (@KERI_CHECKPOINT_BLUEPRINT@); the two policies and the
checkpoint that requires their attestation from the current source build
(@KERI_ATTESTED_BLUEPRINT@). The programs the registry's identity depends on are
the same in both builds (see the examples of the two generations).
-}
world :: IO World
world = do
    deployed <- getEnv "KERI_CHECKPOINT_BLUEPRINT" >>= loadBlueprint >>= either fail pure
    blueprint <- getEnv "KERI_ATTESTED_BLUEPRINT" >>= loadBlueprint >>= either fail pure
    scripts <-
        either
            fail
            pure
            ( deriveRegistryScripts
                stateTemplate
                terms
                (OutputReference (BS.replicate 32 0x77) 0)
                deployed
            )
    attestation <- either fail pure (deriveAdvanceAttestation blueprint)
    checkpoint <-
        either
            fail
            pure
            ( deriveAttestedCheckpoint
                (registryCheckpointTerms terms)
                (scriptsRegistry scripts)
                (hashOf (scriptsApplication scripts))
                attestation
                (scriptsObservers scripts)
                blueprint
            )
    vector <- loadVector
    pure
        World
            { worldVector = vector
            , worldRegistry = scriptsRegistry scripts
            , worldFact = attestationFact attestation
            , worldChange = attestationChange attestation
            , worldCheckpoint = checkpoint
            }

hashOf :: ScriptArtifact -> ByteString
hashOf = scriptHashBytes . artifactScriptHash

factPolicy, changePolicy, checkpointPolicy :: World -> ByteString
factPolicy = hashOf . worldFact
changePolicy = hashOf . worldChange
checkpointPolicy = hashOf . worldCheckpoint

-- ---------------------------------------------------------------------------
-- The transactions
-- ---------------------------------------------------------------------------

advanceAction, freezeAction :: Integer
advanceAction = 1
freezeAction = 2

minimumAda, deposit, freezeBond, premium :: Integer
minimumAda = 2_000_000
deposit = 1_000_000_000
freezeBond = 5_000_000
premium = 2_000_000

-- | The lovelace a checkpoint holds beside its pool: unfrozen, and frozen.
floorUnfrozen, floorFrozen :: Integer
floorUnfrozen = minimumAda + deposit + freezeBond
floorFrozen = minimumAda + deposit

type Minted = [(ByteString, [(ByteString, Integer)])]

-- | The token of the vector's checkpoint, one under the registry's state policy.
token :: World -> [(ByteString, [(ByteString, Integer)])]
token w =
    [
        ( registryStatePolicy (worldRegistry w)
        , [(activeTokenName (worldRegistry w) (vectorAid (worldVector w)), 1)]
        )
    ]

spentReference :: World -> (ByteString, Integer)
spentReference w = (vectorTxid (worldVector w), vectorIndex (worldVector w))

spentData :: World -> Data
spentData w = let (txid, index) = spentReference w in Constr 0 [B txid, I index]

-- | The observer envelope of a claim over the vector's checkpoint, with its evidence.
envelope :: World -> Integer -> Data -> Data
envelope w = envelopeOf (checkpointPolicy w) (spentReference w)

-- | The observer envelope of a claim of an action over the spent output of a checkpoint policy.
envelopeOf :: ByteString -> (ByteString, Integer) -> Integer -> Data -> Data
envelopeOf policy (txid, index) action payload =
    Constr
        0
        [ Constr 0 [I action, B policy, just (Constr 0 [B txid, I index])]
        , payload
        ]

changeName :: World -> Integer -> Integer -> ByteString
changeName w action = advanceAttestationName action (checkpointPolicy w) (spentReference w)

factName :: World -> ByteString
factName w = fromMaybe (error "the vector's fact is not a signed fact") (signedFactName (vectorFact (worldVector w)))

-- | An output of the given credential holding the token, the lovelace and the datum.
checkpointOutputAt :: Credential -> World -> Integer -> Data -> Data
checkpointOutputAt credential w lovelace datum =
    output credential (value (ada lovelace <> token w)) (Just datum)

-- | The checkpoint output: at the address of the applied checkpoint.
checkpointOutput :: World -> Integer -> Data -> Data
checkpointOutput w = checkpointOutputAt (ScriptCredential (checkpointPolicy w)) w

paid :: ByteString -> Integer -> Data
paid key lovelace = output (KeyCredential key) (value (ada lovelace)) Nothing

{- | What the transaction mints under the two policies: the change assets of the
claims at the given quantity, names of the change policy that are none of them, and
the fact asset at its quantity (nothing when it is zero).
-}
mintGeneral :: World -> Integer -> [(Integer, Integer)] -> [ByteString] -> Integer -> Minted
mintGeneral w changeQuantity claims extra factQuantity =
    [ (changePolicy w, names)
    | let names =
            [(changeName w action index, changeQuantity) | (action, index) <- claims]
                <> [(e, 1) | e <- extra]
    , not (null names)
    ]
        <> [(factPolicy w, [(factName w, factQuantity)]) | factQuantity /= 0]

-- | What the transaction mints: the change assets of the claims and the fact asset, each once.
mintOf :: World -> [(Integer, Integer)] -> Bool -> Minted
mintOf w claims withFact = mintGeneral w 1 claims [] (if withFact then 1 else 0)

-- | Where the successor and the payee of a transaction sit among its outputs.
data Placement = SuccessorFirst | SuccessorSecond
    deriving stock (Eq)

-- | The output index of the payee (the premium payee or the hunter); the successor sits at the other.
payeeIndex :: Placement -> Integer
payeeIndex SuccessorFirst = 1
payeeIndex SuccessorSecond = 0

data Transaction = Transaction
    { txInputs :: [Data]
    , txOutputs :: [Data]
    , txSpent :: Data
    , txDatum :: Data
    }

placed :: Placement -> Data -> Data -> [Data]
placed SuccessorFirst successor payee = [successor, payee]
placed SuccessorSecond successor payee = [payee, successor]

{- | The rotation of the vector with the given successor output: the spent
checkpoint, the successor and the premium to a payee, in the given placement.
-}
rotationWith :: World -> Placement -> Data -> Transaction
rotationWith w placement successor =
    Transaction
        { txInputs =
            [ inputAt (vectorTxid v) (vectorIndex v) (checkpointOutput w (floorUnfrozen + pool) (vectorOld v))
            ]
        , txOutputs = placed placement successor (paid (BS.replicate 28 0xaa) premium)
        , txSpent = spentData w
        , txDatum = vectorOld v
        }
  where
    v = worldVector w
    pool = 3_000_000

-- | The rotation of the vector, its successor at the checkpoint address.
rotation :: World -> Placement -> Transaction
rotation w placement =
    rotationWith w placement (checkpointOutput w (floorUnfrozen + 3_000_000 - premium) (vectorNew (worldVector w)))

{- | The freeze of the vector with the given successor output: the unfrozen spent
checkpoint, the successor and the bond to the hunter, in the given placement.
-}
freezeWith :: World -> Placement -> Data -> Transaction
freezeWith w placement successor =
    Transaction
        { txInputs =
            [ inputAt (vectorTxid v) (vectorIndex v) (checkpointOutput w (floorUnfrozen + pool) (vectorOld v))
            ]
        , txOutputs = placed placement successor (paid (BS.replicate 28 0xaa) freezeBond)
        , txSpent = spentData w
        , txDatum = vectorOld v
        }
  where
    v = worldVector w
    pool = 1_000_000

-- | The freeze of the vector, its frozen copy at the checkpoint address.
freeze :: World -> Placement -> Transaction
freeze w placement =
    freezeWith w placement (checkpointOutput w (floorFrozen + 1_000_000) (vectorFrozen (worldVector w)))

{- | The transaction with an input of a key holding the change asset of the claim:
the attestation is held, not read from there.
-}
withHeld :: World -> Integer -> Integer -> Transaction -> Transaction
withHeld w action index t =
    t{txInputs = txInputs t <> [input 8 holder]}
  where
    holder =
        output
            (KeyCredential (BS.replicate 28 0x0b))
            (value (ada 2_000_000 <> [(changePolicy w, [(changeName w action index, 1)])]))
            Nothing

-- | The change policy over a transaction: one claim of an action at a successor index.
changeContext :: World -> Transaction -> Integer -> Data -> Integer -> Minted -> Data
changeContext w t action payload index minted =
    mintingContext
        (changePolicy w)
        (txInputs t)
        (txOutputs t)
        minted
        (changeIssueData [(envelope w action payload, index)])

-- | The checkpoint spend over a transaction.
spendContext :: Transaction -> Data -> Minted -> Data
spendContext t redeemer minted =
    spendingContext (txSpent t) (Just (txDatum t)) [] (txInputs t) (txOutputs t) minted redeemer

-- | A signed fact with its first signature damaged: its name does not change, its signature no longer verifies.
damaged :: Data -> Data
damaged fact = case fact of
    Constr c fs -> Constr c [if i == (7 :: Int) then flipFirst f else f | (i, f) <- zip [0 ..] fs]
    other -> other
  where
    flipFirst (List (x : xs)) = List (flipSignature x : xs)
    flipFirst other = other
    -- a signature is the pair of a position in the keys and the signature bytes
    flipSignature (List [position, B b]) = List [position, B (BS.cons (BS.head b + 1) (BS.tail b))]
    flipSignature other = other

-- | A signed fact without its first signature.
unsigned :: Data -> Data
unsigned fact = case fact of
    Constr c fs -> Constr c [if i == (7 :: Int) then dropFirst f else f | (i, f) <- zip [0 ..] fs]
    other -> other
  where
    dropFirst (List (_ : xs)) = List xs
    dropFirst other = other

-- | The titles of a blueprint's validators with their compiled code.
validatorCodes :: FilePath -> IO [(Text, Maybe Text)]
validatorCodes path = do
    top <- eitherDecodeFileStrict path >>= either fail pure
    entries <- either fail pure (field "validators" top >>= asArray)
    either fail pure (traverse entry entries)
  where
    asArray (Array xs) = Right (toList xs)
    asArray _ = Left "not an array"
    entry v = do
        title <- field "title" v >>= asText
        pure (title, either (const Nothing) Just (field "compiledCode" v >>= asText))

-- ---------------------------------------------------------------------------
-- The names and the redeemers, against the independent generator
-- ---------------------------------------------------------------------------

hex :: ByteString -> Text
hex = TE.decodeUtf8 . convertToBase Base16

{- | The names and the serialised redeemers of a vector, as the library encoders
build them and as the generator wrote them: label, ours, theirs.
-}
generatorRows :: Value -> Text -> Vector -> Either String [(String, Text, Text)]
generatorRows names key v = do
    entry <- field key names
    policy <- field "checkpointPolicy" entry >>= asText >>= hexBytes
    let spent = (vectorTxid v, vectorIndex v)
        fact = vectorFact v
        want k = field k entry >>= asText
        wantIn group k = field group entry >>= field (T.pack k) >>= asText
        claims =
            [ ("advance_at_0", advanceAction, 0, vectorEvidence v)
            , ("advance_at_1", advanceAction, 1, vectorEvidence v)
            , ("freeze_at_0", freezeAction, 0, vectorFreezePayload v)
            , ("freeze_at_1", freezeAction, 1, vectorFreezePayload v)
            ]
    theirFact <- want "factName"
    theirFactRedeemer <- want "factIssueRedeemer"
    theirBurn <- want "burnRedeemer"
    perClaim <-
        traverse
            ( \(label, action, index, payload) -> do
                theirName <- wantIn "changeNames" label
                theirRedeemer <- wantIn "changeIssueRedeemers" label
                pure
                    [ (label <> " name", hex (advanceAttestationName action policy spent index), theirName)
                    , (label <> " redeemer", hex (serialisedData (changeIssueData [(envelopeOf policy spent action payload, index)])), theirRedeemer)
                    ]
            )
            claims
    pure
        ( [ ("fact name", maybe "" hex (signedFactName fact), theirFact)
          , ("fact redeemer", hex (serialisedData (factIssueData [fact])), theirFactRedeemer)
          , ("fact burn redeemer", hex (serialisedData factBurnData), theirBurn)
          , ("change burn redeemer", hex (serialisedData changeBurnData), theirBurn)
          ]
            <> concat perClaim
        )

-- ---------------------------------------------------------------------------
-- R2b: more vectors, two claims in one mint, the bond option and the claim binding
-- ---------------------------------------------------------------------------

-- | The same programs over another committed vector.
withVector :: World -> Vector -> World
withVector w v = w{worldVector = v}

-- | The fields of a version 2 live datum, as Plutus Data.
liveFields :: Data -> [Data]
liveFields datum = case datum of
    Constr 1 [Constr 0 fields] -> fields
    _ -> error "not a version 2 live datum"

-- | The datum with its frozen flag (the fifth field) set to the given value.
withFrozen :: Bool -> Data -> Data
withFrozen frozen datum =
    Constr 1 [Constr 0 [if i == (4 :: Int) then Constr (if frozen then 1 else 0) [] else f | (i, f) <- zip [0 ..] (liveFields datum)]]

{- | The two transactions of an advance in the given placement: the spent datum and its
lovelace, the successor datum and its lovelace, and the premium to a payee.
-}
advanceTx :: World -> Placement -> Data -> Integer -> Data -> Integer -> Transaction
advanceTx w placement spentDatum spentLovelace successorDatum successorLovelace =
    Transaction
        { txInputs = [inputAt (vectorTxid v) (vectorIndex v) (checkpointOutput w spentLovelace spentDatum)]
        , txOutputs = placed placement (checkpointOutput w successorLovelace successorDatum) (paid (BS.replicate 28 0xaa) premium)
        , txSpent = spentData w
        , txDatum = spentDatum
        }
  where
    v = worldVector w

{- | The deposit intent the successor's keys sign for a transaction: the network, the
checkpoint policy, the spent output reference, the identifier, the successor's
sequence number and epoch, and the amount the intent names.
-}
depositIntent :: World -> Data -> Integer -> DepositIntent
depositIntent w successor amount =
    DepositIntent
        { diDomain = depositDomain
        , diNetworkId = 0
        , diCheckpointPolicy = checkpointPolicy w
        , diSpentTxId = vectorTxid v
        , diSpentIndex = vectorIndex v
        , diAid = aid
        , diNewSn = sn
        , diNewEpoch = epoch
        , diDeposit = amount
        }
  where
    v = worldVector w
    (aid, sn, epoch) = case liveFields successor of
        B a : I s : I e : _ -> (a, s, e)
        _ -> error "the successor is not a live datum"

-- | The signatures of an intent by the keys of the given seeds, at their positions.
signIntent :: [ByteString] -> DepositIntent -> [(Int, ByteString)]
signIntent seeds intent = [(position, signedBy seed (depositIntentPreimage intent)) | (position, seed) <- zip [0 ..] seeds]

-- | The checkpoint spend of an advance transaction under a bond option.
advanceSpendWith :: World -> Transaction -> Placement -> Integer -> BondOption -> Minted -> Data
advanceSpendWith _ t placement index bond =
    spendContext t (advanceAttestedSpendRedeemerData (payeeIndex placement) bond index)

-- | The claim of an advance over a transaction, against the change policy.
advanceClaimOver :: World -> Transaction -> Integer -> Minted -> Data
advanceClaimOver w t = changeContext w t advanceAction (vectorEvidence (worldVector w))

-- | The fact policy over the facts a transaction mints.
factsContext :: World -> [Data] -> Minted -> Data
factsContext w facts minted =
    mintingContext (factPolicy w) [] [] minted (factIssueData facts)

-- | The fact policy over the transaction the other programs see: its inputs, its outputs and its whole mint.
factsOver :: World -> Transaction -> [Data] -> Minted -> Data
factsOver w t facts minted =
    mintingContext (factPolicy w) (txInputs t) (txOutputs t) minted (factIssueData facts)

-- | The change policy over several claims of one transaction: the vector, its action and payload, its successor index.
changeClaimsContext :: World -> Transaction -> [(Vector, Integer, Data, Integer)] -> Minted -> Data
changeClaimsContext w t claims minted =
    mintingContext
        (changePolicy w)
        (txInputs t)
        (txOutputs t)
        minted
        ( changeIssueData
            [ (envelopeOf (checkpointPolicy w) (vectorTxid v, vectorIndex v) action payload, index)
            | (v, action, payload, index) <- claims
            ]
        )

-- | The two advances of two vectors in one transaction: the first's outputs first.
bothAdvances :: World -> World -> Transaction
bothAdvances a b =
    Transaction
        { txInputs = txInputs ta <> txInputs tb
        , txOutputs = txOutputs ta <> txOutputs tb
        , txSpent = txSpent ta
        , txDatum = txDatum ta
        }
  where
    ta = rotation a SuccessorFirst
    tb = rotation b SuccessorFirst

-- | What a transaction of two claims mints: the change assets and the fact assets of both, once each.
mintBoth :: World -> World -> [(Integer, Integer)] -> [(Integer, Integer)] -> Minted
mintBoth a b claimsA claimsB =
    [(changePolicy a, [(changeName a action index, 1) | (action, index) <- claimsA] <> [(changeName b action index, 1) | (action, index) <- claimsB])]
        <> [(factPolicy a, sortNames [(factName a, 1), (factName b, 1)])]
  where
    sortNames = id

-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "the two-policy advance, as the ledger evaluates it" $ do
    describe "the two generations" $ do
        it "tells the attested blueprint from the deployed generation's, and the observer-era derivations refuse the attested one" $ do
            deployed <- getEnv "KERI_CHECKPOINT_BLUEPRINT" >>= loadBlueprint >>= either fail pure
            attested <- getEnv "KERI_ATTESTED_BLUEPRINT" >>= loadBlueprint >>= either fail pure
            blueprintIsAttested deployed `shouldBe` False
            blueprintIsAttested attested `shouldBe` True
            let registry = deriveRegistryScripts stateTemplate terms (OutputReference (BS.replicate 32 0x77) 0)
            -- the controls: the deployed generation derives, by the same functions
            deriveV1Scripts fixtureRegistry fixtureApplicationPolicy deployed `shouldSatisfy` isRight
            registry deployed `shouldSatisfy` isRight
            -- the attested blueprint reaches neither the registry derivation (the path
            -- the registry deployment and the command line publish through) nor the
            -- historical publication inventory
            deriveV1Scripts fixtureRegistry fixtureApplicationPolicy attested `shouldBe` Left attestedBlueprintRefusal
            registry attested `shouldBe` Left attestedBlueprintRefusal
        it "binds the deployed generation's blueprint to the build recorded in its README" $ do
            path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            bytes <- BS.readFile path
            show (hash bytes :: Digest SHA256)
                `shouldBe` "523fd1b732ec53bdb2c2be2b13794d0f74721bca43043e5426b0eaf0400ace75"
        it "differ in the checkpoint and the two policies only: every other validator's program is the same" $ do
            deployed <- getEnv "KERI_CHECKPOINT_BLUEPRINT" >>= validatorCodes
            attested <- getEnv "KERI_ATTESTED_BLUEPRINT" >>= validatorCodes
            [title | (title, code) <- attested, Just code' <- [lookup title deployed], code /= code']
                `shouldSatisfy` (\differing -> not (null differing) && all (T.isPrefixOf "checkpoint_register.") differing)
            sort [title | (title, _) <- attested, isNothing (lookup title deployed)]
                `shouldBe` [ "advance_attestation.advance_attestation.else"
                           , "advance_attestation.advance_attestation.mint"
                           , "event_attestation.event_attestation.else"
                           , "event_attestation.event_attestation.mint"
                           ]
            [title | (title, _) <- deployed, isNothing (lookup title attested)] `shouldBe` []
        it "applies to programs of the measured sizes" $ do
            w <- world
            let size = SBS.length . artifactProgram
            (size (worldFact w), size (worldChange w), size (worldCheckpoint w)) `shouldBe` (10_629, 8_355, 8_911)
    describe "the names and the redeemers" $ do
        it "name a signed fact of exactly the nine-field record and no other shape" $ do
            v <- loadVector
            let fact = vectorFact v
                fields = case fact of
                    Constr 0 fs -> fs
                    _ -> []
                nameOf = signedFactName
                dropFrom n = Constr 0 (take n fields)
            length fields `shouldBe` 9
            nameOf fact `shouldSatisfy` isJust
            -- the seven preimage fields alone, with no signature and no receipt field
            nameOf (dropFrom 7) `shouldBe` Nothing
            nameOf (dropFrom 8) `shouldBe` Nothing
            -- a field beyond the record
            nameOf (Constr 0 (fields <> [I 0])) `shouldBe` Nothing
            -- a field of another type
            nameOf (Constr 0 (take 4 fields <> [B "x"] <> drop 5 fields)) `shouldBe` Nothing
            nameOf (Constr 0 (take 7 fields <> [B "x", List []])) `shouldBe` Nothing
            nameOf (Constr 0 (take 7 fields <> [List [I 1], List []])) `shouldBe` Nothing
            nameOf (Constr 0 (take 2 fields <> [I 2] <> drop 3 fields)) `shouldBe` Nothing
            -- the weighted threshold is structural to its weights: the valid weighted vector,
            -- and the same fact with one clause or one weight malformed, in each threshold field
            weighted <- loadVectorNamed "seven_commitments"
            let weightedFields = case vectorFact weighted of
                    Constr 0 fs -> fs
                    _ -> []
                weightedAt position replacement =
                    Constr 0 [if i == position then replacement else f | (i, f) <- zip [0 :: Int ..] weightedFields]
                weights n = [Constr 0 [I 1, I 3] | _ <- [1 .. n :: Int]]
                weightedThreshold clauses = Constr 1 [List clauses]
            length weightedFields `shouldBe` 9
            nameOf (vectorFact weighted) `shouldSatisfy` isJust
            for_ [2, 6] $ \position -> do
                -- a valid weighted control of another shape of the same structure
                nameOf (weightedAt position (weightedThreshold [List (weights 3), List (weights 2)])) `shouldSatisfy` isJust
                -- a clause that is not a list, a weight of another constructor, of one integer, of
                -- three, of bytes, and the weighted constructor with another field count
                nameOf (weightedAt position (weightedThreshold [List (weights 2), I 1])) `shouldBe` Nothing
                nameOf (weightedAt position (weightedThreshold [List [Constr 1 [I 1, I 3]]])) `shouldBe` Nothing
                nameOf (weightedAt position (weightedThreshold [List [Constr 0 [I 1]]])) `shouldBe` Nothing
                nameOf (weightedAt position (weightedThreshold [List [Constr 0 [I 1, I 3, I 4]]])) `shouldBe` Nothing
                nameOf (weightedAt position (weightedThreshold [List [Constr 0 [I 1, B "3"]]])) `shouldBe` Nothing
                nameOf (weightedAt position (weightedThreshold [List (weights 2 <> [I 1])])) `shouldBe` Nothing
                nameOf (weightedAt position (Constr 1 [List [List (weights 2)], I 0])) `shouldBe` Nothing
                nameOf (weightedAt position (Constr 1 [I 1])) `shouldBe` Nothing
            -- structure is not admissibility: a weight outside the reduced canonical form, a zero
            -- denominator, and a clause no keys could satisfy are structurally fine and are named;
            -- the policy decides them
            nameOf (weightedAt 2 (weightedThreshold [List [Constr 0 [I 7, I 0]]])) `shouldSatisfy` isJust
            nameOf (weightedAt 2 (weightedThreshold [List [Constr 0 [I 6, I 4]]])) `shouldSatisfy` isJust
            nameOf (weightedAt 2 (weightedThreshold [])) `shouldSatisfy` isJust
            -- another constructor, and no constructor
            nameOf (Constr 1 fields) `shouldBe` Nothing
            nameOf (I 0) `shouldBe` Nothing
        it "equal those of the independent generator for each committed vector" $ do
            path <- getDataFileName "test/keri-fixtures/fixtures/advance-split-names.json"
            names <- eitherDecodeFileStrict path >>= either fail pure
            mapM_
                ( \key -> do
                    v <- loadVectorNamed key
                    rows <- either fail pure (generatorRows names key v)
                    [(label, ours) | (label, ours, _) <- rows] `shouldBe` [(label, theirs) | (label, _, theirs) <- rows]
                )
                ["two_key", "unwitnessed", "seven_commitments"]
    describe "the fact policy" $ do
        it "accepts the signed fact minted once" $ do
            w <- world
            accepted (worldFact w) (factContext w (vectorFact (worldVector w)) [(factName w, 1)]) `shouldBe` True
        it "refuses the same fact with a surplus positive name, an empty name or the fact minted twice" $ do
            w <- world
            let fact = vectorFact (worldVector w)
            accepted (worldFact w) (factContext w fact [(factName w, 1), ("surplus", 1)]) `shouldBe` False
            accepted (worldFact w) (factContext w fact [(factName w, 1), ("", 1)]) `shouldBe` False
            accepted (worldFact w) (factContext w fact [(factName w, 2)]) `shouldBe` False
        it "refuses a fact whose signature is damaged, or whose signatures are fewer than the threshold" $ do
            w <- world
            let fact = vectorFact (worldVector w)
            accepted (worldFact w) (factContext w (damaged fact) [(factName w, 1)]) `shouldBe` False
            accepted (worldFact w) (factContext w (unsigned fact) [(factName w, 1)]) `shouldBe` False
        it "burns without evidence when every own entry is negative, and refuses a Burn that mints" $ do
            w <- world
            let burn minted = mintingContext (factPolicy w) [] [] [(factPolicy w, minted)] factBurnData
            accepted (worldFact w) (burn [("a", -1), ("", -2)]) `shouldBe` True
            accepted (worldFact w) (burn [("a", -1), ("b", 1)]) `shouldBe` False
            accepted (worldFact w) (burn [("a", -1), ("", 1)]) `shouldBe` False
    describe "the change policy" $ do
        it "accepts the claim of the rotation with its fact asset, and of the freeze with its fact asset" $ do
            w <- world
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] True)) `shouldBe` True
            accepted (worldChange w) (freezeClaim w SuccessorFirst 0 (mintOf w [(freezeAction, 0)] True)) `shouldBe` True
        it "accepts the same claims when the successor sits at index one and the claim and its name say one" $ do
            w <- world
            accepted (worldChange w) (rotationClaim w SuccessorSecond 1 (mintOf w [(advanceAction, 1)] True)) `shouldBe` True
            accepted (worldChange w) (freezeClaim w SuccessorSecond 1 (mintOf w [(freezeAction, 1)] True)) `shouldBe` True
        it "refuses the claim whose index the minted name does not carry, the successor being valid at the claimed index" $ do
            w <- world
            -- the transactions of the two examples above, the minted name alone moved to the other index
            accepted (worldChange w) (rotationClaim w SuccessorSecond 1 (mintOf w [(advanceAction, 0)] True)) `shouldBe` False
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintOf w [(advanceAction, 1)] True)) `shouldBe` False
            accepted (worldChange w) (freezeClaim w SuccessorSecond 1 (mintOf w [(freezeAction, 0)] True)) `shouldBe` False
            accepted (worldChange w) (freezeClaim w SuccessorFirst 0 (mintOf w [(freezeAction, 1)] True)) `shouldBe` False
        it "refuses the successor at another address, the datum and the claim being those of the accepted example" $ do
            w <- world
            let v = worldVector w
                elsewhere = checkpointOutputAt (ScriptCredential (BS.replicate 28 0x0c)) w
                rotated = rotationWith w SuccessorFirst (elsewhere (floorUnfrozen + 3_000_000 - premium) (vectorNew v))
                frozen = freezeWith w SuccessorFirst (elsewhere (floorFrozen + 1_000_000) (vectorFrozen v))
            accepted
                (worldChange w)
                (changeContext w rotated advanceAction (vectorEvidence v) 0 (mintOf w [(advanceAction, 0)] True))
                `shouldBe` False
            accepted
                (worldChange w)
                (changeContext w frozen freezeAction (vectorFreezePayload v) 0 (mintOf w [(freezeAction, 0)] True))
                `shouldBe` False
        it "refuses the rotation without its fact asset, and with a surplus positive name" $ do
            w <- world
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] False)) `shouldBe` False
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintGeneral w 1 [(advanceAction, 0)] ["surplus"] 1))
                `shouldBe` False
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintGeneral w 1 [(advanceAction, 0)] [""] 1))
                `shouldBe` False
        it "refuses its own asset, and the fact asset it reads, at quantity two" $ do
            w <- world
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintGeneral w 2 [(advanceAction, 0)] [] 1)) `shouldBe` False
            accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintGeneral w 1 [(advanceAction, 0)] [] 2)) `shouldBe` False
        it "refuses a freeze whose successor is not frozen" $ do
            w <- world
            let v = worldVector w
                notFrozen = freezeWith w SuccessorFirst (checkpointOutput w (floorFrozen + 1_000_000) (vectorOld v))
            accepted
                (worldChange w)
                (changeContext w notFrozen freezeAction (vectorFreezePayload v) 0 (mintOf w [(freezeAction, 0)] True))
                `shouldBe` False
        it "refuses a claim naming an input the transaction does not spend" $ do
            w <- world
            let v = worldVector w
                other = (rotation w SuccessorFirst){txInputs = [input 3 (checkpointOutput w (floorUnfrozen + 3_000_000) (vectorOld v))]}
            accepted
                (worldChange w)
                (changeContext w other advanceAction (vectorEvidence v) 0 (mintOf w [(advanceAction, 0)] True))
                `shouldBe` False
        it "burns without evidence when every own entry is negative, and refuses a Burn that mints" $ do
            w <- world
            let burn minted = mintingContext (changePolicy w) [] [] [(changePolicy w, minted)] changeBurnData
            accepted (worldChange w) (burn [("a", -1), ("", -2)]) `shouldBe` True
            accepted (worldChange w) (burn [("a", -1), ("b", 1)]) `shouldBe` False
    describe "the checkpoint spend" $ do
        it "accepts the advance and the freeze whose change asset is minted by the transaction" $ do
            w <- world
            accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] True) id) `shouldBe` True
            accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintOf w [(freezeAction, 0)] True) id) `shouldBe` True
        it "accepts them when the successor sits at index one and the redeemer and the minted name say one" $ do
            w <- world
            accepted (worldCheckpoint w) (advanceSpend w SuccessorSecond 1 (mintOf w [(advanceAction, 1)] True) id) `shouldBe` True
            accepted (worldCheckpoint w) (freezeSpend w SuccessorSecond 1 (mintOf w [(freezeAction, 1)] True) id) `shouldBe` True
        it "refuses a redeemer index the minted name does not carry, the successor being valid at the redeemer index" $ do
            w <- world
            -- the transactions of the two examples above, the minted name alone moved to the other index
            accepted (worldCheckpoint w) (advanceSpend w SuccessorSecond 1 (mintOf w [(advanceAction, 0)] True) id) `shouldBe` False
            accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintOf w [(advanceAction, 1)] True) id) `shouldBe` False
            accepted (worldCheckpoint w) (freezeSpend w SuccessorSecond 1 (mintOf w [(freezeAction, 0)] True) id) `shouldBe` False
            accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintOf w [(freezeAction, 1)] True) id) `shouldBe` False
        it "reads the change asset from the mint field, not from an input: the same held input beside a fresh mint and beside none" $ do
            w <- world
            let heldAdvance = withHeld w advanceAction 0
                heldFreeze = withHeld w freezeAction 0
            -- one transaction each, the key-held input in both; the quantity of the named asset in the mint field alone differs
            accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] True) heldAdvance) `shouldBe` True
            accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintOf w [] True) heldAdvance) `shouldBe` False
            accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintOf w [(freezeAction, 0)] True) heldFreeze) `shouldBe` True
            accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintOf w [] True) heldFreeze) `shouldBe` False
        it "refuses the change asset minted twice" $ do
            w <- world
            accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintGeneral w 2 [(advanceAction, 0)] [] 1) id) `shouldBe` False
            accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintGeneral w 2 [(freezeAction, 0)] [] 1) id) `shouldBe` False
    describe "each committed vector" $
        for_ ["two_key", "unwitnessed", "seven_commitments"] $ \name ->
            it ("applies the three programs over the vector " <> T.unpack (name :: Text)) $ do
                base <- world
                v <- loadVectorNamed name
                let w = withVector base v
                    vector = worldVector w
                    spendAdvance = advanceSpend w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] True) id
                    spendFreeze = freezeSpend w SuccessorFirst 0 (mintOf w [(freezeAction, 0)] True) id
                -- the fact policy over the same inputs, outputs and whole mint as the rotation's change policy and spend
                accepted (worldFact w) (factsOver w (rotation w SuccessorFirst) [vectorFact vector] (mintOf w [(advanceAction, 0)] True)) `shouldBe` True
                accepted (worldChange w) (rotationClaim w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] True)) `shouldBe` True
                accepted (worldChange w) (freezeClaim w SuccessorFirst 0 (mintOf w [(freezeAction, 0)] True)) `shouldBe` True
                accepted (worldCheckpoint w) spendAdvance `shouldBe` True
                accepted (worldCheckpoint w) spendFreeze `shouldBe` True
                -- the matched pair: the same key-held input in both spends; only the named change asset in the mint field varies
                let held action = withHeld w action 0
                accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintOf w [(advanceAction, 0)] True) (held advanceAction)) `shouldBe` True
                accepted (worldCheckpoint w) (advanceSpend w SuccessorFirst 0 (mintOf w [] True) (held advanceAction)) `shouldBe` False
                accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintOf w [(freezeAction, 0)] True) (held freezeAction)) `shouldBe` True
                accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (mintOf w [] True) (held freezeAction)) `shouldBe` False
    describe "two checkpoints in one transaction" $ do
        let pair = do
                a <- world
                vb <- loadVectorNamed "unwitnessed"
                let b = withVector a vb
                    t = bothAdvances a b
                    claims = [(worldVector a, advanceAction, vectorEvidence (worldVector a), 0), (vb, advanceAction, vectorEvidence vb, 2)]
                    mint = mintBoth a b [(advanceAction, 0)] [(advanceAction, 2)]
                    spendA = spendContext t (advanceAttestedSpendRedeemerData 1 Keep 0)
                    spendB = spendContext t{txSpent = spentData b, txDatum = vectorOld vb} (advanceAttestedSpendRedeemerData 3 Keep 2)
                pure (a, b, vb, t, claims, mint, spendA, spendB)
        it "accepts both facts in one Issue, both claims in one Issue, and each checkpoint's spend over the one mint" $ do
            (a, b, vb, t, claims, mint, spendA, spendB) <- pair
            -- the fact policy over the same two inputs, four outputs and whole mint as the change policy and both spends
            accepted (worldFact a) (factsOver a t [vectorFact (worldVector a), vectorFact vb] mint) `shouldBe` True
            accepted (worldChange a) (changeClaimsContext a t claims mint) `shouldBe` True
            accepted (worldCheckpoint a) (spendA mint) `shouldBe` True
            accepted (worldCheckpoint b) (spendB mint) `shouldBe` True
        it "refuses a fact Issue that repeats one fact, or that leaves a minted name without its fact" $ do
            (a, _, vb, _, _, mint, _, _) <- pair
            let factMint = filter ((== factPolicy a) . fst) mint
                fa = vectorFact (worldVector a)
            -- the same mint, one fact named once and the same fact named twice: only the repetition differs
            accepted (worldFact a) (factsContext a [fa] [(factPolicy a, [(factName a, 1)])]) `shouldBe` True
            accepted (worldFact a) (factsContext a [fa, fa] [(factPolicy a, [(factName a, 1)])]) `shouldBe` False
            -- both names minted, one fact: the other name has no fact
            accepted (worldFact a) (factsContext a [fa] factMint) `shouldBe` False
            accepted (worldFact a) (factsContext a [fa, vectorFact vb] factMint) `shouldBe` True
        it "refuses the claims when one checkpoint's change asset, or its fact asset, is not minted, or when the claims are repeated or name each other's successor" $ do
            (a, b, vb, t, claims, mint, _, _) <- pair
            let onlyA = mintBoth a b [(advanceAction, 0)] []
                withoutFactB = filter ((/= factPolicy a) . fst) mint <> [(factPolicy a, [(factName a, 1)])]
                crossed = [(worldVector a, advanceAction, vectorEvidence (worldVector a), 2), (vb, advanceAction, vectorEvidence vb, 0)]
            accepted (worldChange a) (changeClaimsContext a t claims onlyA) `shouldBe` False
            accepted (worldChange a) (changeClaimsContext a t claims withoutFactB) `shouldBe` False
            -- the same mint, one claim named once and the same claim named twice: only the repetition differs
            accepted (worldChange a) (changeClaimsContext a t (take 1 claims) onlyA) `shouldBe` True
            accepted (worldChange a) (changeClaimsContext a t (take 1 claims <> take 1 claims) onlyA) `shouldBe` False
            accepted (worldChange a) (changeClaimsContext a t crossed (mintBoth a b [(advanceAction, 2)] [(advanceAction, 0)])) `shouldBe` False
        it "refuses a checkpoint's spend when its own change asset is not minted, whatever the other's is" $ do
            (a, b, _, _, _, _, spendA, spendB) <- pair
            let onlyA = mintBoth a b [(advanceAction, 0)] []
                onlyB = mintBoth a b [] [(advanceAction, 2)]
            accepted (worldCheckpoint a) (spendA onlyA) `shouldBe` True
            accepted (worldCheckpoint b) (spendB onlyA) `shouldBe` False
            accepted (worldCheckpoint b) (spendB onlyB) `shouldBe` True
            accepted (worldCheckpoint a) (spendA onlyB) `shouldBe` False
    describe "the bond option" $ do
        let setup = do
                w <- world
                seeds <- loadSeeds
                let v = worldVector w
                    pool = 3_000_000
                    successor = vectorNew v
                    frozenTx = advanceTx w SuccessorFirst (vectorFrozen v) (floorFrozen + pool) successor (floorUnfrozen + pool - premium)
                    unfrozenTx = advanceTx w SuccessorFirst (vectorOld v) (floorUnfrozen + pool) successor (floorUnfrozen + pool - premium)
                    mint = mintOf w [(advanceAction, 0)] True
                    sign = signIntent
                pure (w, seeds, v, successor, frozenTx, unfrozenTx, mint, sign)
        it "accepts a depositing rotation of a frozen checkpoint whose successor's keys signed the intent naming the bond, in the three programs" $ do
            (w, seeds, _, successor, frozenTx, _, mint, sign) <- setup
            let sigs = sign (rotationSeeds seeds) (depositIntent w successor freezeBond)
            accepted (worldCheckpoint w) (advanceSpendWith w frozenTx SuccessorFirst 0 (Deposit sigs) mint) `shouldBe` True
            accepted (worldChange w) (advanceClaimOver w frozenTx 0 mint) `shouldBe` True
            accepted (worldFact w) (factsOver w frozenTx [vectorFact (worldVector w)] mint) `shouldBe` True
        it "refuses the same transaction when the intent is not the required one: no signature, one of two, the old keys, another amount, another output, another policy" $ do
            (w, seeds, v, successor, frozenTx, _, mint, sign) <- setup
            let required = depositIntent w successor freezeBond
                good = sign (rotationSeeds seeds) required
                spendWith sigs = advanceSpendWith w frozenTx SuccessorFirst 0 (Deposit sigs) mint
            accepted (worldCheckpoint w) (spendWith good) `shouldBe` True
            accepted (worldCheckpoint w) (spendWith []) `shouldBe` False
            accepted (worldCheckpoint w) (spendWith (take 1 good)) `shouldBe` False
            accepted (worldCheckpoint w) (spendWith (sign (inceptionSeeds seeds) required)) `shouldBe` False
            accepted (worldCheckpoint w) (spendWith (sign (rotationSeeds seeds) required{diDeposit = 0})) `shouldBe` False
            accepted (worldCheckpoint w) (spendWith (sign (rotationSeeds seeds) required{diSpentIndex = vectorIndex v + 1})) `shouldBe` False
            accepted (worldCheckpoint w) (spendWith (sign (rotationSeeds seeds) required{diCheckpointPolicy = BS.replicate 28 0x00})) `shouldBe` False
        it "names zero on an unfrozen checkpoint: the intent for zero is accepted and the intent for the bond is refused" $ do
            (w, seeds, _, successor, _, unfrozenTx, mint, sign) <- setup
            let spendWith amount = advanceSpendWith w unfrozenTx SuccessorFirst 0 (Deposit (sign (rotationSeeds seeds) (depositIntent w successor amount))) mint
            accepted (worldCheckpoint w) (spendWith 0) `shouldBe` True
            accepted (worldCheckpoint w) (spendWith freezeBond) `shouldBe` False
        it "keeps a frozen checkpoint frozen under Keep and refuses Keep when the successor is unfrozen" $ do
            (w, _, v, successor, _, _, mint, _) <- setup
            let pool = 3_000_000
                keptFrozen = advanceTx w SuccessorFirst (vectorFrozen v) (floorFrozen + pool) (withFrozen True successor) (floorFrozen + pool - premium)
                unfrozenKeep = advanceTx w SuccessorFirst (vectorFrozen v) (floorFrozen + pool) successor (floorUnfrozen + pool - premium)
            accepted (worldCheckpoint w) (advanceSpendWith w keptFrozen SuccessorFirst 0 Keep mint) `shouldBe` True
            accepted (worldChange w) (advanceClaimOver w keptFrozen 0 mint) `shouldBe` True
            accepted (worldCheckpoint w) (advanceSpendWith w unfrozenKeep SuccessorFirst 0 Keep mint) `shouldBe` False
    describe "the binding of the change asset at the spend" $ do
        it "names the action, the spent output and the checkpoint policy: another action's asset, another output's and another policy's are refused" $ do
            w <- world
            let v = worldVector w
                other = changePolicy w
                factOnly = [(factPolicy w, [(factName w, 1)])]
                minting name = [(other, [(name, 1)])] <> factOnly
                spendOf name = advanceSpend w SuccessorFirst 0 (minting name) id
                nameFor action policy spent = advanceAttestationName action policy spent 0
            accepted (worldCheckpoint w) (spendOf (nameFor advanceAction (checkpointPolicy w) (vectorTxid v, vectorIndex v))) `shouldBe` True
            accepted (worldCheckpoint w) (spendOf (nameFor freezeAction (checkpointPolicy w) (vectorTxid v, vectorIndex v))) `shouldBe` False
            accepted (worldCheckpoint w) (spendOf (nameFor advanceAction (checkpointPolicy w) (vectorTxid v, vectorIndex v + 1))) `shouldBe` False
            accepted (worldCheckpoint w) (spendOf (nameFor advanceAction (checkpointPolicy w) (BS.replicate 32 0x00, vectorIndex v))) `shouldBe` False
            accepted (worldCheckpoint w) (spendOf (nameFor advanceAction (BS.replicate 28 0xcc) (vectorTxid v, vectorIndex v))) `shouldBe` False
            accepted (worldCheckpoint w) (freezeSpend w SuccessorFirst 0 (minting (nameFor advanceAction (checkpointPolicy w) (vectorTxid v, vectorIndex v))) id) `shouldBe` False
  where
    factContext w fact minted =
        mintingContext (factPolicy w) [] [] [(factPolicy w, minted)] (factIssueData [fact])
    rotationClaim w placement =
        changeContext w (rotation w placement) advanceAction (vectorEvidence (worldVector w))
    freezeClaim w placement =
        changeContext w (freeze w placement) freezeAction (vectorFreezePayload (worldVector w))
    advanceSpend w placement index minted adjust =
        spendContext
            (adjust (rotation w placement))
            (advanceAttestedSpendRedeemerData (payeeIndex placement) Keep index)
            minted
    freezeSpend w placement index minted adjust =
        spendContext
            (adjust (freeze w placement))
            (freezeAttestedSpendRedeemerData (payeeIndex placement) index)
            minted
