# Inventory check interface

A reviewer can run the same inventory reconciliation against the checked-in record or an explicitly supplied damaged copy.

| Interface | Arguments | Result and constraints |
|---|---|---|
| FUN-410-CHECK | `python3 scripts/check-lean-invariants-inventory.py --check --inventory PATH` | Integer exit status; zero only for complete valid inventory bound to the frozen source and fresh compiled extent. Nonzero includes an `INVENTORY-REJECT` diagnostic identifying the failed inventory layer. |
| FUN-410-WRITE | `python3 scripts/check-lean-invariants-inventory.py --write --inventory PATH` | Writes reproducible inventory records inside the owned path; reads source inputs and compiled libraries without changing them. |

Default inventory path may be `docs/design/lean-invariants-inventory/inventory.json`. Additional internal functions are implementation decisions inside the owned modules. Script errors and unavailable build prerequisites are distinct from inventory rejection. The gate never imports or depends on the checker to obtain its reference extent.
