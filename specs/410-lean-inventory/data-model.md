# Inventory record contract

A reviewer can compare machine records without inferring policy from their names. These are machine-facing schemas, not a classified register.

| Record | Fields and constraints |
|---|---|
| DATA-410-INVENTORY | `subject`: exact SHA; `libraries`: both existing library names; `declarations`: complete records; `sources`: complete required source records; `traces`: retained structured artifacts; `external_sources`: exact revisions and content availability. |
| DATA-410-DECL | `name`: full compiled identity; `module`: original compiled module; `kind`: Lean constant kind; `proposition`: whether the declaration type inhabits Prop; `axioms`: complete transitive axiom names; `source`: exact repository source path. Unique name, exact set equality, generated/private identities retained. |
| DATA-410-SOURCE | `path`, `sha256`, `git_blob`: exact frozen-tree identity. Source records preserve every included original path and its bytes by immutable Git identity. |
| DATA-410-TRACE | `source`: required JSON/JSONL evidence path; `data`: complete original parsed payload; `execution`: `retained-historical` for retained outputs or `source-fixture` for scenario inputs. Human overview derives case identities/counts from payloads, separately for each corpus. |
| DATA-410-EXTERNAL | Immutable source revision/URL, file identity, available/unavailable content, byte hash when available, provenance of historical hash claims. An unavailable source does not acquire invented content or policy status. |

Missing, duplicate, empty, truncated, orphaned and substituted identities fail. No policy-disposition field is introduced.
