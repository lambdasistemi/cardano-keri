{- |
Module      : Cardano.KERI.AID.ReaderStatusSpec
Description : The reader's status table over the frozen corpus (#353)

Layer one of the status component. It is a test of the decision table, and of
nothing that produces the table's inputs.

* __Supplied__ from the frozen corpus (@lean\/reader-status-vectors.json@, read
  through "Cardano.KERI.AID.ReaderCorpus") for every row: the custody the Lean
  classifier read, whether the history admits a holder, and the leaf the
  history established. They are the answer cells @custody@, @admitsHolder@ and
  @leaf@; nothing here derives them from raw evidence, so nothing here
  validates the production of any of them.
* __Executed__: the production 'readerStatus', with the environment of the
  row's own evidence and the corpus context, so the authentication guard runs
  on actual row data.
* __Expected__: the answer cell @status@ and nothing else. It is read only as
  the expectation.

For a combination of the three supplied values that no authenticated row
holds, the controls bind the decision branches to the model's table
(@verdict@ in @ReaderStatus.lean@) rather than restate it: a branch whose
clause ignores a value is checked against the corpus' own answer at the same
combination with the ignored value changed, and a branch with no clause is
checked as unavailable. No rival table is written here.

Synthetic pairs. The table is total over its three inputs, but real evidence
constrains them: a history of the identifier's registry through the asked point
that agrees with a holder and establishes a leaf establishes the active one
(@leaf_allows_holder_iff@, @ReaderStatusGoals.lean@). A holder the history
admits paired with an unknown or terminal leaf is therefore a control of the
table, named as such in the examples below; it is not a state the evidence of a
reader can reach.
-}
module Cardano.KERI.AID.ReaderStatusSpec (
    spec,
) where

import Cardano.KERI.AID.Application (Credential (..))
import Cardano.KERI.AID.Consumer (
    Context (..),
    Environment (..),
    Release (..),
 )
import Cardano.KERI.AID.Reader (
    Custody (..),
    Determined (..),
    RegistryLeaf (..),
    Status (..),
    readerStatus,
 )
import Cardano.KERI.AID.ReaderCorpus (
    Corpus (..),
    Row (..),
    loadCorpus,
    rowNamed,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (nub)
import Test.Hspec (
    Spec,
    describe,
    it,
    runIO,
    shouldBe,
    shouldSatisfy,
 )

-- | Every combination of the three supplied values.
allCombinations :: [Determined]
allCombinations =
    [ Determined custody admits leaf
    | custody <- [minBound .. maxBound]
    , admits <- [False, True]
    , leaf <- Nothing : map Just [minBound .. maxBound]
    ]

-- | A credential, policy or hash of the width of the corpus' own, that no row uses.
anotherBytes :: ByteString
anotherBytes = BS.replicate 28 0x0c

credentialBytes :: Credential -> ByteString
credentialBytes = \case
    ScriptCredential b -> b
    KeyCredential b -> b

-- | The release with one field changed, for each field.
releaseChanges :: [(String, Release -> Release)]
releaseChanges =
    [ ("the application policy", \r -> r{rlApplicationPolicy = anotherBytes})
    , ("the application credential", \r -> r{rlApplicationCredential = anotherBytes})
    , ("the state program", \r -> r{rlStateProgram = anotherBytes})
    , ("the state policy", \r -> r{rlStatePolicy = anotherBytes})
    ]

{- | Changes of a resolved environment, each of which makes it fail to
authenticate the context.
-}
environmentRefusals :: Context -> [(String, Environment -> Environment)]
environmentRefusals context =
    [("another network", \e -> e{envNetwork = envNetwork e + 1})]
        <> [("an unresolved release", \e -> e{envRelease = Nothing})]
        <> [ ("another release in " <> field, \e -> e{envRelease = Just (change (cxRelease context))})
           | (field, change) <- releaseChanges
           ]
        <> [ ("an unresolved checkpoint credential", \e -> e{envCheckpointCredential = Nothing})
           , ("another checkpoint credential", \e -> e{envCheckpointCredential = Just (ScriptCredential anotherBytes)})
           ,
               ( "a key credential with the checkpoint credential's bytes"
               , \e ->
                    e{envCheckpointCredential = Just (KeyCredential (credentialBytes (cxCheckpointCredential context)))}
               )
           ]

-- | Changes of the relying context, each of which makes the resolved environment fail to authenticate it.
contextRefusals :: [(String, Context -> Context)]
contextRefusals =
    [("another network", \c -> c{cxNetwork = cxNetwork c + 1})]
        <> [ ("another release in " <> field, \c -> c{cxRelease = change (cxRelease c)})
           | (field, change) <- releaseChanges
           ]
        <> [("another checkpoint credential", \c -> c{cxCheckpointCredential = ScriptCredential anotherBytes})]

spec :: Spec
spec = describe "reader status (reader-status-vectors.json)" $ do
    corpus <- runIO loadCorpus
    let context = cpContext corpus
        rows = cpRows corpus
        -- the environment the trusted integration resolves for the context
        authentic =
            Environment
                { envNetwork = cxNetwork context
                , envRelease = Just (cxRelease context)
                , envCheckpointCredential = Just (cxCheckpointCredential context)
                }
        authenticated = [r | r <- rows, rowEnvironment r == authentic]
        answered = [r | r <- rows, rowStatus r /= Unavailable]
        statusOfRow r = readerStatus (rowEnvironment r) context (rowDetermined r)
        supplied = [rowDetermined r | r <- authenticated]
        statusesAt d = nub [rowStatus r | r <- authenticated, rowDetermined r == d]
        absentFromCorpus = [d | d <- allCombinations, d `notElem` supplied]

    describe "the corpus the table is driven over" $ do
        it "is the frozen corpus: 72 rows with distinct names" $ do
            length rows `shouldBe` 72
            length (nub (map rowId rows)) `shouldBe` 72
        it "answers each of the five outcomes in several rows" $
            mapM_
                (\s -> (s, length [() | r <- rows, rowStatus r == s]) `shouldSatisfy` ((>= 3) . snd))
                [minBound .. maxBound]
        it "holds every custody, both history agreements, and every leaf as well as a missing one" $ do
            length (nub (map (dtCustody . rowDetermined) rows)) `shouldBe` length [minBound .. maxBound :: Custody]
            length (nub (map (dtHistoryAdmitsHolder . rowDetermined) rows)) `shouldBe` 2
            length (nub (map (dtEstablishedLeaf . rowDetermined) rows)) `shouldBe` 1 + length [minBound .. maxBound :: RegistryLeaf]
        it "keeps the rows that do not authenticate apart: they are the context refusals of the corpus" $ do
            length authenticated `shouldSatisfy` (< length rows)
            mapM_ (\r -> (rowId r, rowStatus r) `shouldBe` (rowId r, Unavailable)) [r | r <- rows, rowId r `notElem` map rowId authenticated]
        it "gives every combination it holds one status" $
            mapM_ (\d -> (d, length (statusesAt d)) `shouldBe` (d, 1)) supplied

    describe "the decision table over the 72 rows" $ do
        it "answers every row with the status the corpus gives it" $
            mapM_ (\r -> (rowId r, statusOfRow r) `shouldBe` (rowId r, rowStatus r)) rows
        it "answers each of the five outcomes" $
            nub (map statusOfRow rows) `shouldSatisfy` ((== length [minBound .. maxBound :: Status]) . length)
        it "answers a termination request that the history agrees with as pending termination" $ do
            let r = rowNamed corpus "pending-requested-with-history"
            (dtCustody (rowDetermined r), dtHistoryAdmitsHolder (rowDetermined r)) `shouldBe` (CustodyRequest, True)
            statusOfRow r `shouldBe` PendingTermination
        it "answers a history that contradicts the holder as unavailable" $ do
            let r = rowNamed corpus "pending-requested-with-history"
            readerStatus (rowEnvironment r) context (rowDetermined r){dtHistoryAdmitsHolder = False} `shouldBe` Unavailable

    describe "an established unknown leaf and a missing leaf are different" $ do
        let r = rowNamed corpus "never-registered-history-only"
            withLeaf leaf = readerStatus (rowEnvironment r) context (rowDetermined r){dtEstablishedLeaf = leaf}
        it "the row establishes the unknown leaf and answers never registered" $ do
            dtEstablishedLeaf (rowDetermined r) `shouldBe` Just LeafUnknown
            statusOfRow r `shouldBe` NeverRegistered
        it "the same row with no leaf established answers unavailable" $
            withLeaf Nothing `shouldBe` Unavailable
        it "the same row with the terminal leaf answers terminal, with the active leaf unavailable" $ do
            withLeaf (Just LeafTerminal) `shouldBe` Terminal
            withLeaf (Just LeafActive) `shouldBe` Unavailable

    describe "an environment that does not authenticate the context answers unavailable" $ do
        it "is exercised over rows that do answer" $
            length answered `shouldSatisfy` (>= 20)
        mapM_
            ( \(name, mutate) ->
                it ("whatever else is established: " <> name) $
                    mapM_
                        ( \r -> do
                            let environment = rowEnvironment r
                            (rowId r, mutate environment /= environment) `shouldBe` (rowId r, True)
                            (rowId r, readerStatus (mutate environment) context (rowDetermined r)) `shouldBe` (rowId r, Unavailable)
                        )
                        answered
            )
            (environmentRefusals context)
        mapM_
            ( \(name, mutate) ->
                it ("whatever else is established, by the context: " <> name) $
                    mapM_
                        ( \r -> do
                            (rowId r, mutate context /= context) `shouldBe` (rowId r, True)
                            (rowId r, readerStatus (rowEnvironment r) (mutate context) (rowDetermined r)) `shouldBe` (rowId r, Unavailable)
                        )
                        answered
            )
            contextRefusals

    describe "combinations of the supplied values that no authenticated row holds" $ do
        let holders = [CustodyLive, CustodyConvicted, CustodyRequest]
            settled = [CustodyNotEstablished, CustodyAbsent]
            holderAdmitted = [d | d <- absentFromCorpus, dtCustody d `elem` holders, dtHistoryAdmitsHolder d]
            holderRefused = [d | d <- absentFromCorpus, dtCustody d `elem` holders, not (dtHistoryAdmitsHolder d)]
            leafDecides = [d | d <- absentFromCorpus, dtCustody d `elem` settled]
            unrecognised = [d | d <- absentFromCorpus, dtCustody d == CustodyInconsistent]
            -- the status the corpus gives a holder custody the history admits, whatever the leaf
            holderAnswer c = nub [rowStatus r | r <- authenticated, dtCustody (rowDetermined r) == c, dtHistoryAdmitsHolder (rowDetermined r), rowStatus r /= Unavailable]
            check = readerStatus authentic context
        it "fall in four families that together are all of them, each non-empty" $ do
            length absentFromCorpus `shouldSatisfy` (>= 20)
            length holderAdmitted + length holderRefused + length leafDecides + length unrecognised
                `shouldBe` length absentFromCorpus
            mapM_ (\family -> length family `shouldSatisfy` (> 0)) [holderAdmitted, holderRefused, leafDecides, unrecognised]
        it "a holder the history admits decides alone, whatever the leaf; pairs with an unknown or terminal leaf are synthetic table controls (the three holder clauses of verdict)" $
            mapM_
                (\d -> (d, [check d]) `shouldBe` (d, holderAnswer (dtCustody d)))
                holderAdmitted
        it "a holder the history refuses is never decided by the leaf (no clause of verdict)" $
            mapM_ (\d -> (d, check d) `shouldBe` (d, Unavailable)) holderRefused
        it "with no holder the leaf decides alone, whatever the history agreement (the terminal and never registered clauses)" $
            mapM_
                ( \d -> do
                    let counterpart = d{dtHistoryAdmitsHolder = not (dtHistoryAdmitsHolder d)}
                    (d, length (statusesAt counterpart)) `shouldBe` (d, 1)
                    (d, [check d]) `shouldBe` (d, statusesAt counterpart)
                )
                leafDecides
        it "an inconsistent custody is never decided (no clause of verdict)" $
            mapM_ (\d -> (d, check d) `shouldBe` (d, Unavailable)) unrecognised
