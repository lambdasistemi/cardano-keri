# Model pin of the conviction tests

Draft #582 at 95d97298200630f4afb376d0e06a77245664966e, with #592 at b4f62b653d70653ba022a82fb935ced131b853db on top (the model's corrected rotation rule: #595 a rotation's own next threshold, #596 a signing threshold of zero is never satisfied, #598 witness changes; operator note 2026-11-27). Earlier pin: #582 c274b341 over #577 e1a4cfd4 (superseded; its signed receipts stay as history).

| file | what it is | sha256 |
|---|---|---|
| checkpoint-rival-validity-vectors.json | `lean/checkpoint-rival-validity-vectors.json` at b4f62b65; byte-identical to the c274b341 file; a fresh run of `CheckpointRivalValidityVectors.lean` at b4f62b65 reproduces it (`jq -S` equal) | 2f7e5f504119bd8ba7fa2afaf67bff6e34d698ee84c49aa7a374b376e4d150aa |
| rotation-admission.json | the output of `lean --run RotationAdmissionChecks.lean` at b4f62b65 (Lean 4.27.0; compiled with Duplicity, CheckpointConviction, DuplicityExamples, CheckpointEventHistory only; its `#guard`s hold) | see below |

Regeneration: extract `lean/` at b4f62b65, compile `CardanoKeri/{Duplicity,CheckpointConviction,DuplicityExamples}.lean` and `RotationAdmissionChecks.lean` with `lean -o` into a directory on `LEAN_PATH`, then `lean --run RotationAdmissionChecks.lean`.
397a542b4229ae6684bec0fcbfa418bff6269936f37de3160ca14bc184513d61
