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

The gate-review repair makes these records strict: unknown top-level or mapping-row keys are refused, including policy-disposition additions. `scope` fixes inventory-only=true, classification=held and issue_410=open; `annotations` carries only the three supplied desk annotations; `open_decisions` preserves the five still-open names. Exact serialized values are frozen in the gate contract. Historical payloads remain original source data, not new dispositions.

External records use `id`, `revision`, `url`, `availability` and `historical_metadata`, derived from the frozen plan and prior manifests. The seven references cover the KERI specification, KERIpy comparison, prior gist, whitepaper, expired Internet Draft, and both updated gist files. Their external content is not retained in this frozen repository tree: state that availability literally; hashes inside historical metadata remain attributed historical claims, not fresh byte verification. This slice can preserve those exact references without inventing unavailable contents.
