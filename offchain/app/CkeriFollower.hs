module Main (main) where

import Cardano.KERI.Indexer.App (
    FollowerSettings,
    runFollowerApp,
 )
import OptEnvConf (
    runSettingsParser,
 )
import Paths_cardano_keri (
    version,
 )

main :: IO ()
main = do
    settings <-
        runSettingsParser
            version
            "Run the KERI chain follower with an interactive local-store query prompt"
    runFollowerApp (settings :: FollowerSettings)
