# Ordinary events against keripy 1.3.5

An offline corpus of ordinary, well-formed KERI events and thresholds. Each input goes to keripy 1.3.5 and to every
admission layer of this repository that models the same stage, and each pair of results is recorded in one matrix row.
No network transaction is made. All keys are test keys derived from a fixed seed.

## What is in the corpus

| kind | cases |
|---|---|
| inceptions | I01 (1-of-1, basic prefix), I02 (2-of-3, all sign), I03a (three weights of 1/2, two sign) |
| rotations | R01 (2-of-2), R07 (one of two revealed keys rotates), R08a (weighted prior next threshold), R10c (weighted signing threshold), R17 (rotation to an empty next commitment), R18 (one committed key and one new key), W01 (one witness cut, one added, receipts from both), W09 (witnesses unchanged, receipts from both) |
| interactions | X01 (signed by the current keys), X07 (after a rotation, signed by the rotated keys) |
| thresholds | T01 to T03, T06 to T10, T14, T18, T19, T26, T28, T30: every signer subset of each |

Every case is a positive control: keripy persists it. Only ordinary inputs are included.

## Premise

keripy admits an event when the event is in its key event log: a readback finds the exact SAID at the event's
sequence number and the exact stored bytes. An event that is not in the log is reported as it is (an escrow index,
an exception class, or unknown); nothing is inferred from a missing exception. Each rotation case runs against its
inception as predecessor; the interaction after a rotation runs against the log that holds both.

## Run

```
bash run.sh [output directory]      # corpus, every layer, the matrix (default ./evidence)
bash controls.sh [evidence]         # each mutation of the recorded evidence must make the matrix fail
```

Needs nix with flakes. keripy 1.3.5 comes from the pinned flake in the parent directory, Lean 4.27.0 from
`lean/flake.nix`, Aiken from the pin in `run.sh`.

Every reporting step reads its receipt strictly (`receipts.py`) and exits 1, writing nothing, when a result is missing,
unexpected or repeated, when a typed verdict is not one the predicate defines, when a test carries more than one verdict,
when a suite has no completion summary or one that disagrees with its results, when the model driver has no answer for a
translated row, or when a threshold result lacks one of its signer subsets. `matrix.py` takes the expected cases from the
corpus definitions, re-reads the Aiken transcripts, and also exits 1 when any step keripy reports as persisted (context
steps included) has no consistent log readback. A coverage exclusion is declared by the producer (a translated row marked
not comparable, or a threshold the codec cannot hold) and is never inferred from an absent line.

`controls.sh` runs 17 controls: the unmodified evidence passes every reporting path, and each mutation of a copy of the
evidence (a missing or extra fixture row, a missing model output, an unknown verdict, a second verdict, a missing
evaluation receipt, a missing completion summary, a missing signer subset, a contradicted context readback) is rejected with
its stated reason by the script that reads that receipt. Generated transcripts are normalised where they are produced
(no carriage returns, no trailing whitespace, the compiler notices of the copied project dropped: only the test section is kept), so the published tree passes `git diff --check`.

## Layers

| layer | what it is asked | file |
|---|---|---|
| keripy 1.3.5 | `Kevery.processEvent`, then the log readback | `keripy_admission.py` |
| model | `CardanoKeri.Duplicity.rotationValid` on the decoded inputs (a Boolean), `Threshold.satisfied` on every signer subset | `Admission.lean` |
| chain | the typed verdict of `registration_predicate` (inceptions), `advance_predicate` (rotations from an inception), `threshold.well_formed` and `threshold.evaluate` | `registration.py`, `advance.py`, `gen_aiken_thresholds.py` |

The Aiken tests are generated into a copy of the `onchain` project, never into the repository's own test path: each test
prints its verdict and ends with `False` on purpose, so the printed trace is the measurement.

## Result of the recorded run (`evidence/matrix/`)

13 event cases, 14 threshold cases, 38 rows.

| relation | rows |
|---|---|
| same verdict | 31 |
| DISAGREEMENT | 2 |
| no like surface | 5 |

| row | keripy | layer | ticket |
|---|---|---|---|
| I01, basic-prefix inception | persisted | registration predicate: `E2AidMismatch` | #590 |
| R17, rotation to an empty next commitment | persisted | advance predicate: `Eq8CreatedIllFormed` (the model admits it) | #591 |

The 5 rows with no like surface are the three inceptions and two interactions at the model: it has an admission predicate for
rotations only. The chain has no standalone interaction predicate.

## Coverage limits

- A finite set of ordinary inputs: each row exhibits its case, and a result says nothing about inputs outside it.
- Persisted events only. This corpus does not measure what each layer refuses.
- Model rows are decoded inputs. The `verified` flag of a signature is true when the signing key is the key the event
  names at that position; the translation does not check a signature, keripy's own run did.
- Chain rows run the predicate as a pure function on the evidence an honest prover supplies: no transaction, no deployed
  script, no ledger. The predicates for I01 and R17 are therefore predicate-level results.
- Chain rows for rotations use the inception as the predecessor; no multi-rotation lifecycle.
- No Haskell replay.
