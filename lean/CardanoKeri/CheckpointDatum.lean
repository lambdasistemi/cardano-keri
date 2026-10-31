import CardanoKeri.ConsumerBytesGoals

/-! The checkpoint inline datum, version 2, and the consumer's decoder (#498).

The consumer statements leave the datum decoder an interpretation input. This
module declares the datum a checkpoint holding carries, as Plutus `Data`, and a
concrete decoder from it to the consumer's `DecodedDatum`.

Layout (constructor indices and field order are protocol surface):

* `CheckpointDatum`: `V1` is constructor 0 (the layout of
  `onchain/lib/cardano_keri/checkpoint/datum.ak`, which carries no consumer
  facts and is refused here); `V2` is constructor 1 with one field.
* `CheckpointDatumV2.Live` (constructor 0, eight fields): `aid`, `sn`, `epoch`,
  `poisoned`, `frozen`, `born_at`, `refund_to`, `keys`.
* `CheckpointDatumV2.TerminationPending` (constructor 1, four fields): `aid`,
  `sn`, `epoch`, `keys`.
* `KeyMaterial` (constructor 0, six fields): `cur_keys`, `cur_threshold`,
  `next_keys`, `next_threshold`, `witnesses`, `toad`, with the types of the
  version 1 record. The model does not read them.
* Booleans are Aiken's: `False` constructor 0, `True` constructor 1, no fields.

Facts in the datum, amounts in the value. The datum carries the facts of a
checkpoint state (`State.datumFacts`): sequence number, epoch, poison, freeze,
birth slot, refund address and the pending-termination form. The premium pool
and the bond amounts are held in the output's value; reading them from the
value is a separate obligation the model does not discharge (#339).

Validity. The decoder refuses every shape error in the whole datum: a wrong
constructor, a wrong number of fields, a wrong version or a field of the wrong
kind, including inside the key material. It checks the validity of the fields
it reads only: `sn`, `epoch` and `born_at` are non-negative, `aid` and
`refund_to` are byte strings of bytes. The validity of the key material (key
widths, threshold ranges, witness widths and duplicates, `toad`) is the
checkpoint validator's obligation when it writes the datum, not the consumer's.

Byte carriers, as #489: the AID is its qualified CESR text bytes and the
refund address its byte string, both carried through the bijective numeral
`pack`/`unpack`. A raw application datum (`AH.ObservedOutput.datum`) is the
inline datum's CBOR bytes carried through the same numeral. The serialisation
is Plutus's: constructors 0–6 as tags 121–127, 7–127 as tags 1280–1400, others
as tag 102 over `[index, fields]`; non-empty lists indefinite; maps definite;
byte strings definite up to 64 bytes, otherwise in chunks of 64; integers
plain below 2^64, otherwise tagged big numbers. The reader also accepts the
other well-formed encodings of the same `Data`. One layout serves every
release at this model revision; a new layout is a new version constructor. -/
namespace CardanoKeri.CheckpointDatum
open CardanoKeri.Checkpoint
open CardanoKeri.ConsumerIdentity
open CardanoKeri.ConsumerIdentity.Bytes

/-! ## Plutus Data -/

/-- Plutus `Data`. Byte strings hold bytes as `Nat`, as in #489. -/
inductive Data where
  | constr (index : Nat) (fields : List Data)
  | map (entries : List (Data × Data))
  | list (items : List Data)
  | int (value : Int)
  | bytes (value : List Nat)
  deriving Repr, Inhabited

/-! ## Serialisation -/

/-- A signed integer: plain below 2^64, otherwise a tagged big number. -/
def intBytes : Int → List Nat
  | .ofNat n => Bytes.int n
  | .negSucc n => if n < 18446744073709551616 then head 1 n else [0xc3] ++ bstr (minimalBe n)

/-- The tag of constructor `i`, followed by its fields' list. -/
def constrTag (i : Nat) : List Nat :=
  if i < 7 then head 6 (121 + i)
  else if i < 128 then head 6 (1280 + (i - 7))
  else head 6 102 ++ [0x82] ++ intBytes i

/-- A list's body: empty definite, otherwise indefinite. -/
def wrapList (empty : Bool) (items : List Nat) : List Nat :=
  if empty then [0x80] else [0x9f] ++ items ++ [0xff]

mutual
/-- The Plutus serialisation of a `Data`. -/
def cbor : Data → List Nat
  | .constr i fs => constrTag i ++ wrapList fs.isEmpty (cborItems fs)
  | .map es => if es.length < 18446744073709551616 then head 5 es.length ++ cborEntries es
               else [0xbf] ++ cborEntries es ++ [0xff]
  | .list xs => wrapList xs.isEmpty (cborItems xs)
  | .int n => intBytes n
  | .bytes bs => bstr bs

/-- The items of a list, back to back. -/
def cborItems : List Data → List Nat
  | [] => []
  | d :: ds => cbor d ++ cborItems ds

/-- The entries of a map, key then value. -/
def cborEntries : List (Data × Data) → List Nat
  | [] => []
  | (k, v) :: es => cbor k ++ cbor v ++ cborEntries es
end

/-! ## Reading -/

mutual
/-- Read one `Data` item. `fuel` bounds the nesting; the input length is enough. -/
def parse : Nat → List Nat → Option (Data × List Nat)
  | 0, _ => none
  | _ + 1, [] => none
  | fuel + 1, b :: rest =>
    if b = 0x5f then (readChunks (rest.length + 1) rest).map fun p => (.bytes p.1, p.2)
    else if b = 0x9f then (parseUntilBreak fuel rest).map fun p => (.list p.1, p.2)
    else if b = 0xbf then (parseEntriesUntilBreak fuel rest).map fun p => (.map p.1, p.2)
    else match readHead (b :: rest) with
      | some (m, n, r) =>
        if m = 0 then some (.int n, r)
        else if m = 1 then some (.int (Int.negSucc n), r)
        else if m = 2 then (if n ≤ r.length then some (.bytes (r.take n), r.drop n) else none)
        else if m = 4 then (parseCount fuel n r).map fun p => (.list p.1, p.2)
        else if m = 5 then (parseEntries fuel n r).map fun p => (.map p.1, p.2)
        else if m = 6 then
          if n = 2 then (readBstr r).map fun p => (.int (beVal p.1), p.2)
          else if n = 3 then (readBstr r).map fun p => (.int (Int.negSucc (beVal p.1)), p.2)
          else if 121 ≤ n ∧ n < 128 then
            match parse fuel r with
            | some (.list fs, r') => some (.constr (n - 121) fs, r')
            | _ => none
          else if 1280 ≤ n ∧ n < 1401 then
            match parse fuel r with
            | some (.list fs, r') => some (.constr (n - 1280 + 7) fs, r')
            | _ => none
          else if n = 102 then
            match parse fuel r with
            | some (.list [.int (.ofNat i), .list fs], r') => some (.constr i fs, r')
            | _ => none
          else none
        else none
      | none => none

/-- Read items up to the break byte. -/
def parseUntilBreak : Nat → List Nat → Option (List Data × List Nat)
  | 0, _ => none
  | _ + 1, [] => none
  | fuel + 1, b :: rest =>
    if b = 0xff then some ([], rest) else
    match parse fuel (b :: rest) with
    | some (d, r) => (parseUntilBreak fuel r).map fun p => (d :: p.1, p.2)
    | none => none

/-- Read exactly `n` items. -/
def parseCount : Nat → Nat → List Nat → Option (List Data × List Nat)
  | _, 0, r => some ([], r)
  | 0, _ + 1, _ => none
  | fuel + 1, n + 1, r =>
    match parse fuel r with
    | some (d, r') => (parseCount fuel n r').map fun p => (d :: p.1, p.2)
    | none => none

/-- Read exactly `n` map entries. -/
def parseEntries : Nat → Nat → List Nat → Option (List (Data × Data) × List Nat)
  | _, 0, r => some ([], r)
  | 0, _ + 1, _ => none
  | fuel + 1, n + 1, r =>
    match parse fuel r with
    | some (k, r1) =>
      match parse fuel r1 with
      | some (v, r2) => (parseEntries fuel n r2).map fun p => ((k, v) :: p.1, p.2)
      | none => none
    | none => none

/-- Read map entries up to the break byte. -/
def parseEntriesUntilBreak : Nat → List Nat → Option (List (Data × Data) × List Nat)
  | 0, _ => none
  | _ + 1, [] => none
  | fuel + 1, b :: rest =>
    if b = 0xff then some ([], rest) else
    match parse fuel (b :: rest) with
    | some (k, r1) =>
      match parse fuel r1 with
      | some (v, r2) => (parseEntriesUntilBreak fuel r2).map fun p => ((k, v) :: p.1, p.2)
      | none => none
    | none => none
end

/-- Read a whole byte string as exactly one `Data`, with nothing left over. -/
def ofBytes? (bs : List Nat) : Option Data :=
  match parse bs.length bs with
  | some (d, []) => some d
  | _ => none

/-! ## The layout -/

/-- A threshold weight `num/den`, unread by the model. -/
abbrev Weight := Int × Int

/-- A KERI signing threshold, as `threshold.ak`'s `Threshold`. -/
inductive Threshold where
  | unweighted (m : Int)
  | weighted (clauses : List (List Weight))
  deriving Repr, DecidableEq

/-- The key material a checkpoint carries and the model does not read. -/
structure KeyMaterial where
  curKeys : List (List Nat)
  curThreshold : Threshold
  nextKeys : List (List Nat)
  nextThreshold : Threshold
  witnesses : List (List Nat)
  toad : Int
  deriving Repr, DecidableEq

def boolData : Bool → Data
  | false => .constr 0 []
  | true => .constr 1 []

def weightData (w : Weight) : Data := .constr 0 [.int w.1, .int w.2]

def thresholdData : Threshold → Data
  | .unweighted m => .constr 0 [.int m]
  | .weighted cs => .constr 1 [.list (cs.map fun c => .list (c.map weightData))]

def bytesListData (ks : List (List Nat)) : Data := .list (ks.map .bytes)

def keyMaterialData (k : KeyMaterial) : Data :=
  .constr 0 [bytesListData k.curKeys, thresholdData k.curThreshold, bytesListData k.nextKeys,
    thresholdData k.nextThreshold, bytesListData k.witnesses, .int k.toad]

/-- The version 2 datum of a checkpoint state that has an output, for the AID
and key material it carries. A state without an output has no datum. The pool
is not written: it is an amount held in the value. -/
def datum (aid : AID) (k : KeyMaterial) : State → Option Data
  | .present l => some (.constr 1 [.constr 0 [.bytes (unpack aid), .int l.sn, .int l.epoch,
      boolData l.poisoned, boolData l.frozen, .int l.bornAt, .bytes (unpack l.refundTo),
      keyMaterialData k]])
  | .terminationPending h => some (.constr 1 [.constr 1 [.bytes (unpack aid), .int h.sn,
      .int h.epoch, keyMaterialData k]])
  | .absent | .convicted => none

/-! ## The decoder -/

def bool? : Data → Option Bool
  | .constr 0 [] => some false
  | .constr 1 [] => some true
  | _ => none

def nat? : Data → Option Nat
  | .int (.ofNat n) => some n
  | _ => none

/-- A byte string of bytes. -/
def byteString? : Data → Option (List Nat)
  | .bytes bs => if bs.all (· < 256) then some bs else none
  | _ => none

def bytesShape? : Data → Option (List Nat)
  | .bytes bs => some bs
  | _ => none

def bytesList? : Data → Option (List (List Nat))
  | .list xs => xs.mapM bytesShape?
  | _ => none

def weight? : Data → Option Weight
  | .constr 0 [.int n, .int d] => some (n, d)
  | _ => none

def clause? : Data → Option (List Weight)
  | .list ws => ws.mapM weight?
  | _ => none

def threshold? : Data → Option Threshold
  | .constr 0 [.int m] => some (.unweighted m)
  | .constr 1 [.list cs] => (cs.mapM clause?).map .weighted
  | _ => none

def keyMaterial? : Data → Option KeyMaterial
  | .constr 0 [ck, ct, nk, nt, ws, .int toad] => do
    pure { curKeys := ← bytesList? ck, curThreshold := ← threshold? ct, nextKeys := ← bytesList? nk,
           nextThreshold := ← threshold? nt, witnesses := ← bytesList? ws, toad := toad }
  | _ => none

/-- The consumer's decoder at the `Data` level: version 2 only, every shape
checked, the read fields validated, the pool left at zero. -/
def decodeData : Data → Option DecodedDatum
  | .constr 1 [.constr 0 [aid, sn, epoch, poisoned, frozen, bornAt, refundTo, keys]] => do
    let aid ← byteString? aid
    let sn ← nat? sn
    let epoch ← nat? epoch
    let poisoned ← bool? poisoned
    let frozen ← bool? frozen
    let bornAt ← nat? bornAt
    let refundTo ← byteString? refundTo
    let _ ← keyMaterial? keys
    pure ⟨pack aid, .present ⟨sn, epoch, poisoned, frozen, bornAt, pack refundTo, 0⟩⟩
  | .constr 1 [.constr 1 [aid, sn, epoch, keys]] => do
    let aid ← byteString? aid
    let sn ← nat? sn
    let epoch ← nat? epoch
    let _ ← keyMaterial? keys
    pure ⟨pack aid, .terminationPending ⟨epoch, sn⟩⟩
  | _ => none

/-- The raw carrier of a `Data`: its serialisation through the numeral. -/
def raw (d : Data) : Nat := pack (cbor d)

/-- The consumer's decoder on a raw application datum. The release does not
select the layout at this model revision. -/
def decode (_ : AH.PublishedRelease) (r : Nat) : Option DecodedDatum :=
  (ofBytes? (unpack r)).bind decodeData

/-- The concrete interpretation: the #489 identity bytes and this decoder. -/
def interpretation : Interpretation := Bytes.interpretation decode

end CardanoKeri.CheckpointDatum
