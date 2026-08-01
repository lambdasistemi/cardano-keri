module Main (main) where

import Cardano.KERI.Indexer.AppSpec qualified as AppSpec
import Cardano.KERI.Indexer.AtomicitySpec qualified as AtomicitySpec
import Cardano.KERI.Indexer.CodecsSpec qualified as CodecsSpec
import Cardano.KERI.Indexer.FollowerSpec qualified as FollowerSpec
import Cardano.KERI.Indexer.ReadsSpec qualified as ReadsSpec
import Cardano.KERI.Indexer.ResumeSpec qualified as ResumeSpec
import Cardano.KERI.Indexer.RollbackSpec qualified as RollbackSpec
import Cardano.KERI.Indexer.ShellSpec qualified as ShellSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    AppSpec.spec
    AtomicitySpec.spec
    CodecsSpec.spec
    FollowerSpec.spec
    ReadsSpec.spec
    ResumeSpec.spec
    RollbackSpec.spec
    ShellSpec.spec
