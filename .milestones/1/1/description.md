Outcome: identity core — witnessed checkpoints on Cardano, delivered as usable packaged executables.

Observable test (the thing that decides this milestone), in two parts. FIRST: a stranger installs packaged `ckeri` from a PUBLISHED release and, with standard `kli` and the published docs alone, completes the full preprod identity lifecycle — register including 2-of-5 multisig, witnessed rotate, freeze/respond/claim/thaw, close with escrow reclaim — every step with a reproducible transcript and settled txids. SECOND (operator ruling 2026-08-06, and the milestone does not close without it): a downstream Cardano transaction CONSUMES an identity checkpoint to gate an action — a validator that resolves the checkpoint as a reference input, revalidates policy, quantity-one asset, script version, AID, datum and role address, and enforces its own authorization rule against the identity's current key state. Maintaining an identity on Cardano is not the same as using one, and only the second part demonstrates the offer this milestone makes.

Artifact: `ckeri`. Epic forks retire into the milestone release line, which graduates into the product `ckeri` line at close.

Boundaries, so they are not misread as omissions: production rollout, operations and announcement are outside this milestone. Publication is NOT excluded — the outcome test is unsatisfiable without a published release. Issue #220 is out of scope and is the first post-milestone item.

Live state — diagrams, per-issue status, blockers, priority; refreshed daily and before any pause: https://github.com/lambdasistemi/cardano-keri/wiki/M1-State
