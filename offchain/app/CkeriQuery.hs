module Main (main) where

import Cardano.KERI.Indexer.App (
    ReaderSettings,
    runReaderApp,
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
            "Run the KERI query endpoint: checkpoint, board, and watchability answers over HTTP"
    runReaderApp (settings :: ReaderSettings)
