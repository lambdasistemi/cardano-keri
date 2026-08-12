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

The historical entry is immutable released evidence: its version stays
@0@ (the @v1CheckpointVersion@ of the M1 release, whose name refers to the
manifest schema, not the family generation) and it is never relabelled as the
new family.  The new family is published __beside__ it.
-}
module Cardano.KERI.Deployment.CheckpointMigration (
    CheckpointFamilyIdentity (..),
    PublicationError (..),
    historicalCheckpointFamily,
    migrationCheckpointFamily,
    publishedCheckpointFamilies,
    checkpointFamilyPublicationErrors,
) where

import Cardano.KERI.Deployment.Script (
    checkpointFamilyV1Version,
    v1CheckpointVersion,
 )
import Data.Text (
    Text,
 )

{- | One published checkpoint family: its generation, minting policy, the
address its ACTIVE role occupies, the generation it succeeds (absent for the
first), and the source commit that produced it.
-}
data CheckpointFamilyIdentity = CheckpointFamilyIdentity
    { cfiVersion :: !Integer
    -- ^ the program generation (DAT-254-VERSION)
    , cfiPolicy :: !Text
    -- ^ the minting policy id, lowercase hex
    , cfiPredecessor :: !(Maybe Integer)
    -- ^ the generation this one succeeds, absent for the first
    , cfiSourceCommit :: !Text
    -- ^ the commit whose build produced this family
    , cfiManifestPath :: !Text
    -- ^ the released manifest recording it, when one exists
    }
    deriving stock (Show, Eq)

-- | Why a published family set is not coherent.
data PublicationError
    = -- | two entries claim the same generation
      DuplicateFamilyVersion !Integer
    | -- | a predecessor edge names a generation that is not published
      UnknownPredecessor !Integer !Integer
    | -- | generations are not contiguous along the predecessor edge
      NonContiguousFamilies !Integer !Integer
    | -- | more than one family claims to be the first
      MultipleRootFamilies
    | -- | an identity field is empty
      EmptyIdentityField !Integer !Text
    | -- | the historical family is absent or was relabelled
      HistoricalFamilyNotPreserved
    | -- | this contract is not implemented
      PublicationNotImplemented
    deriving stock (Show, Eq)

{- | The deployed preprod M1 checkpoint family.  Immutable released evidence:
its generation is @v1CheckpointVersion@ (= 0) and its manifest entry is
historical fact.
-}
historicalCheckpointFamily :: CheckpointFamilyIdentity
historicalCheckpointFamily =
    CheckpointFamilyIdentity
        { cfiVersion = v1CheckpointVersion
        , cfiPolicy = "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
        , cfiPredecessor = Nothing
        , cfiSourceCommit = "50a582064ddfde15ebfa3649c6b6fea8d39fc697"
        , cfiManifestPath = "deploy/preprod/m1-manifest.json"
        }

{- | The #254 checkpoint family: generation 1, succeeding the deployed
generation 0.  It carries no manifest path because it is not deployed — this
is a build contract, not a cutover record.
-}
migrationCheckpointFamily :: CheckpointFamilyIdentity
migrationCheckpointFamily =
    CheckpointFamilyIdentity
        { cfiVersion = checkpointFamilyV1Version
        , cfiPolicy = "" -- derived at deployment; see S254-3
        , cfiPredecessor = Just v1CheckpointVersion
        , cfiSourceCommit = ""
        , cfiManifestPath = ""
        }

-- | Both families, oldest first.  History is retained, never replaced.
publishedCheckpointFamilies :: [CheckpointFamilyIdentity]
publishedCheckpointFamilies =
    [historicalCheckpointFamily, migrationCheckpointFamily]

{- | Every structural fault in a published family set, or an empty list.  All
faults are reported together so one build reveals the whole picture.
-}
checkpointFamilyPublicationErrors ::
    [CheckpointFamilyIdentity] -> [PublicationError]
checkpointFamilyPublicationErrors _ = [PublicationNotImplemented]
