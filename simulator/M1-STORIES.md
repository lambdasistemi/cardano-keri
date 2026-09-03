# The checkpoint, as it will ship — user stories

The M1 return, written for the people who will use it and for the simulator
that will let them try it. Everything here follows the rulings of 2026-09-02
(D-022 to D-034) and the plan `AUDIT-M1-RETURN`. Where a detail is still open
it says so. Nothing here is built yet.

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

- **Checkpoint**: one UTxO per identity holding Alice's current key state,
  a token that is minted once and never again, and three separate sums of
  money.
- **Conviction bond** `D_reg`: Alice's stake against duplicity. Seized only
  by a proof. Never a fee.
- **Freeze bond** `B`: what a hunter takes when Alice's pool cannot pay for a
  rotation.
- **Pool**: advance funds; pays the premium `P` to whoever lands a rotation.
- **Refund address**: where the money goes when Alice leaves. Set when the
  checkpoint is registered, moved only at a rotation and only by the new
  keys.
- **Consumable**: what the treasury accepts — both bonds full, not poisoned,
  older than the juvenility window `W`.
- **Epoch**: the life of one set of current keys, from one rotation to the
  next.

Parameters `D_reg`, `B`, `P` and `W` belong to the deployment. On preprod
today `D_reg` is 1,000 tADA and `B` is 5 tADA; `P` and `W` are new.

---

## 1. Alice's identity appears on Cardano

*As anyone holding Alice's public inception, I want to register her
checkpoint, so that Cardano contracts can read her key state.*

- **Before**: nothing on chain for this AID; the registry has no row for it.
- **Action**: a transaction carrying the inception event, a registry absence
  proof, `D_reg + B + pool₀`, and a refund address chosen by whoever pays.
- **The chain checks**: the inception parses and self-addresses; the AID is
  absent from the registry, and is inserted — this is the only way the token
  can ever be minted; both bonds are present.
- **After**: `Present`, epoch 0, not poisoned, born now, unconsumable for
  `W` slots (juvenile).
- **Alice sees** a checkpoint she did not necessarily create. If a stranger
  registered it, the refund address is the stranger's — until Alice's first
  rotation moves it (story 8).
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
- **The chain checks**: the advance predicate; that both bonds are full on
  the output.
- **After**: next epoch, bonds full, born now (juvenile again for `W`
  slots), consumable after that.
- **Hal sees** a pool worth landing rotations for again.

## 5. Alice goes away

*As Alice, I want to park my identity and take my money out, so that nobody
consumes it while I am gone and nobody can wake it but me.*

- **Before**: `Present`, bonded.
- **Action**: a rotation with `withdraw`. It needs her next keys and her
  witnesses' receipts like any rotation.
- **The chain checks**: the advance predicate; then it pays `D_reg + B +
  pool` to the refund address.
- **After**: the state stays on chain, unbonded — that is what paused means;
  unconsumable.
- **Mallory, holding Alice's current keys, sees** nothing she can do: the
  parked checkpoint answers only to a rotation.

## 6. Alice comes back

*As Alice, I want my parked identity live again.*

- **Before**: unbonded.
- **Action**: a rotation with `deposit`, bringing `D_reg` and `B` back.
- **The chain checks**: the advance predicate; both bonds full on the
  output.
- **After**: bonded, born now, juvenile for `W` slots, then consumable.
- **Note**: there is no replay. The state never left the chain.

## 7. Mallory steals the current keys; Alice poisons, then rotates

*As Alice, when my current keys are stolen, I want every consumer to stop
trusting this epoch now, before I have managed to rotate.*

- **Before**: `Present`, bonded, not poisoned.
- **Action**: Alice's key holders sign, with `kli sign`, a short declaration
  over the policy, the AID and the current sequence; anyone lands it.
- **The chain checks**: signatures at the current threshold — one stolen
  member key of a multisig cannot poison; that the epoch is not already
  poisoned.
- **After**: poisoned; unconsumable; **close is disabled**, so Mallory
  cannot take the bonds; the only way out is a rotation.
- **Then** Alice rotates with her next keys (story 2 or 4): the poison
  clears, because it was local to the keys she just retired.
- **Mallory sees** her stolen keys good for nothing on chain.
- **Limit, stated**: if Mallory also holds the next keys, her rotation is
  control by KERI's own rule; the chain follows KERI. Alice's poison lasts
  until that rotation and no longer.

## 8. Alice moves her refund address

*As Alice, I want the money to come back to me and not to whoever
registered my checkpoint.*

- **Before**: any bonded state whose refund address is not hers.
- **Action**: at a rotation, Alice's new keys sign the new refund address
  along with the rotation.
- **The chain checks**: the signature over the new address at the new
  threshold by the keys the rotation reveals. A relayer submitting her
  public rotation without that signature leaves the address unchanged.
- **After**: the refund address is Alice's. If a stranger had registered
  her, the stranger's bonds now go to Alice at close: a stale registration
  is a donation.

## 9. Cora convicts

*As Cora, holding two of Alice's rotations at the same sequence, each
receipted by at least `toad` of her witnesses, I want to end this identity
on chain and take its conviction bond.*

- **Before**: `Present`, any bonded or poisoned state.
- **Action**: a transaction carrying the second rotation with its receipts,
  naming Cora as payee.
- **The chain checks**: the second rotation is at the tip's sequence,
  reveals the same keys the tip holds, is signed at the current threshold,
  carries receipts from at least `toad` of the tip's witnesses, and differs
  from the accepted one. No history needed: the revealed keys are the
  current keys.
- **After**: `Convicted` — terminal. No rotation, no poison, no close, ever.
  `D_reg` to Cora.
- **Why final**: no KERI event un-duplicates an identifier, so the chain
  invents no recovery. Only a holder of the pre-committed keys could have
  signed the second rotation, and only colluding witnesses could have
  receipted both.
- **Open**: `B` and the pool — recommended back to the refund address.

## 10. Alice leaves for good

*As Alice, I want my identity off Cardano and my money back.*

- **Before**: `Present`, not poisoned.
- **Action**: her current key holders sign the close.
- **The chain checks**: signatures at the current threshold; not poisoned.
  Then it pays everything to the refund address and burns the token.
- **After**: `Gone`. The registry row stays, so this AID can never be
  registered on Cardano again. Terminal.
- **Mallory, with stolen current keys, sees** that closing gets her nothing:
  the money goes to Alice's refund address, and Alice can block the close
  itself by poisoning first.

## 11. The treasury reads Alice's checkpoint

*As the treasury validator, I want to authorize a payment only if Alice's
keys really are current, so I read her checkpoint as a reference input.*

- **The predicate**: present; `D_reg` full; `B` full; not poisoned; born at
  least `W` slots ago; the signature on the payment satisfies the current
  threshold. Later, when validity ships: within `valid_until`.
- **Fails closed** on: absent, unbonded, frozen, poisoned, juvenile,
  convicted, gone.
- **What it cannot know**: whether Alice rotated on KERI an hour ago and no
  hunter has landed it yet. That is why the pool exists.

## 12. A stranger registers Alice at a stale epoch

*As Mallory, holding keys Alice retired long ago, I register her AID
myself and stop advancing at my epoch.*

- **Action**: story 1, then advances up to the epoch whose keys Mallory
  holds.
- **What limits it**: the checkpoint is juvenile for `W` slots; anyone can
  advance it onward with Alice's later public rotations; the moment that
  happens, Mallory's bonds answer to Alice's keys (story 8). It can happen
  once per AID, ever.
- **Stated as a limit**: this residual exists because advance is
  permissionless — the chain cannot tell the owner from a relayer — and
  removing it would mean removing the relayer.

## 13. Anyone tops up the pool

*As a friend of Alice, I want to pay for her maintenance.*

- **Action**: add value to the pool; the datum is untouched; no signature.
- **After**: hunters have a reason to serve her.

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
  brings the checkpoint back. The fields are reserved in the datum now.

---

## State at a glance

| State | Bonds | Poisoned | Who can act | Consumable |
|---|---|---|---|---|
| Absent | — | — | anyone: register | no |
| Live | `D_reg` full, `B` full | no | next keys: rotate (keep / withdraw / deposit); current quorum: poison, close; anyone: top-up; proof: freeze if pool < `P`, convict | after `W` slots |
| Poisoned | full | yes | next keys: rotate; anyone: top-up; proof: convict | no |
| Paused | withdrawn | either | next keys: rotate with deposit; anyone: top-up | no |
| Frozen | `B` missing | no | next keys: rotate with deposit; current quorum: poison, close; anyone: top-up; proof: convict | no |
| Convicted | `D_reg` seized | — | nobody | never |
| Gone | paid out | — | nobody; the AID cannot return | never |

## What is deliberately not here

No record tree, no cursor, no occupancy maps; no interactions (`ixn`) on
chain; no freeze for lag; no hunter bounty; no conviction that clears; no
oracle anywhere. Delegated identities are a later milestone.
