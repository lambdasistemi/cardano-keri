# R01 and R17: an ordinary rotation and the abandonment rotation

Two signed rotations, each with its own predecessor inception, generated and read back with keripy 1.3.5
(`offchain/test/keri-fixtures/uv.lock`) from the corpus of #589 (`test/589-keripy-admission-corpus`, commit
`d67af49f467e2811818327af27f465411299e8dd`). Test keys derived from the fixed test seed of `gen_fixtures.py`.

| | R01 | R17 |
|---|---|---|
| lineage | 2-key, 2-of-2 self-addressing inception, then one rotation at sequence 1 | the same |
| rotation | 2 revealed keys, `kt` 2, next commitment of 2 digests, `nt` 2 | 2 revealed keys, `kt` 2, **no next keys** (`n` = [], `nt` 0) |
| attachments | indexed controller signatures over the exact rotation bytes; no witnesses, **empty receipt list** | the same |

Per fixture: `predecessor-icp.json` and `rotation.json` (the exact signed bytes), `*.cesr` (the same bytes with their
signatures as a stream), `signatures.json`, `witness-receipts.json`, `keripy-first-seen.json` (keripy's readback),
`model-input.json` (decoded inputs of the Lean `rotationValid`), `aiken-advance-input.ak` (the predicate's input) and
`predicate-results.json`. `scripts/january-591-vectors.mjs` turns them into `../january-591-cases.json`, the Plutus Data
of the advance journeys, and checks the signatures, the digests and the offsets independently.

Limits: unwitnessed lineages; the model rows run decoded inputs; the rotation's `p` is not checked on chain against the
immediately preceding event (the signed bytes carry it, nothing links it to the KEL).
