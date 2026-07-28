# Tasks: preprod witness pool (#157)

## Slice 1 — public witness pool vertical

- [ ] **T157-S1** Build a dependency-locked keripy 1.3.5 witness image.
- [ ] **T157-S2** Define three persistent, supervised, healthy Traefik-routed
  witness services and endpoint configurations.
- [ ] **T157-S3** Deploy the pool, capture three distinct AIDs, and publish
  their public controller OOBIs in `deploy/preprod/witnesses.json`.
- [ ] **T157-S4** Prove service restart preserves all three AIDs and public
  reachability.
- [ ] **T157-S5** Add the machine-checkable clean-client acceptance and CI job;
  prove witness count 3, receipts 3, threshold 2.
- [ ] **T157-S6** Ship the navigable “The preprod witness pool” docs page with
  the captured transcript and explicit trust/availability boundaries.
- [ ] **T157-S7** Run the exact-tree gate, refresh PR metadata, obtain green CI,
  restore the standing gate, and park PR #167 for operator merge.

