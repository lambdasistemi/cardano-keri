{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.Indexer.PublicSurfaceSpec
Description : #262 A-262-03 — the eager-rejection property over the COMPLETE public export surface

Three audits found the same class at three different names: the runner the
write path used, the two generic snapshot runners it did not cover, and then
'Cardano.KERI.Indexer.ChainQuery.runLocalInterpreter' one layer below those.
Each repair was correct for the surface it named, and each was followed by an
audit naming the next one. That is one failure repeated: the property was
established per NAME instead of over the SURFACE, and a fourth name exists
for as long as the enumeration is written by hand (NOTE-004).

So this module does not contain a list of functions to check. It DERIVES the
set of public entry points that can be handed an eagerly-rejectable input,
from the repository's own structure, and then requires that every derived
member is one the behaviour suites actually exercise. A newly exported
qualifying entry point therefore fails this property automatically, which is
the only form of the check that cannot rot.

Three derivations, each from a different source of truth, none of them a
hand-maintained list of names:

  * WHICH MODULES ARE PUBLIC comes from @cardano-keri.cabal@, parsed by
    Cabal's own parser (the same technique, and the same reason, as
    "Cardano.KERI.CLI.WriteCompositionBoundarySpec": a hand parser is brittle
    in the direction that stays silent);
  * WHAT EACH MODULE EXPORTS, and each export's type, comes from that
    module's own source;
  * WHICH INPUT TYPES CAN BE EAGERLY REJECTED comes from the smart
    constructors in "Cardano.KERI.ChainQuery.Program" that actually call a
    validator, plus the records that embed those types.

The local layer needs one derivation the type system cannot give: a public
export can open a store transaction without mentioning a program in its type
(a wrapper does exactly that). So membership there is call-graph
reachability to the store runner, computed over the interpreter module's own
source.

Every derivation carries a control proving it can see something known to be
present AND exclude something known to be absent, because a derivation that
silently returned the empty set would make this whole property vacuous — the
precise failure mode the three prior submissions kept shipping.
-}
module Cardano.KERI.Indexer.PublicSurfaceSpec (spec) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    runChainQuery,
    runChainQueryResultSnapshot,
 )
import Cardano.KERI.ChainQuery.Koios (
    koiosBoardCatalog,
    koiosCurrentCheckpoint,
    koiosLiveCheckpoints,
    koiosReferenceScripts,
 )
import Cardano.KERI.ChainQuery.Program (
    ChainQuery,
    currentCheckpoint,
    eagerRejection,
    foldChainQuery,
    outputAt,
    payerUtxos,
 )
import Cardano.KERI.ChainQuery.Registration (
    RegistrationQueryRequest (..),
    runRegistrationSnapshot,
 )
import Cardano.KERI.ChainQuery.Types (
    ActiveCheckpoint,
    BoardLocator (..),
    ChainAssetUtxo,
    ChainQueryError (..),
    CheckpointLocator (..),
    ColdOr (Cold),
    OutputLocator (..),
    QuerySource (SourceLocal),
    SnapshotConsistency (AtomicLocal),
 )
import Cardano.KERI.Deployment.CLI (
    RegisterRuntime (..),
    RegisterSettings (..),
    runRegisterWith,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (readEndpointBoardManifest)
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
    ScriptEntry (..),
    readManifest,
 )
import Cardano.KERI.Indexer.ChainQuery (
    LocalQueryScope (..),
    LocalSettings,
    runLocalQuery,
    runLocalRegistrationSnapshot,
 )
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Indexer (withInMemoryIndexerRunner)
import Codec.Binary.Bech32 qualified as Bech32
import Control.Exception (SomeException, bracket, try)
import Control.Monad (unless, when)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Char (isAlpha, isAlphaNum)
import Data.Foldable (fold, for_, toList)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isSuffixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Traversable (for)
import Database.KV.Transaction (RunTransaction (..))
import Distribution.Fields.ParseResult (runParseResult)
import Distribution.PackageDescription.Parsec (parseGenericPackageDescription)
import Distribution.Pretty (prettyShow)
import Distribution.Types.BuildInfo (BuildInfo (hsSourceDirs, otherModules))
import Distribution.Types.CondTree (CondTree)
import Distribution.Types.GenericPackageDescription (
    GenericPackageDescription (condLibrary, condSubLibraries),
 )
import Distribution.Types.Library (Library (exposedModules, libBuildInfo))
import Paths_cardano_keri (getDataFileName)
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldNotBe)

-- ---------------------------------------------------------------------------
-- The property

spec :: Spec
spec =
    describe
        "#262 A-262-03 -- every PUBLIC entry point that can be handed an eagerly \
        \rejectable input is covered by a zero-effect proof, over the derived \
        \export surface rather than a list of names (NOTE-004)"
        $ do
            it "derivation control: the public module set comes from the real cabal file and is non-empty" $ do
                modules <- publicModules
                modules `shouldNotBe` []
                map fst modules `shouldContainName` "Cardano.KERI.ChainQuery.Interpreter"
                map fst modules `shouldContainName` "Cardano.KERI.Indexer.ChainQuery"

            it "derivation control: a module that is NOT cabal-exposed is absent from the public set" $ do
                modules <- publicModules
                -- every test module lives outside every library component
                filter ("Spec" `isSuffixOf`) (map fst modules) `shouldBe` []

            it "derivation control: exported signatures are read from the module's own source, and a private definition is not among them" $ do
                signatures <- exportedSignaturesOf "Cardano.KERI.Indexer.ChainQuery"
                map fst signatures `shouldContainName` "runLocalQuery"
                -- 'localOutputAt' is defined in that module but deliberately
                -- not exported; if it appeared here the reader would be
                -- reporting definitions rather than exports.
                map fst signatures `shouldNotContainName` "localOutputAt"

            it "derivation control: an umbrella module's `module X` reexports are expanded, so a second public route is a real member (CORRECTION-008)" $ do
                umbrella <- exportedSignaturesOf "Cardano.KERI.ChainQuery"
                -- the umbrella's export list is nothing but reexports, so an
                -- unexpanded reader would report zero
                map fst umbrella `shouldContainName` "runChainQuery"
                map fst umbrella `shouldContainName` "runChainQueryResultSnapshot"

            it "derivation control: `Type (..)` field selectors are expanded, so a public field is visible to the rules (CORRECTION-008)" $ do
                signatures <- exportedSignaturesOf localInterpreterModule
                map fst signatures `shouldContainName` "localScopeRunner"

            it "derivation control: an exported operator is parsed from both its export item and its top-level signature (CORRECTION-011)" $ do
                case classifyExportItem "(>>>)" of
                    Right (PlainName name) -> name `shouldBe` ">>>"
                    other ->
                        expectationFailure
                            ("an operator export item was not recognised as a name: " <> show other)
                map fst (topLevelSignatures "(>>>) :: ChainQuery a -> IO ()")
                    `shouldBe` [">>>"]

            it "derivation control: a reexport of a PRIVATE local module resolves to that module's real names (CORRECTION-011)" $ do
                every <- allLocalModules
                exposed <- publicModules
                let privateModules = filter (`notElem` map fst exposed) (map fst every)
                -- the resolution map must be strictly larger than the seed
                -- set, or a reexport through a private module would silently
                -- contribute nothing
                privateModules `shouldNotBe` []

            it "derivation control: a nested export item does not corrupt its neighbours" $ do
                let items = map (T.unpack . T.strip) (splitTopLevelCommas "Alpha (a, b), Beta, Gamma (..)")
                items `shouldBe` ["Alpha (a, b)", "Beta", "Gamma (..)"]

            it "derivation control: rejectable input types are derived from the validating smart constructors, not listed" $ do
                rejectable <- rejectableInputTypes
                for_ ["ChainQuery", "OutputLocator", "BoardLocator", "CheckpointLocator"] $ \expected ->
                    rejectable `shouldContainName` expected

            it "derivation control: store-runner reachability finds a known reacher and excludes a known non-reacher" $ do
                reaching <- storeReachingExports
                reaching `shouldContainName` "runLocalQuery"
                -- a pure scope constructor performs no store effect
                reaching `shouldNotContainName` "queryHandleLocalScope"

            it "the pure guard every proof rests on recognises an eager rejection" provesEagerRejection

            it "the selector-validated class the type derivation deliberately cannot see is still asserted (reference hashes)" $
                provesNoProviderCall (\url -> koiosReferenceScripts url Nothing ["not-canonical-hex"])

            it "anti-vacuity control: the logging interpreter observes a real dispatch, and the counting runner counts a real transaction" $ do
                calls <- newIORef []
                _ <- runChainQueryResultSnapshot (loggingInterpreter calls) validCheckpointProgram
                observed <- readIORef calls
                observed `shouldNotBe` []
                withInMemoryIndexerRunner $ \_handle runner -> do
                    counter <- newIORef (0 :: Int)
                    _ <- runLocalQuery (bareScope (countingRunner counter runner)) validPayerProgram
                    readIORef counter >>= (`shouldBe` 1)

            it "capability control: the detector recognises a store-transaction-backed interpreter capability when shown one" $
                supplyingStoreBackedInterpreter
                    "LocalQueryScope cf op -> ChainQueryInterpreter (Transaction IO cf Cols op)"
                    `shouldBe` True

            it "capability control: the detector does NOT flag an interpreter over a caller-chosen effect" $
                supplyingStoreBackedInterpreter "Text -> Maybe KoiosToken -> ChainQueryInterpreter IO"
                    `shouldBe` False

            it "signature control: a record field's type parses the same way a top-level signature does" $ do
                signatures <- exportedSignaturesOf localInterpreterModule
                case lookup "localScopeRunner" signatures of
                    Nothing -> expectationFailure "the field expansion lost localScopeRunner"
                    Just signature -> resultPortion signature `shouldNotBe` ""

            it "signature control: PHYSICAL FORMATTING does not change the derived public set -- a field whose type continues past the `::` line derives exactly what the one-line spelling derives (submission-4 audit counterexample 1)" $ do
                continued <- derivedSurfaceOf multilineFieldSpelling
                oneLine <- derivedSurfaceOf singleLineFieldSpelling
                sort continued `shouldBe` sort oneLine

            it "signature control: and that continued field really JOINS the qualifying set under the shipped rules, rather than being derived as an empty type nobody can classify (submission-4 audit counterexample 1)" $ do
                continued <- derivedSurfaceOf multilineFieldSpelling
                rejectable <- rejectableInputTypes
                case lookup mutantFieldName continued of
                    Nothing ->
                        expectationFailure
                            ( "the field expansion lost "
                                <> mutantFieldName
                                <> " entirely: "
                                <> show continued
                            )
                    Just signature -> do
                        acceptsRejectableInput rejectable signature `shouldBe` True
                        performsAnEffect signature `shouldBe` True

            it "capability control: a store-transaction-backed interpreter NESTED under an ordinary result container is still a handed-out capability, read through the real source derivation (submission-4 audit counterexample 2)" $ do
                continued <- derivedSurfaceOf multilineFieldSpelling
                case lookup mutantCapabilityName continued of
                    Nothing ->
                        expectationFailure
                            ("the export reader lost " <> mutantCapabilityName)
                    Just signature ->
                        supplyingStoreBackedInterpreter signature `shouldBe` True

            it "capability control: the same nesting is detected directly, under each container the result of such an export realistically wears" $
                for_
                    [ "LocalQueryScope cf op -> Maybe (ChainQueryInterpreter (Transaction IO cf Cols op))"
                    , "LocalQueryScope cf op -> IO (ChainQueryInterpreter (Transaction IO cf Cols op))"
                    , "LocalQueryScope cf op -> Either ChainQueryError (ChainQueryInterpreter (Transaction IO cf Cols op))"
                    , "LocalQueryScope cf op -> [ChainQueryInterpreter (Transaction IO cf Cols op)]"
                    ]
                    (\signature -> supplyingStoreBackedInterpreter signature `shouldBe` True)

            it "fail-closed control: a legal module whose declaration begins at BYTE ZERO is enumerated, not silently emptied (submission-5 audit finding 1)" $ do
                atByteZero <- derivedSurfaceOfSource (mutantSurfaceSource [] multilineFieldSpelling)
                belowAComment <- derivedSurfaceOf multilineFieldSpelling
                sort atByteZero `shouldBe` sort belowAComment

            it "fail-closed control: and the omission was never synthetic -- a really Cabal-exposed module that declares at byte zero really does have exports" $ do
                signatures <- exportedSignaturesOf "Cardano.KERI.AID.CESR"
                map fst signatures `shouldContainName` "parsePrimitive"

            it "fail-closed control: a zero-byte module cannot be reported as a successfully empty public surface, and the diagnostic names it" $
                requiresFailClosed [mutantSurfaceModule] (derivedSurfaceOfSource "")

            it "fail-closed control: an export shape the reader cannot place identifies itself instead of being skipped" $
                requiresFailClosed
                    [mutantSurfaceModule, T.unpack unclassifiableExportItem]
                    (derivedSurfaceOfSource unclassifiableExportSource)

            it "fail-closed control: a public export whose type cannot be found here or in any local module identifies itself instead of leaving the surface quietly" $
                requiresFailClosed
                    [mutantSurfaceModule, untypedExportName]
                    (derivedSurfaceOfSource untypedExportSource)

            it "fail-closed control: a module that cannot be read is not mistaken for one with no exports, and the diagnostic names its module and its path" $
                requiresFailClosed
                    [mutantSurfaceModule, unreadableSourcePath]
                    ( signaturesOf
                        [(mutantSurfaceModule, unreadableSourcePath)]
                        Set.empty
                        mutantSurfaceModule
                    )

            it "capability control: widening to nested results does NOT swallow the caller-chosen-effect negative, at any nesting" $
                for_
                    [ "Text -> Maybe KoiosToken -> ChainQueryInterpreter IO"
                    , "Text -> Maybe KoiosToken -> Maybe (ChainQueryInterpreter IO)"
                    , "Text -> Maybe KoiosToken -> IO (ChainQueryInterpreter effect)"
                    ]
                    (\signature -> supplyingStoreBackedInterpreter signature `shouldBe` False)

            it "no public export hands out a store-transaction-backed interpreter capability (A-262-03)" $ do
                capabilities <- storeBackedInterpreterCapabilities
                if null capabilities
                    then pure ()
                    else
                        expectationFailure $
                            "these PUBLIC exports supply an interpreter already bound to a store \
                            \transaction: "
                                <> show capabilities
                                <> ". The store runner is public from its own package and the scope \
                                   \exposes it, so such an export lets any caller rebuild the retired \
                                   \wrapper -- runTransaction (localScopeRunner scope) (runChainQuery \
                                   \(thatCapability scope) alreadyRejectedProgram) -- and open a \
                                   \transaction for a locator that was already refused. Withdraw it and \
                                   \keep it private behind a guarded named runner."

            it "closure control: a qualifying export in ANOTHER module is a distinct member, even when its bare name is already covered" $ do
                let elsewhereButSameName =
                        SurfaceMember "Cardano.KERI.Some.Future.Module" "runLocalQuery"
                uncoveredMembers [elsewhereButSameName] (map fst proofActions)
                    `shouldBe` [elsewhereButSameName]

            it "every derived qualifying public entry point has an EXECUTABLE zero-effect proof, and it is executed here" $ do
                derived <- qualifyingPublicEntryPoints
                derived `shouldNotBe` []
                let uncovered = uncoveredMembers derived (map fst proofActions)
                if not (null uncovered)
                    then
                        expectationFailure $
                            "these PUBLIC entry points can be handed an eagerly rejectable input but no \
                            \EXECUTABLE zero-effect proof covers them: "
                                <> show uncovered
                                <> ". Either write a proof action that runs the entry point with an eagerly \
                                   \rejected input and asserts zero operation handlers, zero watermark \
                                   \handler and zero store-runner calls, or withdraw it from the public \
                                   \surface. A name alone cannot satisfy this."
                    else for_ derived $ \member ->
                        case lookup member proofActions of
                            Nothing -> expectationFailure ("no proof action for " <> show member)
                            Just proof -> proof

            it "coverage control: every proof action still names a real derived member, so the registry cannot drift into fiction" $ do
                derived <- qualifyingPublicEntryPoints
                uncoveredMembers (map fst proofActions) derived `shouldBe` []

{- | Each public entry point paired with an EXECUTABLE proof that it obeys the
property, not with a claim that it does.

The first version of this registry was @[String]@ — a list of names the
closure check compared against the derived set. CORRECTION-004 rejected it,
correctly: a manually editable name list can turn the closure green without
asserting any behaviour, which is the hand-list defect NOTE-004 forbids,
moved from the surface side to the coverage side. A new qualifying export
could be appeased by typing its name.

So a member is covered only by an 'IO' action that RUNS the real entry point
with an eagerly rejected input and asserts the zeros that apply at its layer:
zero operation handlers and zero watermark handler wherever an interpreter is
reachable, and zero store-runner invocations wherever a store is. The closure
property executes every one of these; a name with no action fails, and an
action that stops asserting fails on its own.
-}
proofActions :: [(SurfaceMember, IO ())]
proofActions = definingModuleRoutes <> umbrellaRoutes

definingModuleRoutes :: [(SurfaceMember, IO ())]
definingModuleRoutes =
    [
        ( interpreterModuleMember "runChainQuery"
        , -- the dispatcher's own Either wraps the program's, and a program
          -- that rejected before building a node dispatches nothing, so the
          -- rejection arrives nested inside a successful run
          provesQueryLayer $ \interpreter ->
            runChainQuery interpreter invalidOutputProgram >>= \case
                Right (Left (InvalidLocator _)) -> pure ()
                other -> unexpected "Right (Left (InvalidLocator _))" other
        )
    ,
        ( interpreterModuleMember "runChainQueryResultSnapshot"
        , provesQueryLayer $ \interpreter ->
            runChainQueryResultSnapshot interpreter invalidOutputProgram >>= \case
                Left (InvalidLocator _) -> pure ()
                other -> unexpected "Left (InvalidLocator _)" other
        )
    , (SurfaceMember "Cardano.KERI.ChainQuery.Program" "foldChainQuery", provesFoldChainQuery)
    ,
        ( SurfaceMember "Cardano.KERI.ChainQuery.Registration" "runRegistrationSnapshot"
        , provesRegistrationQueryLayer
        )
    ,
        ( SurfaceMember localInterpreterModule "runLocalQuery"
        , provesLocalLayer (`runLocalQuery` invalidOutputProgram)
        )
    ,
        ( SurfaceMember localInterpreterModule "runLocalRegistrationSnapshot"
        , provesLocalLayer (`runLocalRegistrationSnapshot` invalidRegistrationRequest)
        )
    ,
        ( SurfaceMember "Cardano.KERI.Deployment.CLI" "registerQuerySnapshot"
        , provesRegisterCarryingRunnerRefusesFirst
        )
    ,
        ( koiosModuleMember "koiosCurrentCheckpoint"
        , provesNoProviderCall (\url -> koiosCurrentCheckpoint url Nothing invalidCheckpointLocator validAidText)
        )
    ,
        ( koiosModuleMember "koiosLiveCheckpoints"
        , provesNoProviderCall (\url -> koiosLiveCheckpoints url Nothing invalidCheckpointLocator)
        )
    ,
        ( koiosModuleMember "koiosBoardCatalog"
        , provesNoProviderCall (\url -> koiosBoardCatalog url Nothing invalidBoardLocator)
        )
    ]

{- | The same function reached through the stable umbrella module is a
DISTINCT public route, so it is a distinct member with its own executed
proof. "Cardano.KERI.ChainQuery" re-exports the whole algebra, and a
consumer importing from there is not importing from the defining module.
-}
umbrellaRoutes :: [(SurfaceMember, IO ())]
umbrellaRoutes =
    [ (SurfaceMember "Cardano.KERI.ChainQuery" name, action)
    | (SurfaceMember _definingModule name, action) <- definingModuleRoutes
    , name `elem` reexportedByUmbrella
    ]
  where
    reexportedByUmbrella =
        [ "runChainQuery"
        , "runChainQueryResultSnapshot"
        , "foldChainQuery"
        , "runRegistrationSnapshot"
        ]

interpreterModuleMember :: String -> SurfaceMember
interpreterModuleMember = SurfaceMember "Cardano.KERI.ChainQuery.Interpreter"

koiosModuleMember :: String -> SurfaceMember
koiosModuleMember = SurfaceMember "Cardano.KERI.ChainQuery.Koios"

{- | A member of the public surface is @(module, export)@, never a bare name.

CORRECTION-005: keying by bare name collapsed distinct members. Two exposed
modules may export the same name, and the second one would have silently
inherited the first one's proof action — so "a newly exported qualifying API
automatically joins or fails the enumeration", the whole point of deriving
the set, would have been false for exactly the case a hand list gets wrong.
-}
data SurfaceMember = SurfaceMember
    { memberModule :: String
    , memberExport :: String
    }
    deriving stock (Eq, Ord, Show)

{- | Derived members with no executable proof. Pure, so the closure rule can
be exercised directly on synthetic inputs by the control below rather than
only through the real surface.
-}
uncoveredMembers :: [SurfaceMember] -> [SurfaceMember] -> [SurfaceMember]
uncoveredMembers derived covered = filter (`notElem` covered) derived

{- | The provider layer's form of the same property: an eagerly rejected
locator must be refused before any HTTP call.

The base URL is unreachable on purpose, which is what makes the assertion
sharp: a rejection that happened before the call returns 'InvalidLocator',
while one that dialled first would surface as a transport 'ProviderFailure'
or hang. The same technique
"Cardano.KERI.ChainQuery.Koios.DecodeSpec" already uses.
-}
provesNoProviderCall :: (Text -> IO (Either ChainQueryError a)) -> IO ()
provesNoProviderCall call = do
    outcome <- call "https://unreachable.invalid"
    case outcome of
        Left (InvalidLocator _) -> pure ()
        Left other ->
            expectationFailure
                ("expected an eager InvalidLocator with no provider call, got " <> show other)
        Right _ -> expectationFailure "expected the invalid locator to be refused"

{- | The shared query-layer proof: hand the entry point an eagerly rejected
program through a call-logging interpreter and require that nothing was
dispatched — no operation handler, and no watermark handler.

The logging interpreter is total, so an unexpected invocation appears as an
extra entry rather than as an exception that could be mistaken for unrelated
breakage. Its own ability to observe a real effect is proved separately by
the anti-vacuity control below.
-}
provesQueryLayer :: (ChainQueryInterpreter IO -> IO ()) -> IO ()
provesQueryLayer assertOutcome = do
    calls <- newIORef []
    assertOutcome (loggingInterpreter calls)
    readIORef calls >>= (`shouldBe` [])

{- | CORRECTION-010: every action asserts the RETURNED outcome as well as the
zero counters. Zeros alone are half the property — a runner could answer the
wrong value without touching a handler and stay green.
-}
unexpected :: (Show a) => String -> a -> IO ()
unexpected expected got =
    expectationFailure ("expected " <> expected <> ", got " <> show got)

{- | 'foldChainQuery' takes the handler directly rather than an interpreter,
so its proof counts handler invocations at that level.
-}
provesFoldChainQuery :: IO ()
provesFoldChainQuery = do
    calls <- newIORef ([] :: [String])
    outcome <-
        foldChainQuery
            (\_operation -> modifyIORef' calls ("dispatched" :) >> fail "no operation may be dispatched")
            invalidOutputProgram
    readIORef calls >>= (`shouldBe` [])
    case outcome of
        Left (InvalidLocator _) -> pure ()
        other -> unexpected "Left (InvalidLocator _)" other

{- | 'eagerRejection' is the guard the runners consult. It is pure, so it is
not itself a qualifying entry point — it can perform no effect — but every
proof above rests on it recognising the rejection, so it is asserted here
rather than left implicit.
-}
provesEagerRejection :: IO ()
provesEagerRejection =
    case eagerRejection invalidOutputProgram of
        Just (InvalidLocator _) -> pure ()
        other -> expectationFailure ("expected an InvalidLocator rejection, got " <> show other)

-- | The registration entry point, at the query layer, with an invalid locator.
provesRegistrationQueryLayer :: IO ()
provesRegistrationQueryLayer = do
    calls <- newIORef []
    outcome <- runRegistrationSnapshot (loggingInterpreter calls) invalidRegistrationRequest
    readIORef calls >>= (`shouldBe` [])
    case outcome of
        Left (InvalidLocator _) -> pure ()
        _ -> expectationFailure "expected the registration request to be rejected eagerly"

{- | The shared local-layer proof: run the entry point against a counting
store runner and require that no store transaction was opened at all.

The counter's ability to count is proved by the anti-vacuity control, which
requires a VALID program through the same runner to open exactly one.
-}
provesLocalLayer ::
    (forall cf op. LocalQueryScope cf op -> IO (Either ChainQueryError a)) -> IO ()
provesLocalLayer run =
    withInMemoryIndexerRunner $ \_handle runner -> do
        counter <- newIORef (0 :: Int)
        outcome <- run (bareScope (countingRunner counter runner))
        readIORef counter >>= (`shouldBe` 0)
        case outcome of
            Left (InvalidLocator _) -> pure ()
            Left other -> unexpected "Left (InvalidLocator _)" other
            Right _ -> expectationFailure "expected the rejected locator to be refused"

{- | The member the repaired field reader FOUND, and why its proof is about
the CARRYING RUNNER rather than about any one runtime value.

'Cardano.KERI.Deployment.CLI.registerQuerySnapshot' is a public @Type (..)@
field selector whose type continues past its physical @::@ line, so the
pre-repair reader derived an empty type for it and it was absent from the
enumeration through all four submissions. It qualifies on the same terms as
every other member: it takes a 'RegistrationQueryRequest', which is eagerly
rejected, and its result is an 'IO' action over a 'LocalQueryScope'.

But it is a SLOT, not a runner: it returns whatever the constructing caller
put in it. Nothing can be promised about a callback a caller supplies, and an
action that ran the value this suite chose to construct would prove today's
construction site rather than the surface — the manufactured-confidence shape
this campaign exists to remove (A-004). What CAN be promised, and is what the
production carrying runner now enforces, is that an eagerly rejected request
never reaches the slot at all:
'Cardano.KERI.Deployment.CLI.runRegisterWith' asks the request's own program
whether it already refused BEFORE it decodes an identity, opens a local
scope, or invokes any caller-supplied callback.

So this proof hands 'runRegisterWith' a deliberately hostile runtime — a
callback that records its own invocation and fails, over a manifest whose
checkpoint policy is not a canonical script hash — together with a local
opener that records ITS own invocation, and requires all three things: the
opener never ran, the callback never ran, and the refusal that came back is
the eager 'InvalidLocator' rather than an incidental decode failure. Because
the callback is never reached, the result holds for every callback a caller
could put in that slot, which is the universal statement the selector needs
and the one-value action could not make.

Stated limit, so the green is not read as more than it earns: the CLI's own
address and policy decoders would independently have refused these same
inputs today. What the guard adds is that the refusal is now the runner's own
stated invariant, asserted by identity — so a future change that moves,
loosens, or reorders those decoders fails this proof instead of silently
letting a rejected request reach a caller's callback.
-}
provesRegisterCarryingRunnerRefusesFirst :: IO ()
provesRegisterCarryingRunnerRefusesFirst = do
    kelPath <- getDataFileName "deployment-test/fixtures/kli-export-2-of-5.cesr"
    manifestPath <- getDataFileName "deployment-test/fixtures/register-preflight-m1-manifest.json"
    boardManifestPath <-
        getDataFileName "deployment-test/fixtures/register-preflight-board-manifest.json"
    opened <- newIORef (0 :: Int)
    reached <- newIORef (0 :: Int)
    outcome <-
        try
            ( runRegisterWith
                (refusingLocalOpener opened)
                (hostileRegisterRuntime reached kelPath manifestPath boardManifestPath)
                (rejectedRegisterSettings kelPath manifestPath boardManifestPath)
            )
    readIORef opened >>= (`shouldBe` 0)
    readIORef reached >>= (`shouldBe` 0)
    case outcome of
        Right () ->
            expectationFailure
                "the registration runner accepted a request its own program had already refused"
        Left failure
            | "InvalidLocator" `isInfixOf` show (failure :: SomeException) -> pure ()
            | otherwise ->
                expectationFailure
                    ( "the request was refused, but not BY THE EAGER GUARD -- an incidental \
                      \failure cannot be relied on to keep a caller-supplied callback away \
                      \from a rejected request: "
                        <> show failure
                    )

{- | A local opener that must never be reached. It counts first, so a reached
opener is visible even though it then refuses to open anything.
-}
refusingLocalOpener :: IORef Int -> LocalSettings -> (forall cf op. LocalQueryScope cf op -> IO a) -> IO a
refusingLocalOpener opened _settings _use = do
    atomicModifyIORef' opened (\n -> (n + 1, ()))
    fail "no local scope may be opened for an eagerly rejected registration request"

{- | The hostile runtime: every reader is real, so the flow gets far enough
to build its request, and the one caller-supplied query callback records that
it was reached. Its snapshot is never returned because it must never run.
-}
hostileRegisterRuntime :: IORef Int -> FilePath -> FilePath -> FilePath -> RegisterRuntime
hostileRegisterRuntime reached _kelPath _manifestPath _boardManifestPath =
    RegisterRuntime
        { registerReadKel = BS.readFile
        , registerReadManifest = fmap (fmap withUnusableCheckpointPolicy) . readManifest
        , registerReadBoardManifest = readEndpointBoardManifest
        , registerQuerySnapshot = \_scope _request -> do
            atomicModifyIORef' reached (\n -> (n + 1, ()))
            fail "a caller-supplied callback received an eagerly rejected registration request"
        , registerWriteLine = \_line -> pure ()
        , registerSubmit = \_scope _settings _manifest _plan ->
            fail "registration submitted despite an eagerly rejected request"
        }

{- | The same manifest with its checkpoint policy replaced by a value that is
not a canonical 28-byte hex script hash, kept consistent with its own script
entry so the registration plan still builds and the REQUEST is what fails.
-}
withUnusableCheckpointPolicy :: Manifest -> Manifest
withUnusableCheckpointPolicy manifest =
    manifest
        { manifestCheckpoint =
            (manifestCheckpoint manifest){checkpointPolicyId = unusablePolicyId}
        , manifestScripts = map rehash (manifestScripts manifest)
        }
  where
    rehash entry
        | scriptName entry == "checkpoint-register" = entry{scriptHash = unusablePolicyId}
        | otherwise = entry

unusablePolicyId :: Text
unusablePolicyId = "not-a-canonical-28-byte-hex-script-hash"

rejectedRegisterSettings :: FilePath -> FilePath -> FilePath -> RegisterSettings
rejectedRegisterSettings kelPath manifestPath boardManifestPath =
    RegisterSettings
        { registerNetwork = "preprod"
        , registerNetworkMagic = 1
        , registerKel = kelPath
        , registerPayer = "unused-payer"
        , registerNodeSocket = "unused-node-socket"
        , registerFundingAddress = "unused-funding-address"
        , registerManifest = manifestPath
        , registerBoardManifest = boardManifestPath
        , registerStorePath = "unused-store-path"
        , registerTimeoutSeconds = 30
        , registerAllowUnlistedWitnesses = False
        , registerAllowExistingCheckpoint = False
        , registerEscrowLovelace = 1_007_000_000
        }

-- ---------------------------------------------------------------------------
-- Fixtures and harness for the proof actions
--
-- Per-spec copies, matching this codebase's existing convention for the
-- in-memory indexer harness rather than introducing a new shared test-only
-- export.

-- | An exact-output program whose locator is rejected before any node exists.
invalidOutputProgram :: ChainQuery (Either ChainQueryError ChainAssetUtxo)
invalidOutputProgram =
    outputAt OutputLocator{outputLocatorTxId = T.replicate 64 "A", outputLocatorIndex = 0}

invalidCheckpointLocator :: CheckpointLocator
invalidCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = "not-a-policy-id"
        , checkpointLocatorAddress = "not-an-address"
        }

invalidBoardLocator :: BoardLocator
invalidBoardLocator =
    BoardLocator
        { boardLocatorPolicyId = "not-a-policy-id"
        , boardLocatorAddress = "not-an-address"
        }

-- | A registration request whose checkpoint locator is rejected the same way.
invalidRegistrationRequest :: RegistrationQueryRequest
invalidRegistrationRequest =
    RegistrationQueryRequest
        { registrationQueryCheckpointLocator =
            CheckpointLocator
                { checkpointLocatorPolicyId = "not-a-policy-id"
                , checkpointLocatorAddress = "not-an-address"
                }
        , registrationQueryAid = "not-an-aid"
        , registrationQueryBoardLocator = Nothing
        , registrationQueryReferenceHashes = []
        , registrationQueryPayerAddresses = []
        }

{- | A VALID program, for the anti-vacuity controls: the detector must be
shown observing a real dispatch before any absence it reports is believed.
-}
validCheckpointProgram :: ChainQuery (Either ChainQueryError (Maybe ActiveCheckpoint))
validCheckpointProgram = currentCheckpoint validCheckpointLocator validAidText

validPayerProgram :: ChainQuery (Either ChainQueryError [ChainAssetUtxo])
validPayerProgram = payerUtxos [canonicalAddressText]

validCheckpointLocator :: CheckpointLocator
validCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 0x00))
        , checkpointLocatorAddress = canonicalAddressText
        }

canonicalAddressText :: Text
canonicalAddressText =
    Bech32.encodeLenient
        (either (error . show) id (Bech32.humanReadablePartFromText "addr_test"))
        (Bech32.dataPartFromBytes (BS.replicate 28 0x00))

validAidText :: Text
validAidText = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

{- | A scope with no checkpoint or board identity: the proof actions here are
about whether a transaction is opened at all, never about what a scan finds.
-}
bareScope :: RunTransaction IO cf Cols op -> LocalQueryScope cf op
bareScope runner =
    LocalQueryScope
        { localScopeRunner = runner
        , localScopeCheckpointIdentity = Nothing
        , localScopeBoardIdentity = Nothing
        }

countingRunner :: IORef Int -> RunTransaction IO cf Cols op -> RunTransaction IO cf Cols op
countingRunner counter runner =
    RunTransaction
        { runTransaction = \transaction -> do
            atomicModifyIORef' counter (\n -> (n + 1, ()))
            runTransaction runner transaction
        }

-- | A call-logging interpreter: every handler records its own name.
loggingInterpreter :: IORef [String] -> ChainQueryInterpreter IO
loggingInterpreter calls =
    chainQueryInterpreter
        (\_ _ -> observed "currentCheckpoint" (Right Nothing))
        (\_ -> observed "liveCheckpoints" (Right []))
        (\_ -> observed "referenceScripts" (Right []))
        (\_ -> observed "boardCatalog" (Right []))
        (\_ -> observed "boardCatalogWithOutputs" (Right []))
        (\_ -> observed "payerUtxos" (Right []))
        (\_ -> observed "outputAt" (Left (UnsupportedOperation "unexpected test effect")))
        (observed "storeWatermark" (Right Cold))
        SourceLocal
        AtomicLocal
  where
    observed label result = modifyIORef' calls (<> [label]) >> pure result

-- ---------------------------------------------------------------------------
-- Permanent controls for the two shapes the fourth audit proved invisible
--
-- The fourth fresh audit compiled two public shapes that the derivation
-- claimed to enumerate and did not see: a `Type (..)` field selector whose
-- type continues past the physical `::` line, and a store-backed interpreter
-- capability nested inside an ordinary result container. Neither was a
-- product defect -- the shipped surface was safe -- but both refute the one
-- promise NOTE-004 exists to make: that a new qualifying export JOINS the set
-- or FAILS the check. A detector that silently under-counts is the
-- hand-maintained list wearing the derivation's clothes.
--
-- So they stay here as permanent controls, not as one-off repairs. They are
-- driven through the SAME readers the shipped property uses -- 'signaturesOf'
-- over a real file on disk, and the shipped 'supplyingStoreBackedInterpreter'
-- -- rather than through a test-local parser that could agree with the tests
-- while the real derivation stays blind. A control that bypasses the
-- instrument under test proves nothing about it.

mutantSurfaceModule :: String
mutantSurfaceModule = "Mutant.Surface"

mutantFieldName :: String
mutantFieldName = "mutantField"

mutantCapabilityName :: String
mutantCapabilityName = "mutantNestedCapability"

{- | The audit's first counterexample: one public record field, spelled with
its type continued after the @::@. Its argument list mentions 'ChainQuery',
so the derived signature is one the real qualification rules must accept.
-}
multilineFieldSpelling :: [Text]
multilineFieldSpelling =
    [ "    { mutantField ::"
    , "        LocalQueryScope cf op ->"
    , "        ChainQuery a ->"
    , "        IO (Either ChainQueryError ())"
    , "    }"
    ]

{- | The identical field written on the @::@ line. The audit's sharpest
observation was that this spelling IS detected while the one above is not, so
the control is an equality between the two derivations rather than a claim
about either one alone.
-}
singleLineFieldSpelling :: [Text]
singleLineFieldSpelling =
    [ "    { mutantField :: LocalQueryScope cf op -> ChainQuery a -> IO (Either ChainQueryError ())"
    , "    }"
    ]

{- | A module exporting both counterexamples: the field through @Type (..)@,
and the audit's second counterexample as a top-level export whose result
container hides the store-backed interpreter.
-}
mutantSurfaceSource :: [Text] -> [Text] -> Text
mutantSurfaceSource prelude fieldLines =
    T.unlines $
        prelude
            <> [ "module Mutant.Surface (MutantCarrier (..), mutantNestedCapability) where"
               , ""
               , "data MutantCarrier cf op = MutantCarrier"
               ]
            <> fieldLines
            <> [ ""
               , "mutantNestedCapability ::"
               , "    LocalQueryScope cf op ->"
               , "    Maybe (ChainQueryInterpreter (Transaction IO cf Cols op))"
               , "mutantNestedCapability = error \"a fixture, not a definition\""
               ]

{- | The ordinary prelude: a comment above the declaration, which is what
almost every module in this repository looks like — and exactly why the
byte-zero case below went unnoticed for five submissions.
-}
commentPrelude :: [Text]
commentPrelude =
    [ "-- A control fixture, never compiled: it is read by the same"
    , "-- derivation the shipped property runs against the real tree."
    ]

{- | The exported names and signatures the SHIPPED reader derives from that
module, resolved from a real file, because the reader takes a path and reads
it. Nothing tracked is written: the fixture lives in the temporary directory
and is removed even if the example fails.
-}
derivedSurfaceOf :: [Text] -> IO [(String, Text)]
derivedSurfaceOf = derivedSurfaceOfSource . mutantSurfaceSource commentPrelude

-- | The same reader, over source text the control supplies verbatim.
derivedSurfaceOfSource :: Text -> IO [(String, Text)]
derivedSurfaceOfSource source =
    withMutantSurfaceFile source $ \path ->
        signaturesOf [(mutantSurfaceModule, path)] Set.empty mutantSurfaceModule

{- | An export item this reader deliberately does not understand: a namespaced
@type@ export. No module in this repository writes one today, which is the
point — the reader must say so rather than skip it and report a surface it
never actually enumerated.
-}
unclassifiableExportItem :: Text
unclassifiableExportItem = "type MutantAlias"

unclassifiableExportSource :: Text
unclassifiableExportSource =
    T.unlines
        [ "module Mutant.Surface (type MutantAlias, mutantNestedCapability) where"
        , ""
        , "mutantNestedCapability ::"
        , "    LocalQueryScope cf op ->"
        , "    Maybe (ChainQueryInterpreter (Transaction IO cf Cols op))"
        , "mutantNestedCapability = error \"a fixture, not a definition\""
        ]

{- | A public VALUE export with no type signature anywhere. The reader cannot
tell whether it is a qualifying entry point, so the only honest answers are
"here it is with its type" and "I could not classify this one" — never
silence.
-}
untypedExportName :: String
untypedExportName = "mutantUntypedExport"

untypedExportSource :: Text
untypedExportSource =
    T.unlines
        [ "module Mutant.Surface (mutantUntypedExport) where"
        , ""
        , "mutantUntypedExport = error \"a fixture, not a definition\""
        ]

{- | A path no fixture was ever written to, so the reader must refuse rather
than report a module it could not open as one with no exports.
-}
unreadableSourcePath :: FilePath
unreadableSourcePath = "/nonexistent/public-surface-control/Mutant/Surface.hs"

{- | Require that a derivation FAILS, and that its diagnostic names each of
the given things.

Both halves matter. A derivation that fails for an unrelated reason — a
missing fixture, a harness slip, an exception from somewhere else entirely —
would satisfy "it failed" while proving nothing about the classifier, which
is precisely the manufactured-confidence shape this suite exists to refuse.
So the failure has to identify what it could not handle.
-}
requiresFailClosed :: (Show a) => [String] -> IO a -> IO ()
requiresFailClosed named derivation = do
    outcome <- try derivation
    case outcome of
        Right derived ->
            expectationFailure
                ( "the derivation reported a surface instead of failing closed on input it \
                  \cannot enumerate; it returned "
                    <> show derived
                )
        Left failure ->
            for_ named $ \needle ->
                unless (needle `isInfixOf` show (failure :: SomeException)) $
                    expectationFailure
                        ( "the derivation failed, but its diagnostic does not name "
                            <> show needle
                            <> ", so an unrelated exception would satisfy this control just as \
                               \well: "
                            <> show failure
                        )

{- | One unambiguous lifecycle (CORRECTION-023): acquire writes the fixture
and closes its handle, returning only a path; release removes that path; the
reader under test sees a closed file. Nothing about the fixture's cleanup can
then be mistaken for the classifier's verdict.
-}
withMutantSurfaceFile :: Text -> (FilePath -> IO a) -> IO a
withMutantSurfaceFile source use = do
    directory <- getTemporaryDirectory
    bracket (writeFixture directory) removeFile use
  where
    writeFixture directory = do
        (path, handle) <- openTempFile directory "MutantSurface.hs"
        BS.hPut handle (TE.encodeUtf8 source)
        hClose handle
        pure path

-- ---------------------------------------------------------------------------
-- Derivation 1: which modules are public

cabalFilePath :: FilePath
cabalFilePath = "cardano-keri.cabal"

{- | Every module a library component exposes, paired with its source file.
Taken from the cabal file through Cabal's own parser and folded across all
conditional branches, so no branch is silently skipped.
-}
publicModules :: IO [(String, FilePath)]
publicModules = modulesOfLibraries exposedOnly

{- | Every module of every library component, exposed or not, for RESOLVING a
re-export target.

An exposed module may legally re-export an @other-modules@ implementation
module, and those names become public through the exposed re-exporter
(CORRECTION-011). Resolution therefore needs the private sources too, while
the derived set is still SEEDED only from exposed modules — a private module
is not itself a public route.
-}
allLocalModules :: IO [(String, FilePath)]
allLocalModules = modulesOfLibraries exposedAndPrivate

exposedOnly :: Library -> [String]
exposedOnly = map prettyShow . exposedModules

exposedAndPrivate :: Library -> [String]
exposedAndPrivate library =
    map prettyShow (exposedModules library) <> map prettyShow (otherModules (libBuildInfo library))

modulesOfLibraries :: (Library -> [String]) -> IO [(String, FilePath)]
modulesOfLibraries selectModules = do
    contents <- BS.readFile cabalFilePath
    case runParseResult (parseGenericPackageDescription contents) of
        (_warnings, Left (_version, errs)) ->
            fail ("failed to parse " <> cabalFilePath <> ": " <> show (toList errs))
        (_warnings, Right gpd) -> do
            let libraries =
                    maybeToList (condLibrary gpd)
                        <> map snd (condSubLibraries gpd)
            fmap (nub . concat) (traverse (resolveLibrary selectModules) libraries)

resolveLibrary ::
    (Library -> [String]) -> CondTree confVar componentDeps Library -> IO [(String, FilePath)]
resolveLibrary selectModules tree = do
    let library = fold tree
        sourceDirs = map prettyShow (hsSourceDirs (libBuildInfo library))
        moduleNames = selectModules library
    fmap concat . for moduleNames $ \moduleName -> do
        let candidates =
                [ directory </> map dotToSlash moduleName <> ".hs"
                | directory <- sourceDirs
                ]
        existing <- filterExisting candidates
        case existing of
            (path : _) -> pure [(moduleName, path)]
            []
                -- Cabal generates this one; there is no source file to read
                -- and no public surface of ours in it. Named, not skipped.
                | moduleName == generatedPathsModule -> pure []
                | otherwise ->
                    failClosed
                        ( moduleName
                            <> " is declared by the Cabal file but no source was found at any of "
                            <> show candidates
                            <> "; a module that cannot be located cannot be enumerated, and \
                               \omitting it would report a surface that was never read"
                        )
  where
    dotToSlash character = if character == '.' then '/' else character

-- | Cabal's generated path module, which has no source file in the tree.
generatedPathsModule :: String
generatedPathsModule = "Paths_cardano_keri"

filterExisting :: [FilePath] -> IO [FilePath]
filterExisting paths = do
    flags <- traverse doesFileExist paths
    pure [path | (path, True) <- zip paths flags]

-- ---------------------------------------------------------------------------
-- Derivation 2: what each module exports, and with what type

{- | Every exported name of a public module paired with its own top-level
type signature, both read from that module's source.
-}
exportedSignaturesOf :: String -> IO [(String, Text)]
exportedSignaturesOf moduleName = do
    -- resolution uses every local module, including private ones an exposed
    -- module may re-export through (CORRECTION-011)
    modules <- allLocalModules
    signaturesOf modules Set.empty moduleName

{- | A module's exported names and their types, following the shapes an
export list can actually take (CORRECTION-008).

Three of them are not a bare name with a top-level signature, and the first
version of this reader saw only that one:

  * @module X@ RE-EXPORTS everything X exports.
    "Cardano.KERI.ChainQuery" is Cabal-exposed and its export list is nothing
    BUT these, so every runner has a second public route through it. A member
    is keyed by the module a consumer imports it from, so the same function
    re-exported by the umbrella is a DISTINCT member from the one in its
    defining module — that is two public routes, and the property is about
    routes.
  * @Type (..)@ exports the type's record field SELECTORS, which are public
    functions whose signatures live indented inside the data declaration.
    @LocalQueryScope (..)@ in the module under repair is exactly this.
  * @Type (a, b)@ exports named members, and its commas are nested — splitting
    the export list on every comma would corrupt the neighbouring items.

The visited set is what makes the re-export recursion terminate on a cycle.
-}
signaturesOf ::
    [(String, FilePath)] -> Set.Set String -> String -> IO [(String, Text)]
signaturesOf modules visited moduleName
    | moduleName `Set.member` visited = pure []
    | otherwise = case lookup moduleName modules of
        -- a re-export of a module outside this package contributes no public
        -- surface of its own. This is a CLASSIFICATION, not a skip: the map
        -- passed in holds every local module, exposed and private alike, so a
        -- name absent from it belongs to another package, whose surface is
        -- not ours to enumerate. A local module missing its source fails in
        -- 'resolveLibrary' before it can reach here.
        Nothing -> pure []
        Just path -> do
            contents <- readModuleSource moduleName path
            items <-
                either (failClosedIn moduleName path) pure (exportItems contents)
            let topLevel = topLevelSignatures contents
                fields = recordFieldSignatures contents
                known name = lookup name topLevel `orElse` lookup name fields
            fmap concat . for items $ \item ->
                case classifyExportItem item of
                    Left reason -> failClosedIn moduleName path reason
                    Right (ReexportedModule other) ->
                        signaturesOf modules (Set.insert moduleName visited) other
                    Right (WildcardType typeName) ->
                        -- @Type (..)@ contributes its record field SELECTORS.
                        -- Data constructors and class methods are deliberately
                        -- not members: a constructor returns the type, it
                        -- cannot dispatch an operation or open a transaction.
                        -- A sum type with no fields therefore contributes
                        -- nothing, by this stated rule rather than by silence.
                        pure (fieldsOfType typeName contents)
                    Right (ExplicitMembers typeName members) ->
                        fmap
                            concat
                            (traverse (resolveMember modules moduleName path known) (typeName : members))
                    Right (PlainName name) -> resolveMember modules moduleName path known name
  where
    orElse (Just value) _ = Just value
    orElse Nothing fallback = fallback

{- | One exported name, resolved to its type or else refused by name.

The refusal is the point. A lowercase export is a VALUE, and a value whose
type this reader cannot find is a value it cannot classify — it might be a
qualifying entry point and there is no way to tell. Dropping it out of a list
comprehension is how a public export leaves the enumeration without anyone
knowing, which is the exact defect this property exists to prevent, so it
fails and says which export it was.
-}
resolveMember ::
    [(String, FilePath)] ->
    String ->
    FilePath ->
    (String -> Maybe Text) ->
    String ->
    IO [(String, Text)]
resolveMember modules moduleName path known name =
    case known name of
        Just signature -> pure [(name, signature)]
        Nothing
            -- a type, class, or data constructor: no value-level signature
            -- exists to read, and none is expected
            | any (`elem` ['A' .. 'Z']) (take 1 name) -> pure []
            | otherwise -> do
                -- a module may export a name it IMPORTED, whose signature
                -- lives in the module that defines it. That name is part of
                -- THIS module's public surface -- a second route to it -- so
                -- the reader follows it rather than dropping it, which is how
                -- 'Cardano.KERI.Deployment.Registration.plutusDataJson' had
                -- been leaving the enumeration unnoticed.
                defined <- signaturesDefinedLocally modules name
                case nub defined of
                    [signature] -> pure [(name, signature)]
                    [] ->
                        failClosedIn
                            moduleName
                            path
                            ( "public export `"
                                <> name
                                <> "` has no readable type signature here or in any local \
                                   \module, so it cannot be classified as a qualifying entry \
                                   \point or excluded from the surface"
                            )
                    ambiguous ->
                        failClosedIn
                            moduleName
                            path
                            ( "public export `"
                                <> name
                                <> "` resolves to more than one local signature, so which one \
                                   \this module re-exports cannot be determined: "
                                <> show ambiguous
                            )

{- | Every top-level or field signature any LOCAL module gives this name.

Used only for a name a module exports without defining, so it costs a read of
the package's own sources exactly when a re-export needs resolving.
-}
signaturesDefinedLocally :: [(String, FilePath)] -> String -> IO [Text]
signaturesDefinedLocally modules name =
    fmap concat . for modules $ \(definingModule, definingPath) -> do
        contents <- readModuleSource definingModule definingPath
        pure
            ( maybeToList (lookup name (topLevelSignatures contents))
                <> maybeToList (lookup name (recordFieldSignatures contents))
            )

{- | Read a module's source, or refuse while naming both the module and the
path.

An unreadable or empty source is the shape that matters here: a reader that
answers "no exports" for a module it never actually read reports a complete
surface it never enumerated, and the report looks exactly like a module that
genuinely exports nothing.
-}
readModuleSource :: String -> FilePath -> IO Text
readModuleSource moduleName path = do
    outcome <- try (BS.readFile path)
    bytes <- case outcome of
        Left failure ->
            failClosedIn
                moduleName
                path
                ("its source could not be read: " <> show (failure :: SomeException))
        Right bytes -> pure bytes
    when (BS.null bytes) $
        failClosedIn moduleName path "its source is empty, so it has no module declaration to read"
    pure (TE.decodeUtf8 bytes)

{- | The derivation refuses rather than under-reporting (NOTE-005).

The product rule #240 established for checkpoint decoding is that a source
that cannot be read fails closed and names itself, with no silent fallback.
This instrument was written to enforce that rule and then broke it: a module
whose declaration begins at byte zero left the enumeration silently, so the
check could not fail for the very thing it omitted. Over-inclusion costs
noise; under-inclusion costs the invariant.
-}
failClosed :: String -> IO a
failClosed reason =
    fail ("public-surface derivation FAILED CLOSED -- " <> reason)

failClosedIn :: String -> FilePath -> String -> IO a
failClosedIn moduleName path reason =
    failClosed (moduleName <> " (" <> path <> "): " <> reason)

data ExportItem
    = ReexportedModule String
    | WildcardType String
    | ExplicitMembers String [String]
    | PlainName String
    deriving stock (Eq, Show)

classifyExportItem :: Text -> Either String ExportItem
classifyExportItem item
    | T.null trimmed = Left "an empty export item, which no export list should produce"
    | otherwise =
        case T.words trimmed of
            ("module" : other : _) -> Right (ReexportedModule (T.unpack other))
            ["module"] ->
                Left "an export item reading `module` with no module named after it"
            (namespace : _)
                | namespace `elem` ["type", "pattern", "data"] ->
                    Left
                        ( "a namespaced export item this reader does not understand: `"
                            <> T.unpack trimmed
                            <> "`"
                        )
            _
                -- an operator export is written parenthesised, e.g. @(>>>)@, so
                -- it has no leading identifier at all; both it and its top-level
                -- signature normalise to the bare symbol (CORRECTION-011)
                | Just symbol <- operatorName trimmed -> Right (PlainName symbol)
                | "(..)" `T.isInfixOf` withoutSpaces -> named WildcardType
                | "(" `T.isInfixOf` withoutSpaces ->
                    named $ \name ->
                        ExplicitMembers
                            name
                            ( map T.unpack
                                . filter (not . T.null)
                                . map T.strip
                                . T.splitOn ","
                                . T.takeWhile (/= ')')
                                . T.drop 1
                                . T.dropWhile (/= '(')
                                $ withoutSpaces
                            )
                | otherwise -> named PlainName
  where
    trimmed = T.strip item
    withoutSpaces = T.filter (/= ' ') trimmed
    headName = T.unpack (T.takeWhile (\c -> c /= '(' && c /= ' ') trimmed)
    -- an item whose leading name is empty is a shape this reader cannot
    -- place; it says so rather than contributing a nameless member
    named build
        | null headName =
            Left ("an export item with no leading name: `" <> T.unpack trimmed <> "`")
        | otherwise = Right (build headName)

{- | The bare symbol of a parenthesised operator, if that is what this text
is. Used for both export items and top-level signatures so the two agree on
one key.
-}
operatorName :: Text -> Maybe String
operatorName text = do
    inner <- T.stripSuffix ")" =<< T.stripPrefix "(" text
    let symbol = T.strip inner
    if not (T.null symbol) && T.all isOperatorChar symbol
        then Just (T.unpack symbol)
        else Nothing

isOperatorChar :: Char -> Bool
isOperatorChar c = c `elem` ("!#$%&*+./<=>?@\\^|-~:" :: String)

{- | A module's export items, split at top level only, so the commas inside
@Type (a, b)@ do not split their own item.
-}
exportItems :: Text -> Either String [Text]
exportItems rawContents = do
    declaration <- moduleDeclaration
    let afterName = T.dropWhile (/= '(') declaration
    when (T.null afterName) $
        Left "its module declaration has no export list, so its public surface cannot be enumerated"
    let (region, closing) = T.breakOn ") where" (T.drop 1 afterName)
    when (T.null closing) $
        Left "its export list has no closing `) where`, so where it ends cannot be determined"
    -- Haskell permits a trailing comma before the closing parenthesis, and
    -- most export lists here use one, so the split yields a final
    -- whitespace-only item. Discarding it cannot lose an export -- there is
    -- no name in it to lose -- which is what separates it from the silent
    -- skips this repair removes. Anything non-empty still has to classify.
    pure (filter (not . T.null . T.strip) (splitTopLevelCommas (flattened region)))
  where
    -- Comments and string literals are removed BEFORE the declaration is
    -- located. Without that, a module haddock containing the word "module" at
    -- the start of a line captures the search and the reader parses an export
    -- list out of prose: 'Cardano.KERI.Indexer.Query.Tx' really does say
    -- "\nmodule haddock on ..." in its header, and the pre-repair reader
    -- derived `twice` from the phrase "(twice, unexported)" while missing
    -- every real export of that module. It reported a surface it had never
    -- read, and said nothing.
    contents = stripCommentsAndStrings rawContents
    -- A module declaration may also begin at BYTE ZERO. Searching only for a
    -- preceding newline silently emptied every such module -- including the
    -- really Cabal-exposed 'Cardano.KERI.AID.CESR' and
    -- 'Cardano.KERI.AID.Ed25519' (submission-5 audit finding 1).
    moduleDeclaration
        | "module " `T.isPrefixOf` T.stripStart contents = Right (T.stripStart contents)
        | otherwise = case T.breakOn "\nmodule " contents of
            (_, rest)
                | T.null rest ->
                    Left "it contains no `module` declaration, at byte zero or anywhere else"
                | otherwise -> Right (T.drop 1 rest)
    flattened = T.unwords . map T.strip . T.lines

splitTopLevelCommas :: Text -> [Text]
splitTopLevelCommas = go (0 :: Int) "" . T.unpack
  where
    go _ acc [] = [T.pack (reverse acc)]
    go depth acc (c : rest)
        | c == ',' && depth == 0 = T.pack (reverse acc) : go 0 "" rest
        | c == '(' = go (depth + 1) (c : acc) rest
        | c == ')' = go (depth - 1) (c : acc) rest
        | otherwise = go depth (c : acc) rest

{- | Every record field selector a data declaration defines, with the field's
own type. These are public functions whenever the type is exported with
@(..)@ or with the field named explicitly.

A field's type may continue past the physical @::@ line exactly as a
top-level signature's may, and the fourth audit proved that reading only the
@::@ line dropped such a field from the derived surface while its IDENTICAL
one-line spelling was found. Physical formatting is not part of what a module
exports, so a public field must derive the same way in either spelling or the
enumeration is not the surface it claims to be.

Continuation lines are therefore gathered the same semantic way
'topLevelSignatures' gathers them, at the field's level rather than the
module's: a continuation is a non-blank line indented STRICTLY DEEPER than
the line that opened the field. That single rule is what makes the next
field, the closing brace, a @deriving@ clause, and a sibling signature in an
indented @where@ block all terminate the type — each of them sits at the
opening line's own indentation or less.
-}
recordFieldSignatures :: Text -> [(String, Text)]
recordFieldSignatures contents = go (T.lines contents)
  where
    go [] = []
    go (line : rest)
        | Just (name, opening) <- fieldStart line =
            let (continuation, remainder) = span (continues line) rest
                signature =
                    T.unwords
                        (filter (not . T.null) (opening : map T.strip continuation))
             in (name, signature) : go remainder
        | otherwise = go rest
    fieldStart line
        | " " `T.isPrefixOf` line || "\t" `T.isPrefixOf` line
        , let stripped = T.strip line
        , "::" `T.isInfixOf` stripped
        , let (before, rest) = T.breakOn "::" stripped
        , let name = T.strip (T.dropWhile (\c -> c == ',' || c == '{' || c == ' ') before)
        , not (T.null name)
        , isAlpha (T.head name)
        , T.all (\c -> isAlphaNum c || c == '\'' || c == '_') name =
            Just (T.unpack name, T.strip (T.drop 2 rest))
        | otherwise = Nothing
    continues opening line =
        not (T.null (T.strip line))
            && indentationOf line > indentationOf opening
            -- a Haddock or ordinary comment under a field is documentation,
            -- not more type, and appending it would corrupt the very
            -- signature this repair exists to derive correctly
            && not ("--" `T.isPrefixOf` T.strip line)
    indentationOf line = T.length (T.takeWhile (\c -> c == ' ' || c == '\t') line)

-- | The field selectors belonging to one named data declaration.
fieldsOfType :: String -> Text -> [(String, Text)]
fieldsOfType typeName contents =
    recordFieldSignatures (T.unlines declarationLines)
  where
    declarationLines =
        takeWhile (\line -> T.null (T.strip line) || " " `T.isPrefixOf` line || "\t" `T.isPrefixOf` line)
            . drop 1
            . dropWhile (not . declares)
            $ T.lines contents
    declares line = case T.words line of
        (keyword : name : _) -> keyword `elem` ["data", "newtype"] && name == T.pack typeName
        _ -> False

{- | Every top-level @name :: type@ in a module, with the type flattened to
one line. A signature may span many lines, so continuation lines are joined
until the next top-level construct begins.
-}
topLevelSignatures :: Text -> [(String, Text)]
topLevelSignatures contents = go (T.lines contents)
  where
    go [] = []
    go (line : rest)
        | Just name <- signatureStart line =
            let (continuation, remainder) = span isContinuation rest
                signature = T.unwords (map T.strip (afterColons line : continuation))
             in (name, signature) : go remainder
        | otherwise = go rest
    signatureStart line = case T.words line of
        (name : "::" : _)
            | not (T.null name)
            , not (" " `T.isPrefixOf` line) ->
                if isAlpha (T.head name) && T.all isIdentifierChar name
                    then Just (T.unpack name)
                    else -- a top-level operator declaration, @(>>>) :: ...@,
                    -- normalised to the same bare symbol its export item is
                        operatorName name
        _ -> Nothing
    afterColons line = T.strip (T.drop 2 (snd (T.breakOn "::" line)))
    isContinuation line =
        not (T.null (T.strip line)) && (" " `T.isPrefixOf` line || "\t" `T.isPrefixOf` line)
    isIdentifierChar c = isAlphaNum c || c == '\'' || c == '_'

-- ---------------------------------------------------------------------------
-- Derivation 3: which input types can be eagerly rejected

{- | The types a caller can hand in that are validated EAGERLY, derived from
the smart constructors that actually call a validator plus the program and
interpreter types themselves, plus any record that embeds one of those.

Derived rather than listed because the whole point of NOTE-004 is that a
list is the defect wearing a different hat: a new locator type, or a new
request record embedding one, joins this set without anybody remembering to
add it.
-}
rejectableInputTypes :: IO [String]
rejectableInputTypes = do
    -- Stated limit: 'Text' and '[Text]' selectors are eagerly validated too
    -- (reference hashes, payer addresses), but they are far too generic to
    -- derive from -- qualifying on them would sweep in every probe that
    -- happens to take a 'Text' and cannot return 'InvalidLocator' at all,
    -- turning the property into noise. The selector class is asserted
    -- explicitly instead, in its own example above.
    validated <- validatedConstructorArgumentTypes
    embedding <- recordsEmbedding (validated <> coreTypes)
    pure (nub (sort (validated <> coreTypes <> embedding)))
  where
    -- the program itself, and the interpreter that executes one: a caller
    -- handed either can supply an eagerly rejected program
    coreTypes = ["ChainQuery", "ChainQueryInterpreter"]

{- | The argument types of every exported smart constructor in
"Cardano.KERI.ChainQuery.Program" whose body calls a validator.
-}
validatedConstructorArgumentTypes :: IO [String]
validatedConstructorArgumentTypes = do
    signatures <- exportedSignaturesOf "Cardano.KERI.ChainQuery.Program"
    contents <- moduleSourceOf "Cardano.KERI.ChainQuery.Program"
    let bodies = topLevelBodies contents
        validating =
            [ name
            | (name, body) <- bodies
            , "valid" `T.isInfixOf` body
            ]
    pure
        [ typeName
        | (name, signature) <- signatures
        , name `elem` validating
        , typeName <- typeNamesIn (argumentPortion signature)
        , typeName `notElem` ["Text", "Either", "Maybe", "ChainQuery"]
        ]

-- | Record types with a field whose type is one of the given names.
recordsEmbedding :: [String] -> IO [String]
recordsEmbedding inner = do
    modules <- publicModules
    fmap (nub . concat) . for modules $ \(_name, path) -> do
        contents <- TE.decodeUtf8 <$> BS.readFile path
        pure (recordsEmbeddingIn inner contents)

recordsEmbeddingIn :: [String] -> Text -> [String]
recordsEmbeddingIn inner contents = go (T.lines contents) Nothing []
  where
    go [] _ found = found
    go (line : rest) current found
        | Just name <- dataStart line = go rest (Just name) found
        | Just name <- current
        , any (\typeName -> T.pack typeName `T.isInfixOf` line) inner
        , "::" `T.isInfixOf` line =
            go rest current (name : found)
        | T.null (T.strip line) = go rest Nothing found
        | otherwise = go rest current found
    dataStart line = case T.words line of
        ("data" : name : _) -> Just (T.unpack name)
        ("newtype" : name : _) -> Just (T.unpack name)
        _ -> Nothing

-- ---------------------------------------------------------------------------
-- Derivation 4: which public exports reach the store runner

{- | Public exports of the local interpreter module whose definitions reach
the store runner, directly or through another definition in the same module.

The type system cannot answer this: a wrapper opens a transaction without
mentioning a program in its signature, which is exactly the shape the
submission-3 repair would have introduced had it not been derived. So this is
call-graph reachability over the module's own source.
-}
storeReachingExports :: IO [String]
storeReachingExports = do
    contents <- moduleSourceOf localInterpreterModule
    exported <- map fst <$> exportedSignaturesOf localInterpreterModule
    let bodies = topLevelBodies (stripCommentsAndStrings contents)
        defined = Set.fromList (map fst bodies)
        -- An edge exists only to a name this module actually DEFINES, so a
        -- word appearing in text cannot manufacture one; comments and string
        -- literals are already gone before this point.
        graph =
            Map.fromList
                [ (name, Set.intersection defined (Set.fromList (identifiersIn body)))
                | (name, body) <- bodies
                ]
        seeds =
            Set.fromList
                [ name
                | (name, body) <- bodies
                , storeRunner `elem` identifiersIn body
                ]
        reaching = reverseReachable graph seeds
    pure (filter (`Set.member` reaching) exported)

-- | The store runner every local acquisition ultimately spends.
storeRunner :: String
storeRunner = "runTransaction"

{- | Every definition that reaches the seed set, by iterating "add the callers
of what we already have" to a fixed point.

CORRECTION-004: the first version recursed from each export over every
identifier without memoisation and did not terminate in test time. This walks
a finite graph a bounded number of times — each round either grows the set or
stops — so the property runs in test time rather than minutes.
-}
reverseReachable :: Map.Map String (Set.Set String) -> Set.Set String -> Set.Set String
reverseReachable graph = go
  where
    go reached =
        let grown = Set.union reached (callersOf reached)
         in if grown == reached then reached else go grown
    callersOf reached =
        Set.fromList
            [ name
            | (name, callees) <- Map.toList graph
            , not (Set.disjoint callees reached)
            ]

{- | Remove comments and string literals before any structural reading of a
module. Without this, a function name mentioned in a Haddock paragraph looks
exactly like a call, which both slows the graph walk and can manufacture a
reachability edge that does not exist in the code.
-}
stripCommentsAndStrings :: Text -> Text
stripCommentsAndStrings = T.unlines . map stripLine . T.lines . removeBlockComments
  where
    stripLine = removeStringLiterals . fst . T.breakOn "--"
    removeStringLiterals line = T.intercalate " " (everyOtherChunk (T.splitOn "\"" line))
    everyOtherChunk chunks = [chunk | (index, chunk) <- zip [0 :: Int ..] chunks, even index]
    removeBlockComments contents =
        case T.breakOn "{-" contents of
            (before, rest)
                | T.null rest -> before
                | otherwise ->
                    before <> " " <> removeBlockComments (T.drop 2 (snd (T.breakOn "-}" rest)))

localInterpreterModule :: String
localInterpreterModule = "Cardano.KERI.Indexer.ChainQuery"

-- ---------------------------------------------------------------------------
-- The derived qualifying set

{- | Every public entry point a caller can hand an eagerly rejectable input
to: the query layer's by type, the local layer's by type OR by reaching the
store runner.
-}
qualifyingPublicEntryPoints :: IO [SurfaceMember]
qualifyingPublicEntryPoints = do
    rejectable <- rejectableInputTypes
    modules <- publicModules
    byType <- fmap concat . for modules $ \(moduleName, _path) -> do
        signatures <- exportedSignaturesOf moduleName
        pure
            [ SurfaceMember moduleName name
            | (name, signature) <- signatures
            , acceptsRejectableInput rejectable signature
            , performsAnEffect signature
            ]
    storeReaching <- storeReachingExports
    storeReachingSignatures <- exportedSignaturesOf localInterpreterModule
    let storeReachingWithRejectableInput =
            [ SurfaceMember localInterpreterModule name
            | name <- storeReaching
            , Just signature <- [lookup name storeReachingSignatures]
            , acceptsRejectableInput rejectable signature
            ]
    pure (nub (sort (byType <> storeReachingWithRejectableInput)))

{- | A-262-03: public exports whose RESULT hands the caller an interpreter
already bound to a store transaction.

This is a second capability class, and it exists because withdrawing a
wrapper is not enough while its body stays publicly reconstructible. The
store runner is public from its own package and 'LocalQueryScope' exposes
it, so an export returning @ChainQueryInterpreter (Transaction ...)@ is the
one missing piece: with it, any caller writes the retired wrapper again in
three lines and opens a transaction for an already-rejected program.

Such an export cannot be covered by a proof action — the capability performs
no effect itself, the caller does — so the rule is that the class must be
EMPTY on the public surface.
-}
storeBackedInterpreterCapabilities :: IO [SurfaceMember]
storeBackedInterpreterCapabilities = do
    modules <- publicModules
    fmap concat . for modules $ \(moduleName, _path) -> do
        signatures <- exportedSignaturesOf moduleName
        pure
            [ SurfaceMember moduleName name
            | (name, signature) <- signatures
            , supplyingStoreBackedInterpreter signature
            ]

{- | Whether a signature's result is an interpreter over a STORE
transaction, as opposed to one over an effect the caller supplies.

The distinction matters: an interpreter over @IO@ or over a caller-chosen
effect carries no store with it, while one over @Transaction ...@ is already
attached to the local store and only needs a runner the caller can already
obtain.

The fourth audit proved that reading only the result's HEAD missed the same
capability handed back inside an ordinary container:
@Maybe (ChainQueryInterpreter (Transaction ...))@ is the identical capability
with one @fmap@ between the caller and it. So every application of
'ChainQueryInterpreter' in the result is examined, at any depth — and it
remains the EFFECT IT IS APPLIED TO that decides, which is what keeps the
caller-chosen-effect negative excluded at every one of those depths rather
than swallowed by the widening.

@Transaction@ is matched as a SUBSTRING, so a longer unrelated effect name
containing it is also flagged: a deliberate over-approximation kept per
NOTE-005, because over-inclusion costs a noisy guard while under-inclusion
costs the invariant.
-}
supplyingStoreBackedInterpreter :: Text -> Bool
supplyingStoreBackedInterpreter signature =
    any ("Transaction" `T.isInfixOf`) (interpreterEffects (resultPortion signature))

-- | The name whose applications carry the capability this rule forbids.
interpreterTypeName :: Text
interpreterTypeName = "ChainQueryInterpreter"

{- | The effect argument of every 'ChainQueryInterpreter' application in a
type fragment, at any nesting depth.

Both ends of each occurrence are checked for a token boundary, so a longer
type name that merely contains this one cannot be read as an application of
it. A module qualification is a boundary rather than part of the name, so a
qualified occurrence is still found.
-}
interpreterEffects :: Text -> [Text]
interpreterEffects = go
  where
    go fragment =
        case T.breakOn interpreterTypeName fragment of
            (_, match)
                | T.null match -> []
            (before, match) ->
                let after = T.drop (T.length interpreterTypeName) match
                 in [firstTypeArgument after | isWholeToken before after]
                        <> go after
    isWholeToken before after =
        boundary (fmap snd (T.unsnoc before)) && boundary (fmap fst (T.uncons after))
    boundary Nothing = True
    boundary (Just character) =
        not (isAlphaNum character || character == '\'' || character == '_')

{- | The first type argument applied to something: a parenthesised group
taken whole, or the bare word that follows.
-}
firstTypeArgument :: Text -> Text
firstTypeArgument text =
    case T.uncons applied of
        Nothing -> ""
        Just ('(', rest) -> balancedGroup rest
        _ -> T.takeWhile (`notElem` (" ()[],-" :: String)) applied
  where
    applied = T.stripStart text

-- | Everything up to the parenthesis that closes the group already entered.
balancedGroup :: Text -> Text
balancedGroup = T.pack . go (0 :: Int) . T.unpack
  where
    go _ [] = []
    go depth (character : rest)
        | character == ')' && depth == 0 = []
        | character == ')' = character : go (depth - 1) rest
        | character == '(' = character : go (depth + 1) rest
        | otherwise = character : go depth rest

acceptsRejectableInput :: [String] -> Text -> Bool
acceptsRejectableInput rejectable signature =
    any (`elem` typeNamesIn (argumentPortion signature)) rejectable

{- | Whether a signature's RESULT can carry out an effect.

Accepting a rejectable input is not enough on its own to make an export an
entry point this property is about: a smart constructor takes a locator and
returns a program, a validator takes one and returns 'Either', an accessor
takes an interpreter and returns its provenance. None of them can dispatch an
operation or open a transaction, so requiring a zero-effect proof of them
would be asserting a tautology and would bury the members that matter.

The discriminator is the result's head: a type VARIABLE applied to something
(@effect (...)@, @m a@) is an effect the caller chooses, and 'IO' or
'Transaction' is one this repository names. An uppercase head that is neither
— @ChainQuery ...@, @Either ...@, @ChainQueryInterpreter effect@ — is a
value being returned, not an effect being performed.
-}
performsAnEffect :: Text -> Bool
performsAnEffect signature =
    case T.words (resultPortion signature) of
        (headWord : _ : _)
            | Just (first', _) <- T.uncons (T.dropWhile (== '(') headWord) ->
                first' `elem` ['a' .. 'z'] || headWord `elem` ["IO", "Transaction"]
        _ -> False

resultPortion :: Text -> Text
resultPortion signature =
    case reverse (splitTopLevelArrows signature) of
        [] -> ""
        (result : _) -> T.strip result

-- ---------------------------------------------------------------------------
-- Small source readers

moduleSourceOf :: String -> IO Text
moduleSourceOf moduleName = do
    modules <- publicModules
    case lookup moduleName modules of
        Nothing -> fail ("no cabal-exposed module named " <> moduleName)
        Just path -> TE.decodeUtf8 <$> BS.readFile path

{- | Every top-level definition's body text, keyed by the defined name. Used
for "does this call a validator" and for call-graph reachability.
-}
topLevelBodies :: Text -> [(String, Text)]
topLevelBodies contents = go (T.lines contents)
  where
    go [] = []
    go (line : rest)
        | Just name <- definitionStart line =
            let (body, remainder) = span isContinuation rest
             in (name, T.unlines (line : body)) : go remainder
        | otherwise = go rest
    definitionStart line = case T.words line of
        (name : next : _)
            | next /= "::"
            , not (T.null name)
            , isAlpha (T.head name)
            , T.all isIdentifierChar name
            , not (" " `T.isPrefixOf` line)
            , not (isKeyword name) ->
                Just (T.unpack name)
        _ -> Nothing
    isContinuation line =
        T.null (T.strip line) || " " `T.isPrefixOf` line || "\t" `T.isPrefixOf` line
    isIdentifierChar c = isAlphaNum c || c == '\'' || c == '_'
    isKeyword name =
        name `elem` ["module", "import", "data", "newtype", "type", "class", "instance", "deriving"]

{- | The argument portion of a signature: everything before the final arrow.

Signatures arrive here WITHOUT their @::@, from both readers — top-level
declarations and record fields alike. Keeping the two shapes identical
matters: an earlier version left the @::@ on one of them, and every field
type silently failed to parse, so the field-expansion work would have derived
nothing while looking correct.
-}
argumentPortion :: Text -> Text
argumentPortion signature =
    case reverse (splitTopLevelArrows signature) of
        [] -> ""
        (_result : arguments) -> T.unwords (reverse arguments)

{- | Split on @->@ at parenthesis depth zero, so a higher-order argument's
own arrows do not look like top-level ones. This is what makes a rank-2
callback taking a 'ChainQueryInterpreter' count as an ARGUMENT rather than
being mistaken for the result.
-}
splitTopLevelArrows :: Text -> [Text]
splitTopLevelArrows = go 0 "" . T.unpack
  where
    go :: Int -> String -> String -> [Text]
    go _ acc [] = [T.pack (reverse acc)]
    go depth acc ('-' : '>' : rest)
        | depth == 0 = T.pack (reverse acc) : go 0 "" rest
        | otherwise = go depth ('>' : '-' : acc) rest
    go depth acc (c : rest)
        | c `elem` ("([" :: String) = go (depth + 1) (c : acc) rest
        | c `elem` (")]" :: String) = go (depth - 1) (c : acc) rest
        | otherwise = go depth (c : acc) rest

-- | Every capitalised type name mentioned in a fragment of a signature.
typeNamesIn :: Text -> [String]
typeNamesIn fragment =
    [ T.unpack word
    | word <- T.split (not . isIdentifierChar) fragment
    , not (T.null word)
    , isAlpha (T.head word)
    , T.head word `elem` ['A' .. 'Z']
    ]
  where
    isIdentifierChar c = isAlphaNum c || c == '\'' || c == '_' || c == '.'

-- | Every identifier mentioned in a definition body.
identifiersIn :: Text -> [String]
identifiersIn body =
    [ T.unpack word
    | word <- T.split (not . isIdentifierChar) body
    , not (T.null word)
    , isAlpha (T.head word)
    ]
  where
    isIdentifierChar c = isAlphaNum c || c == '\'' || c == '_'

-- ---------------------------------------------------------------------------
-- Assertion helpers that name what went wrong

shouldContainName :: [String] -> String -> IO ()
shouldContainName haystack needle
    | needle `elem` haystack = pure ()
    | otherwise =
        expectationFailure
            ("expected the derivation to find " <> needle <> ", but it found " <> show (sort haystack))

shouldNotContainName :: [String] -> String -> IO ()
shouldNotContainName haystack needle
    | needle `notElem` haystack = pure ()
    | otherwise =
        expectationFailure
            ("the derivation wrongly included " <> needle <> "; it found " <> show (sort haystack))
