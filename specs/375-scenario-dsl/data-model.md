# Data model — #375 scenario DSL

Artifact ceiling: 4,500 bytes and 115 lines.

## DAT-375-DOCUMENT — parsed DSL document

- `grammarVersion`: exact machine-readable version required by the document.
- `family`: `checkpoint` or `registry`.
- `scenario`: exactly one complete value in the corresponding existing JSON
  scenario shape.
- `sourceName`: diagnostic identity supplied by the caller.
- `locations`: source line ownership sufficient to locate every parsed field
  and structural error.

Unknown, duplicate, missing-required, wrongly typed, unsafe-integer, or
family-incompatible values invalidate the whole document. No partially parsed
scenario is returned.

## DAT-375-CHECKPOINT — checkpoint scenario value

Losslessly represents the existing story/title/goal/params/steps/atoms/forks
shape. A step preserves slot, actor narration, optional parameter/state/evidence
changes, action, and the complete expectation including verdict, flow, and
exhibits. A fork preserves identity, departure point, title, and ordered steps.

## DAT-375-REGISTRY — registry scenario value

Losslessly represents the existing id/slug/story/narrative/params/plugin/
actors/env/steps/forks/expectFinal shape. A step preserves time, actor labels,
action, expectation and flow, exhibits, and note. A fork preserves identity,
departure point, title, environment/final assertions when present, and ordered
steps.

## DAT-375-BRANCH — exported current branch

- Family and current page parameters.
- Initial evidence/world required to replay the origin.
- The ordered origin-to-cursor nodes selected by the user.
- Each node's time, evidence/world change, action, narration, result
  expectation, flow, exhibits, and family-specific final assertion required by
  the existing checker.

Only the selected current branch is exported. Sibling branches that are not on
the origin-to-cursor path are not silently presented as part of it.

## DAT-375-DIAGNOSTIC — closed refusal

- `sourceName`: file name or caller label.
- `line`: positive one-based line number.
- `column`: positive one-based column when available.
- `message`: concise violated grammar or validation rule.

A refusal contains no scenario. Page admission preserves the previously
playing tree until a later complete document succeeds.

## DAT-375-EXTENT — proof denominator

- Discovered checkpoint source count and replayed step count.
- Discovered registry source count and replayed step count.
- Total source count.

GREEN requires `(15, 104)`, `(15, 115)`, and total `30`; zero or truncated
counts are invalid rather than smaller successes.
