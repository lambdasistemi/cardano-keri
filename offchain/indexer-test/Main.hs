module Main (main) where

import Cardano.KERI.Indexer.AppSpec qualified as AppSpec
import Cardano.KERI.Indexer.AtomicitySpec qualified as AtomicitySpec
import Cardano.KERI.Indexer.BoardSpec qualified as BoardSpec
import Cardano.KERI.Indexer.CodecsSpec qualified as CodecsSpec
import Cardano.KERI.Indexer.FollowerSpec qualified as FollowerSpec
import Cardano.KERI.Indexer.IdentityReadSpec qualified as IdentityReadSpec
import Cardano.KERI.Indexer.Query.ServerSpec qualified as QueryServerSpec
import Cardano.KERI.Indexer.Query.SwaggerDriftSpec qualified as QuerySwaggerDriftSpec
import Cardano.KERI.Indexer.Query.TxSpec qualified as QueryTxSpec
import Cardano.KERI.Indexer.Query.TypesSpec qualified as QueryTypesSpec
import Cardano.KERI.Indexer.ReadsSpec qualified as ReadsSpec
import Cardano.KERI.Indexer.ReleaseHoldingsSpec qualified as ReleaseHoldingsSpec
import Cardano.KERI.Indexer.ReleaseReaderSpec qualified as ReleaseReaderSpec
import Cardano.KERI.Indexer.RequestHolderSpec qualified as RequestHolderSpec
import Cardano.KERI.Indexer.ResumeSpec qualified as ResumeSpec
import Cardano.KERI.Indexer.RollbackSpec qualified as RollbackSpec
import Cardano.KERI.Indexer.StoreBindingSpec (holdStoreOpen)
import Cardano.KERI.Indexer.StoreBindingSpec qualified as StoreBindingSpec
import System.Environment (getArgs)
import Test.Hspec (hspec)

{- | The suite, or (for the store-binding examples, which need a holder in a
separate process) one process that opens a store and holds it until its input ends.
-}
main :: IO ()
main = do
    arguments <- getArgs
    case arguments of
        ["--hold-store", path] -> holdStoreOpen path
        _ -> suite

suite :: IO ()
suite = hspec $ do
    AppSpec.spec
    AtomicitySpec.spec
    BoardSpec.spec
    CodecsSpec.spec
    FollowerSpec.spec
    IdentityReadSpec.spec
    QueryServerSpec.spec
    QuerySwaggerDriftSpec.spec
    QueryTxSpec.spec
    QueryTypesSpec.spec
    ReadsSpec.spec
    ResumeSpec.spec
    RollbackSpec.spec
    ReleaseHoldingsSpec.spec
    ReleaseReaderSpec.spec
    RequestHolderSpec.spec
    StoreBindingSpec.spec
