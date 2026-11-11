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

import Data.List (isPrefixOf, stripPrefix, tails)
import Data.Maybe (listToMaybe)

{- | Whether a rejection is exactly the rejection of a transaction that spends an
input that no longer exists, given the input as it renders and the index of its
spend in the transaction. Four failures follow from the missing input and no
others: the input is not there, the value no longer balances, the input cannot
be translated for the scripts, and the redeemer of its spend has nothing to
redeem. Another input, a further failure or a missing one is not that rejection.
-}
consumedInputAlone :: String -> Int -> String -> Bool
consumedInputAlone input index rendered =
    case listToMaybe [rest | text <- tails rendered, Just rest <- [stripPrefix marker text]] of
        Just rest -> case renderedElements rest of
            [imbalance, translation, redeemer] ->
                imbalanceHead `isPrefixOf` imbalance
                    && translatesMissing translation
                    && redeemer == extraRedeemer
            _ -> False
        Nothing -> False
  where
    marker =
        "ConwayApplyTxError (ConwayUtxowFailure (UtxoFailure (BadInputsUTxO (NonEmptySet (fromList ["
            <> input
            <> "])))) :| ["
    imbalanceHead = "ConwayUtxowFailure (UtxoFailure (ValueNotConservedUTxO "
    translationHead =
        "ConwayUtxowFailure (UtxoFailure (UtxosFailure (CollectErrors (BadTranslation (BabbageContextError (AlonzoContextError (TranslationLogicMissingInput ("
            <> input
    translatesMissing translation =
        case stripPrefix translationHead translation of
            Just after ->
                let (closers, tailing) = span (== ')') after
                 in not (null closers)
                        && " :| []" `isPrefixOf` tailing
                        && all (== ')') (drop 6 tailing)
            Nothing -> False
    extraRedeemer =
        "ConwayUtxowFailure (ExtraRedeemers (ConwaySpending (AsIx {unAsIx = "
            <> show index
            <> "}) :| []))"

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
