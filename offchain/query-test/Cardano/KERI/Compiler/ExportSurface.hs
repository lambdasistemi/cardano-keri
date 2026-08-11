{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Compiler.ExportSurface
Description : #266 MOD-266-COMPILER-SURFACE — the public export surface as GHC resolved it
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A test-support boundary that answers one question and knows nothing else:
for a module this package exposes, WHICH NAMES does a consumer importing that
module actually get, and WHAT IS EACH ONE'S TYPE?

The answer comes from GHC, over the compiled package modules — never from
Haskell source. That is the whole point of #266. A source reader has to
re-implement the language to answer this: export lists, @module X@
re-exports, @Type (..)@ field selectors, operators, imported re-exports,
layout, comments, string literals. Five #262 submissions each taught the
reader one more spelling and each was followed by an audit naming the next,
because a reader that silently under-counts is the hand-maintained list
wearing a derivation's clothes. GHC has already resolved every one of those
shapes in order to produce the interface files this session reads, so the
correct move is to ask it rather than to re-derive it.

Two identities are kept for every export, because they are genuinely
different (RQ-266-02):

  * the ROUTE module — the Cabal-exposed module a consumer writes in an
    @import@, which is the module this session was asked about;
  * the DEFINING module — where GHC says the name actually comes from.

A re-export makes these differ, and a member is keyed by the route. The same
function reached through an umbrella module is a second public route to it,
so it is a second member with its own obligations (DATA-INV-266-04).

This module has no chain-query, qualification or zero-effect knowledge, so it
can be lifted out to a reusable package later without moving any domain
behaviour with it (PROMOTE-266-01). It is deliberately not published as one
here.

== The environment it needs

A GHC session cannot be started by a compiled binary on its own: a program
linked against the @ghc@ library still has no way to find a compiler
installation — @findTopDir Nothing@ answers @\<dirname exe\>/../lib@, and
@GHC.Settings.Config@ carries no libdir constant. The environment is
therefore supplied explicitly by whoever runs the suite (the Nix dev shell
and the packaged @local-write-path-check@ runner both export it), and its
absence fails closed rather than reporting an empty public surface.
-}
module Cardano.KERI.Compiler.ExportSurface (
    -- * Session
    CompilerExportSession,
    withCompilerExportSession,
    exposedRoutesOf,

    -- * Queries
    publicExportsOf,
    publicValuesOf,
    publicValuesOfModules,

    -- * What a query answers
    PublicExport (..),
    ExportKind (..),
    PublicValue (..),

    -- * How a query refuses
    SurfaceFailure (..),
    SurfacePhase (..),

    -- * The environment bindings this boundary requires
    libdirVariable,
    packageDbVariable,
) where

import Control.Exception (Exception, throwIO)
import Control.Monad.IO.Class (liftIO)
import Data.List (isPrefixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import GHC (
    Ghc,
    ModuleInfo,
    ModuleName,
    Name,
    TyThing (..),
    Unit,
    getModuleInfo,
    getSession,
    getSessionDynFlags,
    lookupName,
    mkModule,
    mkModuleName,
    modInfoExports,
    modInfoLookupName,
    moduleName,
    moduleNameString,
    nameModule,
    runGhc,
    setSessionDynFlags,
 )
import GHC.Driver.Env (hsc_units)
import GHC.Driver.Monad (Session, reflectGhc, reifyGhc)
import GHC.Driver.Session (DynFlags (packageDBFlags), PackageDBFlag (..), PkgDbRef (..))
import GHC.Types.Id (idType)
import GHC.Types.Name (nameOccName, occNameString)
import GHC.Unit.Info (unitExposedModules, unitId)
import GHC.Unit.State (listUnitInfo)
import GHC.Unit.Types (Definite (..), GenUnit (..), unitIdString)
import GHC.Utils.Outputable (SDoc, defaultSDocContext, ppr, showSDocOneLine)
import System.Directory (doesDirectoryExist)
import System.Environment (lookupEnv)

-- ---------------------------------------------------------------------------
-- What a query answers

{- | One export, on one public route, as GHC resolved it
(DAT-266-PUBLIC-VALUE).

'exportDefiningModule' may coincide across routes — that is exactly what a
re-export is — but it never collapses two routes into one member.
-}
data PublicExport = PublicExport
    { exportRoute :: String
    -- ^ the Cabal-exposed module a consumer imports it through
    , exportName :: String
    -- ^ the occurrence GHC reports on that route
    , exportDefiningModule :: String
    -- ^ GHC's identity for the module the name comes from
    , exportKind :: ExportKind
    -- ^ what kind of entry it is, always stated
    }
    deriving stock (Eq, Ord, Show)

{- | Every export is CLASSIFIED, never dropped.

Only 'ExportedValue' is a callable value-level entry carrying a type. The
other constructors exist so that a type, a data constructor or a class arrives
as an explicit answer rather than as silence — a surface reader that discards
what it does not understand is indistinguishable from one that never read the
module (RQ-266-04).
-}
data ExportKind
    = -- | a callable value, with the type GHC gives it
      ExportedValue Text
    | -- | a type constructor or class
      ExportedTypeOrClass
    | -- | a data constructor or pattern synonym
      ExportedConstructor
    | -- | a coercion axiom
      ExportedAxiom
    deriving stock (Eq, Ord, Show)

{- | The projection the #262 guard consumes: a public route to a callable
value, with its type.
-}
data PublicValue = PublicValue
    { routeModule :: String
    , exportedName :: String
    , definingIdentity :: String
    , exportedType :: Text
    }
    deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------------
-- How a query refuses

{- | A terminal failure of the derived surface (DAT-266-SURFACE-FAILURE).

Never converted into an empty module or an omitted member: an exposed module
that cannot be described is the one case where reporting a surface would be a
lie, because the report is indistinguishable from a module that genuinely
exports nothing.
-}
data SurfaceFailure = SurfaceFailure
    { failedModule :: String
    , failedPhase :: SurfacePhase
    , failedContext :: String
    }
    deriving stock (Eq, Show)

instance Exception SurfaceFailure

-- | Which phase of the query could not be completed.
data SurfacePhase
    = -- | no compiled unit of this package exposes the requested module
      ModuleResolution
    | -- | GHC has no module information for it
      ModuleInformation
    | -- | an exported name has no resolvable entry
      ValueType
    | -- | the compiler environment itself is unusable
      CompilerEnvironment
    deriving stock (Eq, Show)

failClosed :: String -> SurfacePhase -> String -> IO a
failClosed moduleName' phase context =
    throwIO
        SurfaceFailure
            { failedModule = moduleName'
            , failedPhase = phase
            , failedContext = context
            }

-- ---------------------------------------------------------------------------
-- Session

{- | One configured GHC session, plus the map from exposed module name to the
compiled unit of this package that exposes it.

Addressing a module through its owning unit rather than through a plain name
lookup is deliberate: this package's sub-components are registered as hidden
units, so a name lookup would have to expose them globally first — weaker,
and less precise, than naming the unit we mean.
-}
data CompilerExportSession = CompilerExportSession
    { sessionHandle :: Session
    , sessionRoutes :: [(Unit, [ModuleName])]
    }

-- | The environment variable naming the GHC installation to run the session in.
libdirVariable :: String
libdirVariable = "KERI_PUBLIC_SURFACE_GHC_LIBDIR"

{- | The environment variable naming the extra package databases that describe
this package's compiled components, colon-separated. May be unset when the
libdir's own database already describes them.
-}
packageDbVariable :: String
packageDbVariable = "KERI_PUBLIC_SURFACE_PACKAGE_DBS"

{- | Run an action with one session serving the COMPLETE enumeration
(FUN-266-SESSION).

One session, not one per module: interface loading is cached inside it, and a
per-module session would also let two modules be described by two different
compilers, which is not a surface anyone could import.
-}
withCompilerExportSession :: (CompilerExportSession -> IO a) -> IO a
withCompilerExportSession use = do
    libdir <- requiredLibdir
    dbs <- requestedPackageDbs
    runGhc (Just libdir) $ do
        dflags <- getSessionDynFlags
        _ <- setSessionDynFlags dflags{packageDBFlags = [PackageDB (PkgDbPath db) | db <- dbs]}
        routes <- ownRoutes
        liftIO (requireNonEmptyEnvironment libdir dbs routes)
        reifyGhc (\handle -> use (CompilerExportSession handle routes))

{- | An environment that resolves no unit of this package at all would make
every later query answer "nothing exported", which is precisely the silent
skip this derivation exists to remove. It is a terminal environment failure
instead.
-}
requireNonEmptyEnvironment :: FilePath -> [FilePath] -> [(Unit, [ModuleName])] -> IO ()
requireNonEmptyEnvironment libdir dbs routes
    | not (null routes) = pure ()
    | otherwise =
        failClosed
            "<no module>"
            CompilerEnvironment
            ( "no compiled unit whose id begins with "
                <> show ownUnitPrefix
                <> " is registered in this compiler environment; libdir "
                <> show libdir
                <> ", package databases "
                <> show dbs
            )

requiredLibdir :: IO FilePath
requiredLibdir =
    lookupEnv libdirVariable >>= \case
        Nothing -> unusable "is not set"
        Just "" -> unusable "is set but empty"
        Just libdir -> do
            present <- doesDirectoryExist libdir
            if present
                then pure libdir
                else unusable ("names " <> show libdir <> ", which is not a directory")
  where
    unusable reason =
        failClosed
            "<no module>"
            CompilerEnvironment
            ( libdirVariable
                <> " "
                <> reason
                <> ". A binary linked against the GHC API cannot locate a compiler \
                   \installation by itself, so the runner must supply one; without it there \
                   \is no compiler-owned surface to report, and reporting an empty one would \
                   \be the silent skip this guard exists to prevent"
            )

requestedPackageDbs :: IO [FilePath]
requestedPackageDbs =
    lookupEnv packageDbVariable >>= \case
        Nothing -> pure []
        Just raw -> traverse requireDirectory (filter (not . null) (splitOnColon raw))
  where
    requireDirectory db = do
        present <- doesDirectoryExist db
        if present
            then pure db
            else
                failClosed
                    "<no module>"
                    CompilerEnvironment
                    ( packageDbVariable
                        <> " names package database "
                        <> show db
                        <> ", which does not exist"
                    )

splitOnColon :: String -> [String]
splitOnColon text = case break (== ':') text of
    (chunk, []) -> [chunk]
    (chunk, _ : rest) -> chunk : splitOnColon rest

{- | Every compiled unit belonging to this package, with the modules it
exposes.
-}
ownRoutes :: Ghc [(Unit, [ModuleName])]
ownRoutes = do
    units <- listUnitInfo . hsc_units <$> getSession
    pure
        [ (RealUnit (Definite (unitId info)), map fst (unitExposedModules info))
        | info <- units
        , ownUnitPrefix `isPrefixOf` unitIdString (unitId info)
        ]

{- | Units of this package are the ones whose unit id begins with the package
name. Both build paths agree on that shape: the Cabal build registers
@cardano-keri-0.4.0-inplace-\<component\>@ and the packaged build registers
@cardano-keri-0.4.0-\<hash\>@.
-}
ownUnitPrefix :: String
ownUnitPrefix = "cardano-keri"

{- | Every module name this package's compiled units expose, as the compiler
environment sees it. Used by the controls to prove the session is looking at
the same package the Cabal seed describes.
-}
exposedRoutesOf :: CompilerExportSession -> [String]
exposedRoutesOf session =
    sort
        [ moduleNameString name
        | (_unit, names) <- sessionRoutes session
        , name <- names
        ]

-- ---------------------------------------------------------------------------
-- Queries

{- | Every export of one exposed module, classified (FUN-266-MODULE).

Fails closed, naming the route, when no compiled unit of this package exposes
the module, when GHC has no information for it, or when an exported name has
no resolvable entry. A partial answer is never returned (DATA-INV-266-01,
DATA-INV-266-02).
-}
publicExportsOf :: CompilerExportSession -> String -> IO [PublicExport]
publicExportsOf session routeModule' = do
    unit <- unitExposing session routeModule'
    reflectGhc (describe unit) (sessionHandle session)
  where
    name = mkModuleName routeModule'
    describe unit =
        getModuleInfo (mkModule unit name) >>= \case
            Nothing ->
                liftIO $
                    failClosed
                        routeModule'
                        ModuleInformation
                        "the compiled unit exposes this module but GHC has no module \
                        \information for it, so its public surface was never read"
            Just info -> do
                things <- traverse (\n -> (,) n <$> entryFor info n) (modInfoExports info)
                liftIO (traverse (uncurry (exportOf routeModule')) things)

{- | The entry describing an exported name, whether it is defined here or
merely routed through here.

'modInfoLookupName' alone is not enough, and the way it fails is nasty: a
RE-EXPORTED name is described by its DEFINING module's interface, so looking
it up in the re-exporting module's own environment answers 'Nothing' unless
that other interface happens to have been loaded already by an earlier query.
That makes the answer depend on the order modules are asked about — under
Hspec, on the random seed. An instrument whose verdict moves with a test seed
is worse than no instrument, so the lookup falls back to the session-wide
'lookupName', which loads the defining interface on demand.
-}
entryFor :: ModuleInfo -> Name -> Ghc (Maybe TyThing)
entryFor info name =
    modInfoLookupName info name >>= \case
        Just thing -> pure (Just thing)
        Nothing -> lookupName name

unitExposing :: CompilerExportSession -> String -> IO Unit
unitExposing session routeModule' =
    case [unit | (unit, names) <- sessionRoutes session, name `elem` names] of
        (unit : _) -> pure unit
        [] ->
            failClosed
                routeModule'
                ModuleResolution
                "no compiled unit of this package exposes it, so the Cabal-declared \
                \exposed-module set and the compiled surface disagree; an omitted module \
                \would report a public surface that was never enumerated"
  where
    name = mkModuleName routeModule'

exportOf :: String -> Name -> Maybe TyThing -> IO PublicExport
exportOf routeModule' name thing = do
    kind <- classifyThing routeModule' name thing
    pure
        PublicExport
            { exportRoute = routeModule'
            , exportName = occNameString (nameOccName name)
            , exportDefiningModule = moduleNameString (moduleName (nameModule name))
            , exportKind = kind
            }

classifyThing :: String -> Name -> Maybe TyThing -> IO ExportKind
classifyThing routeModule' name = \case
    Just (AnId identifier) -> pure (ExportedValue (renderType (ppr (idType identifier))))
    Just (AConLike _) -> pure ExportedConstructor
    Just (ATyCon _) -> pure ExportedTypeOrClass
    Just (ACoAxiom _) -> pure ExportedAxiom
    Nothing ->
        failClosed
            routeModule'
            ValueType
            ( "GHC reports `"
                <> occNameString (nameOccName name)
                <> "` as exported but has no entry describing it, so it can be neither \
                   \classified as a qualifying entry point nor excluded from the surface"
            )

-- | The callable values of one exposed module, with their types.
publicValuesOf :: CompilerExportSession -> String -> IO [PublicValue]
publicValuesOf session routeModule' = do
    exports <- publicExportsOf session routeModule'
    pure
        [ PublicValue
            { routeModule = exportRoute export
            , exportedName = exportName export
            , definingIdentity = exportDefiningModule export
            , exportedType = signature
            }
        | export <- exports
        , ExportedValue signature <- [exportKind export]
        ]

{- | The callable values of every requested exposed module, through the one
session (FUN-266-SURFACE).
-}
publicValuesOfModules :: CompilerExportSession -> [String] -> IO [PublicValue]
publicValuesOfModules session = fmap concat . traverse (publicValuesOf session)

-- ---------------------------------------------------------------------------
-- Rendering

{- | A rendered type on one line, unqualified: the spelling the downstream
#262 type rules read.

Flattening is not cosmetic. The rules split a signature on its top-level
arrows and read the head word of the result, so an internal line break would
change how a type classifies — which is the physical-formatting sensitivity
this ticket removes, and it must not be reintroduced here.
-}
renderType :: SDoc -> Text
renderType = T.unwords . T.words . T.pack . showSDocOneLine defaultSDocContext
