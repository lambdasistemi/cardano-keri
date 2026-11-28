# The deployed generation's blueprint

`plutus.json` is the Aiken blueprint of the sources at commit `8fdfcf6c` (the
last commit before the two-policy advance), built with `nix build .#plutus-blueprint`
from `offchain/` at that commit, aiken v1.1.23. Its checkpoint validator reads the
advance observer's withdrawal; it carries neither `event_attestation` nor
`advance_attestation`.

The observer-era derivations (`deriveV1Scripts`, `deriveRegistryScripts`, the
registry deployment), the builders, the journeys and the identities page are of
that generation and run against this file (`KERI_CHECKPOINT_BLUEPRINT`). The
current source build (`KERI_ATTESTED_BLUEPRINT`, the `ckeri` default) is of the
attested generation, which the observer-era derivations refuse.

The file's SHA-256 is pinned in `AdvanceAttestationBoundarySpec`; it changes only by
a decision to move the deployed generation.
