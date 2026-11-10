{-# LANGUAGE OverloadedStrings #-}

-- | Prints the identities of this generation's registry scripts, one line each:
-- @<name> <script hash, hex> <applied program bytes>@.
--
-- The scripts are the library's own derivation ('deriveRegistryScripts') over the
-- blueprint compiled from the repository's sources, with the deployed
-- generation's terms and a fixed reference seed (an all-zero transaction id,
-- index 0). The application and the state script do not depend on the seed;
-- the checkpoint validator does. Run through @scripts/registry-identities.sh@.
module Main (main) where

import Cardano.KERI.AID.Application (OutputReference (..), RegistryIdentity (..))
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Application (ApplicationParameters (..))
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    deployedCheckpointTerms,
    loadBlueprint,
    scriptHashBytes,
 )
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Short qualified as SBS
import System.Environment (getArgs)

terms :: RegistryTerms
terms =
    RegistryTerms
        { registryCheckpointTerms = deployedCheckpointTerms
        , registryParameters =
            ApplicationParameters
                { registrationCost = 1_000_000
                , minimumTip = 500_000
                , processTime = 90_000
                , bookingWidth = 5_000
                }
        }

hexOf :: ByteString -> String
hexOf = BC.unpack . convertToBase Base16

line :: String -> ByteString -> Int -> String
line name hash size = name <> " " <> hexOf hash <> " " <> show size

main :: IO ()
main = do
    [blueprintPath] <- getArgs
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    let seed = OutputReference (BS.replicate 32 0) 0
    scripts <-
        either fail pure (deriveRegistryScripts stateTemplate terms seed blueprint)
    let application = scriptsApplication scripts
        checkpoint = scriptsCheckpoint scripts
    putStrLn $
        line
            "application"
            (scriptHashBytes (artifactScriptHash application))
            (SBS.length (artifactProgram application))
    putStrLn $
        line
            "state-script"
            (scriptsStateHash scripts)
            (SBS.length (scriptsStateProgram scripts))
    putStrLn $
        line
            "checkpoint-register"
            (scriptHashBytes (artifactScriptHash checkpoint))
            (SBS.length (artifactProgram checkpoint))
    putStrLn ("registry-name " <> hexOf (registryName (scriptsRegistry scripts)))
