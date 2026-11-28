# Stage C on the chain: rotations through `advance_predicate` (generated; do not edit)

| case | what it tests | keripy 1.3.5 | advance predicate | direction |
|---|---|---|---|---|
| R01 | 2-of-2 rotation signed by both revealed keys | accepted | Valid | agree |
| R07 | prior next threshold 1 of 2: one revealed key rotates | accepted | Valid | agree |
| R08a | prior next threshold [1/2,1/2]: both revealed keys sign | accepted | Valid | agree |
| R10c | rotation weighted threshold, both keys sign, weights [1/2,1/2] | accepted | Valid | agree |
| R17 | rotation to an empty next commitment (abandonment), next threshold 0 | accepted | Eq8CreatedIllFormed | WE-REFUSE |
| R18 | prior next threshold 1 of 2; revealed keys are one committed key and one new key, both sign | accepted | Valid | agree |
| W01 | cut one, add one, toad 2, receipts from both of the derived witnesses | accepted | Valid | agree |
| W09 | no witness change, toad kept, receipts from both | accepted | Valid | agree |
