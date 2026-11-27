-- Test-side helper: enact the protocol-version-11 governance transition on a local devnet node.
-- usage: runghc EnactPV11.hs <node socket>
import Cardano.Node.Client.E2E.Governance (assertPV11Enacted, enactPV11Transition)
import Cardano.Node.Client.E2E.Setup (devnetMagic)
import Cardano.Node.Client.N2C.Connection (newLSQChannel, newLTxSChannel, runNodeClient)
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Control.Concurrent.Async (async, cancel)
import Control.Exception (finally)
import System.Environment (getArgs)

main :: IO ()
main = do
    [socket] <- getArgs
    lsq <- newLSQChannel 16
    ltxs <- newLTxSChannel 16
    client <- async (runNodeClient devnetMagic socket lsq ltxs)
    ( do
            enactPV11Transition lsq ltxs
            assertPV11Enacted (mkN2CProvider lsq)
            putStrLn "pv11-enacted"
        )
        `finally` cancel client
