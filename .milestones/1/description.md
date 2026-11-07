# M1 — Identity core: witnessed checkpoints on Cardano, with poison, bonds and a unique registry

This is the milestone description as published on GitHub milestone 1
(re-cut 2026-09-03 with plan v2). It replaces the 2026-08-17 record/cursor
description and the freeze/respond/claim/thaw outcome test that went with it —
that design is gone under D-031 (freeze removed), D-033 (pause is a rotation
that withdraws the bond) and D-039/D-040 (three registry states, one UTxO).

---

Identity core: witnessed checkpoints on Cardano, with poison, bonds and a
unique registry.

One milestone, two repositories: the registry is upstream work in
`cardano-mpfs-onchain` and `cardano-mpfs-offchain` that M1 implies.

**Done means, on preprod:** an identity registered once through the registry;
rotations landed by hunters for a premium; a freeze when the pool is short;
poison by the current quorum, cleared by rotation; close by the next keys and
reopen by a later rotation; conviction on a duplicity proof, terminal; a
consumer contract reading the checkpoint with the fail-closed verdict; `ckeri`
and a hunter daemon doing all of it; the fifteen stories replayed on preprod as
the acceptance suite; docs written from the stories; release 0.5.0.

The design is settled by the Lean model (checkpoint machine, 62 theorems at the
time of writing, 74 after slice 3; registry machine) and by the simulations:

- https://lambdasistemi.github.io/cardano-keri/simulator/
- https://lambdasistemi.github.io/cardano-keri/simulator/registry/

Epics K0–K10 here; U1–U2 upstream in `cardano-mpfs-onchain`; U3 is #316.

---

## The half of the old outcome test that must not be lost

The superseded description carried an operator ruling of 2026-08-06 that the
milestone does not close on identity *maintenance* alone: **a downstream
Cardano transaction must CONSUME an identity checkpoint to gate an action** — a
validator resolving the checkpoint as a reference input and enforcing its own
authorization rule against the identity's current key state.

Plan v2 keeps this: it is "a consumer contract reading the checkpoint with the
fail-closed verdict", built by K4 ticket #343. Recorded here because the
wording changed and the requirement did not — maintaining an identity on
Cardano is not the same as using one, and only the consumer half demonstrates
the offer this milestone makes.
