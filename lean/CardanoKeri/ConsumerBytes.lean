import CardanoKeri.ConsumerIdentity

/-! Concrete consumer identity bytes (#489).

The consumer statements leave the registry key, the preimage codec and the
hash abstract. This module declares one concrete choice for each, against the
public Singular revision pinned in `lakefile.lean`:

* the registry key of an AID is the AID's qualified CESR text bytes;
* the codec is the Plutus Data serialisation of the `Preimage` type of
  Singular's `onchain/lib/singular_state/preimage.ak`, one constructor per
  role, numbered as the upstream Lean `Preimage`;
* the hash is BLAKE2b-256, as that module's `role_name`.

Byte carrier. The upstream model carries byte strings (transaction ids,
policies, asset names, keys) as `Nat`. Every such field carries its bytes
through the bijective base-256 numeral `pack`/`unpack`, a bijection between
byte strings and `Nat`, so empty strings and leading zero bytes keep their
identity. Integers (output index, deposit) are plain `Nat`.

The holding address of a registration approval carries the address's own
Plutus Data serialisation, spliced as is; that role is outside the consumer
statements and its separation is not claimed here.

The datum decoder stays an interpretation input. The collision freedom of
BLAKE2b-256 over the finite identity domain stays an explicit assumption: a
256-bit digest of unbounded inputs is not injective, so no proof exists. -/
namespace CardanoKeri.ConsumerIdentity.Bytes
open CardanoKeri.Checkpoint

/-! ## Byte carrier -/

/-- Bijective base-256 numeral, least significant digit first. -/
def pack : List Nat → Nat
  | [] => 0
  | b :: bs => b + 1 + 256 * pack bs

/-- Inverse of `pack`. -/
def unpack (n : Nat) : List Nat :=
  if h : n = 0 then [] else (n - 1) % 256 :: unpack ((n - 1) / 256)
termination_by n
decreasing_by omega

def Bytes (bs : List Nat) : Prop := ∀ b ∈ bs, b < 256

/-- BL1. Given any carried number; when unpacked to bytes and packed again; then it is unchanged. -/
theorem pack_unpack (n : Nat) : pack (unpack n) = n := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    rw [unpack]
    split
    · simp [pack, *]
    · simp only [pack]
      rw [ih _ (by omega)]
      omega

/-- BL2. Given a byte string (every element below 256); when packed and unpacked; then it is
unchanged. -/
theorem unpack_pack (bs : List Nat) (h : Bytes bs) : unpack (pack bs) = bs := by
  induction bs with
  | nil => simp [pack, unpack]
  | cons b bs ih =>
    have hb : b < 256 := h b (by simp)
    have hbs : Bytes bs := fun x hx => h x (by simp [hx])
    rw [unpack, dif_neg (by simp [pack])]
    simp only [pack]
    have e1 : (b + 1 + 256 * pack bs - 1) % 256 = b := by omega
    have e2 : (b + 1 + 256 * pack bs - 1) / 256 = pack bs := by omega
    rw [e1, e2, ih hbs]

/-- BL3. Given two carried numbers with the same bytes; when compared; then they are equal. -/
theorem unpack_injective {m n : Nat} (h : unpack m = unpack n) : m = n := by
  rw [← pack_unpack m, ← pack_unpack n, h]

/-- BL4. Given two byte strings with the same carried number; when compared; then they are equal. -/
theorem pack_injective {a b : List Nat} (ha : Bytes a) (hb : Bytes b)
    (h : pack a = pack b) : a = b := by
  rw [← unpack_pack a ha, ← unpack_pack b hb, h]

/-- The `Nat` carrying a byte string. -/
def ofBytes (bs : List Nat) : Nat := pack bs

/-- Bytes of a string's UTF-8 encoding. -/
def utf8 (s : String) : List Nat := s.toUTF8.toList.map (·.toNat)

/-! ## Plutus Data serialisation -/

/-- Big-endian, exactly `k` bytes. -/
def be : Nat → Nat → List Nat
  | 0, _ => []
  | k + 1, n => be k (n / 256) ++ [n % 256]

/-- Big-endian value of a byte string. -/
def beVal (bs : List Nat) : Nat := bs.foldl (fun acc b => acc * 256 + b) 0

/-- Big-endian, without leading zero bytes. -/
def minimalBe (n : Nat) : List Nat :=
  if n = 0 then [] else minimalBe (n / 256) ++ [n % 256]
termination_by n
decreasing_by omega

/-- CBOR head: major type and argument, in the shortest form. -/
def head (major n : Nat) : List Nat :=
  if n < 24 then [major * 32 + n]
  else if n < 256 then [major * 32 + 24] ++ be 1 n
  else if n < 65536 then [major * 32 + 25] ++ be 2 n
  else if n < 4294967296 then [major * 32 + 26] ++ be 4 n
  else [major * 32 + 27] ++ be 8 n

/-- Definite chunks of at most 64 bytes. -/
def chunks (bs : List Nat) : List Nat :=
  if bs = [] then [] else head 2 (min 64 bs.length) ++ bs.take 64 ++ chunks (bs.drop 64)
termination_by bs.length
decreasing_by cases bs <;> simp_all <;> omega

/-- A byte string: definite up to 64 bytes, otherwise indefinite in chunks of 64. -/
def bstr (bs : List Nat) : List Nat :=
  if bs.length ≤ 64 then head 2 bs.length ++ bs else [0x5f] ++ chunks bs ++ [0xff]

/-- A non-negative integer: plain below 2^64, otherwise a tagged big number. -/
def int (n : Nat) : List Nat :=
  if n < 18446744073709551616 then head 0 n else [0xc2] ++ bstr (minimalBe n)

/-- Constructor `i` (below 7) with already serialised fields: the empty field
list definite, any other list indefinite. -/
def constr (i : Nat) (fields : List (List Nat)) : List Nat :=
  [0xd8, 121 + i] ++ (if fields = [] then [0x80] else [0x9f] ++ fields.flatten ++ [0xff])

/-- `OutputReference { transaction_id, output_index }`. -/
def outRef (o : Singular.OutRef) : List Nat :=
  constr 0 [bstr (unpack o.tx), int o.index]

/-- `RegistryIdentity { policy, name }`. -/
def registry (t : Singular.TokenId) : List Nat :=
  constr 0 [bstr (unpack t.policy), bstr (unpack t.name)]

/-- The Plutus Data serialisation of Singular's `Preimage`. -/
def code : AH.Codec
  | .state seed => constr 0 [outRef seed]
  | .active r key => constr 1 [registry r, bstr (unpack key)]
  | .applicationConfiguration r => constr 2 [registry r]
  | .registrationApproval r key address datum deposit =>
      constr 3 [registry r, bstr (unpack key), unpack address, bstr (unpack datum), int deposit]
  | .terminationApproval r key => constr 4 [registry r, bstr (unpack key)]

/-! ## BLAKE2b-256 (RFC 7693) -/

namespace Blake2b

def iv : Array UInt64 := #[0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b,
  0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b,
  0x5be0cd19137e2179]

def sigma : Array (Array Nat) := #[
  #[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  #[14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  #[11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  #[7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  #[9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  #[2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  #[12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  #[13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  #[6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  #[10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]]

def rotr (x : UInt64) (n : UInt64) : UInt64 := (x >>> n) ||| (x <<< (64 - n))

def mix (v : Array UInt64) (a b c d : Nat) (x y : UInt64) : Array UInt64 := Id.run do
  let mut v := v
  v := v.set! a (v[a]! + v[b]! + x)
  v := v.set! d (rotr (v[d]! ^^^ v[a]!) 32)
  v := v.set! c (v[c]! + v[d]!)
  v := v.set! b (rotr (v[b]! ^^^ v[c]!) 24)
  v := v.set! a (v[a]! + v[b]! + y)
  v := v.set! d (rotr (v[d]! ^^^ v[a]!) 16)
  v := v.set! c (v[c]! + v[d]!)
  v := v.set! b (rotr (v[b]! ^^^ v[c]!) 63)
  return v

/-- Little-endian 64-bit word at byte offset `8 * i` of a 128-byte block. -/
def word (block : Array UInt8) (i : Nat) : UInt64 :=
  (List.range 8).foldr (fun j acc => (acc <<< 8) ||| (block[8 * i + j]!).toUInt64) 0

def compress (h : Array UInt64) (block : Array UInt8) (t : Nat) (last : Bool) :
    Array UInt64 := Id.run do
  let m := (List.range 16).toArray.map (word block)
  let mut v := h ++ iv
  v := v.set! 12 (v[12]! ^^^ (t % 18446744073709551616).toUInt64)
  v := v.set! 13 (v[13]! ^^^ (t / 18446744073709551616).toUInt64)
  if last then v := v.set! 14 (~~~ v[14]!)
  for r in [0:12] do
    let s := sigma[r % 10]!
    v := mix v 0 4 8 12 m[s[0]!]! m[s[1]!]!
    v := mix v 1 5 9 13 m[s[2]!]! m[s[3]!]!
    v := mix v 2 6 10 14 m[s[4]!]! m[s[5]!]!
    v := mix v 3 7 11 15 m[s[6]!]! m[s[7]!]!
    v := mix v 0 5 10 15 m[s[8]!]! m[s[9]!]!
    v := mix v 1 6 11 12 m[s[10]!]! m[s[11]!]!
    v := mix v 2 7 8 13 m[s[12]!]! m[s[13]!]!
    v := mix v 3 4 9 14 m[s[14]!]! m[s[15]!]!
  return (List.range 8).toArray.map fun i => h[i]! ^^^ v[i]! ^^^ v[i + 8]!

def pad (bs : List UInt8) : Array UInt8 := (bs ++ List.replicate (128 - bs.length) 0).toArray

/-- Absorb all blocks; `done` bytes were absorbed before `bs`. The last block,
possibly empty when the whole input is empty, is the final one. -/
def absorb (h : Array UInt64) (done : Nat) (bs : List UInt8) : Array UInt64 :=
  if bs.length ≤ 128 then compress h (pad bs) (done + bs.length) true
  else absorb (compress h (pad (bs.take 128)) (done + 128) false) (done + 128) (bs.drop 128)
termination_by bs.length
decreasing_by simp; omega

def digest (bs : List UInt8) : List UInt8 :=
  let h := (iv.set! 0 (iv[0]! ^^^ 0x01010020))
  let out := absorb h 0 bs
  ((List.range 4).flatMap fun i => (List.range 8).map fun j => (out[i]! >>> (8 * j).toUInt64).toUInt8)

end Blake2b

/-- BLAKE2b-256 of a byte string, as bytes. -/
def blake2b256 (bs : List Nat) : List Nat :=
  (Blake2b.digest (bs.map (·.toUInt8))).map (·.toNat)

/-- BL5. Given any input; when hashed with BLAKE2b-256; then every output element is a byte. -/
theorem blake2b256_bytes (bs : List Nat) : Bytes (blake2b256 bs) := by
  intro b hb
  simp only [blake2b256, List.mem_map] at hb
  obtain ⟨u, _, rfl⟩ := hb
  exact u.toNat_lt

/-- The asset name of a role: the hash of its serialised preimage. -/
def hash : AH.Hash := fun bs => pack (blake2b256 bs)

/-- The registry key of an AID: its qualified CESR text bytes. AID labels and
keys share the byte carrier, so the key is the label itself. -/
def keyOf (aid : AID) : Singular.Key := aid

/-- The AID label of a qualified CESR text. -/
def aidOfCesr (text : String) : AID := pack (utf8 text)

/-- The concrete interpretation. The datum decoder stays an input. -/
def interpretation (decode : AH.PublishedRelease → Nat → Option DecodedDatum) :
    Interpretation where
  hash := hash
  code := code
  keyOf := keyOf
  decode := decode

end CardanoKeri.ConsumerIdentity.Bytes
