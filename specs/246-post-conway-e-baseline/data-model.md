# #246 data model

Field-level contract for the records this ticket emits. Shapes only; no
encoding, storage, or implementation is prescribed here.

## D-01 `evaluation_outcome`

Exactly one of `ESTABLISHED`, `REFUTED`, `COULD-NOT-EVALUATE`, on every record
that asserts anything. `COULD-NOT-EVALUATE` additionally carries the name of
the layer that failed. It is RED. It is never elided, aggregated away, or
rendered as a pass, a skip, or "no counterexample found".

`COULD-NOT-EVALUATE` has two named causes that must not be collapsed:
the assertion ran and could not settle, or the **measurement itself could not
be established** — `MEASUREMENT-FAILED`. An inventory that is absent,
unreadable, or unexpectedly empty is the second, and is never reported as a
zero: a genuine zero and a failed measurement must not produce the same green.

## D-02 reference resolution record

Per reference the tracked bridge source makes into a pinned upstream package:

| field | meaning | validation |
|---|---|---|
| `reference` | the exact qualified name as the source states it | non-empty |
| `source_path` | tracked file the reference is made from | must be a tracked bridge source path |
| `target_package` | which pinned upstream package it must resolve against | one of the three declared upstream packages |
| `resolved` | whether it exists at that pin | boolean |
| `evaluation_outcome` | D-01 | unresolved implies not `ESTABLISHED` |

## D-03 control record

| field | meaning | validation |
|---|---|---|
| `control_id` | stable identifier | unique within a run |
| `kind` | `positive-resolution` or `seeded-retired-reference` | exactly these two exist in Slice A |
| `expected_effect` | what the control must cause | stated before the run, not derived from it |
| `observed_effect` | what it did cause | mechanically captured |
| `evaluation_outcome` | D-01 | `observed_effect` ≠ `expected_effect` implies RED |

## D-04 variant availability record

| field | meaning | validation |
|---|---|---|
| `variant` | the named `BuiltinSemanticsVariant` under question | names E explicitly |
| `expressible_at_pin` | whether the pinned upstream can express it | boolean |
| `selection_mechanism` | how a variant would be selected, named rather than assumed | non-empty; a version-derived selection must say so |
| `evaluation_outcome` | D-01 | unanswered is `COULD-NOT-EVALUATE`, never a default |

## D-05 baseline identity (Slice B; declared here so Slice A cannot contradict it)

`COMMIT + TOOLCHAIN + VARIANT`, expanded to: source commit; blueprint SHA-256;
Aiken version; the three upstream pin identities; lock identity; `PlutusV3`;
protocol era; `BuiltinSemanticsVariant`. Per title: exact title, declared
parameter count, `program_sha256`. Cardinality: 23 titles over 8 distinct
programs.

Every value is computed from the artifact it describes. A literal that happens
to equal the computed value does not satisfy this record.

## D-06 downstream claim record (Slice C; the schema #247/#248 fill)

Extends D-01 with a required falsifiability pair for each individual P0 claim:
a `REFUTED` record against a deliberately broken variant, recorded **before**
the `ESTABLISHED` record, in the same slice and under the same frozen identity.
A claim carrying only an `ESTABLISHED` record is incomplete, not passing.

For the Advance family the schema requires two records under the E identity,
distinctly labelled, each stating its own purpose in the record: the
compatibility/refreeze identity run, and the P3/P6 composed-claim run. A reader
must not have to infer why the claim was run twice.

## D-07 bundle inventory entry (Slice C)

The bundle's contents are a declared list, not a tree walk. Tracked-file
enumeration may contribute entries; it may not be the definition. Untracked
means uncovered by default.

| field | meaning | validation |
|---|---|---|
| `path` | artifact's path inside the assembled bundle | unique within the inventory |
| `origin` | where the artifact comes from — tracked source, generated output, or an untracked deliverable declared by hand | an untracked origin is legal and must be declarable |
| `mode` | required file mode, executable bit included | asserted on the assembled bundle, not only on the source |
| `required` | whether absence is RED | absence of a required entry is RED; there is no warning level |
| `declared` | how many inventory entries were examined | established before any missing count is reported; absent, unreadable or unexpectedly empty ⇒ `MEASUREMENT-FAILED` |
| `missing` | how many required entries were absent from the assembly | read only against `declared`; never published alone |

## D-09 measurement provenance (every record that carries a number)

| field | meaning | validation |
|---|---|---|
| `instrument` | what produced the quantity | named; a quantity with no instrument is not a measurement |
| `window` | the interval the quantity covers | named; for a rate or percentage this includes its reset time |

A quantity whose window cannot be stated is `COULD-NOT-EVALUATE`, never a
smaller number reported as if it were complete.

## D-08 identity consistency (applies to every record, receipts included)

A record does not merely carry the triple; the triple has to agree with
itself.

| field | meaning | validation |
|---|---|---|
| `commit` | source commit the record is about | named; non-empty |
| `toolchain` | the Aiken version that produced the artifact, and the pinned bridge upstreams | named; the Aiken value must be the one the repository validates its onchain sources with, stated rather than assumed |
| `variant` | `BuiltinSemanticsVariant` | named explicitly; absence is `COULD-NOT-EVALUATE`, never a default |
| `artifact` | blueprint and program identity the record describes | must be the artifact that `commit` and `toolchain` together produce |

A record whose elements are each true of a *different* configuration is RED,
irrespective of every command in it exiting 0. The enforcing check's
falsification case is the retained pre-slice receipt, not an invented input.

## State invariants

- any unresolved reference ⇒ the run is RED;
- any `COULD-NOT-EVALUATE` ⇒ the run is RED;
- a resolved count of zero ⇒ `COULD-NOT-EVALUATE`, never a clean scan;
- any control whose observed effect differs from its expected effect ⇒ RED;
- a record naming variant C, or naming no variant, is not baseline evidence;
- a declared inventory entry absent from the assembled bundle ⇒ RED;
- an assembled artifact whose mode differs from its declared mode ⇒ RED.
