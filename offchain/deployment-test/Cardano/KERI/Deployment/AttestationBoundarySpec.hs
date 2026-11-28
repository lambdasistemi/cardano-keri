{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.AttestationBoundarySpec
Description : the booking attestation policy, as the ledger evaluates it

The Aiken tests run the validators' source through the Aiken evaluator over
transactions written in Aiken. These examples run the /applied programs of the
production derivation/ ('deriveRegistryScripts') through the Plutus ledger
evaluator ('evaluateScriptCounting'), with the version 3 script context written
here as Plutus Data from the ledger's own layout, by code that shares nothing with
the Aiken fixtures. The request, its datum and its evidence are built with the
library's encoders ('heldDatumData', 'liveOfKeyState', 'bookingAttestationName')
from the committed keripy inception of @reg_2key@.

Each story is an accepted transaction beside its refused neighbour that differs by
one thing:

* an Issue that mints a name it did not verify (a surplus positive mint);
* a Burn that mints (a positive entry, and the empty name);
* a booking of the application whose attestation is held by an input of the
  transaction and not minted by it (the application's mint, over the same request).
-}
module Cardano.KERI.Deployment.AttestationBoundarySpec (
    spec,
    Inception (..),
    Booking (..),
    accepted,
    acceptedWithBudget,
    booking,
    issueOf,
    applicationBooking,
    derived,
    mintingContext,
    terms,
) where

import Cardano.KERI.AID.Application (
    Action (..),
    ApplicationParameters (..),
    Credential (..),
    HeldDatum (..),
    OutputReference (..),
    RegistrationData (..),
    actionData,
    configurationTokenName,
    heldDatumData,
    registrationApprovalName,
    unstakedAddress,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive, qb64Aid)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    checkpointDatumToData,
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Qualified (codeD, qualify)
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    bookingAttestationBurnData,
    bookingAttestationIssueData,
    bookingAttestationName,
 )
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.Script (
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    loadBlueprint,
    scriptHashBytes,
 )
import Control.Monad ((>=>))
import Control.Monad.Writer (runWriterT)
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.List (elemIndex, sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.Test.V3.EvaluationContext (costModelParamsForTesting)
import PlutusLedgerApi.V3 (
    CostModelApplyError,
    EvaluationContext,
    ExBudget,
    MajorProtocolVersion (..),
    VerboseMode (..),
    deserialiseScript,
    evaluateScriptCounting,
    mkEvaluationContext,
 )
import System.Environment (getEnv)
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- The ledger's evaluator
-- ---------------------------------------------------------------------------

evaluationContext :: EvaluationContext
evaluationContext =
    case runWriterT (mkEvaluationContext (map snd costModelParamsForTesting)) of
        Left err -> error (show (err :: CostModelApplyError))
        Right (ctx, _) -> ctx

-- | Whether the ledger accepts the applied program over the script context.
accepted :: ScriptArtifact -> Data -> Bool
accepted artifact context = either (const False) (const True) (acceptedWithBudget artifact context)

-- | The budget the ledger counts for the accepted evaluation, or the refusal.
acceptedWithBudget :: ScriptArtifact -> Data -> Either String ExBudget
acceptedWithBudget artifact context =
    case deserialiseScript (MajorProtocolVersion 10) (artifactProgram artifact) of
        Left err -> error (show err)
        Right script ->
            case snd (evaluateScriptCounting (MajorProtocolVersion 10) Quiet evaluationContext script context) of
                Left err -> Left (show err)
                Right budget -> Right budget

-- ---------------------------------------------------------------------------
-- The version 3 script context, as Plutus Data
-- ---------------------------------------------------------------------------

bool :: Bool -> Data
bool b = Constr (if b then 1 else 0) []

nothing :: Data
nothing = Constr 1 []

{- | A value as the ledger passes it: policies and names in ascending order, which
the validators' value lookups rely on.
-}
value :: [(ByteString, [(ByteString, Integer)])] -> Data
value assets =
    Map
        [ (B policy, Map [(B name, I quantity) | (name, quantity) <- sortOn fst tokens])
        | (policy, tokens) <- sortOn fst assets
        ]

address :: Credential -> Data
address (KeyCredential h) = Constr 0 [Constr 0 [B h], nothing]
address (ScriptCredential h) = Constr 0 [Constr 1 [B h], nothing]

output :: Credential -> Data -> Maybe Data -> Data
output credential val datum =
    Constr
        0
        [ address credential
        , val
        , maybe (Constr 0 []) (\d -> Constr 2 [d]) datum
        , nothing
        ]

input :: Integer -> Data -> Data
input index out = Constr 0 [Constr 0 [B (BS.replicate 32 0x55), I index], out]

ada :: Integer -> [(ByteString, [(ByteString, Integer)])]
ada lovelace = [("", [("", lovelace)])]

-- | The validity range of a transaction valid at any time.
anyTime :: Data
anyTime =
    Constr
        0
        [ Constr 0 [Constr 0 [], bool True]
        , Constr 0 [Constr 2 [], bool True]
        ]

-- | The validity range from @lower@ (inclusive) to @upper@ (exclusive).
between :: Integer -> Integer -> Data
between lower upper =
    Constr
        0
        [ Constr 0 [Constr 1 [I lower], bool True]
        , Constr 0 [Constr 1 [I upper], bool False]
        ]

-- | A version 3 minting script context.
mintingContext ::
    ByteString -> [Data] -> [Data] -> [(ByteString, [(ByteString, Integer)])] -> Data -> Data
mintingContext policy = mintingContextWith policy [] anyTime

mintingContextWith ::
    ByteString ->
    [Data] ->
    Data ->
    [Data] ->
    [Data] ->
    [(ByteString, [(ByteString, Integer)])] ->
    Data ->
    Data
mintingContextWith policy references validity inputs outputs minted redeemer =
    Constr
        0
        [ Constr
            0
            [ List inputs
            , List references
            , List outputs
            , I 0
            , value minted
            , List []
            , Map []
            , validity
            , List []
            , Map []
            , Map []
            , B (BS.replicate 32 0x99)
            , Map []
            , List []
            , nothing
            , nothing
            ]
        , redeemer
        , Constr 0 [B policy]
        ]

-- ---------------------------------------------------------------------------
-- The inception of the committed keripy fixture @reg_2key@
-- ---------------------------------------------------------------------------

data Inception = Inception
    { inceptionView :: KeyStateView
    , inceptionEvidence :: RegistrationEvidence
    , inceptionIdentifier :: ByteString
    -- ^ the qualified text of the identifier, as the datum and the request keep it
    , inceptionKeys :: [ByteString]
    -- ^ the qualified texts of the current keys
    }

field :: Text -> Value -> Either String Value
field k v = case v of
    Object o | Just x <- KM.lookup (K.fromText k) o -> Right x
    _ -> Left (T.unpack k <> " missing")

text :: Value -> Either String Text
text (String t) = Right t
text _ = Left "not a string"

int :: Value -> Either String Int
int (Number n) = Right (truncate n)
int _ = Left "not a number"

list :: Value -> Either String [Value]
list (Array a) = Right (toList a)
list _ = Left "not an array"

hexBytes :: Text -> Either String ByteString
hexBytes = convertFromBase Base16 . TE.encodeUtf8

primitive :: Text -> Either String Primitive
primitive t = case parsePrimitive (TE.encodeUtf8 t) of
    Right (p, rest) | BS.null rest -> Right p
    _ -> Left (T.unpack t <> ": not a primitive")

verkey, digest :: Text -> Either String ByteString
verkey t =
    primitive t >>= \case
        Ed25519PublicKey raw -> Right raw
        _ -> Left "not a public key"
digest t =
    primitive t >>= \case
        SelfAddressing raw -> Right raw
        _ -> Left "not a digest"

hexInt :: Text -> Either String Integer
hexInt t
    | T.null t = Left "empty numeral"
    | otherwise = T.foldl' step (Right 0) t
  where
    step acc c = do
        n <- acc
        d <- maybe (Left "not a numeral") Right (elemIndex c "0123456789abcdef")
        pure (n * 16 + fromIntegral d)

loadInception :: IO Inception
loadInception = do
    path <- getDataFileName "test/keri-fixtures/fixtures/registration.json"
    top <- eitherDecodeFileStrict path >>= either fail pure
    either fail pure (inceptionOf top)

inceptionOf :: Value -> Either String Inception
inceptionOf top = do
    sub <- field "reg_2key" top
    ev <- field "event" sub
    raw <- field "raw_hex" ev >>= text >>= hexBytes
    ked <- field "ked" ev
    aid <- field "i" ked >>= text >>= digest
    keys <- field "k" ked >>= list >>= traverse (text >=> verkey)
    nexts <- field "n" ked >>= list >>= traverse (text >=> digest)
    kt <- field "kt" ked >>= text >>= hexInt
    nt <- field "nt" ked >>= text >>= hexInt
    sigs <- field "event_sigs" sub >>= list >>= traverse sigOf
    pure
        Inception
            { inceptionView =
                KeyStateView
                    { cdCesrAid = aid
                    , cdCurKeys = keys
                    , cdCurThreshold = Unweighted kt
                    , cdNextKeys = nexts
                    , cdNextThreshold = Unweighted nt
                    , cdWitnesses = []
                    , cdToad = 0
                    , cdSeq = 0
                    , cdNativeSn = 0
                    }
            , inceptionEvidence =
                RegistrationEvidence
                    { reEventBytes = raw
                    , reCtrlSigs = sigs
                    , reWitReceipts = []
                    }
            , inceptionIdentifier = qb64Aid aid
            , inceptionKeys = map (qualify codeD) keys
            }
  where
    sigOf s = do
        i <- field "index" s >>= int
        sig <- field "sig_hex" s >>= text >>= hexBytes
        pure (i, sig)

-- ---------------------------------------------------------------------------
-- The registry the derivation produces
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

derived :: IO RegistryScripts
derived = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <- loadBlueprint path >>= either fail pure
    either
        fail
        pure
        ( deriveRegistryScripts
            stateTemplate
            terms
            (OutputReference (BS.replicate 32 0x77) 0)
            blueprint
        )

-- ---------------------------------------------------------------------------
-- The booking transaction of the policy
-- ---------------------------------------------------------------------------

deposit :: Integer
deposit = 1_009_000_000

-- | The request of the inception: the datum it commits is its key's initial state.
requestOf :: RegistryScripts -> Inception -> (RegistrationData, Data)
requestOf scripts Inception{inceptionView = view, inceptionIdentifier = identifier, inceptionKeys = keys} =
    ( RegistrationData
        { requestRegistry = scriptsRegistry scripts
        , requestKey = identifier
        , requestController = BS.replicate 28 0x01
        , requestRefundAddress = unstakedAddress (KeyCredential (BS.replicate 28 0x02))
        , requestHoldingAddress = unstakedAddress (ScriptCredential (BS.replicate 28 0x03))
        , requestInitialDatum = initial
        , requestDeposit = deposit
        , requestBookedAt = 10
        , requestProcessDeadline = 15
        , requestReclaimEnd = 15
        }
    , initial
    )
  where
    initial =
        checkpointDatumToData
            ( V2
                ( case liveOfKeyState (BS.cons 0x60 (BS.replicate 28 0x02)) 10 view of
                    live@Live{lvKeys} -> live{lvAid = identifier, lvKeys = lvKeys{kmCurKeys = keys}}
                    other -> other
                )
            )

data Booking = Booking
    { bookingContext :: Data
    , bookingName :: ByteString
    }

{- | The booking of the inception: its request at the application, its hash-proof
token spent and burned, its attestation minted (or not), under the redeemer.
-}
booking ::
    RegistryScripts -> Inception -> [(ByteString, Integer)] -> (ByteString -> Data) -> Booking
booking scripts inception extraMint redeemerOf =
    Booking
        { bookingContext =
            mintingContext
                attestationPolicy
                [ input
                    0
                    ( output
                        (KeyCredential (BS.replicate 28 0x0b))
                        ( value
                            ( ada 2_000_000
                                <> [(proofPolicy, [(proofName, 1)])]
                            )
                        )
                        Nothing
                    )
                ]
                [ output
                    (ScriptCredential applicationPolicy)
                    (value (ada 1_009_000_003))
                    (Just (heldDatumData (Registration request)))
                ]
                ( [(proofPolicy, [(proofName, -1)])]
                    <> [(attestationPolicy, extraMint)]
                )
                (redeemerOf applicationPolicy)
        , bookingName = name
        }
  where
    (request, initial) = requestOf scripts inception
    applicationPolicy = scriptHashBytes (artifactScriptHash (scriptsApplication scripts))
    attestationPolicy = scriptHashBytes (artifactScriptHash (scriptsAttestation scripts))
    proofPolicy = scriptHashBytes (artifactScriptHash (observerHashProof (scriptsObservers scripts)))
    proofName = proofTokenName (reEventBytes (inceptionEvidence inception)) (cdCesrAid (inceptionView inception))
    name = bookingAttestationName applicationPolicy 0 initial deposit

issueOf :: Inception -> ByteString -> Data
issueOf inception application =
    bookingAttestationIssueData application [(0, inceptionEvidence inception)]

-- ---------------------------------------------------------------------------
-- The booking transaction of the application
-- ---------------------------------------------------------------------------

{- | The booking of the inception's request, as the application's mint sees it:
the request output holding its approval, the configuration record of the registry
as a reference input, the approval minted, and the attestation either minted in
this transaction or only held by an input of it.
-}
applicationBooking :: RegistryScripts -> Inception -> Bool -> Data
applicationBooking scripts inception mintsAttestation =
    mintingContextWith
        applicationPolicy
        [ input
            9
            ( output
                (ScriptCredential applicationPolicy)
                ( value
                    ( ada 2_000_000
                        <> [(applicationPolicy, [(configurationTokenName registry, 1)])]
                    )
                )
                ( Just
                    ( heldDatumData
                        ( Configuration
                            (ApplicationParameters 2 1 5 1)
                            (ScriptCredential checkpoint)
                        )
                    )
                )
            )
        ]
        (between 9 10)
        [ input
            1
            ( output
                (KeyCredential (BS.replicate 28 0x0b))
                (value (ada 2_000_000 <> [(attestationPolicy, [(name, 1)]) | not mintsAttestation]))
                Nothing
            )
        ]
        [ output
            (ScriptCredential applicationPolicy)
            (value (ada (deposit + 3) <> [(applicationPolicy, [(approval, 1)])]))
            (Just (heldDatumData (Registration request)))
        ]
        ( [(applicationPolicy, [(approval, 1)])]
            <> [(attestationPolicy, [(name, 1)]) | mintsAttestation]
        )
        (List [actionData (BookRegistration 0)])
  where
    (request, initial) = requestOf scripts inception
    registry = scriptsRegistry scripts
    applicationPolicy = scriptHashBytes (artifactScriptHash (scriptsApplication scripts))
    attestationPolicy = scriptHashBytes (artifactScriptHash (scriptsAttestation scripts))
    checkpoint = BS.replicate 28 0x03
    name = bookingAttestationName applicationPolicy 0 initial deposit
    approval =
        registrationApprovalName
            registry
            (requestKey request)
            (requestHoldingAddress request)
            initial
            deposit

-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "the booking attestation policy, as the ledger evaluates it" $ do
    it "accepts the booking of an inception with its attestation minted once" $ do
        scripts <- derived
        inception <- loadInception
        let probe = booking scripts inception [] (issueOf inception)
            minted = booking scripts inception [(bookingName probe, 1)] (issueOf inception)
        accepted (scriptsAttestation scripts) (bookingContext minted) `shouldBe` True
    it "refuses the same booking with a surplus positive name beside the attestation" $ do
        scripts <- derived
        inception <- loadInception
        let probe = booking scripts inception [] (issueOf inception)
            surplus = booking scripts inception [(bookingName probe, 1), ("surplus", 1)] (issueOf inception)
            emptyName = booking scripts inception [(bookingName probe, 1), ("", 1)] (issueOf inception)
            twice = booking scripts inception [(bookingName probe, 2)] (issueOf inception)
        accepted (scriptsAttestation scripts) (bookingContext surplus) `shouldBe` False
        accepted (scriptsAttestation scripts) (bookingContext emptyName) `shouldBe` False
        accepted (scriptsAttestation scripts) (bookingContext twice) `shouldBe` False
    it "reads no attestation from an input: the same booking with the token held, not minted, is refused by the application" $ do
        scripts <- derived
        inception <- loadInception
        accepted (scriptsApplication scripts) (applicationBooking scripts inception True) `shouldBe` True
        accepted (scriptsApplication scripts) (applicationBooking scripts inception False) `shouldBe` False
    it "burns without evidence when every own entry is negative" $ do
        scripts <- derived
        let attestationPolicy = scriptHashBytes (artifactScriptHash (scriptsAttestation scripts))
            burn minted = mintingContext attestationPolicy [] [] [(attestationPolicy, minted)] bookingAttestationBurnData
        accepted (scriptsAttestation scripts) (burn [("a", -1), ("", -2)]) `shouldBe` True
    it "refuses a Burn that mints: a positive entry, and the empty name" $ do
        scripts <- derived
        let attestationPolicy = scriptHashBytes (artifactScriptHash (scriptsAttestation scripts))
            burn minted = mintingContext attestationPolicy [] [] [(attestationPolicy, minted)] bookingAttestationBurnData
        accepted (scriptsAttestation scripts) (burn [("a", -1), ("b", 1)]) `shouldBe` False
        accepted (scriptsAttestation scripts) (burn [("a", -1), ("", 1)]) `shouldBe` False
