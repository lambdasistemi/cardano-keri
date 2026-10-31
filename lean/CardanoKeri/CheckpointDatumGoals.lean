import CardanoKeri.CheckpointDatum

/-! Laws of the checkpoint datum and its decoder (#498).

Serialisation: every `Data` is read back from its serialisation, with any rest
left untouched, and every serialised byte is a byte, so the raw carrier is
faithful. Layout: every datum written for a state with an output decodes to
that state's datum facts, and the decoder accepts nothing else, which refuses
every malformed shape. Consumer: with this decoder in the concrete #489
interpretation, a holding carrying the written datum is accepted exactly when
the written state is consumable, funded pools included. -/
namespace CardanoKeri.CheckpointDatum
open CardanoKeri.Checkpoint
open CardanoKeri.ConsumerIdentity
open CardanoKeri.ConsumerIdentity.Bytes

/-! ## Reading back the serialisation -/

/-- Given fuel above a bound; when inspected; then it is a successor whose predecessor is at least the bound. -/
theorem fuel_succ {fuel n : Nat} (h : n + 1 ≤ fuel) : ∃ f, fuel = f + 1 ∧ n ≤ f :=
  ⟨fuel - 1, by omega, by omega⟩

/-- Given a CBOR head of a major type below 7 and any rest; when written; then the first byte is
not the break byte. -/
theorem head_first (m n : Nat) (hm : m < 7) (rest : List Nat) :
    ∃ b r, head m n ++ rest = b :: r ∧ b ≠ 0xff := by
  obtain ⟨b, r, hh, hmaj, _⟩ := head_cons m n
  exact ⟨b, r ++ rest, by simp [hh], by omega⟩

/-- Given any `Data`; when serialised; then it is not empty and does not start with the break
byte, so a list or map reader never mistakes an item for its end. -/
theorem cbor_first (d : Data) : ∃ b r, cbor d = b :: r ∧ b ≠ 0xff := by
  cases d with
  | constr i fs =>
    simp only [cbor, constrTag]
    split
    · exact head_first 6 _ (by omega) _
    split
    · exact head_first 6 _ (by omega) _
    · simp only [List.append_assoc]; exact head_first 6 _ (by omega) _
  | map es =>
    simp only [cbor]
    split
    · exact head_first 5 _ (by omega) _
    · exact ⟨0xbf, _, rfl, by decide⟩
  | list xs =>
    simp only [cbor, wrapList]
    split
    · exact ⟨0x80, _, rfl, by decide⟩
    · exact ⟨0x9f, _, rfl, by decide⟩
  | int n =>
    cases n with
    | ofNat n =>
      simp only [cbor, intBytes, Bytes.int]
      split
      · simpa using head_first 0 n (by omega) []
      · exact ⟨0xc2, _, rfl, by decide⟩
    | negSucc n =>
      simp only [cbor, intBytes]
      split
      · simpa using head_first 1 n (by omega) []
      · exact ⟨0xc3, _, rfl, by decide⟩
  | bytes bs =>
    simp only [cbor, bstr]
    split
    · exact head_first 2 _ (by omega) _
    · exact ⟨0x5f, _, rfl, by decide⟩

/-- Given a CBOR head of major type `m` below 7 and argument below 2^64, and any rest; when read
by one step of the item reader; then the reader dispatches on that major type and argument. -/
theorem parse_head (fuel m n : Nat) (t : List Nat) (hm : m < 7) (hn : n < 18446744073709551616) :
    parse (fuel + 1) (head m n ++ t) =
      if m = 0 then some (.int n, t)
      else if m = 1 then some (.int (Int.negSucc n), t)
      else if m = 2 then (if n ≤ t.length then some (.bytes (t.take n), t.drop n) else none)
      else if m = 4 then (parseCount fuel n t).map fun p => (.list p.1, p.2)
      else if m = 5 then (parseEntries fuel n t).map fun p => (.map p.1, p.2)
      else if m = 6 then
        if n = 2 then (readBstr t).map fun p => (.int (beVal p.1), p.2)
        else if n = 3 then (readBstr t).map fun p => (.int (Int.negSucc (beVal p.1)), p.2)
        else if 121 ≤ n ∧ n < 128 then
          match parse fuel t with
          | some (.list fs, r') => some (.constr (n - 121) fs, r')
          | _ => none
        else if 1280 ≤ n ∧ n < 1401 then
          match parse fuel t with
          | some (.list fs, r') => some (.constr (n - 1280 + 7) fs, r')
          | _ => none
        else if n = 102 then
          match parse fuel t with
          | some (.list [.int (.ofNat i), .list fs], r') => some (.constr i fs, r')
          | _ => none
        else none
      else none := by
  obtain ⟨b, r, hh, hmaj, hai⟩ := head_cons m n
  have hread := readHead_head m n t hn
  rw [hh] at hread ⊢
  have h1 : b ≠ 0x5f := by omega
  have h2 : b ≠ 0x9f := by omega
  have h3 : b ≠ 0xbf := by omega
  simp only [List.cons_append, parse, if_neg h1, if_neg h2, if_neg h3]
  rw [← List.cons_append, hread]
  rfl

/-- Given a signed integer and any rest; when serialised and read with enough fuel; then the
integer and the rest return. -/
theorem parse_intBytes (n : Int) (fuel : Nat) (t : List Nat) (h : (intBytes n).length ≤ fuel) :
    parse fuel (intBytes n ++ t) = some (.int n, t) := by
  cases n with
  | ofNat n =>
    simp only [intBytes, Bytes.int] at h ⊢
    split
    · rename_i hn
      rw [if_pos hn] at h
      obtain ⟨b, r, hh, _, _⟩ := head_cons 0 n
      obtain ⟨f, rfl, _⟩ := fuel_succ (n := r.length) (by rw [hh] at h; simpa using h)
      rw [parse_head f 0 n t (by omega) hn]
      simp
    · rename_i hn
      rw [if_neg hn] at h
      obtain ⟨f, rfl, _⟩ := fuel_succ (n := (bstr (minimalBe n)).length) (by simpa [Nat.add_comm] using h)
      have hread := readHead_head 6 2 (bstr (minimalBe n) ++ t) (by omega)
      have hh : head 6 2 = [0xc2] := by decide
      rw [hh] at hread
      simp only [List.cons_append, List.nil_append, parse, List.append_assoc]
      simp only [show (0xc2 : Nat) ≠ 0x5f by decide, show (0xc2 : Nat) ≠ 0x9f by decide,
        show (0xc2 : Nat) ≠ 0xbf by decide, if_false]
      rw [← List.singleton_append, hread]
      simp [readBstr_bstr, beVal_minimalBe]
  | negSucc n =>
    simp only [intBytes] at h ⊢
    split
    · rename_i hn
      rw [if_pos hn] at h
      obtain ⟨b, r, hh, _, _⟩ := head_cons 1 n
      obtain ⟨f, rfl, _⟩ := fuel_succ (n := r.length) (by rw [hh] at h; simpa using h)
      rw [parse_head f 1 n t (by omega) hn]
      simp
    · rename_i hn
      rw [if_neg hn] at h
      obtain ⟨f, rfl, _⟩ := fuel_succ (n := (bstr (minimalBe n)).length) (by simpa [Nat.add_comm] using h)
      have hread := readHead_head 6 3 (bstr (minimalBe n) ++ t) (by omega)
      have hh : head 6 3 = [0xc3] := by decide
      rw [hh] at hread
      simp only [List.cons_append, List.nil_append, parse, List.append_assoc]
      simp only [show (0xc3 : Nat) ≠ 0x5f by decide, show (0xc3 : Nat) ≠ 0x9f by decide,
        show (0xc3 : Nat) ≠ 0xbf by decide, if_false]
      rw [← List.singleton_append, hread]
      simp [readBstr_bstr, beVal_minimalBe]

/-- Given a byte string and any rest; when serialised and read with enough fuel; then the
string and the rest return. -/
theorem parse_bstr (bs : List Nat) (fuel : Nat) (t : List Nat) (h : (bstr bs).length ≤ fuel) :
    parse fuel (bstr bs ++ t) = some (.bytes bs, t) := by
  unfold bstr at h ⊢
  split
  · rename_i hs
    rw [if_pos hs] at h
    obtain ⟨b, r, hh, _, _⟩ := head_cons 2 bs.length
    obtain ⟨f, rfl, _⟩ := fuel_succ (n := r.length + bs.length)
      (by rw [hh] at h; simp at h; omega)
    rw [List.append_assoc, parse_head f 2 bs.length (bs ++ t) (by omega) (by omega)]
    simp
  · rename_i hs
    rw [if_neg hs] at h
    obtain ⟨f, rfl, _⟩ := fuel_succ (n := (chunks bs).length + 1) (by simp at h; omega)
    simp only [List.append_assoc, List.cons_append, List.nil_append, parse, if_pos rfl]
    rw [readChunks_chunks]
    · rfl
    · have := chunks_length bs
      simp; omega

/-- Given a list of items whose serialisation followed by a break byte is read back with any
enough fuel; when the list is serialised and read; then the list and the rest return. -/
theorem parse_wrapList (xs : List Data) (fuel : Nat) (t : List Nat)
    (h : (wrapList xs.isEmpty (cborItems xs)).length ≤ fuel)
    (items : ∀ f, (cborItems xs).length + 1 ≤ f →
      parseUntilBreak f (cborItems xs ++ 0xff :: t) = some (xs, t)) :
    parse fuel (wrapList xs.isEmpty (cborItems xs) ++ t) = some (.list xs, t) := by
  cases xs with
  | nil =>
    obtain ⟨f, rfl, _⟩ := fuel_succ (fuel := fuel) (n := 0) (by simpa [wrapList] using h)
    have hh : head 4 0 = [0x80] := by decide
    simp only [wrapList, List.isEmpty_nil, if_true]
    rw [← hh, parse_head f 4 0 t (by omega) (by omega)]
    simp [parseCount]
  | cons x xs =>
    simp only [wrapList, List.isEmpty_cons, Bool.false_eq_true, if_false] at h ⊢
    obtain ⟨f, rfl, hf⟩ := fuel_succ (n := (cborItems (x :: xs)).length + 1) (by simp at h; omega)
    simp only [List.append_assoc, List.cons_append, List.nil_append, parse,
      show (0x9f : Nat) ≠ 0x5f by decide, if_false, if_true]
    rw [items f hf]
    rfl

/-- Given a constructor whose fields' serialisation followed by a break byte is read back with
any enough fuel; when serialised and read; then the constructor and the rest return. Every
index takes its own tag form: 121–127, 1280–1400, or 102 over `[index, fields]`. -/
theorem parse_constr (i : Nat) (fs : List Data) (fuel : Nat) (t : List Nat)
    (h : (cbor (.constr i fs)).length ≤ fuel)
    (items : ∀ f, (cborItems fs).length + 1 ≤ f →
      parseUntilBreak f (cborItems fs ++ 0xff :: t) = some (fs, t)) :
    parse fuel (cbor (.constr i fs) ++ t) = some (.constr i fs, t) := by
  have hL : 1 ≤ (wrapList fs.isEmpty (cborItems fs)).length := by
    unfold wrapList; split <;> simp
  have fields := fun f hf => parse_wrapList fs f t hf items
  simp only [cbor, constrTag] at h ⊢
  split
  · rename_i hi
    rw [if_pos hi] at h
    obtain ⟨b, r, hh, _, _⟩ := head_cons 6 (121 + i)
    obtain ⟨f, rfl, hf⟩ := fuel_succ (n := r.length + (wrapList fs.isEmpty (cborItems fs)).length)
      (by rw [hh] at h; simp at h; omega)
    rw [List.append_assoc, parse_head f 6 (121 + i) _ (by omega) (by omega),
      if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega),
      if_pos rfl, if_neg (by omega), if_neg (by omega), if_pos (by omega), fields f (by omega)]
    simp
  split
  · rename_i hi hi'
    rw [if_neg hi, if_pos hi'] at h
    obtain ⟨b, r, hh, _, _⟩ := head_cons 6 (1280 + (i - 7))
    obtain ⟨f, rfl, hf⟩ := fuel_succ (n := r.length + (wrapList fs.isEmpty (cborItems fs)).length)
      (by rw [hh] at h; simp at h; omega)
    rw [List.append_assoc, parse_head f 6 (1280 + (i - 7)) _ (by omega) (by omega),
      if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega),
      if_pos rfl, if_neg (by omega), if_neg (by omega), if_neg (by omega), if_pos (by omega),
      fields f (by omega)]
    have : 1280 + (i - 7) - 1280 + 7 = i := by omega
    simp; omega
  · rename_i hi hi'
    rw [if_neg hi, if_neg hi'] at h
    have hh : head 6 102 = [0xd8, 102] := by decide
    have h82 : [0x82] = head 4 2 := by decide
    rw [hh] at h ⊢
    simp at h
    obtain ⟨f, rfl, hf⟩ := fuel_succ (fuel := fuel) (n := 1 + 1 + (intBytes i).length +
      (wrapList fs.isEmpty (cborItems fs)).length) (by omega)
    have hhead : [0xd8, 102] ++ [0x82] ++ intBytes ↑i ++ wrapList fs.isEmpty (cborItems fs) ++ t =
        head 6 102 ++ (head 4 2 ++ (intBytes ↑i ++ (wrapList fs.isEmpty (cborItems fs) ++ t))) := by
      rw [hh, ← h82]; simp
    have hint : 1 ≤ (intBytes ↑i).length := by
      obtain ⟨b, r, hb, _⟩ := cbor_first (.int i)
      simp only [cbor] at hb
      simp [hb]
    obtain ⟨g, rfl, hg⟩ := fuel_succ (fuel := f) (n := 1 + (intBytes i).length +
      (wrapList fs.isEmpty (cborItems fs)).length) (by omega)
    obtain ⟨g', rfl, hg'⟩ := fuel_succ (fuel := g) (n := (intBytes i).length - 1 +
      (wrapList fs.isEmpty (cborItems fs)).length) (by omega)
    obtain ⟨g'', rfl, hg''⟩ := fuel_succ (fuel := g')
      (n := (wrapList fs.isEmpty (cborItems fs)).length) (by omega)
    rw [hhead, parse_head (g'' + 1 + 1 + 1) 6 102 _ (by omega) (by omega),
      if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega),
      if_pos rfl, if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega),
      if_pos rfl, parse_head (g'' + 1 + 1) 4 2 _ (by omega) (by omega),
      if_neg (by omega), if_neg (by omega), if_neg (by omega), if_pos rfl]
    simp only [parseCount]
    rw [parse_intBytes (↑i) (g'' + 1) _ (by omega)]
    simp only [parseCount]
    rw [fields g'' hg'']
    rfl

/-- Given a map whose entries are read back with any enough fuel, counted or up to a break
byte; when serialised and read; then the map and the rest return. -/
theorem parse_map (es : List (Data × Data)) (fuel : Nat) (t : List Nat)
    (h : (cbor (.map es)).length ≤ fuel)
    (entries : ∀ f, (cborEntries es).length ≤ f →
      parseEntries f es.length (cborEntries es ++ t) = some (es, t))
    (entriesBreak : ∀ f, (cborEntries es).length + 1 ≤ f →
      parseEntriesUntilBreak f (cborEntries es ++ 0xff :: t) = some (es, t)) :
    parse fuel (cbor (.map es) ++ t) = some (.map es, t) := by
  simp only [cbor] at h ⊢
  split
  · rename_i hn
    rw [if_pos hn] at h
    obtain ⟨b, r, hh, _, _⟩ := head_cons 5 es.length
    obtain ⟨f, rfl, hf⟩ := fuel_succ (n := r.length + (cborEntries es).length)
      (by rw [hh] at h; simp at h; omega)
    rw [List.append_assoc, parse_head f 5 es.length _ (by omega) hn,
      if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega), if_pos rfl,
      entries f (by omega)]
    rfl
  · rename_i hn
    rw [if_neg hn] at h
    obtain ⟨f, rfl, hf⟩ := fuel_succ (n := (cborEntries es).length + 1) (by simp at h; omega)
    simp only [List.append_assoc, List.cons_append, List.nil_append, parse,
      show (0xbf : Nat) ≠ 0x5f by decide, show (0xbf : Nat) ≠ 0x9f by decide, if_false, if_true]
    rw [entriesBreak f hf]
    rfl

mutual
/-- Given any `Data`, any rest and fuel of at least its serialisation's length; when serialised
and read; then the `Data` and the rest return. -/
theorem parse_cbor (d : Data) (fuel : Nat) (t : List Nat) (h : (cbor d).length ≤ fuel) :
    parse fuel (cbor d ++ t) = some (d, t) :=
  match d, h with
  | .constr i fs, h =>
    parse_constr i fs fuel t h fun f hf => parseUntilBreak_cborItems fs f t hf
  | .map es, h =>
    parse_map es fuel t h (fun f hf => parseEntries_cborEntries es f t hf)
      (fun f hf => parseEntriesUntilBreak_cborEntries es f t hf)
  | .list xs, h => by
    simpa [cbor] using parse_wrapList xs fuel t (by simpa [cbor] using h)
      fun f hf => parseUntilBreak_cborItems xs f t hf
  | .int n, h => parse_intBytes n fuel t h
  | .bytes bs, h => parse_bstr bs fuel t h

/-- Given items, any rest and enough fuel; when serialised back to back with a break byte and
read; then the items and the rest return. -/
theorem parseUntilBreak_cborItems (xs : List Data) (fuel : Nat) (t : List Nat)
    (h : (cborItems xs).length + 1 ≤ fuel) :
    parseUntilBreak fuel (cborItems xs ++ 0xff :: t) = some (xs, t) :=
  match xs, h with
  | [], h => by
    obtain ⟨f, rfl, _⟩ := fuel_succ h
    simp [cborItems, parseUntilBreak]
  | d :: ds, h => by
    obtain ⟨b, r, hb, hne⟩ := cbor_first d
    have hd := parse_cbor d (fuel - 1) (cborItems ds ++ 0xff :: t)
      (by simp [cborItems] at h; omega)
    have hds := parseUntilBreak_cborItems ds (fuel - 1) t
      (by simp [cborItems, hb] at h; omega)
    obtain ⟨f, rfl, _⟩ := fuel_succ (fuel := fuel) (n := 0) (by simp [cborItems] at h; omega)
    simp only [Nat.add_sub_cancel] at hd hds
    simp only [cborItems, List.append_assoc]
    rw [hb] at hd ⊢
    simp only [List.cons_append, parseUntilBreak, if_neg hne]
    rw [← List.cons_append, hd]
    simp [hds]

/-- Given map entries, any rest and enough fuel; when serialised and read as that many
entries; then the entries and the rest return. -/
theorem parseEntries_cborEntries (es : List (Data × Data)) (fuel : Nat) (t : List Nat)
    (h : (cborEntries es).length ≤ fuel) :
    parseEntries fuel es.length (cborEntries es ++ t) = some (es, t) :=
  match es, h with
  | [], _ => by simp [cborEntries, parseEntries]
  | (k, v) :: es, h => by
    obtain ⟨bk, rk, hbk, _⟩ := cbor_first k
    obtain ⟨bv, rv, hbv, _⟩ := cbor_first v
    have hk := parse_cbor k (fuel - 1) (cbor v ++ cborEntries es ++ t)
      (by simp [cborEntries, hbv] at h; omega)
    have hv := parse_cbor v (fuel - 1) (cborEntries es ++ t)
      (by simp [cborEntries, hbk] at h; omega)
    have hes := parseEntries_cborEntries es (fuel - 1) t
      (by simp [cborEntries, hbk, hbv] at h; omega)
    obtain ⟨f, rfl, _⟩ := fuel_succ (fuel := fuel) (n := 0) (by simp [cborEntries, hbk] at h; omega)
    simp only [Nat.add_sub_cancel, List.append_assoc] at hk hv hes
    simp only [cborEntries, List.append_assoc, List.length_cons, parseEntries]
    rw [hk]
    simp only
    rw [hv]
    simp [hes]

/-- Given map entries, any rest and enough fuel; when serialised with a break byte and read;
then the entries and the rest return. -/
theorem parseEntriesUntilBreak_cborEntries (es : List (Data × Data)) (fuel : Nat)
    (t : List Nat) (h : (cborEntries es).length + 1 ≤ fuel) :
    parseEntriesUntilBreak fuel (cborEntries es ++ 0xff :: t) = some (es, t) :=
  match es, h with
  | [], h => by
    obtain ⟨f, rfl, _⟩ := fuel_succ h
    simp [cborEntries, parseEntriesUntilBreak]
  | (k, v) :: es, h => by
    obtain ⟨bk, rk, hbk, hne⟩ := cbor_first k
    obtain ⟨bv, rv, hbv, _⟩ := cbor_first v
    have hk := parse_cbor k (fuel - 1) (cbor v ++ cborEntries es ++ 0xff :: t)
      (by simp [cborEntries, hbv] at h; omega)
    have hv := parse_cbor v (fuel - 1) (cborEntries es ++ 0xff :: t)
      (by simp [cborEntries, hbk] at h; omega)
    have hes := parseEntriesUntilBreak_cborEntries es (fuel - 1) t
      (by simp [cborEntries, hbk, hbv] at h; omega)
    obtain ⟨f, rfl, _⟩ := fuel_succ (fuel := fuel) (n := 0) (by simp [cborEntries, hbk] at h; omega)
    simp only [Nat.add_sub_cancel, List.append_assoc] at hk hv hes
    simp only [cborEntries, List.append_assoc]
    rw [hbk] at hk ⊢
    simp only [List.cons_append, parseEntriesUntilBreak, if_neg hne]
    rw [← List.cons_append, hk]
    simp only
    rw [hv]
    simp [hes]
end

/-! ## Every serialised element is a byte -/

/-! `Data` whose byte strings hold bytes only. -/
mutual
def Data.Bytewise : Data → Prop
  | .constr _ fs => itemsBytewise fs
  | .map es => entriesBytewise es
  | .list xs => itemsBytewise xs
  | .int _ => True
  | .bytes bs => Bytes bs

def itemsBytewise : List Data → Prop
  | [] => True
  | d :: ds => d.Bytewise ∧ itemsBytewise ds

def entriesBytewise : List (Data × Data) → Prop
  | [] => True
  | (k, v) :: es => k.Bytewise ∧ v.Bytewise ∧ entriesBytewise es
end

/-- Given two lists; when concatenated; then the result holds bytes only exactly when both do. -/
theorem bytes_append {a b : List Nat} : Bytes (a ++ b) ↔ Bytes a ∧ Bytes b := by
  simp only [Bytes, List.mem_append]
  exact ⟨fun h => ⟨fun x hx => h x (.inl hx), fun x hx => h x (.inr hx)⟩,
    fun h x hx => hx.elim (h.1 x) (h.2 x)⟩

/-- Given a number below 256; when it is the only element; then the list holds bytes only. -/
theorem bytes_singleton {b : Nat} (h : b < 256) : Bytes [b] := by
  intro x hx; simp at hx; omega

/-- Given any carried number; when unpacked; then every element is a byte. -/
theorem unpack_bytes (n : Nat) : Bytes (unpack n) := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    rw [unpack]
    split
    · intro b hb; simp at hb
    · intro b hb
      simp only [List.mem_cons] at hb
      rcases hb with rfl | hb
      · omega
      · exact ih _ (by omega) b hb

/-- Given a width and a number; when written big-endian; then every element is a byte. -/
theorem be_bytes (k n : Nat) : Bytes (be k n) := by
  induction k generalizing n with
  | zero => intro b hb; simp [be] at hb
  | succ k ih => simp only [be]; exact bytes_append.mpr ⟨ih _, bytes_singleton (by omega)⟩

/-- Given a major type below 7 and any argument; when the CBOR head is written; then every element is a byte. -/
theorem head_bytes (m n : Nat) (hm : m < 7) : Bytes (head m n) := by
  unfold head
  split
  · exact bytes_singleton (by omega)
  split
  · exact bytes_append.mpr ⟨bytes_singleton (by omega), be_bytes _ _⟩
  split
  · exact bytes_append.mpr ⟨bytes_singleton (by omega), be_bytes _ _⟩
  split
  · exact bytes_append.mpr ⟨bytes_singleton (by omega), be_bytes _ _⟩
  · exact bytes_append.mpr ⟨bytes_singleton (by omega), be_bytes _ _⟩

/-- Given a byte string; when chunked; then every element of the chunks is a byte. -/
theorem chunks_bytes (bs : List Nat) (h : Bytes bs) : Bytes (chunks bs) := by
  induction hl : bs.length using Nat.strongRecOn generalizing bs with
  | ind n ih =>
    rw [chunks]
    split
    · intro b hb; simp at hb
    · rename_i hb
      have hlen : 0 < bs.length := List.length_pos_iff.mpr hb
      refine bytes_append.mpr ⟨bytes_append.mpr ⟨head_bytes 2 _ (by omega), ?_⟩, ?_⟩
      · exact fun x hx => h x (List.mem_of_mem_take hx)
      · exact ih _ (by simp; omega) (bs.drop 64) (fun x hx => h x (List.mem_of_mem_drop hx)) rfl

/-- Given a byte string; when serialised; then every element is a byte. -/
theorem bstr_bytes (bs : List Nat) (h : Bytes bs) : Bytes (bstr bs) := by
  unfold bstr
  split
  · exact bytes_append.mpr ⟨head_bytes 2 _ (by omega), h⟩
  · exact bytes_append.mpr ⟨bytes_append.mpr ⟨bytes_singleton (by omega), chunks_bytes bs h⟩,
      bytes_singleton (by omega)⟩

/-- Given a number; when written big-endian without leading zeros; then every element is a byte. -/
theorem minimalBe_bytes (n : Nat) : Bytes (minimalBe n) := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    rw [minimalBe]
    split
    · intro b hb; simp at hb
    · exact bytes_append.mpr ⟨ih _ (by omega), bytes_singleton (by omega)⟩

/-- Given a signed integer; when serialised; then every element is a byte. -/
theorem intBytes_bytes (n : Int) : Bytes (intBytes n) := by
  cases n with
  | ofNat n =>
    simp only [intBytes, Bytes.int]
    split
    · exact head_bytes 0 n (by omega)
    · exact bytes_append.mpr ⟨bytes_singleton (by omega), bstr_bytes _ (minimalBe_bytes n)⟩
  | negSucc n =>
    simp only [intBytes]
    split
    · exact head_bytes 1 n (by omega)
    · exact bytes_append.mpr ⟨bytes_singleton (by omega), bstr_bytes _ (minimalBe_bytes n)⟩

/-- Given a constructor index; when its tag is written; then every element is a byte. -/
theorem constrTag_bytes (i : Nat) : Bytes (constrTag i) := by
  unfold constrTag
  split
  · exact head_bytes 6 _ (by omega)
  split
  · exact head_bytes 6 _ (by omega)
  · exact bytes_append.mpr ⟨bytes_append.mpr ⟨head_bytes 6 _ (by omega), bytes_singleton (by omega)⟩,
      intBytes_bytes i⟩

/-- Given list items that are bytes; when wrapped as a list; then every element is a byte. -/
theorem wrapList_bytes (e : Bool) (items : List Nat) (h : Bytes items) :
    Bytes (wrapList e items) := by
  unfold wrapList
  split
  · exact bytes_singleton (by omega)
  · exact bytes_append.mpr ⟨bytes_append.mpr ⟨bytes_singleton (by omega), h⟩,
      bytes_singleton (by omega)⟩

mutual
/-- Given `Data` whose byte strings hold bytes; when serialised; then every element is a byte. -/
theorem cbor_bytes (d : Data) (h : d.Bytewise) : Bytes (cbor d) :=
  match d, h with
  | .constr i fs, h => by
    simp only [cbor]
    exact bytes_append.mpr ⟨constrTag_bytes i,
      wrapList_bytes _ _ (cborItems_bytes fs (by simpa [Data.Bytewise] using h))⟩
  | .map es, h => by
    have he := cborEntries_bytes es (by simpa [Data.Bytewise] using h)
    simp only [cbor]
    split
    · exact bytes_append.mpr ⟨head_bytes 5 _ (by omega), he⟩
    · exact bytes_append.mpr ⟨bytes_append.mpr ⟨bytes_singleton (by omega), he⟩,
        bytes_singleton (by omega)⟩
  | .list xs, h => by
    simp only [cbor]
    exact wrapList_bytes _ _ (cborItems_bytes xs (by simpa [Data.Bytewise] using h))
  | .int n, _ => intBytes_bytes n
  | .bytes bs, h => bstr_bytes bs (by simpa [Data.Bytewise] using h)

/-- Given items whose byte strings hold bytes; when serialised back to back; then every element is a byte. -/
theorem cborItems_bytes (xs : List Data) (h : itemsBytewise xs) : Bytes (cborItems xs) :=
  match xs, h with
  | [], _ => by intro b hb; simp [cborItems] at hb
  | d :: ds, h => by
    simp only [itemsBytewise] at h
    simp only [cborItems]
    exact bytes_append.mpr ⟨cbor_bytes d h.1, cborItems_bytes ds h.2⟩

/-- Given map entries whose byte strings hold bytes; when serialised; then every element is a byte. -/
theorem cborEntries_bytes (es : List (Data × Data)) (h : entriesBytewise es) :
    Bytes (cborEntries es) :=
  match es, h with
  | [], _ => by intro b hb; simp [cborEntries] at hb
  | (k, v) :: es, h => by
    simp only [entriesBytewise] at h
    simp only [cborEntries]
    exact bytes_append.mpr ⟨bytes_append.mpr ⟨cbor_bytes k h.1, cbor_bytes v h.2.1⟩,
      cborEntries_bytes es h.2.2⟩
end

/-- Given any `Data`; when serialised and read as a whole byte string; then it returns. -/
theorem ofBytes?_cbor (d : Data) : ofBytes? (cbor d) = some d := by
  have h := parse_cbor d (cbor d).length [] (Nat.le_refl _)
  simp only [List.append_nil] at h
  simp [ofBytes?, h]

/-- Given `Data` whose byte strings hold bytes; when carried as a raw datum and unpacked; then
its serialisation returns. -/
theorem unpack_raw (d : Data) (h : d.Bytewise) : unpack (raw d) = cbor d :=
  unpack_pack _ (cbor_bytes d h)

/-- Given `Data` whose byte strings hold bytes and any release; when its raw carrier is decoded;
then the result is the `Data`-level decoder's. -/
theorem decode_raw (r : AH.PublishedRelease) (d : Data) (h : d.Bytewise) :
    decode r (raw d) = decodeData d := by
  simp [decode, unpack_raw d h, ofBytes?_cbor]

/-! ## The layout: written datums decode to their facts -/

/-- Given a reader that returns what a writer wrote; when it reads a whole list the writer wrote; then the list returns. -/
theorem mapM_map_inverse {α β : Type} {f : α → Option β} {g : β → α}
    (h : ∀ b, f (g b) = some b) (bs : List β) : (bs.map g).mapM f = some bs := by
  induction bs with
  | nil => rfl
  | cons b bs ih => simp [List.mapM_cons, h, ih]

/-- Given a reader whose every success reads back what a writer writes; when it reads a whole list successfully; then the list is the writer's output of the result. -/
theorem mapM_some_inverse {α β : Type} {f : α → Option β} {g : β → α}
    (h : ∀ a b, f a = some b → a = g b) :
    ∀ (as : List α) (bs : List β), as.mapM f = some bs → as = bs.map g
  | [], bs, hm => by simp at hm; subst hm; rfl
  | a :: as, bs, hm => by
    simp only [List.mapM_cons, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at hm
    obtain ⟨b, hb, bs', hbs, rfl⟩ := hm
    simp [h a b hb, mapM_some_inverse h as bs' hbs]

/-- Given a Boolean; when written and read; then it returns. -/
theorem bool?_boolData (b : Bool) : bool? (boolData b) = some b := by cases b <;> rfl

/-- Given a weight; when written and read; then it returns. -/
theorem weight?_weightData (w : Weight) : weight? (weightData w) = some w := rfl

/-- Given a threshold; when written and read; then it returns. -/
theorem threshold?_thresholdData (t : Threshold) : threshold? (thresholdData t) = some t := by
  cases t with
  | unweighted m => rfl
  | weighted cs =>
    simp only [thresholdData, threshold?]
    rw [mapM_map_inverse (g := fun c => Data.list (c.map weightData))
      (fun c => mapM_map_inverse weight?_weightData c)]
    rfl

/-- Given a list of byte strings; when written and read; then it returns. -/
theorem bytesList?_bytesListData (ks : List (List Nat)) :
    bytesList? (bytesListData ks) = some ks :=
  mapM_map_inverse (f := bytesShape?) (g := Data.bytes) (fun _ => rfl) ks

/-- Given key material; when written and read; then it returns. -/
theorem keyMaterial?_keyMaterialData (k : KeyMaterial) :
    keyMaterial? (keyMaterialData k) = some k := by
  simp [keyMaterialData, keyMaterial?, bytesList?_bytesListData, threshold?_thresholdData]

/-- Given a carried number; when its bytes are read as a byte string; then the bytes return. -/
theorem byteString?_unpack (n : Nat) : byteString? (.bytes (unpack n)) = some (unpack n) := by
  have h : (unpack n).all (· < 256) = true := by
    simpa [List.all_eq_true] using unpack_bytes n
  simp [byteString?, h]

/-- Given any AID, key material and state with an output; when its version 2 datum is written
and decoded; then the decoder returns that AID and the state's datum facts: the state itself,
with the pool, which the datum does not carry, at zero. -/
theorem decodeData_datum (aid : AID) (k : KeyMaterial) (s : State) (d : Data)
    (h : datum aid k s = some d) : decodeData d = some ⟨aid, s.datumFacts⟩ := by
  cases s with
  | present l =>
    simp only [datum, Option.some.injEq] at h
    subst h
    simp [decodeData, byteString?_unpack, nat?, bool?_boolData, keyMaterial?_keyMaterialData,
      pack_unpack, State.datumFacts]
  | terminationPending h' =>
    simp only [datum, Option.some.injEq] at h
    subst h
    simp [decodeData, byteString?_unpack, nat?, keyMaterial?_keyMaterialData, pack_unpack,
      State.datumFacts]
  | absent => simp [datum] at h
  | convicted => simp [datum] at h

/-! ## The decoder accepts nothing else -/

/-- Given `Data` read as a Boolean; when inspected; then it is that Boolean as written. -/
theorem bool?_some {x : Data} {b : Bool} (h : bool? x = some b) : x = boolData b := by
  unfold bool? at h; split at h <;> simp_all [boolData]

/-- Given `Data` read as a non-negative integer; when inspected; then it is that integer as written. -/
theorem nat?_some {x : Data} {n : Nat} (h : nat? x = some n) : x = .int n := by
  unfold nat? at h; split at h <;> simp_all

/-- Given `Data` read as a byte string; when inspected; then it is that byte string and every element is a byte. -/
theorem byteString?_some {x : Data} {bs : List Nat} (h : byteString? x = some bs) :
    x = .bytes bs ∧ Bytes bs := by
  unfold byteString? at h
  split at h
  · split at h
    · rename_i hall
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨rfl, by simpa [List.all_eq_true] using hall⟩
    · simp at h
  · simp at h

/-- Given `Data` read as a list of byte strings; when inspected; then it is that list as written. -/
theorem bytesList?_some {x : Data} {ks : List (List Nat)} (h : bytesList? x = some ks) :
    x = bytesListData ks := by
  unfold bytesList? at h
  split at h
  · simp only [bytesListData]
    congr
    exact mapM_some_inverse (fun a b hab => by unfold bytesShape? at hab; split at hab <;> simp_all) _ _ h
  · simp at h

/-- Given `Data` read as a threshold; when inspected; then it is that threshold as written. -/
theorem threshold?_some {x : Data} {t : Threshold} (h : threshold? x = some t) :
    x = thresholdData t := by
  unfold threshold? at h
  split at h
  · simp at h; subst h; rfl
  · simp only [Option.map_eq_some_iff] at h
    obtain ⟨cs, hcs, rfl⟩ := h
    simp only [thresholdData]
    congr
    refine mapM_some_inverse (fun a b hab => ?_) _ _ hcs
    unfold clause? at hab
    split at hab
    · congr
      refine mapM_some_inverse (fun w v hw => ?_) _ _ hab
      unfold weight? at hw
      split at hw
      · simp only [Option.some.injEq] at hw; subst hw; rfl
      · simp at hw
    · simp at hab
  · simp at h

/-- Given `Data` read as key material; when inspected; then it is that key material as written. -/
theorem keyMaterial?_some {x : Data} {k : KeyMaterial} (h : keyMaterial? x = some k) :
    x = keyMaterialData k := by
  unfold keyMaterial? at h
  split at h
  · simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at h
    obtain ⟨ck, hck, ct, hct, nk, hnk, nt, hnt, ws, hws, rfl⟩ := h
    simp [keyMaterialData, bytesList?_some hck, threshold?_some hct, bytesList?_some hnk,
      threshold?_some hnt, bytesList?_some hws]
  · simp at h

/-- Given any `Data` the decoder accepts; when inspected; then it is exactly the version 2
datum written for the decoded AID, the decoded state and some key material, and the decoded
state is its own datum facts. With `decodeData_datum`, the accepted `Data` are exactly the
written datums, so every other shape is refused. -/
theorem decodeData_complete (d : Data) (r : DecodedDatum) (h : decodeData d = some r) :
    ∃ k, datum r.aid k r.state = some d ∧ r.state.datumFacts = r.state := by
  unfold decodeData at h
  split at h
  · simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at h
    obtain ⟨ab, hab, sn, hsn, ep, hep, po, hpo, fr, hfr, born, hborn, rb, hrb, k, hk, rfl⟩ := h
    obtain ⟨rfl, bab⟩ := byteString?_some hab
    obtain ⟨rfl, brb⟩ := byteString?_some hrb
    refine ⟨k, ?_, rfl⟩
    simp [datum, unpack_pack ab bab, unpack_pack rb brb, nat?_some hsn, nat?_some hep,
      bool?_some hpo, bool?_some hfr, nat?_some hborn, keyMaterial?_some hk]
  · simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at h
    obtain ⟨ab, hab, sn, hsn, ep, hep, k, hk, rfl⟩ := h
    obtain ⟨rfl, bab⟩ := byteString?_some hab
    refine ⟨k, ?_, rfl⟩
    simp [datum, unpack_pack ab bab, nat?_some hsn, nat?_some hep, keyMaterial?_some hk]
  · simp at h

/-- Given any `Data` that is no written datum; when decoded; then it is refused. -/
theorem refused_unless_written (d : Data) (h : ∀ aid k s, datum aid k s ≠ some d) :
    decodeData d = none := by
  cases hd : decodeData d with
  | none => rfl
  | some r =>
    obtain ⟨k, hk, _⟩ := decodeData_complete d r hd
    exact absurd hk (h _ _ _)

/-- Given any `Data` that is not a constructor; when decoded; then it is refused. -/
theorem not_a_constructor_refused (d : Data) (h : ∀ i fs, d ≠ .constr i fs) :
    decodeData d = none :=
  refused_unless_written d fun aid k s hd => by
    cases s <;> simp [datum] at hd <;> exact h _ _ hd.symm

/-- Given a datum of any version other than 2, version 1 included; when decoded; then it is
refused. -/
theorem wrong_version_refused (i : Nat) (fs : List Data) (hi : i ≠ 1) :
    decodeData (.constr i fs) = none :=
  refused_unless_written _ fun aid k s hd => by
    cases s <;> simp [datum] at hd <;> omega

/-- Given a version 1 datum, the layout the checkpoint validator writes today; when decoded;
then it is refused: it carries none of the consumer facts. -/
theorem version_one_refused (fs : List Data) : decodeData (.constr 0 fs) = none :=
  wrong_version_refused 0 fs (by decide)

/-- Given a version 2 datum without exactly one field; when decoded; then it is refused. -/
theorem version_arity_refused (fs : List Data) (h : fs.length ≠ 1) :
    decodeData (.constr 1 fs) = none :=
  refused_unless_written _ fun aid k s hd => by
    cases s <;> simp [datum] at hd <;> (subst hd; simp at h)

/-- Given a version 2 datum whose form is neither live (0) nor pending termination (1); when
decoded; then it is refused. -/
theorem unknown_form_refused (j : Nat) (gs : List Data) (hj : 2 ≤ j) :
    decodeData (.constr 1 [.constr j gs]) = none :=
  refused_unless_written _ fun aid k s hd => by
    cases s <;> simp [datum] at hd <;> omega

/-- Given a live datum without exactly eight fields; when decoded; then it is refused. -/
theorem live_arity_refused (gs : List Data) (h : gs.length ≠ 8) :
    decodeData (.constr 1 [.constr 0 gs]) = none :=
  refused_unless_written _ fun aid k s hd => by
    cases s <;> simp [datum] at hd <;> (subst hd; simp at h)

/-- Given a pending-termination datum without exactly four fields; when decoded; then it is
refused. -/
theorem pending_arity_refused (gs : List Data) (h : gs.length ≠ 4) :
    decodeData (.constr 1 [.constr 1 gs]) = none :=
  refused_unless_written _ fun aid k s hd => by
    cases s <;> simp [datum] at hd <;> (subst hd; simp at h)

/-- Given a live datum the decoder accepts; when its fields are inspected; then each has its
kind: AID bytes, three non-negative integers and two Booleans in their places, refund bytes
and well-shaped key material. Any field of another kind is refused. -/
theorem live_fields_typed (gs : List Data) (r : DecodedDatum)
    (h : decodeData (.constr 1 [.constr 0 gs]) = some r) :
    ∃ (aid refund : List Nat) (sn epoch bornAt : Nat) (poisoned frozen : Bool) (k : KeyMaterial),
      gs = [.bytes aid, .int sn, .int epoch, boolData poisoned, boolData frozen, .int bornAt,
        .bytes refund, keyMaterialData k] := by
  obtain ⟨k, hk, _⟩ := decodeData_complete _ r h
  cases hs : r.state with
  | present l =>
    rw [hs] at hk
    simp [datum] at hk
    exact ⟨_, _, _, _, _, _, _, _, hk.symm⟩
  | terminationPending h' => rw [hs] at hk; simp [datum] at hk
  | absent => rw [hs] at hk; simp [datum] at hk
  | convicted => rw [hs] at hk; simp [datum] at hk

/-- Given a pending-termination datum the decoder accepts; when its fields are inspected; then
each has its kind: AID bytes, two non-negative integers and well-shaped key material. -/
theorem pending_fields_typed (gs : List Data) (r : DecodedDatum)
    (h : decodeData (.constr 1 [.constr 1 gs]) = some r) :
    ∃ (aid : List Nat) (sn epoch : Nat) (k : KeyMaterial),
      gs = [.bytes aid, .int sn, .int epoch, keyMaterialData k] := by
  obtain ⟨k, hk, _⟩ := decodeData_complete _ r h
  cases hs : r.state with
  | terminationPending h' =>
    rw [hs] at hk
    simp [datum] at hk
    exact ⟨_, _, _, _, hk.symm⟩
  | present l => rw [hs] at hk; simp [datum] at hk
  | absent => rw [hs] at hk; simp [datum] at hk
  | convicted => rw [hs] at hk; simp [datum] at hk

/-! ## The raw datum -/

/-- Key material whose keys and witnesses are byte strings of bytes. -/
def KeyMaterial.Bytewise (k : KeyMaterial) : Prop :=
  Bytes k.curKeys.flatten ∧ Bytes k.nextKeys.flatten ∧ Bytes k.witnesses.flatten

/-- Given a list of byte strings of bytes; when written; then every byte string in it holds bytes. -/
theorem bytesListData_bytewise (ks : List (List Nat)) (h : Bytes ks.flatten) :
    (bytesListData ks).Bytewise := by
  simp only [bytesListData, Data.Bytewise]
  induction ks with
  | nil => simp [itemsBytewise]
  | cons k ks ih =>
    simp only [List.flatten_cons] at h
    obtain ⟨hk, hks⟩ := bytes_append.mp h
    simp only [List.map_cons, itemsBytewise, Data.Bytewise]
    exact ⟨hk, ih hks⟩

/-- Given a threshold; when written; then it holds no byte string that is not bytes. -/
theorem thresholdData_bytewise (t : Threshold) : (thresholdData t).Bytewise := by
  cases t with
  | unweighted m => simp [thresholdData, Data.Bytewise, itemsBytewise]
  | weighted cs =>
    simp only [thresholdData, Data.Bytewise, itemsBytewise, and_true]
    induction cs with
    | nil => simp [itemsBytewise]
    | cons c cs ih =>
      simp only [List.map_cons, itemsBytewise]
      refine ⟨?_, ih⟩
      simp only [Data.Bytewise]
      induction c with
      | nil => simp [itemsBytewise]
      | cons w ws ih' =>
        simp only [List.map_cons, itemsBytewise]
        exact ⟨by simp [weightData, Data.Bytewise, itemsBytewise], ih'⟩

/-- Given key material whose keys and witnesses hold bytes; when written; then every byte string in it holds bytes. -/
theorem keyMaterialData_bytewise (k : KeyMaterial) (h : k.Bytewise) :
    (keyMaterialData k).Bytewise := by
  have h1 := bytesListData_bytewise _ h.1
  have h2 := bytesListData_bytewise _ h.2.1
  have h3 := bytesListData_bytewise _ h.2.2
  have t1 := thresholdData_bytewise k.curThreshold
  have t2 := thresholdData_bytewise k.nextThreshold
  exact And.intro h1 (And.intro t1 (And.intro h2 (And.intro t2 (And.intro h3
    (And.intro trivial trivial)))))

/-- Given a Boolean; when written; then it holds no byte string that is not bytes. -/
theorem boolData_bytewise (b : Bool) : (boolData b).Bytewise := by
  cases b <;> simp [boolData, Data.Bytewise, itemsBytewise]

/-- Given a written datum whose key material holds bytes; when inspected; then every byte
string in it holds bytes. -/
theorem datum_bytewise (aid : AID) (k : KeyMaterial) (s : State) (d : Data)
    (h : datum aid k s = some d) (hk : k.Bytewise) : d.Bytewise := by
  have km := keyMaterialData_bytewise k hk
  cases s with
  | present l =>
    simp only [datum, Option.some.injEq] at h
    subst h
    simp [Data.Bytewise, itemsBytewise, unpack_bytes, km, boolData_bytewise]
  | terminationPending h' =>
    simp only [datum, Option.some.injEq] at h
    subst h
    simp [Data.Bytewise, itemsBytewise, unpack_bytes, km]
  | absent => simp [datum] at h
  | convicted => simp [datum] at h

/-- Given any AID, any state with an output and key material holding bytes; when its version 2
datum is carried as a raw application datum and decoded under any release; then the decoder
returns that AID and the state's datum facts. -/
theorem decode_written (r : AH.PublishedRelease) (aid : AID) (k : KeyMaterial) (s : State)
    (d : Data) (h : datum aid k s = some d) (hk : k.Bytewise) :
    decode r (raw d) = some ⟨aid, s.datumFacts⟩ := by
  rw [decode_raw r d (datum_bytewise aid k s d h hk), decodeData_datum aid k s d h]

/-- Given one raw datum decoded twice under one release; when the results are compared; then
they are equal. -/
theorem decode_deterministic (r : AH.PublishedRelease) (x : Nat) (a b : DecodedDatum)
    (ha : decode r x = some a) (hb : decode r x = some b) : a = b := by
  rw [ha] at hb
  exact Option.some.inj hb

/-- Given one raw datum and two releases; when decoded under each; then the results are equal:
the layout does not depend on the release at this model revision. -/
theorem decode_release_independent (r r' : AH.PublishedRelease) (x : Nat) :
    decode r x = decode r' x := rfl

/-- Given a raw datum the decoder accepts; when inspected; then it reads as exactly one `Data`,
which is the version 2 datum written for the decoded AID and state with some key material. -/
theorem decode_accepts_only_written (r : AH.PublishedRelease) (x : Nat) (res : DecodedDatum)
    (h : decode r x = some res) :
    ∃ d k, ofBytes? (unpack x) = some d ∧ datum res.aid k res.state = some d ∧
      res.state.datumFacts = res.state := by
  simp only [decode, Option.bind_eq_some_iff] at h
  obtain ⟨d, hd, hdec⟩ := h
  obtain ⟨k, hk, hf⟩ := decodeData_complete d res hdec
  exact ⟨d, k, hd, hk, hf⟩

/-! ## The consumer with the concrete decoder -/

/-- Given a state; when its datum facts are taken twice; then the result is its datum facts. -/
theorem datumFacts_idem (s : State) : s.datumFacts.datumFacts = s.datumFacts := by
  cases s <;> rfl

/-- Given any Params, slot and state; when the consumer predicate reads the state's datum facts
instead of the state; then its verdict is the same: it never reads the pool. -/
theorem consumable_datumFacts (p : Params) (now : Slot) (s : State) :
    consumableState p now s.datumFacts ↔ consumableState p now s := by
  cases s <;> simp [State.datumFacts, consumableState]

/-- Given a state for which a datum is written; when inspected; then the state has an output. -/
theorem datum_hasOutput (aid : AID) (k : KeyMaterial) (s : State) (d : Data)
    (h : datum aid k s = some d) : s.hasOutput = true := by
  cases s <;> simp_all [datum, State.hasOutput]

/-- Given a holding with the release's credential, the representative asset once and the raw
version 2 datum written for the intended AID and any state with an output, pool included;
when observed through the concrete interpretation; then it realizes that state. -/
theorem written_realizes (c : Context) (s : State) (k : KeyMaterial) (d : Data)
    (o : AH.ObservedOutput) (hd : datum c.aid k s = some d) (hk : k.Bytewise)
    (cred : o.credential = c.release.applicationCredential)
    (qty : AH.quantity o (representativeAsset interpretation c) = 1)
    (held : o.datum = .application (raw d)) :
    realizesState interpretation c s o := by
  refine ⟨cred, ?_, ?_⟩
  · simp [qty, State.representativeHeld, datum_hasOutput _ _ _ _ hd]
  · simp [decoded, held, interpretation, Bytes.interpretation,
      decode_written c.release c.aid k s d hd hk, DecodedDatum.facts, datumFacts_idem]

/-- Given an authenticated context and a holding carrying the raw version 2 datum written for
the intended AID and any state with an output, funded pools included; when the concrete
consumer reads it; then it is accepted exactly when the written state is consumable. -/
theorem written_holding_iff (c : Context) (e : Environment) (p : Params) (now : Slot)
    (s : State) (k : KeyMaterial) (d : Data) (o : AH.ObservedOutput)
    (context : authenticatedContext c e) (hd : datum c.aid k s = some d) (hk : k.Bytewise)
    (cred : o.credential = c.release.applicationCredential)
    (qty : AH.quantity o (representativeAsset interpretation c) = 1)
    (held : o.datum = .application (raw d)) :
    consumableHolding interpretation c e p now o ↔ consumableState p now s :=
  existing_eligibility_preserved interpretation c e p now s o context
    (written_realizes c s k d o hd hk cred qty held)

/-- Given a registration funding the premium pool with any amount and a holding carrying the
raw datum written for the registered state; when the registration bridge's datum clause reads
it through the concrete interpretation; then the clause holds: the bridge does not refuse a
funded registration for its pool. -/
theorem funded_registration_agrees (c : Context) (p : Params) (env : Env) (now : Slot)
    (refund : Addr) (pool0 : Value) (flow : Flow) (st : State) (k : KeyMaterial) (d : Data)
    (o : AH.ObservedOutput)
    (registration : stepFn p env (.register refund pool0) now .absent = some (flow, st))
    (hd : datum c.aid k st = some d) (hk : k.Bytewise) (held : o.datum = .application (raw d)) :
    st = .present ⟨0, 0, false, false, now, refund, pool0⟩ ∧
      decide ((decoded interpretation c o).map DecodedDatum.facts =
        some ⟨c.aid, st.datumFacts⟩) = true := by
  simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at registration
  refine ⟨registration.2.symm, ?_⟩
  simp [decoded, held, interpretation, Bytes.interpretation,
    decode_written c.release c.aid k st d hd hk, DecodedDatum.facts, datumFacts_idem]

/-- Given a holding carrying any raw version 1 datum; when the concrete consumer reads it; then
it is refused, whatever the rest of the holding. -/
theorem version_one_holding_refused (c : Context) (e : Environment) (p : Params) (now : Slot)
    (o : AH.ObservedOutput) (fs : List Data) (hb : (Data.constr 0 fs).Bytewise)
    (held : o.datum = .application (raw (.constr 0 fs))) :
    ¬ consumableHolding interpretation c e p now o :=
  malformed_datum_refused interpretation c e p now o (by
    simp [decoded, held, interpretation, Bytes.interpretation, decode_raw _ _ hb,
      version_one_refused])

end CardanoKeri.CheckpointDatum
