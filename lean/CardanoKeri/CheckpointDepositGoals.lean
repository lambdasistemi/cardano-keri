import CardanoKeri.CheckpointDeposit
import CardanoKeri.CheckpointDatumGoals
import CardanoKeri.CheckpointGoals

/-! What the deposit intent's bytes bind (#517).

The bytes determine the intent: two intents with the same bytes are the same
intent, so changing the network, the policy, the spent output, the AID, the
sequence number, the epoch, the amount or the domain changes the bytes. The
amount the intent names is what the deposit moves, `B − bHeld`. Under the
concrete reading of `Env.depositAuthorized`, a deposit step carries the new
keys' signature over exactly the intent for its spent state, output and
amount, and every bond option stays enabled when its evidence is. Signatures
made over one intent count for no other. -/
namespace CardanoKeri.CheckpointDeposit
open CardanoKeri.Checkpoint
open CardanoKeri.CheckpointDatum
open CardanoKeri.ConsumerIdentity.Bytes (unpack unpack_injective)

/-! ## The bytes determine the intent -/

/-- Given two intents with the same Plutus Data; when compared; then they are the same intent. -/
theorem toData_injective {i j : DepositIntent} (h : i.toData = j.toData) : i = j := by
  obtain ⟨d, n, c, ⟨tx, ix⟩, a, s, e, v⟩ := i
  obtain ⟨d', n', c', ⟨tx', ix'⟩, a', s', e', v'⟩ := j
  simp only [DepositIntent.toData, Data.constr.injEq, List.cons.injEq, Data.bytes.injEq,
    Data.int.injEq, and_true, true_and] at h
  obtain ⟨hd, hn, hc, ⟨htx, hix⟩, ha, hs, he, hv⟩ := h
  have hn : n = n' := by exact_mod_cast hn
  have hix : ix = ix' := by exact_mod_cast hix
  have hs : s = s' := by exact_mod_cast hs
  have he : e = e' := by exact_mod_cast he
  have hv : v = v' := by exact_mod_cast hv
  have hc := unpack_injective hc
  have htx := unpack_injective htx
  have ha := unpack_injective ha
  subst hd hn hc htx hix ha hs he hv
  rfl

/-- Given two intents whose signed bytes are equal; when compared; then they are the same
intent. -/
theorem preimage_injective {i j : DepositIntent} (h : i.preimage = j.preimage) : i = j := by
  have hi := ofBytes?_cbor i.toData
  have hj := ofBytes?_cbor j.toData
  rw [show cbor i.toData = cbor j.toData from h, hj] at hi
  exact toData_injective (Option.some.inj hi).symm

/-- Given any two intents; when their signed bytes are compared; then they are equal exactly when
the intents are. -/
theorem preimage_eq_iff (i j : DepositIntent) : i.preimage = j.preimage ↔ i = j :=
  ⟨preimage_injective, fun h => h ▸ rfl⟩

/-- Given two intents that differ in any field, the domain, the network, the policy, the spent
output, the AID, the sequence number, the epoch or the amount; when serialised; then their signed
bytes differ. -/
theorem preimage_ne_of_ne {i j : DepositIntent} (h : i ≠ j) : i.preimage ≠ j.preimage :=
  fun e => h (preimage_injective e)

/-- Given two deposit rotations, each a spent state, its observed network, policy, output and AID,
and a new sequence number; when the intents the validator requires are serialised; then the bytes
are equal exactly when the observed facts, the new sequence numbers, the new epochs and the
amounts are. -/
theorem intentFor_preimage_eq_iff (p p' : Params) (o o' : Observed) (l l' : Live) (sn sn' : Seq) :
    (intentFor p o l sn).preimage = (intentFor p' o' l' sn').preimage ↔
      o = o' ∧ sn = sn' ∧ l.epoch + 1 = l'.epoch + 1 ∧ p.B - l.bHeld p = p'.B - l'.bHeld p' := by
  rw [preimage_eq_iff]
  obtain ⟨n, c, r, a⟩ := o
  obtain ⟨n', c', r', a'⟩ := o'
  simp only [intentFor, DepositIntent.mk.injEq, Observed.mk.injEq, true_and]
  constructor
  · rintro ⟨hn, hc, hr, ha, hs, he, hv⟩
    exact ⟨⟨hn, hc, hr, ha⟩, hs, he, hv⟩
  · rintro ⟨⟨hn, hc, hr, ha⟩, hs, he, hv⟩
    exact ⟨hn, hc, hr, ha, hs, he, hv⟩

/-! ## The amount is what moves -/

/-- Given a spent live state and any observed facts and sequence number; when the intent the
validator requires is built; then its amount is `B − bHeld`: the freeze bond `B` when the state is
frozen, `0` when it is not. -/
theorem intentFor_deposit (p : Params) (o : Observed) (l : Live) (sn' : Seq) :
    (intentFor p o l sn').deposit = p.B - l.bHeld p ∧
    (l.frozen = true → (intentFor p o l sn').deposit = p.B) ∧
    (l.frozen = false → (intentFor p o l sn').deposit = 0) := by
  refine ⟨rfl, fun h => ?_, fun h => ?_⟩ <;> simp [intentFor, Live.bHeld, h]

/-- Given a deposit rotation step from a live state; when its flow is read; then the amount it
brings into the output is the amount the required intent names, whatever was observed. -/
theorem deposit_step_moves_named_amount (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow}
    {s' : State} {sn' : Seq} {payee : Addr}
    (h : Step p env (.rotate sn' .deposit payee) t (.present l) f s') (o : Observed) :
    f.bIn = (intentFor p o l sn').deposit := by
  cases h <;> rfl

/-! ## The concrete reading of the deposit authorization -/

/-- Given an environment that reads the deposit concretely at this rotation; when a deposit
rotation step from the spent state is taken; then the new keys at the new threshold signed the
intent for this spent state, this output and this amount. -/
theorem deposit_step_requires_signed_intent (verify : Verify) (p : Params) (env : Env)
    (ev : Evidence) {t : Slot} {l : Live} {f : Flow} {s' : State} {sn' : Seq} {payee : Addr}
    (hread : ReadsDeposit verify p env ev l sn')
    (h : Step p env (.rotate sn' .deposit payee) t (.present l) f s') :
    ev.authorizes verify p l sn' = true := by
  rw [← hread]
  exact T6_deposit_requires_new_keys p env h

/-- Given an environment that reads the deposit concretely at this rotation, a witnessed rotation
to a later sequence number and evidence that authorizes the intent; when a deposit is submitted;
then the deposit step is enabled and brings exactly the amount the intent names. -/
theorem deposit_enabled (verify : Verify) (p : Params) (env : Env) (ev : Evidence) (t : Slot)
    (l : Live) (sn' : Seq) (payee : Addr) (hread : ReadsDeposit verify p env ev l sn')
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hauth : ev.authorizes verify p l sn' = true) :
    ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' .deposit payee) t (.present l) f (.present l') ∧
      f.bIn = (intentFor p ev.observed l sn').deposit := by
  have hok : env.bondOpOk (l.epoch + 1) .deposit = true := by
    simp only [Env.bondOpOk]; rw [hread]; exact hauth
  obtain ⟨f, l', hs⟩ := T5_every_bond_option p env t l sn' payee hev hsn .deposit hok
  exact ⟨f, l', hs, deposit_step_moves_named_amount p env hs ev.observed⟩

/-- Given an unfrozen live state, an environment that reads the deposit concretely, a witnessed
rotation and evidence that authorizes the intent; when a deposit is submitted; then the step is
enabled, the intent names `0` and the step brings nothing. -/
theorem unfrozen_deposit_accepted_for_zero (verify : Verify) (p : Params) (env : Env)
    (ev : Evidence) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr) (hfull : l.frozen = false)
    (hread : ReadsDeposit verify p env ev l sn')
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hauth : ev.authorizes verify p l sn' = true) :
    (intentFor p ev.observed l sn').deposit = 0 ∧
    ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' .deposit payee) t (.present l) f (.present l') ∧
      f.bIn = 0 := by
  have h0 := (intentFor_deposit p ev.observed l sn').2.2 hfull
  obtain ⟨f, l', hs, hb⟩ := deposit_enabled verify p env ev t l sn' payee hread hev hsn hauth
  exact ⟨h0, f, l', hs, hb.trans h0⟩

/-! ## Which signatures count -/

/-- Given keys, a message and signatures; when the verified positions are computed; then a position
is among them exactly when some signature at that position, by the key at that position, verifies
over the message. -/
theorem mem_verifiedPositions (verify : Verify) (keys : List (List Nat)) (m : List Nat)
    (sigs : List (Nat × List Nat)) (k : Nat) :
    k ∈ verifiedPositions verify keys m sigs ↔
      ∃ s key, (k, s) ∈ sigs ∧ keys[k]? = some key ∧ verify key m s = true := by
  simp only [verifiedPositions, List.mem_filterMap]
  constructor
  · rintro ⟨⟨i, s⟩, hmem, hc⟩
    simp only [counted] at hc
    split at hc
    · rename_i key hkey
      split at hc
      · cases hc; exact ⟨s, key, hmem, hkey, by assumption⟩
      · cases hc
    · cases hc
  · rintro ⟨s, key, hmem, hkey, hv⟩
    exact ⟨(k, s), hmem, by simp [counted, hkey, hv]⟩

/-- Given signatures none of which verifies over the message under any of the new keys, and a
threshold no empty signer set satisfies; when checked; then the new keys did not sign the
message. -/
theorem only_new_keys_count (verify : Verify) (keys : List Nat) (threshold : Duplicity.Threshold)
    (sigs : List (Nat × List Nat)) (m : List Nat)
    (hnone : ∀ k s, (k, s) ∈ sigs → ∀ key ∈ keys.map unpack, verify key m s = false)
    (hnontrivial : threshold.satisfied (List.range keys.length) [] = false) :
    signed verify keys threshold sigs m = false := by
  have hempty : verifiedPositions verify (keys.map unpack) m sigs = [] := by
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro k hk
    obtain ⟨s, key, hmem, hkey, hv⟩ := (mem_verifiedPositions verify _ m sigs k).mp hk
    have := hnone k s hmem key (List.mem_of_getElem? hkey)
    simp_all
  simp only [signed, hempty, hnontrivial]

/-- Given a signature that verifies, under one key, over the bytes of two intents, and signatures
that bind their message; when the intents are compared; then they are the same intent. -/
theorem signature_binds_one_intent (verify : Verify) (hbind : SignatureBinding verify)
    {key s : List Nat} {i j : DepositIntent}
    (hi : verify key i.preimage s = true) (hj : verify key j.preimage s = true) : i = j :=
  preimage_injective (hbind key _ _ s hi hj)

/-- Given signatures each of which verifies, under the key at its position, over the bytes of the
intent `i` only, a threshold no empty signer set satisfies and another intent `j`; when the new
keys' signature over `j` is checked; then it is refused. -/
theorem signed_for_one_not_another (verify : Verify) (keys : List Nat)
    (threshold : Duplicity.Threshold) (sigs : List (Nat × List Nat)) {i j : DepositIntent}
    (honly : ∀ k s, (k, s) ∈ sigs → ∀ key m, (keys.map unpack)[k]? = some key →
      verify key m s = true → m = i.preimage)
    (hnontrivial : threshold.satisfied (List.range keys.length) [] = false) (hne : j ≠ i) :
    signed verify keys threshold sigs j.preimage = false := by
  have hempty : verifiedPositions verify (keys.map unpack) j.preimage sigs = [] := by
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro k hk
    obtain ⟨s, key, hmem, hkey, hv⟩ := (mem_verifiedPositions verify _ _ sigs k).mp hk
    exact hne (preimage_injective (honly k s hmem key _ hkey hv))
  simp only [signed, hempty, hnontrivial]

/-- Given signatures that bind their message, each signature verifying under the key at its
position over the bytes of the intent for one deposit rotation, and a threshold no empty signer set
satisfies; when the same keys and signatures are presented for a rotation whose required intent
differs, in network, policy, spent output, AID, sequence number, epoch or amount; then they do not
authorize it. -/
theorem authorization_does_not_transfer (verify : Verify) (hbind : SignatureBinding verify)
    (p p' : Params) (ev : Evidence) (o' : Observed) (l l' : Live) (sn sn' : Seq)
    (hover : ∀ k s, (k, s) ∈ ev.signatures → ∀ key, (ev.newKeys.map unpack)[k]? = some key →
      verify key (intentFor p ev.observed l sn).preimage s = true)
    (hnontrivial : ev.newThreshold.satisfied (List.range ev.newKeys.length) [] = false)
    (hdiff : intentFor p' o' l' sn' ≠ intentFor p ev.observed l sn) :
    Evidence.authorizes verify p' { ev with observed := o' } l' sn' = false := by
  apply signed_for_one_not_another verify ev.newKeys ev.newThreshold ev.signatures _ hnontrivial hdiff
  intro k s hmem key m hkey hv
  exact hbind key m _ s hv (hover k s hmem key hkey)

end CardanoKeri.CheckpointDeposit
