{-# LANGUAGE NumericUnderscores #-}

-- | Prints the identities of the registry the devnet journey creates, one
-- @label|value@ row each, in the labels of the identities page.
--
-- The terms are the journey's own ('devnetTerms', the module the journey
-- imports). The scripts are the library's derivation ('deriveRegistryScripts')
-- over the blueprint compiled from the repository's sources, derived for two
-- reference seeds: the program stops with an error unless the application and
-- the state script are the same for both and the checkpoint validator is not,
-- so the statement that only the checkpoint validator depends on the seed is
-- derived, not declared. Run through @scripts/registry-identities.sh@.
module Main (main) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    OutputReference (..),
    RegistryIdentity (..),
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.E2E.DevnetTerms (devnetTerms)
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.Script (
    CheckpointTerms (..),
    ScriptArtifact (..),
    loadBlueprint,
    scriptHashBytes,
 )
import Control.Monad (unless)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Short qualified as SBS
import System.Environment (getArgs)

hexOf :: ByteString -> String
hexOf = BC.unpack . convertToBase Base16

row :: String -> String -> IO ()
row label value = putStrLn (label <> "|" <> value)

main :: IO ()
main = do
    [blueprintPath] <- getArgs
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    let derive seed =
            either fail pure (deriveRegistryScripts stateTemplate devnetTerms seed blueprint)
    scripts <- derive (OutputReference (BS.replicate 32 0) 0)
    other <- derive (OutputReference (BS.replicate 32 1) 1)
    let application = scriptsApplication scripts
        checkpoint = scriptsCheckpoint scripts
        applicationHash = scriptHashBytes (artifactScriptHash application)
        checkpointHash = scriptHashBytes (artifactScriptHash checkpoint)
        checkpointTerms = registryCheckpointTerms devnetTerms
        parameters = registryParameters devnetTerms
    unless (applicationHash == scriptHashBytes (artifactScriptHash (scriptsApplication other))) $
        fail "the application depends on the seed"
    unless (scriptsStateHash scripts == scriptsStateHash other) $
        fail "the state script depends on the seed"
    unless (checkpointHash /= scriptHashBytes (artifactScriptHash (scriptsCheckpoint other))) $
        fail "the checkpoint validator does not depend on the seed"
    row "Network discriminator" (show (termsNetwork checkpointTerms))
    row "Registration deposit (lovelace)" (show (termsDeposit checkpointTerms))
    row "Freeze bond (lovelace)" (show (termsFreezeBond checkpointTerms))
    row "Premium (lovelace)" (show (termsPremium checkpointTerms))
    row "Registration cost (lovelace)" (show (registrationCost parameters))
    row "Minimum tip (lovelace)" (show (minimumTip parameters))
    row "Processing time (milliseconds)" (show (processTime parameters))
    row "Booking width (milliseconds)" (show (bookingWidth parameters))
    row "Checkpoint minimum ADA (lovelace)" (show (registryMinimumAda devnetTerms))
    row "Termination request carrier (lovelace)" (show (registryTerminationCarrier devnetTerms))
    row "Application script hash" (hexOf applicationHash)
    row "Application program bytes" (show (SBS.length (artifactProgram application)))
    row "State script hash" (hexOf (scriptsStateHash scripts))
    row "State script program bytes" (show (SBS.length (scriptsStateProgram scripts)))
    row "Application and state script across two seeds" "the same"
    row "Checkpoint validator script hash" (hexOf checkpointHash)
    row "Checkpoint validator program bytes" (show (SBS.length (artifactProgram checkpoint)))
    row "Reference registry name" (hexOf (registryName (scriptsRegistry scripts)))
