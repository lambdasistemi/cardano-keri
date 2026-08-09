{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.ParityOracle.Capture
Description : T240-S1-01 -- shared base/candidate parity-oracle capture

RQ-240-09 (parity oracle): both the frozen base @5bf8498@ and the migrated
candidate run the exact same deterministic-fixture specs already proven by
#181 (see each spec's own @standInRuntime@\/@testPParams@), and each success
path calls 'captureShape' once with the exact signed 'ConwayTx' it just
built and independently asserted on. This module performs no fixture
construction and no assertion of its own, so it cannot itself be the source
of a parity difference; it only names and serializes what the spec already
proved.

Capture is opt-in via @CKERI_PARITY_ORACLE_DIR@ so every existing spec run
(a plain @cabal test@, CI, `just deployment-unit`, ...) stays exactly as
hermetic and side-effect-free as before; a parity-oracle run additionally
sets that one environment variable.
-}
module Cardano.KERI.Deployment.ParityOracle.Capture (captureShape) where

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Lens.Micro ((^.))
import System.Directory (createDirectoryIfMissing)
import System.Environment (lookupEnv)
import System.FilePath ((<.>), (</>))

{- | Write one write-shape's canonical, hex-encoded transaction body plus
its already-rendered transaction id under
@CKERI_PARITY_ORACLE_DIR/\<shapeName\>@, when that variable is set; a no-op
otherwise (T240-S1-01's opt-in contract). @shapeName@ is a stable
per-call-site identifier (e.g. \"premint\", \"register\", \"advance\"), not
derived from anything the migration changes, so base and candidate runs
write the same file names for the same shape.
-}
captureShape :: String -> Text -> ConwayTx -> IO ()
captureShape shapeName txId tx = do
    maybeDir <- lookupEnv "CKERI_PARITY_ORACLE_DIR"
    case maybeDir of
        Nothing -> pure ()
        Just dir -> do
            createDirectoryIfMissing True dir
            TIO.writeFile (dir </> shapeName <.> "txid") (txId <> "\n")
            TIO.writeFile
                (dir </> shapeName <.> "txbody.cbor.hex")
                (hexOf (canonicalTxBodyBytes tx) <> "\n")
  where
    hexOf = TE.decodeUtf8 . convertToBase Base16

{- | The canonical CBOR encoding of one signed transaction's own body, at
the protocol version this repository already decodes ledger outputs with
(matching "Cardano.KERI.Indexer.ChainQuery"'s @decodeFull (eraProtVerLow
\@ConwayEra) ...@ counterpart) -- never the whole 'ConwayTx' (witnesses
would fold the signing envelope's own non-determinism into a value the
spec calls a *transaction-body* oracle).
-}
canonicalTxBodyBytes :: ConwayTx -> ByteString
canonicalTxBodyBytes tx = serialize' (eraProtVerLow @ConwayEra) (tx ^. bodyTxL)
