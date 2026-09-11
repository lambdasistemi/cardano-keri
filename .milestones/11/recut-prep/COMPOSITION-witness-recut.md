# CANDIDATE-COMPOSITION MANIFEST — witness recut (seeds, duties, hashes)

Authority: A-026 §1. Every seed is read-only evidence; every resulting
byte is owned and re-proved by the fresh campaign.

## Base and reland

| ingredient | source | duty |
|---|---|---|
| base | main `ad0c99bbf13d52fb9f359035051120100a996e8d` (tree `c2828872…`, byte-identical to pre-PR-302 main) | verify by read-back at branch time |
| S0 reland | accepted head `137edef07917d493914e73e69b72839b2c833b50` | reland FIRST; record exact tree/content equivalence evidence; design not reopened |

## Witness + repair content (seeds from the terminal campaign, read-only)

| ingredient | seed | duty |
|---|---|---|
| witness slice content | `d5e542bc…` (tree `14d63a80…`); audited-PASS evidence 16bbb311 | replay/cherry-pick as seed only; re-prove everything on the new candidate |
| stamp/mandate baseline | `8c546e16…` | Tasks-trailer discipline per gate-script |
| packaging repair | `6a8d6ef6…` two files (`M12TxBSpec.hs` env-bound reads w/ throw-on-unset; `flake.nix` bindings + glibcLocales/C.UTF-8) | reapply; CONVERT `../specs`/`../scripts` literals to declared flake inputs per CI-S2W-E — no untested survivor |
| manifest digest | F1's cause | the composition commit RE-DERIVES `integration.measured_source_set_sha256` from ITS OWN committed tree (auditor's computed value at the old head was `8241501a…` — a hypothesis; recompute) |
| docs corrections | `228a0cdd…` three files | reapply; PLUS audit-2 A1 duties: a v1.1→v1.2-style paragraph for the new gate naming its authorizing answer + cause-set delta; the falsification-evidence sentence must describe the REAL evidence shapes; `modules-model.md` changed-component list includes `offchain/flake.nix` |
| mandate bundle hash | F3's cause | define an EXECUTABLE, versioned recipe (script in the mandate dir); derive; gate verifies from the committed tree |

## Hardening (new in this candidate)

- Gate implements the six mandatory controls (see brief) — receipts print
  and verify candidate head+tree; dirty-tree refusal; manifest and
  bundle re-derivation checks.
- Known instrument residuals to close in the NEW gate (not the frozen
  evidence gates): stale usage-string class; campaign-bar-as-parameter
  for the token wrapper; per-leg fail-before-command wrapper support.

## Re-derivations (old numbers are hypotheses)

REFERENCE determination; aggregate vs `maxRefScriptSizePerTx`; the three
signed-creation envelopes vs `maxTxSize`; INLINE live measurement; fee
tiers at 25,599/25,600/25,601; the S0 seven-member size table on the new
ancestry. Every figure re-measured under the gate's own legs.
