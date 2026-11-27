//// The signed-byte layer of the conviction predicate over real keripy 1.3.5
//// events (rival_bytes_vectors.ak): every event, signature, receipt and SAID is
//// keripy's. A rival is opened from its exact bytes: every value it consumes is
//// bound to its canonical top-level field of the signed event, the own digest is
//// opened from the same bytes, and the conviction predicate runs over what was
//// opened. The defensive tests build tampered bytes to show that field
//// selection is by the canonical structure and not by a supplied position.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/registration.{respell_hex}
use cardano_keri/checkpoint/rival.{
  Rotation, Tip, conviction_accepts, rotation_valid,
}
use cardano_keri/checkpoint/rival_bytes_vectors.{
  Case, advance_witnessed_2key, all, fork_recorded, fork_rival,
  fork_witnessed_recorded, fork_witnessed_rival, honest_2key_rotation,
}
use cardano_keri/checkpoint/rival_evidence.{
  RivalClaim, canonical_structure, open_digest, open_rival,
}
use cardano_keri/checkpoint/threshold.{Unweighted}

fn opened(c: Case) -> Option<Rotation> {
  open_rival(c.previous, c.claim, c.event_bytes, c.ctrl_sigs, c.wit_receipts)
}

/// The checkpoint a conviction spends when `writer` is the installed event.
fn tip_of(writer: Case) -> Tip {
  expect Some(digest) = open_digest(writer.claim, writer.event_bytes)
  Tip {
    aid: writer.claim.aid,
    epoch: 1,
    sn: writer.claim.sn,
    previous: Some(writer.previous),
    writer_digest: digest,
  }
}

fn convicts(writer: Case, rival: Case) -> Bool {
  when opened(rival) is {
    Some(rotation) -> conviction_accepts(tip_of(writer), rotation)
    None -> False
  }
}

fn valid(c: Case) -> Bool {
  when opened(c) is {
    Some(rotation) -> rotation_valid(c.previous, rotation)
    None -> False
  }
}

fn with_sigs(c: Case, sigs: List<(Int, ByteArray)>) -> Case {
  Case { ..c, ctrl_sigs: sigs }
}

fn with_receipts(c: Case, receipts: List<(Int, ByteArray)>) -> Case {
  Case { ..c, wit_receipts: receipts }
}

fn with_claim(c: Case, claim: RivalClaim) -> Case {
  Case { ..c, claim }
}

fn first_of(xs: List<a>) -> List<a> {
  when xs is {
    [first, ..] -> [first]
    [] -> []
  }
}

// ---------------------------------------------------------
// The own SAID opened from the exact bytes is keripy's
// ---------------------------------------------------------

fn said_is_keripys(c: Case) -> Bool {
  expect Some(digest) = open_digest(c.claim, c.event_bytes)
  qb64_aid(digest) == c.said
}

test said_of_fork_recorded_is_keripys() {
  said_is_keripys(fork_recorded)
}

test said_of_fork_rival_is_keripys() {
  said_is_keripys(fork_rival)
}

test said_of_fork_witnessed_recorded_is_keripys() {
  said_is_keripys(fork_witnessed_recorded)
}

test said_of_fork_witnessed_rival_is_keripys() {
  said_is_keripys(fork_witnessed_rival)
}

test said_of_honest_2key_rotation_is_keripys() {
  said_is_keripys(honest_2key_rotation)
}

test said_of_advance_witnessed_2key_is_keripys() {
  said_is_keripys(advance_witnessed_2key)
}

// ---------------------------------------------------------
// Each genuine rotation opens and is valid against the establishment it follows
// ---------------------------------------------------------

test fork_recorded_is_a_valid_rival() {
  valid(fork_recorded)
}

test fork_rival_is_a_valid_rival() {
  valid(fork_rival)
}

test fork_witnessed_recorded_is_a_valid_rival() {
  valid(fork_witnessed_recorded)
}

test fork_witnessed_rival_is_a_valid_rival() {
  valid(fork_witnessed_rival)
}

test honest_2key_rotation_is_a_valid_rival() {
  valid(honest_2key_rotation)
}

test advance_witnessed_2key_is_a_valid_rival() {
  valid(advance_witnessed_2key)
}

// ---------------------------------------------------------
// Two valid siblings at one position convict each other; one event does not
// ---------------------------------------------------------

test fork_rival_convicts_the_recorded_writer() {
  convicts(fork_recorded, fork_rival)
}

test fork_recorded_convicts_the_rival_as_writer() {
  convicts(fork_rival, fork_recorded)
}

test fork_witnessed_rival_convicts_the_recorded_writer() {
  convicts(fork_witnessed_recorded, fork_witnessed_rival)
}

test the_recorded_writer_does_not_convict_itself() {
  !convicts(fork_recorded, fork_recorded)
}

test the_witnessed_recorded_writer_does_not_convict_itself() {
  !convicts(fork_witnessed_recorded, fork_witnessed_recorded)
}

// ---------------------------------------------------------
// Signatures, receipts and thresholds are checked over the exact bytes
// ---------------------------------------------------------

test a_signature_of_another_event_does_not_count() {
  and {
    valid(fork_rival),
    !valid(with_sigs(fork_rival, fork_recorded.ctrl_sigs)),
  }
}

test a_witness_receipt_of_another_event_does_not_count() {
  and {
    valid(fork_witnessed_rival),
    !valid(
      with_receipts(fork_witnessed_rival, fork_witnessed_recorded.wit_receipts),
    ),
  }
}

test a_missing_witness_receipt_leaves_the_threshold_unmet() {
  !valid(with_receipts(fork_witnessed_rival, []))
}

test one_signature_of_two_leaves_the_own_threshold_unmet() {
  and {
    valid(advance_witnessed_2key),
    !valid(
      with_sigs(
        advance_witnessed_2key,
        first_of(advance_witnessed_2key.ctrl_sigs),
      ),
    ),
  }
}

test one_receipt_of_two_leaves_the_receipt_threshold_unmet() {
  !valid(
    with_receipts(
      advance_witnessed_2key,
      first_of(advance_witnessed_2key.wit_receipts),
    ),
  )
}

// ---------------------------------------------------------
// The claim is bound to the canonical fields of the bytes
// ---------------------------------------------------------

test every_genuine_event_has_the_canonical_structure() {
  list.all(all, fn(c) { canonical_structure(c.claim, c.event_bytes) })
}

test a_claim_that_hides_a_witness_cut_is_refused() {
  let claim = RivalClaim { ..advance_witnessed_2key.claim, cuts: [] }
  and {
    valid(advance_witnessed_2key),
    opened(with_claim(advance_witnessed_2key, claim)) == None,
  }
}

test a_claim_that_hides_a_witness_addition_is_refused() {
  let claim = RivalClaim { ..advance_witnessed_2key.claim, adds: [] }
  opened(with_claim(advance_witnessed_2key, claim)) == None
}

test a_claim_that_hides_a_key_is_refused() {
  let claim = RivalClaim {
    ..advance_witnessed_2key.claim,
    cur_keys: first_of(advance_witnessed_2key.claim.cur_keys),
  }
  opened(with_claim(advance_witnessed_2key, claim)) == None
}

test a_claim_that_hides_a_next_key_is_refused() {
  let claim = RivalClaim {
    ..advance_witnessed_2key.claim,
    next_keys: first_of(advance_witnessed_2key.claim.next_keys),
  }
  opened(with_claim(advance_witnessed_2key, claim)) == None
}

test a_claim_of_another_sequence_is_refused() {
  let claim = RivalClaim { ..fork_rival.claim, sn: 2 }
  opened(with_claim(fork_rival, claim)) == None
}

test a_claim_of_another_identifier_is_refused() {
  let claim = RivalClaim {
    ..fork_rival.claim,
    aid: fork_witnessed_rival.claim.aid,
  }
  opened(with_claim(fork_rival, claim)) == None
}

test a_claim_of_another_threshold_is_refused() {
  let claim = RivalClaim {
    ..advance_witnessed_2key.claim,
    cur_threshold: Unweighted(1),
  }
  opened(with_claim(advance_witnessed_2key, claim)) == None
}

// The bytes carry a p that is not a qualified digest (a quote in place of its
// code) and the claim says so too: the bytes match the claim and the structure
// is still refused.
test a_prior_that_is_not_a_qualified_digest_is_refused() {
  let c = fork_rival
  let bad = bytearray.concat("\"", bytearray.drop(c.claim.prior, 1))
  let claim = RivalClaim { ..c.claim, prior: bad }
  let bytes = splice(c.event_bytes, c.off_p, 44, bad)
  and {
    canonical_structure(c.claim, c.event_bytes),
    bytearray.slice(bytes, c.off_p, c.off_p + 43) == bad,
    !canonical_structure(claim, bytes),
  }
}

// ---------------------------------------------------------
// Field selection is by the canonical structure, not by a supplied position
// ---------------------------------------------------------

fn splice(
  bytes: ByteArray,
  at: Int,
  drop_length: Int,
  put: ByteArray,
) -> ByteArray {
  bytearray.concat(
    bytearray.concat(bytearray.take(bytes, at), put),
    bytearray.drop(bytes, at + drop_length),
  )
}

fn zeros(n: Int) -> ByteArray {
  if n <= 0 {
    ""
  } else {
    bytearray.push(zeros(n - 1), 48)
  }
}

/// The version string size field (6 hexadecimal digits at offset 16).
fn resized(bytes: ByteArray) -> ByteArray {
  let size = respell_hex(bytearray.length(bytes))
  splice(
    bytes,
    16,
    6,
    bytearray.concat(zeros(6 - bytearray.length(size)), size),
  )
}

test a_renamed_label_is_not_the_canonical_structure() {
  let c = fork_rival
  let renamed = splice(c.event_bytes, c.off_kt + 2, 1, "T")
  and {
    canonical_structure(c.claim, c.event_bytes),
    !canonical_structure(c.claim, renamed),
  }
}

test a_smuggled_top_level_field_is_not_the_canonical_structure() {
  let c = fork_rival
  let smuggled = resized(splice(c.event_bytes, c.off_a - 4, 0, "\"x\":\"y\","))
  and {
    bytearray.length(smuggled) == bytearray.length(c.event_bytes) + 8,
    !canonical_structure(c.claim, smuggled),
    opened(Case { ..c, event_bytes: smuggled }) == None,
  }
}

test a_repeated_top_level_field_is_not_the_canonical_structure() {
  let c = fork_rival
  let repeated = resized(splice(c.event_bytes, c.off_a - 4, 0, "\"s\":\"1\","))
  !canonical_structure(c.claim, repeated)
}

test an_anchor_tail_that_is_not_a_list_is_not_the_canonical_structure() {
  let c = fork_rival
  !canonical_structure(c.claim, splice(c.event_bytes, c.off_a, 1, "{"))
}

test an_unclosed_anchor_tail_is_not_the_canonical_structure() {
  let c = fork_rival
  let length = bytearray.length(c.event_bytes)
  !canonical_structure(c.claim, splice(c.event_bytes, length - 2, 2, "}}"))
}

// The own digest sits in the top-level d: a genuine SAID moved into the anchors
// leaves the structure intact (the anchors are free text) but the top-level d is
// then not the digest of the bytes.
test a_digest_moved_into_the_anchors_is_not_the_events_digest() {
  let c = fork_rival
  let blank = splice(
    c.event_bytes,
    c.off_d,
    44,
    "############################################",
  )
  let moved = resized(
    splice(
      blank,
      c.off_a + 1,
      0,
      bytearray.concat("\"", bytearray.concat(c.said, "\"")),
    ),
  )
  and {
    canonical_structure(c.claim, moved),
    open_digest(c.claim, moved) == None,
    open_digest(c.claim, c.event_bytes) != None,
  }
}

// ---------------------------------------------------------
// The digest is recomputed from the bytes, never declared
// ---------------------------------------------------------

test a_declared_digest_that_is_not_the_bytes_digest_is_refused() {
  let c = fork_rival
  let declared = splice(c.event_bytes, c.off_d, 44, fork_recorded.said)
  and {
    open_digest(c.claim, c.event_bytes) != None,
    open_digest(c.claim, declared) == None,
    opened(Case { ..c, event_bytes: declared }) == None,
  }
}

test a_changed_byte_changes_the_digest_and_is_refused() {
  let c = fork_rival
  let at = 12
  and {
    bytearray.at(c.event_bytes, at) != 88,
    open_digest(c.claim, splice(c.event_bytes, at, 1, "X")) == None,
  }
}

fn padding(n: Int) -> ByteArray {
  if n <= 0 {
    ""
  } else {
    bytearray.push(padding(n - 1), 32)
  }
}

// Padding inside the anchors keeps the structure; only the size is over the
// hash limit.
test bytes_over_the_hash_limit_are_refused_without_a_hash() {
  let c = fork_rival
  let long = resized(
    splice(c.event_bytes, bytearray.length(c.event_bytes) - 2, 0, padding(700)),
  )
  and {
    bytearray.length(long) > 1024,
    open_digest(c.claim, long) == None,
  }
}
