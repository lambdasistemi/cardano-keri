# The checkpoint, as it will ship — user stories

This is the canonical M1 reader story register. The executable authority is
[Checkpoint](../lean/CardanoKeri/Checkpoint.lean), its goals and the associated
Registry model. A checkpoint is alive until it is convicted: there is no owner
exit, no parked state and no revival. Conviction enters pending custody; an
associated consuming Registry fold alone completes retirement. The local player
and connected system traces implement these model observations; production
validators, builders, deployment and consumer identity extension #439 are separate.

## The cast

- **Alice**, the owner. She has a KERI identity with three witnesses. She
  rotates her keys with `kli` and never touches Cardano except to put money
  in. That is the design: the owner is dumb on Cardano.
- **Hal**, a hunter. He runs a watcher seeded from the on-chain endpoint
  board, polls Alice's witnesses, and lands her rotations on Cardano for a
  fee. When she does not pay, he freezes her instead.
- **The treasury**, a Cardano validator that authorizes payments against
  Alice's current keys by reading her checkpoint as a reference input.
- **Cora**, a convictor. She holds two of Alice's rotations at the same
  sequence, both receipted by Alice's witnesses.
- **Mallory**, a thief. Sometimes she has Alice's current keys; sometimes
  the next ones too.
- **Anyone**: whoever relays a public event, tops up a pool, or registers a
  public inception.

## The words

KERI's words keep KERI's meaning, and each links its clause in the
[specification](https://trustoverip.github.io/kswg-keri-specification/) (KERI 1.1, the version the watcher conformance review
pins):

- **AID**, **KEL**, **inception**, **rotation**: [autonomic identifier](https://trustoverip.github.io/kswg-keri-specification/#autonomic-identifier-aid), [labelling key events in a KEL](https://trustoverip.github.io/kswg-keri-specification/#labelling-key-events-in-a-kel), the [inception](https://trustoverip.github.io/kswg-keri-specification/#inception-event-message-body) and [rotation](https://trustoverip.github.io/kswg-keri-specification/#rotation-event-message-body) event bodies.
- **Current keys**, **next keys**: [pre-rotation](https://trustoverip.github.io/kswg-keri-specification/#pre-rotation) and [rotation using pre-rotation](https://trustoverip.github.io/kswg-keri-specification/#rotation-using-pre-rotation). Whoever reveals the committed next keys rotates; that is control.
- **Witnesses**, **toad**, **receipts**: [witness designation](https://trustoverip.github.io/kswg-keri-specification/#witness-designation), [witnessing policy](https://trustoverip.github.io/kswg-keri-specification/#witnessing-policy), [receipt messages](https://trustoverip.github.io/kswg-keri-specification/#receipt-messages), [KERI's algorithm for witness agreement](https://trustoverip.github.io/kswg-keri-specification/#keris-algorithm-for-witness-agreement-kawa).
- **Duplicity**: [duplicity](https://trustoverip.github.io/kswg-keri-specification/#duplicity), two differing events at one sequence number. What Cora proves.
- **First-seen**: [first-seen policy](https://trustoverip.github.io/kswg-keri-specification/#first-seen-policy), a witness-local observation the chain never reconstructs.

The words below are ours:

- **Checkpoint**: one UTxO per identity holding Alice's current key state,
  a token that is minted once and never again, and three separate sums of
  money.
- **Conviction bond** `D_reg`: Alice's stake against duplicity. Seized only
  by a proof. Never a fee.
- **Freeze bond** `B`: what a hunter takes when Alice's pool cannot pay for a
  rotation; a `deposit` rotation refills it.
- **Pool**: Alice's advance funds; pays the premium `P` to whoever lands a
  rotation. Anyone may top it up.
- **Premium** `P`: the fee the pool pays whoever lands a rotation.
- **Hunter**: anyone paid to land Alice's rotation on chain, or to freeze her
  checkpoint when the pool cannot pay for one. Hal.
- **Poison**: Alice's own lock on her checkpoint: a declaration signed by the
  current keys at their threshold that makes the checkpoint unconsumable
  until a witnessed rotation clears it.
- **Refund address**: where the freeze bond and the pool go when the
  checkpoint is convicted. Chosen by whoever pays the registration and fixed
  for the checkpoint's whole life: no rotation, poison or other step moves it.
- **Pending conviction**: the retained representative remains in custody while
  its associated termination request awaits a consuming Registry fold.
- **Consumable**: what the treasury accepts — bonded (the freeze bond held),
  not poisoned, older than the juvenility window `W`.
- **Juvenility window** `W`: the age a checkpoint must reach, counted from its
  registration, before a consumer trusts it.
- **Convicted**: the terminal Checkpoint state after its associated consuming
  fold burns the representative and permanently retires the registry key.
- **Epoch**: the life of one set of current keys, from one rotation to the
  next.

Parameters `D_reg`, `B`, `P` and `W` belong to the model configuration.
The player uses illustrative values, not a deployment configuration.

---

## 1. Alice's identity appears on Cardano

*As anyone holding Alice's public inception, I want to register her
checkpoint, so that Cardano contracts can read her key state.*

- **Before**: nothing on chain for this AID; the registry has no row for it.
- **Action**: a transaction carrying the inception event, a registry absence
  proof, `D_reg + B + pool₀`, and a refund address chosen by whoever pays.
- **The chain checks**: the inception parses and self-addresses; the AID is
  absent from the registry, and is inserted — this is the only way the token
  can ever be minted; both bonds are present; the first pool is at least
  one premium.
- **After**: `Present`, epoch 0, not poisoned, born now, unconsumable for
  `W` slots (juvenile).
- **Alice sees** a checkpoint she did not necessarily create. If a stranger
  registered it, the refund address is the stranger's, for the checkpoint's
  whole life (story 8).
- **Open**: none.

## 2. Alice rotates, Hal lands it, Hal is paid

*As Hal, I want to land Alice's rotation the moment her witnesses receipt
it, so that her checkpoint stays current and I earn the premium.*

- **Before**: `Present`, bonded, pool ≥ `P`.
- **Action**: Alice runs `kli rotate`; her witnesses receipt it. Hal's
  watcher sees the new event on the witnesses listed on the board and
  submits an advance with `keep`, naming himself as payee.
- **The chain checks**: signatures at the current threshold over the
  rotation bytes; revealed keys match the pre-committed digests at the next
  threshold; receipts from at least `toad` of the new witness set; sequence
  strictly greater. Then it pays `P` from the pool to Hal.
- **After**: next epoch, poison cleared, pool reduced by `P`, bonds
  untouched, consumable.
- **Alice sees** nothing; she never touched Cardano.
- **Open**: whether `P` is one deployment parameter or Alice's own number in
  the datum.

## 3. The pool runs dry, so Hal freezes her instead

*As Hal, when Alice's pool cannot pay me, I want to take the freeze bond
and freeze her checkpoint on its old keys, so that no consumer trusts a
stale key state and Alice comes back to pay.*

- **Before**: `Present`, bonded, pool < `P`, a witnessed rotation exists on
  KERI that the checkpoint has not seen.
- **Action**: Hal submits the same evidence he would use to advance — the
  new rotation with its receipts — but as a freeze, naming himself.
- **The chain checks**: exactly the advance predicate on the presented
  rotation; that the pool is below `P`; that the checkpoint is not poisoned
  (already unconsumable, nothing to freeze). Then it pays `B` to Hal and
  leaves the datum untouched.
- **After**: the old keys still shown, `B` missing — that is what frozen
  means; unconsumable.
- **Alice sees** her identity refused by the treasury, and learns why.
- **Open**: none. The freeze is not a fee on the conviction bond; that bond
  is never touched.

## 4. Alice unfreezes

*As Alice, I want my checkpoint back in service, so I land my rotation
myself, put the freeze bond back, and top up the pool.*

- **Before**: frozen (`B` missing), the rotation from story 3 still
  unapplied on chain.
- **Action**: Alice, or anyone she funds, submits the rotation with
  `deposit`, bringing `B`, and adds to the pool.
- **The chain checks**: the advance predicate; the new keys' signature on
  the deposit; then the freeze bond is back on the output; nothing else
  changes and juvenility is not restarted.
- **After**: next epoch, bonds full, consumable at once if it was before the
  freeze. A deposit on full bonds is a keep in all but its signature.
- **Hal sees** a pool worth landing rotations for again.

## 5. Alice leaves (retired)

Retired: there is no owner exit, so there is no close (the reap) and no parked output. A checkpoint is alive until it is convicted (story 9); its
owner keeps it alive by rotating, unfreezing and topping up. The story keeps
its number; its disposition is in
[checkpoint-story-migration.json](checkpoint-story-migration.json).

## 6. Alice revives her parked identity (retired)

Retired: there is no parked state, so there is no revival. A checkpoint is alive until it is convicted (story 9); its
owner keeps it alive by rotating, unfreezing and topping up. The story keeps
its number; its disposition is in
[checkpoint-story-migration.json](checkpoint-story-migration.json).

## 7. Mallory steals the current keys; Alice poisons, then rotates

*As Alice, when my current keys are stolen, I want every consumer to stop
trusting this epoch now, before I have managed to rotate.*

- **Before**: `Present`, bonded, not poisoned.
- **Action**: Alice's key holders sign, with `kli sign`, a short declaration
  over the policy, the AID and the current sequence; anyone lands it.
- **The chain checks**: signatures at the current threshold — one stolen
  member key of a multisig cannot poison; that the epoch is not already
  poisoned.
- **After**: poisoned; unconsumable; the stolen current keys move no bonds;
  the only way out of the poison is a rotation by the next keys, which
  Mallory does not hold.
- **Then** Alice rotates with her next keys (story 2 or 4): the poison
  clears, because it was local to the keys she just retired.
- **Mallory sees** her stolen keys good for nothing on chain.
- **Limit, stated**: if Mallory also holds the next keys, her rotation is
  control by KERI's own rule; the chain follows KERI. Alice's poison lasts
  until that rotation and no longer.

## 8. The refund address stays the sponsor's

*As a sponsor, I pay Alice's registration — the conviction bond, the
freeze bond and the first pool — and I want the bond and the pool I paid to
go back to the refund address I chose if her checkpoint is ever convicted.*

- **Before**: nothing on chain for this AID.
- **Action**: the sponsor registers Alice with his own refund address; Alice
  rotates, deposits and tops up the pool; Cora convicts.
- **The chain checks**: the registration takes the refund address as given,
  with no signature over it; a rotation leaves the refund address as it was;
  so does a deposit; a top-up adds to the pool and sets the top-up mark,
  nothing else; a conviction
  pays the freeze bond held and the pool to the refund address.
- **After**: `D_reg` goes to Cora; the freeze bond and the whole pool, top-ups
  by others included, go to the sponsor's address. Alice's keys control her
  identity, not the sponsor's money.
- **Open**: none.

## 9. Cora convicts

*As Cora, holding two of Alice's ordinary rotations at the same sequence, each
receipted by its own witness threshold, I want to end this identity
on chain and take its conviction bond.*

- **Before**: `Present`, any bonded or poisoned state.
- **Action**: a transaction carrying the second rotation with its receipts,
  naming Cora as payee.
- **The chain checks**: the second rotation is at the tip's sequence,
  satisfies the common prior-next threshold, satisfies its own current threshold,
  carries receipts from its own derived witness threshold, and differs
  in complete content from the accepted rotation. Both ordinary rotations
  validate against authenticated predecessor context.
- **After**: `terminationPending`, retaining the representative and key state.
  `D_reg` goes to Cora and `B` plus pool to the refund
  address. The whole booked request remains pending until its associated
  consuming Registry fold burns the representative and marks the key retired.
- **Why final**: no KERI event un-duplicates an identifier, so the chain
  invents no recovery. Only a holder of the pre-committed keys could have
  signed the second rotation, and only colluding witnesses could have
  receipted both.
- **Local limit**: no local action leaves pending custody. The connected
  system player shows booking and actual fold completion.

## 10. Alice leaves under attack (retired)

Retired: there is no owner exit; a poisoned checkpoint is recovered by a rotation (story 7). A checkpoint is alive until it is convicted (story 9); its
owner keeps it alive by rotating, unfreezing and topping up. The story keeps
its number; its disposition is in
[checkpoint-story-migration.json](checkpoint-story-migration.json).

## 11. The treasury reads Alice's checkpoint

*As the treasury validator, I want to authorize a payment only if Alice's
keys really are current, so I read her checkpoint as a reference input.*

- **The predicate**: present; the freeze bond held; not poisoned; born at
  least `W` slots ago; the signature on the payment satisfies the current
  threshold. Later, when validity ships: within `valid_until`.
- **Fails closed** on: absent, frozen, poisoned, juvenile,
  pending custody, convicted.
- **What it cannot know**: whether Alice rotated on KERI an hour ago and no
  hunter has landed it yet. That is why the pool exists.

## 12. A stranger registers Alice at a stale epoch

*As Mallory, holding keys Alice retired long ago, I register her AID
myself and stop advancing at my epoch.*

- **Action**: story 1, then advances up to the epoch whose keys Mallory
  holds.
- **What limits it**: the checkpoint is juvenile for `W` slots; anyone can
  advance it onward with Alice's later public rotations. It can happen
  once per AID, ever.
- **Stated as a limit**: this residual exists because advance is
  permissionless — the chain cannot tell the owner from a relayer — and
  removing it would mean removing the relayer. Mallory's bonds stay hers:
  the refund address is fixed at registration (story 8), so a stale
  registration is not a donation to Alice.

## 13. Anyone tops up the pool

*As a friend of Alice, I want to pay for her maintenance.*

- **Action**: add value to the pool, at least one premium, once per key
  state; the datum is untouched but for the top-up mark; no signature.
- **After**: hunters have a reason to serve her. A second top-up of the same
  key state is refused, so nobody can keep the checkpoint busy with a stream
  of tiny top-ups and make Alice's rotation fail on a spent input; the next
  rotation clears the mark.

## 14. Two hunters race

- Both see the rotation. If the pool covers `P`, the first advance wins and
  is paid; the second fails on the spent input. If it does not, the first
  freeze wins `B`; the second finds nothing to take.

## 15. Alice forgets

*As Alice, I go quiet for a year.*

- Today: her checkpoint stays consumable as long as it is bonded and no
  rotation is missing. Nothing on chain says she is gone.
- Direction (D-027, not yet ruled): a validity Alice renews by re-signing
  with her current keys, no next-key reveal; if it lapses, only a rotation
  brings the checkpoint back. This extension is not implemented or claimed here.

---

## State at a glance

| State | Bonds | Poisoned | Who can act | Consumable |
|---|---|---|---|---|
| Absent | — | — | anyone: register | no |
| Live (active) | `D_reg`, `B` held | no | next keys: rotate (keep / deposit); current quorum: poison; anyone: top-up, once per key state; proof: freeze if pool < `P`, convict | after `W` slots |
| Poisoned (active) | held | yes | next keys: rotate; anyone: top-up, once per key state; proof: convict | no |
| Frozen (active) | `B` missing | no | next keys: rotate with deposit (unfreeze); current quorum: poison; anyone: top-up, once per key state; proof: convict | no |
| Pending custody | no bonds or pool; representative retained | — | associated booking and consuming fold only | no |
| Convicted | representative burned at fold; key retired | — | nobody | never |

## What is deliberately not here

No record tree, no cursor, no occupancy maps; no interactions (`ixn`) on
chain; no freeze for lag; no hunter bounty; no conviction that clears; no external freshness oracle. No owner exit: no close, no parking, no revival
and no pause or withdraw; no grace window — the registry's is not the checkpoint's. Delegated identities are a later milestone.
