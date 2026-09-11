# Modules

MOD-279-INVENTORY: scripts/preprod-checkpoint-inventory.py owns public preprod acquisition, replay, role-aware byte decoding, denominator reconciliation, and report output. Depends on frozen wire schemas as protocol reference; no dependency on wallet/signing/backend-write code. Python standard library only; no new package manifests.
MOD-279-TEST: scripts/test-preprod-checkpoint-inventory.py owns permanent observable tests of MOD-279-INVENTORY, including transport errors/pagination and byte-level positive controls. Fixtures may live in scripts/fixtures/preprod-checkpoint-inventory/ with explicit provenance.
MOD-279-DOC: docs/operations/preprod-checkpoint-inventory.md owns reproducible usage, scope, limits, and cutover precondition. Dated public evidence may live in deploy/preprod/inventory-279/.
