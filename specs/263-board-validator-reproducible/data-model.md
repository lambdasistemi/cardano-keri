# Data model — #263 reproducible endpoint-board validator

Artifact ceiling: 5,000 bytes and 130 lines.

## New data

### DAT-263-ARTIFACT — compact board blueprint

A repository JSON value accepted by the existing blueprint decoder with
exactly one validator entry:

- title: `endpoint_board.endpoint_board.mint`;
- compiled program: exact lowercase hexadecimal encoding of 3,158 bytes;
- policy id: `54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c`;
- program SHA-256:
  `b9562988d5d1c8995a0e58a4ebbec21848352f8b1e9e363b46dc3b36bd8543fe`.

Blueprint schema fields required by the production decoder are preserved. No
unrelated historical validator is retained.

### DAT-263-PROVENANCE — recovery record

Metadata carried with **DAT-263-ARTIFACT** records:

- source commit `95b554fbdc9dee5b4437d3a8deeb882f114a0bf3`;
- compiler `aiken 1.1.21` from that commit's Nix build closure;
- complete historical blueprint byte length `581696`;
- complete historical blueprint SHA-256
  `896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c`.

The independent program digest and derived policy are permanent gate oracles;
metadata alone is not trusted as proof of its own payload.

### DAT-263-BOARD-BINDING — distinct artifact location

A runner-provided filesystem path names **DAT-263-ARTIFACT**. It is distinct
from `KERI_CHECKPOINT_BLUEPRINT`, required by every board identity/write
proof, and has no fallback value that points to the current source blueprint.

### DAT-263-NEGATIVE-CONTROL — perturbation receipt

Runtime-only evidence binds the immutable gate hash, candidate tree hash,
changed compiled-program nibble, expected RED result, restoration, and final
GREEN result. It is not shipped as production data.

## Reused data

### DAT-263-FROZEN-MANIFEST — existing board manifest

The existing manifest remains the production oracle for policy, source commit,
compiler, and full-blueprint digest. Its frozen policy and exact
`consumerErrors` comparison are unchanged.

### DAT-263-CURRENT-BLUEPRINT — current source build

The current Aiken blueprint remains independently built and consumed for
checkpoint validators. Its differing endpoint-board policy is not silently
accepted, rewritten, or used as **DAT-263-ARTIFACT**.

## State invariants

- **DATA-INV-263-01:** decoded compiled program length is exactly 3,158 bytes
  and its recomputed SHA-256 equals the frozen program digest.
- **DATA-INV-263-02:** production board derivation over the decoded program
  equals the frozen 28-byte policy; title selection is exact and unique.
- **DATA-INV-263-03:** board and checkpoint bindings cannot alias in the test
  runner configuration.
- **DATA-INV-263-04:** corrupt or absent artifact data fails closed and no
  provider/current-blueprint fallback is attempted.
- **DATA-INV-263-05:** provenance describes the byte-reproduced full blueprint
  and does not claim current-source equivalence.
