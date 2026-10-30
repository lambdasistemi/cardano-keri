import CardanoKeri.ConsumerBytes
import CardanoKeri.ConsumerGoals

/-! Separation premises of the consumer statements for the concrete bytes.

`FiniteEncoding` is proved for the concrete codec over every identity domain:
reading decoders recover each field of a State or Active serialisation, so
equal serialisations have equal preimages. `FiniteCollisionFree` is reduced to
BLAKE2b-256 digest collision freedom over the same finite domain, which stays
an explicit assumption. Key injectivity holds because the key is the AID's
CESR text bytes and the AID label carries exactly those bytes. -/
namespace CardanoKeri.ConsumerIdentity.Bytes
open CardanoKeri.Checkpoint

/-! ## Readers -/

/-- Read `k` big-endian bytes. -/
def readBe (k : Nat) (l : List Nat) : Option (Nat × List Nat) :=
  if k ≤ l.length then some (beVal (l.take k), l.drop k) else none

/-- Read a CBOR head: major type, argument and the rest. -/
def readHead : List Nat → Option (Nat × Nat × List Nat)
  | [] => none
  | b :: rest =>
    if b % 32 < 24 then some (b / 32, b % 32, rest)
    else if b % 32 = 24 then (readBe 1 rest).map fun r => (b / 32, r.1, r.2)
    else if b % 32 = 25 then (readBe 2 rest).map fun r => (b / 32, r.1, r.2)
    else if b % 32 = 26 then (readBe 4 rest).map fun r => (b / 32, r.1, r.2)
    else if b % 32 = 27 then (readBe 8 rest).map fun r => (b / 32, r.1, r.2)
    else none

/-- Read definite byte-string chunks up to the break byte. -/
def readChunks : Nat → List Nat → Option (List Nat × List Nat)
  | 0, _ => none
  | _ + 1, [] => none
  | fuel + 1, b :: rest =>
    if b = 0xff then some ([], rest) else
    match readHead (b :: rest) with
    | some (2, n, r) => (readChunks fuel (r.drop n)).map fun p => (r.take n ++ p.1, p.2)
    | _ => none

/-- Read a byte string, definite or indefinite. -/
def readBstr : List Nat → Option (List Nat × List Nat)
  | [] => none
  | b :: rest =>
    if b = 0x5f then readChunks (rest.length + 1) rest else
    match readHead (b :: rest) with
    | some (2, n, r) => some (r.take n, r.drop n)
    | _ => none

/-- Read a non-negative integer, plain or a tagged big number. -/
def readInt : List Nat → Option (Nat × List Nat)
  | [] => none
  | b :: rest =>
    if b = 0xc2 then (readBstr rest).map fun p => (beVal p.1, p.2) else
    match readHead (b :: rest) with
    | some (0, n, r) => some (n, r)
    | _ => none

/-! ## Round trips -/

/-- BR1. Given a width and a number; when written big-endian at that width; then the length is
the width. -/
theorem be_length (k n : Nat) : (be k n).length = k := by
  induction k generalizing n with
  | zero => rfl
  | succ k ih => simp [be, ih]

/-- BR2. Given bytes and one more byte; when reading the big-endian value; then the value shifts
by one byte and adds it. -/
theorem beVal_append (xs : List Nat) (b : Nat) : beVal (xs ++ [b]) = beVal xs * 256 + b := by
  simp [beVal, List.foldl_append]

/-- BR3. Given a width and a number; when written big-endian and read back; then the number
modulo the width's range returns. -/
theorem beVal_be (k n : Nat) : beVal (be k n) = n % 256 ^ k := by
  induction k generalizing n with
  | zero => simp [be, beVal, Nat.mod_one]
  | succ k ih =>
    rw [be, beVal_append, ih, Nat.pow_succ, Nat.mul_comm (256 ^ k) 256, Nat.mod_mul]
    omega

/-- BR4. Given a number within a width's range and any rest; when written big-endian and read;
then the number and the rest return. -/
theorem readBe_be (k n : Nat) (t : List Nat) (h : n < 256 ^ k) :
    readBe k (be k n ++ t) = some (n, t) := by
  have hl := be_length k n
  simp only [readBe, List.length_append, hl, Nat.le_add_right, if_true]
  rw [List.take_left' hl, List.drop_left' hl, beVal_be, Nat.mod_eq_of_lt h]

/-- BR5. Given a major type below 8, an argument below 2^64 and any rest; when the shortest head
is written and read; then major type, argument and rest return. -/
theorem readHead_head (m n : Nat) (t : List Nat)
    (hn : n < 18446744073709551616) : readHead (head m n ++ t) = some (m, n, t) := by
  unfold head
  split
  · simp only [List.cons_append, List.nil_append, readHead]
    rw [if_pos (by omega)]
    simp only [Option.some.injEq, Prod.mk.injEq, and_true]
    omega
  split
  · simp only [List.cons_append, List.nil_append, readHead]
    rw [if_neg (by omega), if_pos (by omega), readBe_be 1 n t (by omega)]
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq, and_true]
    omega
  split
  · simp only [List.cons_append, List.nil_append, readHead]
    rw [if_neg (by omega), if_neg (by omega), if_pos (by omega), readBe_be 2 n t (by omega)]
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq, and_true]
    omega
  split
  · simp only [List.cons_append, List.nil_append, readHead]
    rw [if_neg (by omega), if_neg (by omega), if_neg (by omega), if_pos (by omega),
      readBe_be 4 n t (by omega)]
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq, and_true]
    omega
  · simp only [List.cons_append, List.nil_append, readHead]
    rw [if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega),
      if_pos (by omega), readBe_be 8 n t (by omega)]
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq, and_true]
    omega

/-- BR15. Given a major type and an argument; when the shortest head is written; then its first
byte carries the major type and an additional-information value of at most 27. -/
theorem head_cons (m n : Nat) : ∃ b rest, head m n = b :: rest ∧ b / 32 = m ∧ b % 32 ≤ 27 := by
  unfold head
  split
  · exact ⟨m * 32 + n, [], rfl, by omega, by omega⟩
  split
  · exact ⟨m * 32 + 24, _, rfl, by omega, by omega⟩
  split
  · exact ⟨m * 32 + 25, _, rfl, by omega, by omega⟩
  split
  · exact ⟨m * 32 + 26, _, rfl, by omega, by omega⟩
  · exact ⟨m * 32 + 27, _, rfl, by omega, by omega⟩

/-- BR6. Given a byte string; when chunked; then the chunks are at least as long as the string. -/
theorem chunks_length (bs : List Nat) : bs.length ≤ (chunks bs).length := by
  induction h : bs.length using Nat.strongRecOn generalizing bs with
  | ind n ih =>
    rw [chunks]
    split
    · simp_all
    · rename_i hb
      have hlen : 0 < bs.length := List.length_pos_iff.mpr hb
      have := ih (bs.drop 64).length (by simp; omega) (bs.drop 64) rfl
      simp only [List.length_append, List.length_take, List.length_drop] at this ⊢
      omega

/-- BR7. Given a byte string, any rest and enough fuel; when its chunks and a break byte are
read; then the string and the rest return. -/
theorem readChunks_chunks (bs t : List Nat) (fuel : Nat) (hf : bs.length < fuel) :
    readChunks fuel (chunks bs ++ 0xff :: t) = some (bs, t) := by
  induction fuel generalizing bs t with
  | zero => omega
  | succ fuel ih =>
    by_cases hb : bs = []
    · subst hb; simp [chunks, readChunks]
    · rw [chunks, if_neg hb]
      have hlen : 0 < bs.length := List.length_pos_iff.mpr hb
      have hm : min 64 bs.length < 18446744073709551616 := by omega
      obtain ⟨b, rest, hh, hmaj, hai⟩ := head_cons 2 (min 64 bs.length)
      have hne : b ≠ 0xff := by omega
      have hread := readHead_head 2 (min 64 bs.length)
        (bs.take 64 ++ (chunks (bs.drop 64) ++ 0xff :: t)) hm
      rw [hh] at hread ⊢
      simp only [List.append_assoc, List.cons_append, readChunks, if_neg hne]
      rw [← List.cons_append, hread]
      simp only
      have htl : (bs.take 64).length = min 64 bs.length := by simp
      rw [List.take_left' htl, List.drop_left' htl]
      rw [ih (bs.drop 64) t (by simp; omega)]
      simp

/-- BR8. Given a byte string and any rest; when serialised and read; then the string and the
rest return. -/
theorem readBstr_bstr (bs t : List Nat) : readBstr (bstr bs ++ t) = some (bs, t) := by
  unfold bstr
  split
  · rename_i hs
    have hm : bs.length < 18446744073709551616 := by omega
    obtain ⟨b, rest, hh, hmaj, hai⟩ := head_cons 2 bs.length
    have hne : b ≠ 0x5f := by omega
    have hread := readHead_head 2 bs.length (bs ++ t) hm
    rw [hh] at hread ⊢
    simp only [List.cons_append, List.append_assoc, readBstr, if_neg hne]
    rw [← List.cons_append, hread]
    simp
  · simp only [List.append_assoc, List.cons_append, readBstr]
    apply readChunks_chunks
    have := chunks_length bs
    simp; omega

/-- BR9. Given a number; when written big-endian without leading zeros and read; then it returns. -/
theorem beVal_minimalBe (n : Nat) : beVal (minimalBe n) = n := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    rw [minimalBe]
    split
    · simp [beVal, *]
    · rw [beVal_append, ih _ (by omega)]
      omega

/-- BR10. Given a non-negative integer and any rest; when serialised and read; then the integer
and the rest return. -/
theorem readInt_int (n : Nat) (t : List Nat) : readInt (int n ++ t) = some (n, t) := by
  unfold int
  split
  · rename_i hn
    obtain ⟨b, rest, hh, hmaj, hai⟩ := head_cons 0 n
    have hne : b ≠ 0xc2 := by omega
    have hread := readHead_head 0 n t hn
    rw [hh] at hread ⊢
    simp only [List.cons_append, readInt, if_neg hne]
    rw [← List.cons_append, hread]
  · simp [readInt, readBstr_bstr, beVal_minimalBe]

/-- BR11. Given two serialised byte strings with rests that concatenate equally; when compared;
then strings and rests are equal. -/
theorem bstr_cancel {a b t u : List Nat} (h : bstr a ++ t = bstr b ++ u) : a = b ∧ t = u := by
  have := congrArg readBstr h
  rw [readBstr_bstr, readBstr_bstr] at this
  simpa using this

/-- BR12. Given two serialised integers with rests that concatenate equally; when compared; then
integers and rests are equal. -/
theorem int_cancel {m n : Nat} {t u : List Nat} (h : int m ++ t = int n ++ u) : m = n ∧ t = u := by
  have := congrArg readInt h
  rw [readInt_int, readInt_int] at this
  simpa using this

/-! ## Separation -/

/-- A State or Active preimage. -/
def IdentityPreimage : AH.Preimage → Prop
  | .state _ | .active _ _ => True
  | _ => False

/-- BR13. Given a seed; when its State preimage is serialised; then the bytes are constructor 0
around the seed's output reference. -/
theorem code_state (seed : Singular.OutRef) : code (.state seed) =
    [0xd8, 121, 0x9f, 0xd8, 121, 0x9f] ++ bstr (unpack seed.tx) ++ int seed.index ++ [0xff, 0xff] := by
  simp [code, outRef, constr]

/-- BR14. Given a registry and a key; when their Active preimage is serialised; then the bytes
are constructor 1 around the registry identity and the key. -/
theorem code_active (r : Singular.TokenId) (key : Singular.Key) : code (.active r key) =
    [0xd8, 122, 0x9f, 0xd8, 121, 0x9f] ++ bstr (unpack r.policy) ++ bstr (unpack r.name) ++
      [0xff] ++ bstr (unpack key) ++ [0xff] := by
  simp [code, registry, constr]

/-- BC1. Given two State or Active preimages; when serialised by the concrete
codec; then equal bytes mean equal preimages, field by field: transaction id
and output index of the seed, or policy and name of the registry and the key. -/
theorem code_injective_on_identity (a b : AH.Preimage) (ha : IdentityPreimage a)
    (hb : IdentityPreimage b) (h : code a = code b) : a = b := by
  cases a <;> cases b <;> simp only [IdentityPreimage] at ha hb
  · rename_i s s'
    rw [code_state, code_state] at h
    simp only [List.append_assoc, List.cons_append, List.nil_append, List.cons.injEq,
      true_and] at h
    obtain ⟨htx, h⟩ := bstr_cancel h
    obtain ⟨hix, -⟩ := int_cancel h
    cases s; cases s'
    obtain rfl := unpack_injective htx
    subst hix; rfl
  · rw [code_state, code_active] at h; simp at h
  · rw [code_active, code_state] at h; simp at h
  · rename_i r k r' k'
    rw [code_active, code_active] at h
    simp only [List.append_assoc, List.cons_append, List.nil_append, List.cons.injEq,
      true_and] at h
    obtain ⟨hp, h⟩ := bstr_cancel h
    obtain ⟨hn, h⟩ := bstr_cancel h
    simp only [List.cons.injEq, true_and] at h
    obtain ⟨hk, -⟩ := bstr_cancel h
    cases r; cases r'
    obtain rfl := unpack_injective hp
    obtain rfl := unpack_injective hn
    obtain rfl := unpack_injective hk
    rfl

/-- BC2. Given any interpretation built from the concrete bytes and any two
consumer contexts; when serialising their identity domain (both State and both
Active preimages); then the finite encoding premise of the consumer statements
holds. No assumption is added. -/
theorem finiteEncoding (decode : AH.PublishedRelease → Nat → Option DecodedDatum)
    (c d : Context) :
    AH.FiniteEncoding (interpretation decode).code
      (identityDomain (interpretation decode) c d) := by
  intro a ha b hb h
  have hi : ∀ x ∈ identityDomain (interpretation decode) c d, IdentityPreimage x := by
    intro x hx
    simp only [identityDomain, List.mem_cons, List.not_mem_nil, or_false] at hx
    rcases hx with rfl | rfl | rfl | rfl <;> trivial
  exact code_injective_on_identity a b (hi a ha) (hi b hb) h

/-- Digest collision freedom of BLAKE2b-256 over a finite preimage domain: the
one explicit cryptographic assumption of the concrete bytes. -/
def DigestCollisionFree (domain : List AH.Preimage) : Prop :=
  ∀ a ∈ domain, ∀ b ∈ domain, blake2b256 (code a) = blake2b256 (code b) → code a = code b

/-- BC3. Given BLAKE2b-256 digest collision freedom over the identity domain;
when names are the carried digests of the serialised preimages; then the
finite collision premise of the consumer statements holds. The premise is not
discharged: a 256-bit digest of unbounded inputs is not injective. -/
theorem finiteCollisionFree (decode : AH.PublishedRelease → Nat → Option DecodedDatum)
    (c d : Context)
    (digest : DigestCollisionFree (identityDomain (interpretation decode) c d)) :
    AH.FiniteCollisionFree (interpretation decode).hash (interpretation decode).code
      (identityDomain (interpretation decode) c d) := by
  intro a ha b hb h
  exact digest a ha b hb (pack_injective (blake2b256_bytes _) (blake2b256_bytes _) h)

/-- BC4. Given two AIDs; when taking their registry keys; then the keys are
the AIDs' qualified CESR text bytes and distinct AIDs have distinct keys. -/
theorem keyOf_cesr (text : String) : unpack (keyOf (aidOfCesr text)) = utf8 text ∧
    ∀ a b : AID, keyOf a = keyOf b → a = b := by
  refine ⟨unpack_pack _ ?_, fun _ _ h => h⟩
  intro b hb
  simp only [utf8, List.mem_map] at hb
  obtain ⟨u, _, rfl⟩ := hb
  exact u.toNat_lt

/-- BC5. Given the concrete interpretation, one registry and two different
AIDs, and digest collision freedom over their identity domain; when deriving
representative assets; then they differ. -/
theorem different_aids_distinct (decode : AH.PublishedRelease → Nat → Option DecodedDatum)
    (c d : Context) (sameRegistry : registryAsset (interpretation decode) c =
      registryAsset (interpretation decode) d)
    (aids : c.aid ≠ d.aid)
    (digest : DigestCollisionFree (identityDomain (interpretation decode) c d)) :
    representativeAsset (interpretation decode) c ≠ representativeAsset (interpretation decode) d :=
  different_encoded_keys_distinct _ c d sameRegistry aids (finiteEncoding decode c d)
    (finiteCollisionFree decode c d digest)

/-- BC6. Given the concrete interpretation and two different seeds, and digest
collision freedom over their identity domain; when deriving registry and
representative assets; then both differ. -/
theorem different_seeds_distinct_bytes (decode : AH.PublishedRelease → Nat → Option DecodedDatum)
    (c d : Context) (seeds : c.seed ≠ d.seed)
    (digest : DigestCollisionFree (identityDomain (interpretation decode) c d)) :
    registryAsset (interpretation decode) c ≠ registryAsset (interpretation decode) d ∧
    representativeAsset (interpretation decode) c ≠ representativeAsset (interpretation decode) d :=
  different_seeds_distinct _ c d seeds (finiteEncoding decode c d)
    (finiteCollisionFree decode c d digest)

/-- BC7. Given the concrete interpretation, a consistent rival seed's singleton
active asset and digest collision freedom over the two contexts' identity
domain; when checked against the consumer's fixed context; then refuse. -/
theorem rival_seed_refused_bytes (decode : AH.PublishedRelease → Nat → Option DecodedDatum)
    (c rival : Context) (e : Environment) (p : Params) (now : Slot) (o : AH.ObservedOutput)
    (n : Nat) (seeds : c.seed ≠ rival.seed)
    (assets : o.assets = [(representativeAsset (interpretation decode) rival, n)])
    (digest : DigestCollisionFree (identityDomain (interpretation decode) c rival)) :
    ¬ consumableHolding (interpretation decode) c e p now o :=
  rival_seed_refused _ c rival e p now o n seeds assets (finiteEncoding decode c rival)
    (finiteCollisionFree decode c rival digest)

end CardanoKeri.ConsumerIdentity.Bytes
