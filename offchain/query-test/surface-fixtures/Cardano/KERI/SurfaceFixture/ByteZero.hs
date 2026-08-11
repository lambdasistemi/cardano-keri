module Cardano.KERI.SurfaceFixture.ByteZero (
    byteZeroExport,
    commentTrapExport,
) where

{- Ticket 266, task T266-S1-04. The module declaration above begins at BYTE ZERO, with no
leading comment, because the #262 submission-5 audit found that a reader
searching for a preceding newline silently emptied every such module — and two
really Cabal-exposed modules are spelled this way. That is why the Haddock
header this repository normally puts first is here instead: moving it above
the declaration would destroy the property this fixture exists to hold.

The rest of this module is a minefield for a source reader and nothing at all
to a compiler.

A nested block comment with a fake header inside it:

{- module Cardano.KERI.SurfaceFixture.NotAModule (notAnExport) where

   notAnExport :: LocalQueryScope cf op -> ChainQuery () -> IO ()
-}

and the word module in ordinary prose, at the start of a line:
module Cardano.KERI.SurfaceFixture.AlsoNotAModule (alsoNotAnExport) where

Neither of those is an export list, neither of those names is exported, and a
control requires the derived surface to contain exactly the two real exports
below.
-}

-- | An ordinary value in a module whose declaration starts at byte zero.
byteZeroExport :: Int
byteZeroExport = 0

{- | A value whose own body mentions @module@ inside a string literal, the
last place the #262 reader could be fooled into finding an export list.
-}
commentTrapExport :: String
commentTrapExport = "module Cardano.KERI.SurfaceFixture.StringLiteral (stringExport) where"
