{- |
Module      : Cardano.KERI.AID.E2E.Rejection
Description : what a rejected transaction was rejected for

The node's rejection of a submitted transaction arrives as the rendering of a
list of ledger failures. A test that says a transaction was refused for one
reason reads the whole set, not a fragment of it.
-}
module Cardano.KERI.AID.E2E.Rejection (
    consumedInputAlone,
    renderedElements,
) where

import Data.List (stripPrefix, tails)
import Data.Maybe (listToMaybe)

{- | Whether a rejection holds exactly two failures: the one input, given as it
renders, is no longer there, and the value no longer balances, which follows from
the missing input. Any other failure, another input, or a third element is not
that rejection.
-}
consumedInputAlone :: String -> String -> Bool
consumedInputAlone input rendered =
    case listToMaybe [rest | text <- tails rendered, Just rest <- [stripPrefix marker text]] of
        Just rest -> case renderedElements rest of
            [imbalance] -> imbalanceHead `isPrefixOfString` imbalance
            _ -> False
        Nothing -> False
  where
    marker =
        "ConwayApplyTxError (ConwayUtxowFailure (UtxoFailure (BadInputsUTxO (NonEmptySet (fromList ["
            <> input
            <> "])))) :| ["
    imbalanceHead = "ConwayUtxowFailure (UtxoFailure (ValueNotConservedUTxO "
    isPrefixOfString prefix text = stripPrefix prefix text /= Nothing

{- | The elements of a rendered list, given the text after its opening bracket:
split at the commas outside any nesting, up to the closing bracket.
-}
renderedElements :: String -> [String]
renderedElements = go (0 :: Int) ""
  where
    go _ accumulated [] = [reverse accumulated]
    go depth accumulated (character : rest)
        | character `elem` opening = go (depth + 1) (character : accumulated) rest
        | character `elem` closing = go (depth - 1) (character : accumulated) rest
        | character == ']' && depth == 0 = [reverse accumulated]
        | character == ']' = go (depth - 1) (character : accumulated) rest
        | character == ',' && depth == 0 =
            reverse accumulated : go 0 "" (dropWhile (== ' ') rest)
        | otherwise = go depth (character : accumulated) rest
    opening, closing :: String
    opening = "([{"
    closing = ")}"
