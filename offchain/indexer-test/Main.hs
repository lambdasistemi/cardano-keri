module Main (main) where

import Cardano.KERI.Indexer.AppSpec qualified as AppSpec
import Cardano.KERI.Indexer.AtomicitySpec qualified as AtomicitySpec
import Cardano.KERI.Indexer.BoardSpec qualified as BoardSpec
import Cardano.KERI.Indexer.CodecsSpec qualified as CodecsSpec
import Cardano.KERI.Indexer.FollowerSpec qualified as FollowerSpec
import Cardano.KERI.Indexer.Query.ServerSpec qualified as QueryServerSpec
import Cardano.KERI.Indexer.Query.SwaggerDriftSpec qualified as QuerySwaggerDriftSpec
import Cardano.KERI.Indexer.Query.TypesSpec qualified as QueryTypesSpec
import Cardano.KERI.Indexer.ReadsSpec qualified as ReadsSpec
import Cardano.KERI.Indexer.ResumeSpec qualified as ResumeSpec
import Cardano.KERI.Indexer.RollbackSpec qualified as RollbackSpec
import Cardano.KERI.Indexer.ShellSpec qualified as ShellSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    AppSpec.spec
    AtomicitySpec.spec
    BoardSpec.spec
    CodecsSpec.spec
    FollowerSpec.spec
    QueryServerSpec.spec
    QuerySwaggerDriftSpec.spec
    QueryTypesSpec.spec
    ReadsSpec.spec
    ResumeSpec.spec
    RollbackSpec.spec
    ShellSpec.spec
