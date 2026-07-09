use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use blake3
use checkpoint

// The full 32-byte BLAKE3 digest of the 1024-byte vector input. A KERI
// E-prefix identifier carries this complete digest.
const valid_digest =
  #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"

// A well-formed but incorrect 32-byte digest, used to isolate a wrong-digest
// rejection from a length rejection.
const wrong_digest =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn singleton(byte: Int) -> ByteArray {
  bytearray.push(#"", byte)
}

fn append_byte(out: ByteArray, byte: Int) -> ByteArray {
  bytearray.concat(out, singleton(byte))
}

fn vector_input_go(i: Int, len: Int, out: ByteArray) -> ByteArray {
  if i == len {
    out
  } else {
    vector_input_go(i + 1, len, append_byte(out, i % 251))
  }
}

fn vector_input(len: Int) -> ByteArray {
  vector_input_go(0, len, #"")
}

fn datum(
  input: ByteArray,
  cv: ByteArray,
  offset: Int,
  len: Int,
  digest: ByteArray,
) {
  checkpoint.Datum {
    input_commitment: blake2b_256(input),
    cv,
    offset,
    len,
    expected_digest: digest,
  }
}

fn base_datum(input: ByteArray, digest: ByteArray) {
  datum(
    input,
    blake3.initial_chaining_value(),
    0,
    bytearray.length(input),
    digest,
  )
}

fn is_none(maybe) {
  when maybe is {
    None -> True
    Some(_) -> False
  }
}

test step_accepts_eight_blocks_and_preserves_static_fields() {
  let input = vector_input(1024)
  let before = base_datum(input, valid_digest)
  expect Some(after) = checkpoint.step(before, input, 8)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)

  after.input_commitment == before.input_commitment && after.cv == chaining_value && after.offset == offset && after.offset == 512 && after.len == before.len && after.expected_digest == valid_digest
}

test finish_accepts_after_required_split() {
  let input = vector_input(1024)
  let before = base_datum(input, valid_digest)
  expect Some(after) = checkpoint.step(before, input, 8)

  checkpoint.finish(after, input)
}

test step_rejects_wrong_commitment() {
  let input = vector_input(1024)
  let before =
    checkpoint.Datum {
      input_commitment: #"00",
      cv: blake3.initial_chaining_value(),
      offset: 0,
      len: 1024,
      expected_digest: valid_digest,
    }

  is_none(checkpoint.step(before, input, 8))
}

test step_rejects_wrong_length() {
  let input = vector_input(1024)
  let before =
    datum(input, blake3.initial_chaining_value(), 0, 1023, valid_digest)

  is_none(checkpoint.step(before, input, 8))
}

test step_rejects_zero_blocks() {
  let input = vector_input(1024)
  let before = base_datum(input, valid_digest)

  is_none(checkpoint.step(before, input, 0))
}

test step_rejects_more_than_eight_blocks() {
  let input = vector_input(1024)
  let before = base_datum(input, valid_digest)

  is_none(checkpoint.step(before, input, 9))
}

test step_rejects_absorbing_through_the_end() {
  let input = vector_input(1024)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let before = datum(input, chaining_value, offset, 1024, valid_digest)

  is_none(checkpoint.step(before, input, 8))
}

test finish_rejects_early_remaining_above_limit() {
  let input = vector_input(1024)
  let before = base_datum(input, valid_digest)

  !checkpoint.finish(before, input)
}

test finish_rejects_empty_remaining_segment() {
  let input = vector_input(1024)
  let before =
    datum(input, blake3.initial_chaining_value(), 1024, 1024, valid_digest)

  !checkpoint.finish(before, input)
}

test finish_rejects_wrong_digest() {
  let input = vector_input(1024)
  let before = base_datum(input, wrong_digest)
  expect Some(after) = checkpoint.step(before, input, 8)

  !checkpoint.finish(after, input)
}

test finish_rejects_wrong_commitment() {
  let input = vector_input(1024)
  let before =
    checkpoint.Datum {
      input_commitment: #"00",
      cv: blake3.initial_chaining_value(),
      offset: 512,
      len: 1024,
      expected_digest: valid_digest,
    }

  !checkpoint.finish(before, input)
}

test finish_rejects_wrong_length() {
  let input = vector_input(1024)
  let before =
    datum(input, blake3.initial_chaining_value(), 512, 1023, valid_digest)

  !checkpoint.finish(before, input)
}

// A KERI E-prefix carries the COMPLETE 32-byte BLAKE3 digest. A caller-selected
// short digest prefix must be rejected: it destroys the genesis binding by
// letting many inputs satisfy the same short target. Each datum below is
// otherwise fully valid (correct commitment, anchored cv, valid offset) so
// digest length is the ONLY rejection cause.

test step_rejects_short_expected_eight_bytes() {
  let input = vector_input(1024)
  let before = base_datum(input, #"42214739f095a406")

  is_none(checkpoint.step(before, input, 8))
}

test step_rejects_short_expected_thirty_one_bytes() {
  let input = vector_input(1024)
  let before =
    base_datum(
      input,
      #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855a",
    )

  is_none(checkpoint.step(before, input, 8))
}

test finish_rejects_short_expected_eight_bytes() {
  let input = vector_input(1024)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let after =
    datum(
      input,
      chaining_value,
      offset,
      bytearray.length(input),
      #"42214739f095a406",
    )

  !checkpoint.finish(after, input)
}

test finish_rejects_short_expected_thirty_one_bytes() {
  let input = vector_input(1024)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let after =
    datum(
      input,
      chaining_value,
      offset,
      bytearray.length(input),
      #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855a",
    )

  !checkpoint.finish(after, input)
}

test step_rejects_oversized_expected_thirty_three_bytes() {
  let input = vector_input(1024)
  let before =
    base_datum(
      input,
      #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af700",
    )

  is_none(checkpoint.step(before, input, 8))
}

test finish_rejects_oversized_expected_thirty_three_bytes() {
  let input = vector_input(1024)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let after =
    datum(
      input,
      chaining_value,
      offset,
      bytearray.length(input),
      #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af700",
    )

  !checkpoint.finish(after, input)
}
