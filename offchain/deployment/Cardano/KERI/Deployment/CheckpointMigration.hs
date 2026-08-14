{- |
Module      : Cardano.KERI.Deployment.CheckpointMigration
Description : Published checkpoint-family identities, #254 (MOD-254-DEPLOYMENT)

The build\/package contract that publishes __both__ checkpoint-family
identities: the historical deployed generation and the new #254 family.

This is deliberately not the S254-3 ordered release registry and not a live
cutover.  It answers one question — which checkpoint families does this build
claim to know about, and are their identities and predecessor edges coherent —
so that a build which silently drops, relabels, or renumbers a family fails
here rather than at a cutover desk.

The historical entry is immutable released evidence: its minting policy is the
deployed one and it is never relabelled as the new family.  The new family is
published __beside__ it.  Release identity is the applied program hash, so a
family is named by its policy and its lineage is the single predecessor policy
it accepts -- there is no generation integer anywhere in this contract.
-}
module Cardano.KERI.Deployment.CheckpointMigration (
    CheckpointFamilyIdentity (..),
    PublicationError (..),
    historicalCheckpointFamily,
    migrationCheckpointFamily,
    publishedCheckpointFamilies,
    checkpointFamilyPublicationErrors,
) where

import Data.Map.Strict qualified as Map
import Data.Maybe (
    isNothing,
 )
import Data.Set qualified as Set
import Data.Text (
    Text,
 )
import Data.Text qualified as Text

{- | One published checkpoint family: its minting policy, the single
predecessor policy it accepts (absent for the first), and the source commit
that produced it.
-}
data CheckpointFamilyIdentity = CheckpointFamilyIdentity
    { cfiPolicy :: !Text
    -- ^ the minting policy id, lowercase hex
    , cfiPredecessor :: !(Maybe Text)
    {- ^ the single predecessor policy this family accepts, absent for the
    first: release identity is the applied hash, so lineage is a policy,
    never a generation integer
    -}
    , cfiSourceCommit :: !Text
    -- ^ the commit whose build produced this family
    , cfiManifestPath :: !Text
    -- ^ the released manifest recording it, when one exists
    }
    deriving stock (Show, Eq)

-- | Why a published family set is not coherent.
data PublicationError
    = -- | two entries claim the same minting policy
      DuplicateFamilyPolicy !Text
    | -- | a predecessor edge names a policy that is not published
      UnknownPredecessor !Text !Text
    | -- | more than one family claims to be the first
      MultipleRootFamilies
    | -- | an identity field is empty
      EmptyIdentityField !Text !Text
    | -- | the historical family is absent or was relabelled
      HistoricalFamilyNotPreserved
    | -- | this contract is not implemented
      PublicationNotImplemented
    deriving stock (Show, Eq)

{- | The deployed preprod M1 checkpoint family.  Immutable released evidence:
its policy and manifest entry are historical fact.
-}
historicalCheckpointFamily :: CheckpointFamilyIdentity
historicalCheckpointFamily =
    CheckpointFamilyIdentity
        { cfiPolicy = "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
        , cfiPredecessor = Nothing
        , cfiSourceCommit = "50a582064ddfde15ebfa3649c6b6fea8d39fc697"
        , cfiManifestPath = "deploy/preprod/m1-manifest.json"
        }

{- | The #254 checkpoint family, accepting the deployed policy as its single
predecessor.  It carries no manifest path because it is not deployed -- this is
a build contract, not a cutover record.
-}
migrationCheckpointFamily :: CheckpointFamilyIdentity
migrationCheckpointFamily =
    CheckpointFamilyIdentity
        { cfiPolicy = "" -- derived at deployment; see S254-3
        , cfiPredecessor =
            Just "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
        , cfiSourceCommit = ""
        , cfiManifestPath = ""
        }

-- | Both families, oldest first.  History is retained, never replaced.
publishedCheckpointFamilies :: [CheckpointFamilyIdentity]
publishedCheckpointFamilies =
    [historicalCheckpointFamily, migrationCheckpointFamily]

{- | Every structural fault in a published family set, or an empty list.  All
faults are reported together so one build reveals the whole picture rather
than one fault per rebuild.

Identity fields are required only of __released__ entries — those carrying a
manifest path.  The new family legitimately has no policy or commit yet: it is
not deployed, and demanding one here would force a placeholder that looks like
a release.
-}
checkpointFamilyPublicationErrors ::
    [CheckpointFamilyIdentity] -> [PublicationError]
checkpointFamilyPublicationErrors families =
    concat
        [ duplicates
        , edgeErrors
        , rootErrors
        , identityErrors
        , historicalErrors
        ]
  where
    policies = map cfiPolicy families
    published = Set.fromList policies

    duplicates =
        [ DuplicateFamilyPolicy policy
        | (policy, count) <- Map.toList (counted policies)
        , count > (1 :: Int)
        ]
    counted = foldr (\v -> Map.insertWith (+) v 1) Map.empty

    edgeErrors =
        concat
            [ case cfiPredecessor family of
                Nothing -> []
                Just predecessor
                    | not (predecessor `Set.member` published) ->
                        [UnknownPredecessor (cfiPolicy family) predecessor]
                    | otherwise -> []
            | family <- families
            ]

    rootErrors
        | length [() | family <- families, isNothing (cfiPredecessor family)] > 1 =
            [MultipleRootFamilies]
        | otherwise = []

    identityErrors =
        concat
            [ [ EmptyIdentityField (cfiPolicy family) name
              | (name, value) <-
                    [("policy", cfiPolicy family), ("commit", cfiSourceCommit family)]
              , Text.null value
              ]
            | family <- families
            , not (Text.null (cfiManifestPath family))
            ]

    -- The deployed family must still be published, with its own policy and
    -- its own manifest entry. This is the check that fails if released history
    -- is ever relabelled as the new family instead of kept beside it.
    historicalErrors
        | any isHistorical families = []
        | otherwise = [HistoricalFamilyNotPreserved]
    isHistorical family =
        cfiPolicy family == cfiPolicy historicalCheckpointFamily
            && cfiManifestPath family == cfiManifestPath historicalCheckpointFamily
