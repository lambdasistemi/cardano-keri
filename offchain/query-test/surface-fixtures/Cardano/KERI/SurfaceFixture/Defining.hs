{- |
Module      : Cardano.KERI.SurfaceFixture.Defining
Description : #266 T266-S1-05 — compiled export shapes the source reader used to mis-derive
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Permanent regression fixtures, COMPILED rather than written to a temporary
file and re-read. That difference is the whole point: the shipped enumeration
now asks GHC, so a control has to hand GHC a real module and require the
answer, instead of handing a string to a parser that no longer exists.

Every declaration here is a shape that made the #262 source reader
under-report at least once. They are deliberately spelled the awkward way —
a field type continued past its @::@ line, a capability nested inside an
ordinary container, an operator, a record whose selectors are public through
@(..)@. If GHC's answer ever stops containing one of them, the control that
names it fails.

This library is @visibility: private@ and is therefore NOT part of the public
surface the guard ranges over: a consumer of @cardano-keri@ cannot import it.
That exclusion is a stated rule (a public route needs a publicly visible
library component), not a name-based skip, and a control asserts it — which
matters here, because 'fixtureNestedCapability' is exactly the shape the
capability rule forbids on the real surface.
-}
module Cardano.KERI.SurfaceFixture.Defining (
    FixtureCarrier (..),
    fixtureNestedCapability,
    fixturePlainValue,
    (>|<),
) where

import Cardano.KERI.ChainQuery.Interpreter (ChainQueryInterpreter)
import Cardano.KERI.ChainQuery.Program (ChainQuery)
import Cardano.KERI.ChainQuery.Types (ChainQueryError)
import Cardano.KERI.Indexer.ChainQuery (LocalQueryScope)
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Database.KV.Transaction (Transaction)

{- | A record whose public field selectors are exported through @(..)@, with
the first field's type continued PAST its @::@ line.

The one-line and continued spellings denote the same selector, and the fourth
#262 audit proved the source reader saw only the one-line one. A compiler
answers both identically because physical layout is not part of what a module
exports.
-}
data FixtureCarrier cf op = FixtureCarrier
    { fixtureContinuedField ::
        LocalQueryScope cf op ->
        ChainQuery () ->
        IO (Either ChainQueryError ())
    , fixtureOneLineField :: LocalQueryScope cf op -> ChainQuery () -> IO (Either ChainQueryError ())
    }

{- | The fifth audit's second counterexample: a store-transaction-backed
interpreter handed back inside an ordinary result container.

It is the identical capability with one @fmap@ between the caller and it, so
a rule that reads only the result's head would miss it.
-}
fixtureNestedCapability ::
    LocalQueryScope cf op ->
    Maybe (ChainQueryInterpreter (Transaction IO cf Cols op))
fixtureNestedCapability _scope = Nothing

-- | An ordinary value, so the fixture module is not made entirely of oddities.
fixturePlainValue :: LocalQueryScope cf op -> Int
fixturePlainValue _scope = 0

{- | An exported operator. Its export item is parenthesised and its top-level
signature is too, which the source reader had to be taught (CORRECTION-011)
and a compiler simply knows.
-}
(>|<) :: ChainQuery a -> ChainQuery a -> ChainQuery a
left >|< _right = left
