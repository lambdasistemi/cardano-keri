# 433 — the project's words, defined at first mention; "the M1 return" retired as a name

Issue: https://github.com/lambdasistemi/cardano-keri/issues/433
Also closes: https://github.com/lambdasistemi/cardano-keri/issues/384

## Mandate

Every reader-facing page under `docs/` (site pages, not the vetting archive)
defines each project word at its first mention on the page, in the wording a
decision record under `docs/design/` fixes. "The M1 return" and "the return"
are replaced by "the accepted design" in reader-facing prose, headings and
admonition titles, with one explanatory sentence on the home page and one in
the roadmap. The simulator story glossary and the speech companions of edited
pages are aligned. The two retired state nouns named by #384 are replaced.

## Acceptance

- `mkdocs build --strict` green; lychee with fragments green.
- The presentation gate reports no new violations against the baseline
  recorded below.
- `grep -rn "M1 return" docs --include=*.md` returns only the two
  explanatory sentences and the vetting archive.
- Each listed word shows a definition clause on its first occurrence per page.
- The decision record is a page under `docs/design/` with one row per word.
- `docs/architecture/value-auth.md` names no `Closed` checkpoint state;
  `docs/roadmap.md` names no tombstone.

## Baseline (origin/main 8e46b45, 2026-10-02)

- `mkdocs build --strict`: exit 0.
- Presentation gate (`check_presentation.py --front docs/index.md docs`):
  165 violations — speech-missing 75, index-labels 66,
  structural-page-without-diagram 13, speech-stale 5,
  speech-headings-mismatch 5, front-page-without-story-heading 1.
