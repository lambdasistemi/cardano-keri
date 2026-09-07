# Poison

!!! note "What ships, and the accepted design"
    Poison is **accepted design**, not shipped. Play
    [Mallory steals the current keys; Alice poisons, then rotates](../simulator/index.html)
    in the checkpoint simulation. The model is
    `lean/CardanoKeri/Checkpoint.lean` (87 theorems in `CheckpointGoals.lean`,
    no `sorry`). What ships today is the V1 checkpoint with no poison bit:
    stolen current keys can still close.

Alice's current keys are stolen. Before she can assemble a rotation, her
key holders sign a short declaration — over a preimage bound to the
policy, her AID and her current sequence — and anyone lands it.

The checkpoint is immediately unconsumable. The thief can do nothing
with it: no close, no second poison, no consumer authorization. The
only way out is a witnessed rotation, which clears the poison because
the poison belonged to the keys the rotation retires.

The poison is **epoch-local**. It is never witnessed. Anyone may relay
it. A second poison in the same epoch is refused. Freeze is refused
while poisoned. Top-up still lands: money does not need the quorum.

The one case this does not cover: if the thief also holds the **next**
keys, her rotation *is* control by KERI's own rule. The poison lasts
until that rotation and no longer. Close answers to the next keys, so
that thief can reap.

Play the forks: Mallory and Hal try everything on the poisoned
checkpoint; Mallory tries the reap with the retired keys and is
refused.

See also [Hunters](hunters.md) and [Close, reopen, revival](reopen-revival.md).
