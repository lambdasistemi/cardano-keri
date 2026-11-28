{- |
Module      : Cardano.KERI.AID.E2E.Rejection
Description : what a rejected transaction was rejected for

The node's rejection of a submitted transaction arrives as the rendering of a
list of ledger failures. A test that says a transaction was refused for one
reason reads the whole set, not a fragment of it.
-}
module Cardano.KERI.AID.E2E.Rejection (
    ExpiredInterval (..),
    consumedInputAlone,
    expiredAmong,
    expiredInterval,
    renderExpiry,
    renderedElements,
) where

import Data.Char (isDigit)
import Data.List (isPrefixOf, stripPrefix, tails)
import Data.Maybe (listToMaybe)

{- | A rejection of the ledger for a validity interval that had already ended when the transaction was
checked: the lower and upper slot of the interval and the slot it was checked at.
-}
data ExpiredInterval = ExpiredInterval
    { eiLower :: !Integer
    , eiUpper :: !Integer
    , eiCheckedAt :: !Integer
    }
    deriving stock (Show, Eq)

{- | Whether a rejection is exactly the ledger's rejection of an expired validity interval (#382):
the one failure @OutsideValidityIntervalUTxO@, with an interval that ends at or before the slot the
transaction was checked at. A transaction checked before its interval starts, or rejected for
anything else besides, is not an expiry.
-}
expiredInterval :: String -> Maybe ExpiredInterval
expiredInterval rendered = do
    (expiry, afterNumber) <- expiryWithRest ("ConwayApplyTxError (ConwayUtxowFailure (UtxoFailure " <> outside) rendered
    -- the failure list holds nothing else: the failure closes and the list ends
    _ <- stripPrefix ")))" afterNumber >>= stripPrefix " :| [])"
    pure expiry

{- | The same expiry, found among other failures of one rejection: the ledger reports every failure of a
transaction, so a transaction built for a consumed input and checked after its interval carries both. It
is still the interval that ended, and a transaction planned again over a fresh interval shows what remains.
-}
expiredAmong :: String -> Maybe ExpiredInterval
expiredAmong rendered = fst <$> expiryWithRest ("UtxoFailure " <> outside) rendered

outside :: String
outside = "(OutsideValidityIntervalUTxO (ValidityInterval {invalidBefore = SJust (SlotNo "

-- | The first expired interval after a marker, and what follows its slot numbers.
expiryWithRest :: String -> String -> Maybe (ExpiredInterval, String)
expiryWithRest marker rendered = do
    rest <- listToMaybe [after | text <- tails rendered, Just after <- [stripPrefix marker text]]
    (lower, afterLower) <- number rest
    afterUpperMarker <- stripPrefix "), invalidHereafter = SJust (SlotNo " afterLower
    (upper, afterUpper) <- number afterUpperMarker
    afterChecked <- stripPrefix ")}) (SlotNo " afterUpper
    (checked, afterNumber) <- number afterChecked
    if checked >= upper then Just (ExpiredInterval lower upper checked, afterNumber) else Nothing
  where
    number text = case span isDigit text of
        ([], _) -> Nothing
        (digits, after) -> Just (read digits, after)

-- | What an expiry says in the output: a ledger expiry of the interval, not a rejection about the domain.
renderExpiry :: ExpiredInterval -> String
renderExpiry (ExpiredInterval lower upper checked) =
    "LEDGER EXPIRY OF THE VALIDITY INTERVAL, not a domain rejection: interval ["
        <> show lower
        <> ","
        <> show upper
        <> ") checked at slot "
        <> show checked
        <> ", "
        <> show (checked - upper)
        <> " slots after its end, "
        <> show (checked - lower)
        <> " slots after it opened"

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
