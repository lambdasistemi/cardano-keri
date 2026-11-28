{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.LedgerContext
Description : the ledger's evaluator and the version 3 script context, as Plutus Data

The applied programs of the production derivation are run through the Plutus
ledger evaluator ('evaluateScriptCounting') over a script context written here as
Plutus Data from the ledger's own layout, by code that shares nothing with the
Aiken fixtures. The specs that evaluate applied programs share these builders.
-}
module Cardano.KERI.Deployment.LedgerContext (
    accepted,
    bool,
    nothing,
    just,
    value,
    address,
    output,
    input,
    inputAt,
    ada,
    anyTime,
    between,
    mintingContext,
    mintingContextWith,
    spendingContext,
) where

import Cardano.KERI.AID.Application (Credential (..))
import Cardano.KERI.Deployment.Script (ScriptArtifact (..))
import Control.Monad.Writer (runWriterT)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (sortOn)
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
accepted artifact context =
    case deserialiseScript (MajorProtocolVersion 10) (artifactProgram artifact) of
        Left err -> error (show err)
        Right script ->
            case snd (evaluateScriptCounting (MajorProtocolVersion 10) Quiet evaluationContext script context) of
                Left _ -> False
                Right (_ :: ExBudget) -> True

-- ---------------------------------------------------------------------------
-- The version 3 script context, as Plutus Data
-- ---------------------------------------------------------------------------

bool :: Bool -> Data
bool b = Constr (if b then 1 else 0) []

nothing :: Data
nothing = Constr 1 []

-- | @Some@ of a value.
just :: Data -> Data
just x = Constr 0 [x]

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
input = inputAt (BS.replicate 32 0x55)

-- | An input spending the given output reference.
inputAt :: ByteString -> Integer -> Data -> Data
inputAt txid index out = Constr 0 [Constr 0 [B txid, I index], out]

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
    scriptContext references validity inputs outputs minted redeemer (Constr 0 [B policy])

{- | A version 3 spending script context: the output reference spent, the datum of
the spent output and the redeemer.
-}
spendingContext ::
    Data ->
    Maybe Data ->
    [Data] ->
    [Data] ->
    [Data] ->
    [(ByteString, [(ByteString, Integer)])] ->
    Data ->
    Data
spendingContext spent datum references inputs outputs minted redeemer =
    scriptContext
        references
        anyTime
        inputs
        outputs
        minted
        redeemer
        (Constr 1 [spent, maybe nothing just datum])

scriptContext ::
    [Data] ->
    Data ->
    [Data] ->
    [Data] ->
    [(ByteString, [(ByteString, Integer)])] ->
    Data ->
    Data ->
    Data
scriptContext references validity inputs outputs minted redeemer purpose =
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
        , purpose
        ]
