# Data model — #240 local-only write tier

Artifact ceiling: 6,000 bytes and 150 lines.

Module placement is in `modules-model.md`; callable signatures are in
`functions-model.md`.

## DAT-240-LOCAL-SETTINGS — write local-store configuration

Fields:

- local follower store path, supplied through opt-env-conf;
- command-owned manifest identities required by the selected snapshot program.

Relationships and validation:

- embedded by each transaction-producing command setting;
- contains no provider URL, token, endpoint, or provider selector;
- a command need not supply checkpoint/board identity for an operation it does
  not request;
- missing or malformed identity for a requested operation fails before that
  store read and never selects a fallback.

## DAT-240-LOCAL-SCOPE — bracketed local query scope

Fields:

- one store transaction runner;
- optional validated checkpoint policy/address identity;
- optional validated endpoint-board policy/address identity.

The scope lives only inside the store bracket. It cannot escape as a detached
handle. The interpreter reports `SourceLocal`/`AtomicLocal`; all operations in
one program plus its watermark share the runner invocation.

## DAT-240-WRITE-RUNTIME — local write orchestration capability

Relationships:

- owns **DAT-240-LOCAL-SCOPE** and the separate temporal probes from
  **DAT-240-SETTLEMENT-PROBES**;
- executes provider-neutral programs before a builder starts;
- hands builders only existing resolved ledger/domain values;
- contains no concrete provider and exposes no generic callback that can query
  during a build.

## DAT-240-REFERENCE-RESOLUTION — derived reference result

Uses #257's existing `ChainReference` and `ChainAssetUtxo` result shapes.
For each canonical requested script hash:

- exactly one currently live follower-held output carries a decodable reference
  script whose computed hash equals the request;
- the complete output identity, address, value, datum, assets, and script bytes
  come from the same stored row;
- results preserve request correspondence deterministically;
- zero requests produce the existing legal empty result;
- absent, duplicate, malformed, or mismatched rows produce a named local
  `ChainQueryError`, never a partial list.

This establishes **DATA-INV-240-01** without a schema or provider read.

## DAT-240-BUILD-SNAPSHOT — one phase's resolved inputs

Uses #257's `QuerySnapshot value` envelope. `value` is the command-specific
combination of existing current-checkpoint, board, reference-output, and payer
values needed by exactly one transaction build.

Invariants:

- every value and watermark is acquired by one local program/run;
- source is local and consistency is atomic local;
- no ambient read fills an omitted field;
- a later transaction or store change requires a new snapshot;
- node protocol/evaluation/submission effects do not retroactively alter the
  resolved snapshot.

## DAT-240-SETTLEMENT-PROBES — follower temporal capabilities

Variants:

- asset observation: exact policy, asset name, tx id, address, and quantity;
- reference observation: exact script hash and tx id;
- transaction observation: exact tx id with at least one live tracked output.

Each probe runs a fresh follower-store observation per poll. Polls are
sequential temporal evidence, not **DAT-240-BUILD-SNAPSHOT** values. Exceptions
retry under the existing timeout policy; timeout identifies the unmatched
target.

## DAT-240-PARITY-RECEIPT — cross-revision proof identity

Fields retained outside Git:

- frozen base and candidate SHAs;
- command/transaction-shape identifier;
- deterministic fixture and resolved-input blob hashes;
- normalized legacy/local snapshot hashes;
- canonical transaction-body hashes and transaction IDs;
- command, exit, duration, and raw evidence hash/path.

A receipt is invalid when both sides use the candidate implementation, when a
fixture differs across sides, or when only semantic field subsets are compared.

## State and rejection invariants

- **DATA-INV-240-02:** write settings cannot represent a provider credential.
- **DATA-INV-240-03:** a local query scope cannot outlive its store bracket.
- **DATA-INV-240-04:** reference resolution is exact-cardinality and
  all-or-nothing.
- **DATA-INV-240-05:** settlement values cannot inhabit `ChainQueryF`.
- Store/provider failure never silently yields empty success or fallback.
