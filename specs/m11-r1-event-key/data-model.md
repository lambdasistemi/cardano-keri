# Data model — R1 event-derived MPF key

| ID | Abstraction | Fields / relationship | Validation and state invariant |
|---|---|---|---|
| R1-D01 | Event key preimage V1 | ordered domain, qualified `i`, integer `s`, tagged optional qualified `p`, qualified `d` | exact canonical Plutus constructor and field order; no caller-owned field |
| R1-D02 | Prior tag | absent for `icp`/`dip`; present with qualified `p` otherwise | absent and present use distinct constructors and agree with event type |
| R1-D03 | Verified event identity | canonical `i/s/p/d` selected from successful total decode | unknown/non-canonical qualification or sequence spelling has no key result |
| R1-D04 | `ParsedEvent.event_key` | 32-byte derived key paired with the verified SAID | created only from R1-D03; record insertion uses this pair |
| R1-D05 | `HistoricalProof` | MPF sibling `proof` only | no key, location, or prior-snapshot field survives |
| R1-D06 | Golden vector row | label, qualified inputs, integer sequence, prior variant, expected 32-byte key, accepted classification | expected bytes are independent data; accepted rows cover all supported codes and both prior variants |
| R1-D07 | Measured-source manifest | path, blob identity, mode, measurement required by the frozen gate | exactly equals the gate-owned source set and committed recipe output |
| R1-D08 | Flake-input declaration | every changed non-onchain path with its classification | complete over the candidate diff; no unclassified input |

## Record relationship

The map value remains the verified SAID in R1. Distinct `d` values produce
distinct keys even when `i`, `s`, and `p` match, so rival branches coexist.
R2 alone owns any later value-schema change.
