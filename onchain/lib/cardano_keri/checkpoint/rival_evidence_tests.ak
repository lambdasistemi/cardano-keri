//// The signed-byte layer of the conviction predicate over real keripy 1.3.5
//// events (rival_bytes_vectors.ak): every event, signature, receipt and SAID is
//// keripy's. A rival is opened from its exact bytes, its own SAID is opened from
//// the same bytes, and the conviction predicate runs over what was opened.

use aiken/primitive/bytearray
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/rival.{
  Rotation, Tip, conviction_accepts, rotation_valid,
}
use cardano_keri/checkpoint/rival_bytes_vectors.{
  Case, advance_witnessed_2key, fork_recorded, fork_rival,
  fork_witnessed_recorded, fork_witnessed_rival, honest_2key_rotation,
}
use cardano_keri/checkpoint/rival_evidence.{
  RivalClaim, event_said, open_rival, signed_event_digest,
}

fn opened(c: Case) -> Option<Rotation> {
  open_rival(c.previous, c.claim, c.evidence)
}

/// The checkpoint a conviction spends when `writer` is the installed event.
fn tip_of(writer: Case) -> Tip {
  expect Some(digest) = signed_event_digest(
    writer.evidence.event_bytes,
    writer.claim.off_d,
  )
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

fn with_evidence(c: Case, e: AdvanceEvidence) -> Case {
  Case { ..c, evidence: e }
}

fn with_claim(c: Case, claim: RivalClaim) -> Case {
  Case { ..c, claim }
}

// ---------------------------------------------------------
// The own SAID opened from the exact bytes is keripy's
// ---------------------------------------------------------

fn said_is_keripys(c: Case) -> Bool {
  expect Some(digest) = signed_event_digest(
    c.evidence.event_bytes,
    c.claim.off_d,
  )
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

// The signature of the sibling does not verify over these bytes.
test a_signature_of_another_event_does_not_count() {
  let swapped = AdvanceEvidence {
    ..fork_rival.evidence,
    ctrl_sigs: fork_recorded.evidence.ctrl_sigs,
  }
  and {
    valid(fork_rival),
    !valid(with_evidence(fork_rival, swapped)),
  }
}

test a_witness_receipt_of_another_event_does_not_count() {
  let swapped = AdvanceEvidence {
    ..fork_witnessed_rival.evidence,
    wit_receipts: fork_witnessed_recorded.evidence.wit_receipts,
  }
  and {
    valid(fork_witnessed_rival),
    !valid(with_evidence(fork_witnessed_rival, swapped)),
  }
}

test a_missing_witness_receipt_leaves_the_threshold_unmet() {
  let none = AdvanceEvidence {
    ..fork_witnessed_rival.evidence,
    wit_receipts: [],
  }
  !valid(with_evidence(fork_witnessed_rival, none))
}

test one_signature_of_two_leaves_the_own_threshold_unmet() {
  let one = AdvanceEvidence {
    ..advance_witnessed_2key.evidence,
    ctrl_sigs: when advance_witnessed_2key.evidence.ctrl_sigs is {
      [first, ..] -> [first]
      [] -> []
    },
  }
  and {
    valid(advance_witnessed_2key),
    !valid(with_evidence(advance_witnessed_2key, one)),
  }
}

test one_receipt_of_two_leaves_the_receipt_threshold_unmet() {
  let one = AdvanceEvidence {
    ..advance_witnessed_2key.evidence,
    wit_receipts: when advance_witnessed_2key.evidence.wit_receipts is {
      [first, ..] -> [first]
      [] -> []
    },
  }
  !valid(with_evidence(advance_witnessed_2key, one))
}

// ---------------------------------------------------------
// The claim is bound to the bytes
// ---------------------------------------------------------

test a_claim_that_hides_a_witness_cut_is_refused() {
  let hidden = AdvanceEvidence {
    ..advance_witnessed_2key.evidence,
    off_br: [],
    wit_cut: [],
  }
  and {
    valid(advance_witnessed_2key),
    opened(with_evidence(advance_witnessed_2key, hidden)) == None,
  }
}

test a_claim_that_hides_a_key_is_refused() {
  let claim = RivalClaim {
    ..advance_witnessed_2key.claim,
    cur_keys: when advance_witnessed_2key.claim.cur_keys is {
      [first, ..] -> [first]
      [] -> []
    },
  }
  let evidence = AdvanceEvidence {
    ..advance_witnessed_2key.evidence,
    off_k: when advance_witnessed_2key.evidence.off_k is {
      [first, ..] -> [first]
      [] -> []
    },
  }
  opened(Case { ..advance_witnessed_2key, claim, evidence }) == None
}

test a_misdirected_offset_is_refused() {
  let misdirected = AdvanceEvidence {
    ..fork_rival.evidence,
    off_s: fork_rival.evidence.off_s + 1,
  }
  opened(with_evidence(fork_rival, misdirected)) == None
}

test a_claim_of_another_sequence_is_refused() {
  let claim = RivalClaim { ..fork_rival.claim, sn: 2 }
  opened(with_claim(fork_rival, claim)) == None
}

// ---------------------------------------------------------
// The digest is recomputed from the bytes, never declared
// ---------------------------------------------------------

// The d span carries the SAID of another genuine event: a declared digest.
test a_declared_digest_that_is_not_the_bytes_digest_is_refused() {
  let off = fork_rival.claim.off_d
  let declared = bytearray.concat(
    bytearray.concat(
      bytearray.take(fork_rival.evidence.event_bytes, off),
      fork_recorded.said,
    ),
    bytearray.drop(fork_rival.evidence.event_bytes, off + 44),
  )
  let evidence = AdvanceEvidence {
    ..fork_rival.evidence,
    event_bytes: declared,
  }
  and {
    signed_event_digest(fork_rival.evidence.event_bytes, off) != None,
    signed_event_digest(declared, off) == None,
    opened(with_evidence(fork_rival, evidence)) == None,
  }
}

test a_changed_byte_changes_the_digest_and_is_refused() {
  let bytes = fork_rival.evidence.event_bytes
  let at = 12
  let changed = bytearray.concat(
    bytearray.concat(bytearray.take(bytes, at), #"58"),
    bytearray.drop(bytes, at + 1),
  )
  and {
    bytearray.at(bytes, at) != 88,
    signed_event_digest(changed, fork_rival.claim.off_d) == None,
  }
}

fn padding(n: Int) -> ByteArray {
  if n <= 0 {
    ""
  } else {
    bytearray.push(padding(n - 1), 32)
  }
}

test bytes_over_the_hash_limit_are_refused_without_a_hash() {
  let long = bytearray.concat(fork_rival.evidence.event_bytes, padding(700))
  and {
    bytearray.length(long) > 1024,
    signed_event_digest(long, fork_rival.claim.off_d) == None,
  }
}

test a_span_outside_the_bytes_is_refused() {
  and {
    event_said(fork_rival.evidence.event_bytes, -1) == None,
    event_said(
      fork_rival.evidence.event_bytes,
      bytearray.length(fork_rival.evidence.event_bytes) - 10,
    ) == None,
    signed_event_digest(fork_rival.evidence.event_bytes, -1) == None,
    signed_event_digest(
      fork_rival.evidence.event_bytes,
      bytearray.length(fork_rival.evidence.event_bytes) - 10,
    ) == None,
  }
}

test a_claim_that_hides_a_next_key_is_refused() {
  let claim = RivalClaim {
    ..advance_witnessed_2key.claim,
    next_keys: when advance_witnessed_2key.claim.next_keys is {
      [first, ..] -> [first]
      [] -> []
    },
  }
  let evidence = AdvanceEvidence {
    ..advance_witnessed_2key.evidence,
    off_n: when advance_witnessed_2key.evidence.off_n is {
      [first, ..] -> [first]
      [] -> []
    },
  }
  and {
    valid(advance_witnessed_2key),
    opened(Case { ..advance_witnessed_2key, claim, evidence }) == None,
  }
}

test a_claim_that_hides_a_witness_addition_is_refused() {
  let hidden = AdvanceEvidence {
    ..advance_witnessed_2key.evidence,
    off_ba: [],
    wit_add: [],
  }
  opened(with_evidence(advance_witnessed_2key, hidden)) == None
}
