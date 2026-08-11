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
  * WHAT EACH MODULE EXPORTS, and each export's type, comes from GHC's
    resolved export information for the compiled module (#266) — never from
    that module's source, so spelling, layout, comments, string literals and
    re-export form cannot move a route in or out;
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
import Cardano.KERI.Compiler.ExportSurface (
    ExportKind (..),
    PublicExport (..),
    PublicValue (..),
    SurfaceFailure (..),
    exposedRoutesOf,
    publicExportsOf,
    publicValuesOf,
    withCompilerExportSession,
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
import Cardano.KERI.SurfaceFixture.ByteZero (commentTrapExport)
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Indexer (withInMemoryIndexerRunner)
import Codec.Binary.Bech32 qualified as Bech32
import Control.Exception (SomeException, try)
import Control.Monad (unless)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Char (isAlpha, isAlphaNum)
import Data.Foldable (fold, for_, toList)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
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
import Distribution.Types.BuildInfo (BuildInfo (hsSourceDirs))
import Distribution.Types.CondTree (CondTree)
import Distribution.Types.GenericPackageDescription (
    GenericPackageDescription (condLibrary, condSubLibraries),
 )
import Distribution.Types.Library (Library (exposedModules, libBuildInfo, libVisibility))
import Distribution.Types.LibraryVisibility (LibraryVisibility (LibraryVisibilityPrivate))
import Paths_cardano_keri (getDataFileName)
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)
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

            it "#266 RQ-266-01 derivation control: exported signatures come from GHC's export data, and a private definition is not among them" $ do
                signatures <- exportedSignaturesOf "Cardano.KERI.Indexer.ChainQuery"
                map fst signatures `shouldContainName` "runLocalQuery"
                -- 'localOutputAt' is defined in that module but deliberately
                -- not exported; if it appeared here the derivation would be
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

            -- #266 T266-S1-05. These four used to drive a hand-written parser
            -- over source text. They now drive the SHIPPED derivation over
            -- COMPILED fixture modules, so each one asserts what GHC answers
            -- about a real export shape rather than what a reader believed
            -- about a string. The fixtures live in a `visibility: private`
            -- component, so they are queryable but are not public routes.

            it "#266 T266-S1-05 shape control: an exported OPERATOR is a public value, with no export-item parsing anywhere in the answer" $
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureDefiningModule
                    map exportedName values `shouldContainName` ">|<"

            it "#266 T266-S1-05 shape control: a record field whose type CONTINUES past its `::` line derives exactly what the one-line spelling derives -- physical layout is not part of what a module exports (the submission-4 counterexample, now compiled)" $
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureDefiningModule
                    let typeOf name =
                            [exportedType value | value <- values, exportedName value == name]
                    case (typeOf "fixtureContinuedField", typeOf "fixtureOneLineField") of
                        ([continued], [oneLine]) -> continued `shouldBe` oneLine
                        other ->
                            expectationFailure
                                ("the two identical field spellings did not both derive: " <> show other)

            it "#266 T266-S1-05 shape control: a whole-module re-export contributes the re-exported names on the RE-EXPORTING route, while GHC still attributes them to their defining module" $
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureUmbrellaModule
                    let defining name =
                            [definingIdentity value | value <- values, exportedName value == name]
                    defining "fixturePlainValue" `shouldBe` [fixtureDefiningModule]
                    -- and an IMPORTED re-export, from another component
                    -- entirely: the 'plutusDataJson' shape that had been
                    -- leaving the #262 enumeration unnoticed
                    defining "outputAt" `shouldBe` ["Cardano.KERI.ChainQuery.Program"]

            it "#266 T266-S1-04 lexical control: a nested block comment carrying a fake module header, `module` in prose, and `module` in a string literal contribute NOTHING -- the route derives exactly its two real exports" $
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureByteZeroModule
                    sort (map exportedName values)
                        `shouldBe` ["byteZeroExport", "commentTrapExport"]

            it "#266 DATA-INV-266-03 fail-closed control: enumeration does not go through source at all -- the fixture routes derive even though their source directory belongs to no publicly visible library, so no source-path resolution for them exists" $ do
                modules <- publicModules
                map fst modules `shouldNotContainName` fixtureDefiningModule
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureDefiningModule
                    values `shouldNotBe` []

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

            it "#266 T266-S1-05 signature control: the continued field really JOINS the qualifying set under the shipped rules, rather than deriving a type nobody can classify (the submission-4 counterexample, now compiled)" $ do
                rejectable <- rejectableInputTypes
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureDefiningModule
                    case [exportedType value | value <- values, exportedName value == "fixtureContinuedField"] of
                        [signature] -> do
                            acceptsRejectableInput rejectable signature `shouldBe` True
                            performsAnEffect signature `shouldBe` True
                        other ->
                            expectationFailure
                                ("the continued field did not derive exactly once: " <> show other)

            it "#266 T266-S1-05 capability control: a store-transaction-backed interpreter NESTED under an ordinary result container is still a handed-out capability, read through the real derivation (the submission-4 counterexample, now compiled)" $
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureDefiningModule
                    case [exportedType value | value <- values, exportedName value == "fixtureNestedCapability"] of
                        [signature] -> supplyingStoreBackedInterpreter signature `shouldBe` True
                        other ->
                            expectationFailure
                                ("the nested capability did not derive exactly once: " <> show other)

            it "capability control: the same nesting is detected directly, under each container the result of such an export realistically wears" $
                for_
                    [ "LocalQueryScope cf op -> Maybe (ChainQueryInterpreter (Transaction IO cf Cols op))"
                    , "LocalQueryScope cf op -> IO (ChainQueryInterpreter (Transaction IO cf Cols op))"
                    , "LocalQueryScope cf op -> Either ChainQueryError (ChainQueryInterpreter (Transaction IO cf Cols op))"
                    , "LocalQueryScope cf op -> [ChainQueryInterpreter (Transaction IO cf Cols op)]"
                    ]
                    (\signature -> supplyingStoreBackedInterpreter signature `shouldBe` True)

            it "#266 T266-S1-04 fail-closed control: a module whose declaration begins at BYTE ZERO is enumerated, not silently emptied (submission-5 audit finding 1) -- and the omission was never synthetic, because a really Cabal-exposed byte-zero module also has exports" $ do
                signatures <- exportedSignaturesOf "Cardano.KERI.AID.CESR"
                map fst signatures `shouldContainName` "parsePrimitive"
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session fixtureByteZeroModule
                    values `shouldNotBe` []

            it "#266 DAT-266-SURFACE-FAILURE fail-closed control: asking for a route no compiled unit exposes names that route instead of answering with an empty surface" $
                withCompilerExportSession $ \session ->
                    requiresSurfaceFailure
                        "Cardano.KERI.SurfaceFixture.NotAModule"
                        (publicExportsOf session "Cardano.KERI.SurfaceFixture.NotAModule")

            it "#266 DAT-266-SURFACE-FAILURE fail-closed control: a route outside the cabal-exposed public set is a category error, not a quietly empty answer" $
                requiresFailClosedDerivation (exportedSignaturesOf "Mutant.Surface")

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

            it "#266 INV-266-FALSIFIABLE (A-262-03): every derived qualifying public entry point has an EXECUTABLE zero-effect proof, and it is executed here -- so a newly exported qualifying entry point joins this set or fails this example" $ do
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

            it "#266 INV-266-NO-REGRESSION coverage control: every proof action still names a real derived member, so the registry cannot drift into fiction while #262's behavioural proofs stay untouched" $ do
                derived <- qualifyingPublicEntryPoints
                uncoveredMembers (map fst proofActions) derived `shouldBe` []

            -- ---------------------------------------------------------------
            -- #266: the enumeration is the COMPILER's, not a source reader's
            --
            -- INV-266-DERIVED is an equality, so it is asserted as one: for
            -- every Cabal-exposed module, the value routes this suite derives
            -- must be exactly the value routes GHC reports for that module.
            -- Anything the derivation adds is fiction; anything it drops is a
            -- public entry point that silently left the guard, which is the
            -- defect five #262 submissions kept shipping under different names.

            it "#266 INV-266-DERIVED: the derived public value routes of EVERY cabal-exposed module are exactly the routes GHC reports for it" $ do
                routes <- publicModuleRoutes
                withCompilerExportSession $ \session -> do
                    disagreements <- fmap concat . for routes $ \route -> do
                        derived <- map fst <$> exportedSignaturesOf route
                        compiled <- map exportedName <$> publicValuesOf session route
                        pure
                            [ (route, sort (nub derived), sort (nub compiled))
                            | sort (nub derived) /= sort (nub compiled)
                            ]
                    if null disagreements
                        then pure ()
                        else
                            expectationFailure $
                                "the enumerated public surface is not the one GHC resolved. Each \
                                \entry is (module, derived here, reported by GHC): "
                                    <> show disagreements

            it "#266 INV-266-DERIVED anti-vacuity: the compiler surface is non-empty and names known public routes, so an equality against nothing cannot pass" $ do
                routes <- publicModuleRoutes
                routes `shouldNotBe` []
                withCompilerExportSession $ \session -> do
                    values <- publicValuesOf session localInterpreterModule
                    map exportedName values `shouldContainName` "runLocalQuery"
                    map exportedName values `shouldContainName` "localScopeRunner"

            it "#266 RQ-266-02: a re-exported name keeps the ROUTE it is imported through, while GHC still reports its defining module -- two identities, never collapsed" $
                withCompilerExportSession $ \session -> do
                    umbrella <- publicValuesOf session "Cardano.KERI.ChainQuery"
                    case [value | value <- umbrella, exportedName value == "runChainQuery"] of
                        [] -> expectationFailure "the umbrella route lost runChainQuery"
                        (value : _) -> do
                            routeModule value `shouldBe` "Cardano.KERI.ChainQuery"
                            definingIdentity value `shouldBe` "Cardano.KERI.ChainQuery.Interpreter"

            it "#266 RQ-266-03/RQ-266-04: GHC's answer contains record field selectors as typed values, and classifies constructors and types explicitly rather than dropping them" $
                withCompilerExportSession $ \session -> do
                    exports <- publicExportsOf session localInterpreterModule
                    let named name = [exportKind e | e <- exports, exportName e == name]
                    case named "localScopeRunner" of
                        [ExportedValue signature] -> resultPortion signature `shouldNotBe` ""
                        other -> expectationFailure ("localScopeRunner: " <> show other)
                    named "LocalQueryScope"
                        `shouldMatchClasses` [ExportedTypeOrClass, ExportedConstructor]

            it "#266 RQ-266-04: an exposed module the compiler environment cannot resolve fails closed and names the route, instead of reporting an empty surface" $
                withCompilerExportSession $ \session ->
                    requiresSurfaceFailure
                        "Cardano.KERI.Definitely.Not.A.Module"
                        (publicExportsOf session "Cardano.KERI.Definitely.Not.A.Module")

            it "#266 DATA-INV-266-01: every module the cabal seed calls public is a module the compiler environment actually exposes, so the two never drift apart silently" $ do
                routes <- publicModuleRoutes
                withCompilerExportSession $ \session -> do
                    let compiled = exposedRoutesOf session
                        unexposed = filter (`notElem` compiled) routes
                    unexposed `shouldBe` []

            it "#266 T266-S1-04 fixture non-vacuity: the compiled comment-trap module really carries the word `module` in a string literal" $
                ("module " `isInfixOf` commentTrapExport) `shouldBe` True

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
-- The compiled regression fixtures (#266 INV-266-REGRESSIONS, T266-S1-04, T266-S1-05)
--
-- Every shape below defeated the #262 source reader at least once. They used
-- to be strings written to a temporary file and read back by that reader, so
-- the control could only ever be as good as the reader's opinion of them.
-- They are now REAL COMPILED MODULES in a `visibility: private` library
-- component, queried through the same session the shipped enumeration uses,
-- and the assertion is on GHC's answer.
--
-- Private visibility is load-bearing twice over: it keeps the fixtures out of
-- the public surface the property ranges over (so the deliberately forbidden
-- capability in them is not a finding), and it makes them a positive control
-- for "enumeration does not read source" -- their source directory belongs to
-- no publicly visible library, so no source-path resolution for them exists,
-- yet they enumerate.

{- | The derivation refuses rather than under-reporting (NOTE-005).

The product rule #240 established for checkpoint decoding is that an input
that cannot be read fails closed and names itself, with no silent fallback.
Over-inclusion costs noise; under-inclusion costs the invariant.
-}
failClosed :: String -> IO a
failClosed reason =
    fail ("public-surface derivation FAILED CLOSED -- " <> reason)

fixtureDefiningModule :: String
fixtureDefiningModule = "Cardano.KERI.SurfaceFixture.Defining"

fixtureUmbrellaModule :: String
fixtureUmbrellaModule = "Cardano.KERI.SurfaceFixture.Umbrella"

fixtureByteZeroModule :: String
fixtureByteZeroModule = "Cardano.KERI.SurfaceFixture.ByteZero"

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

{- | Exposed modules of a library a consumer can actually import.

Ticket #266: visibility is part of the answer, not decoration. A
@visibility: private@ component -- the compiled regression fixtures -- is
unimportable from outside this package, so its modules are not public routes
and must not reach the qualification rules either. Leaving them in would let a
fixture record deliberately embedding 'ChainQuery' widen the derived
rejectable-input set, which is the tests contaminating the thing they measure.
-}
exposedOnly :: Library -> [String]
exposedOnly library
    | libVisibility library == LibraryVisibilityPrivate = []
    | otherwise = map prettyShow (exposedModules library)

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
-- Derivation 2: what each module exports, and with what type -- ASKED, NOT PARSED
--
-- #266. This used to be a source reader: it located a module's file, stripped
-- comments and string literals, found the export list, split it at top-level
-- commas, classified each item, expanded `module X` re-exports and
-- `Type (..)` field selectors, and hunted each name's signature across the
-- package. Five #262 submissions each taught it one more legal spelling, and
-- each was followed by an audit naming the next one -- and it was STILL wrong:
-- the RED commit this replaces recorded eight public record selectors of
-- "Cardano.KERI.Deployment.EndpointBoard" that it never reported.
--
-- GHC already did all of that work to compile the package. So the enumeration
-- now asks it. Source spelling, layout, comments, string literals and
-- re-export form cannot move a route in or out of the derived set, because
-- none of them is an input to it any more (DATA-INV-266-03).

{- | The complete compiler-reported public surface, computed ONCE.

FUN-266-SESSION requires one session to serve the whole enumeration, and the
property asks about the same modules many times, so the result is memoised
rather than the session reopened per question. A session per module would also
allow two modules to be described by two different compilers, which is not a
surface anyone could import.
-}
{-# NOINLINE publicSurfaceCache #-}
publicSurfaceCache :: IORef (Maybe [PublicExport])
publicSurfaceCache = unsafePerformIO (newIORef Nothing)

derivedPublicExports :: IO [PublicExport]
derivedPublicExports =
    readIORef publicSurfaceCache >>= \case
        Just cached -> pure cached
        Nothing -> do
            routes <- publicModuleRoutes
            exports <-
                withCompilerExportSession $ \session ->
                    concat <$> traverse (publicExportsOf session) routes
            writeIORef publicSurfaceCache (Just exports)
            pure exports

{- | Every exported VALUE of a public module, with the type GHC gives it
(FUN-266-EXPORTED).

The consumer-visible route is preserved independently of where GHC says each
name is defined, so a re-export stays a distinct public route. Everything
downstream -- qualification, the capability rule, coverage -- is unchanged;
only where membership comes from has changed.
-}
exportedSignaturesOf :: String -> IO [(String, Text)]
exportedSignaturesOf routeModuleName = do
    routes <- publicModuleRoutes
    unless (routeModuleName `elem` routes) $
        failClosed
            ( routeModuleName
                <> " is not a cabal-exposed public route, so asking for its exported \
                   \signatures is a category error rather than a question with an empty \
                   \answer"
            )
    exports <- derivedPublicExports
    pure
        [ (exportName export, signature)
        | export <- exports
        , exportRoute export == routeModuleName
        , ExportedValue signature <- [exportKind export]
        ]

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

-- ---------------------------------------------------------------------------
-- #266: the Cabal seed, reduced to module ROUTES
--
-- The seed's whole job is now "which modules can a consumer import", and a
-- module name is the entire answer. It deliberately does NOT resolve a source
-- file: under the compiler-owned enumeration, a module's public surface has
-- nothing to do with whether its source is present, readable, or spelled the
-- way a reader expects (DATA-INV-266-03). The source-path resolution below
-- survives only for the two derivations that genuinely read bodies -- which
-- constructors validate, and what reaches the store runner.

{- | Every module a PUBLICLY VISIBLE library component exposes.

Visibility is the rule, not a name list: a consumer can only import through a
component that is visible to them, so a @visibility: private@ component -- the
compiled regression fixtures -- is not a public route, while every real
sub-library remains one.
-}
publicModuleRoutes :: IO [String]
publicModuleRoutes = fmap (nub . sort . concat) (withLibraries publicVisibleModules)
  where
    publicVisibleModules library
        | libVisibility library == LibraryVisibilityPrivate = []
        | otherwise = map prettyShow (exposedModules library)

withLibraries :: (Library -> [a]) -> IO [[a]]
withLibraries selectFrom = do
    contents <- BS.readFile cabalFilePath
    case runParseResult (parseGenericPackageDescription contents) of
        (_warnings, Left (_version, errs)) ->
            fail ("failed to parse " <> cabalFilePath <> ": " <> show (toList errs))
        (_warnings, Right gpd) ->
            pure
                [ selectFrom (fold tree)
                | tree <- maybeToList (condLibrary gpd) <> map snd (condSubLibraries gpd)
                ]

-- ---------------------------------------------------------------------------
-- #266: assertion helpers for the compiler-derived controls

{- | Require a derivation to fail CLOSED with a surface failure that names the
route it could not describe.

Both halves matter, exactly as for the reader this replaces: a failure for an
unrelated reason would satisfy "it failed" while proving nothing about the
enumeration, so the failure has to identify what it could not handle.
-}
requiresSurfaceFailure :: (Show a) => String -> IO a -> IO ()
requiresSurfaceFailure route derivation = do
    outcome <- try derivation
    case outcome of
        Right derived ->
            expectationFailure
                ( "the compiler surface reported a result instead of failing closed on a route \
                  \it cannot describe; it returned "
                    <> show derived
                )
        Left failure
            | failedModule failure == route -> pure ()
            | otherwise ->
                expectationFailure
                    ( "the derivation failed closed, but named "
                        <> show (failedModule failure)
                        <> " rather than "
                        <> show route
                        <> ", so an unrelated failure would satisfy this control: "
                        <> show failure
                    )

-- | Require a set of export classifications, order-independently.
shouldMatchClasses :: [ExportKind] -> [ExportKind] -> IO ()
shouldMatchClasses actual expected
    | sort (map summarise actual) == sort (map summarise expected) = pure ()
    | otherwise =
        expectationFailure
            ( "expected the export classifications "
                <> show expected
                <> " but GHC reported "
                <> show actual
            )
  where
    summarise = \case
        ExportedValue _ -> "value" :: String
        ExportedTypeOrClass -> "type-or-class"
        ExportedConstructor -> "constructor"
        ExportedAxiom -> "axiom"

{- | Require an enumeration to refuse rather than answer.

The refusal has to come from the derivation's own fail-closed rule, so the
control asserts the message it names rather than merely that something threw:
an unrelated exception would otherwise satisfy "it failed" while proving
nothing, which is the manufactured-confidence shape this suite exists to
refuse.
-}
requiresFailClosedDerivation :: (Show a) => IO a -> IO ()
requiresFailClosedDerivation derivation = do
    outcome <- try derivation
    case outcome of
        Right derived ->
            expectationFailure
                ( "the derivation answered instead of failing closed; it returned "
                    <> show derived
                )
        Left failure
            | "public-surface derivation FAILED CLOSED"
                `isInfixOf` show (failure :: SomeException) ->
                pure ()
            | otherwise ->
                expectationFailure
                    ( "the derivation failed, but not through its own fail-closed rule: "
                        <> show failure
                    )
