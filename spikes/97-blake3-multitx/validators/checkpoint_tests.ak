use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use blake3
use checkpoint

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
  prefix: ByteArray,
) {
  checkpoint.Datum {
    input_commitment: blake2b_256(input),
    cv,
    offset,
    len,
    expected_prefix: prefix,
  }
}

fn base_datum(input: ByteArray, prefix: ByteArray) {
  datum(
    input,
    blake3.initial_chaining_value(),
    0,
    bytearray.length(input),
    prefix,
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
  let prefix = #"42214739f095a406"
  let before = base_datum(input, prefix)
  expect Some(after) = checkpoint.step(before, input, 8)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)

  after.input_commitment == before.input_commitment && after.cv == chaining_value && after.offset == offset && after.offset == 512 && after.len == before.len && after.expected_prefix == prefix
}

test finish_accepts_after_required_split() {
  let input = vector_input(1024)
  let before =
    base_datum(
      input,
      #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
    )
  expect Some(after) = checkpoint.step(before, input, 8)

  checkpoint.finish(after, input)
}

test finish_accepts_partial_prefix() {
  let input = vector_input(1024)
  let before = base_datum(input, #"42214739f095a406")
  expect Some(after) = checkpoint.step(before, input, 8)

  checkpoint.finish(after, input)
}

test step_rejects_empty_prefix() {
  let input = vector_input(1024)
  let before = base_datum(input, #"")

  is_none(checkpoint.step(before, input, 8))
}

test finish_rejects_empty_prefix_after_valid_checkpoint() {
  let input = vector_input(1024)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let after = datum(input, chaining_value, offset, bytearray.length(input), #"")

  !checkpoint.finish(after, input)
}

test step_rejects_wrong_commitment() {
  let input = vector_input(1024)
  let before =
    checkpoint.Datum {
      input_commitment: #"00",
      cv: blake3.initial_chaining_value(),
      offset: 0,
      len: 1024,
      expected_prefix: #"42214739",
    }

  is_none(checkpoint.step(before, input, 8))
}

test step_rejects_wrong_length() {
  let input = vector_input(1024)
  let before =
    datum(input, blake3.initial_chaining_value(), 0, 1023, #"42214739")

  is_none(checkpoint.step(before, input, 8))
}

test step_rejects_zero_blocks() {
  let input = vector_input(1024)
  let before = base_datum(input, #"42214739")

  is_none(checkpoint.step(before, input, 0))
}

test step_rejects_more_than_eight_blocks() {
  let input = vector_input(1024)
  let before = base_datum(input, #"42214739")

  is_none(checkpoint.step(before, input, 9))
}

test step_rejects_absorbing_through_the_end() {
  let input = vector_input(1024)
  let blake3.Checkpoint { chaining_value, offset } =
    blake3.absorb(blake3.initial_chaining_value(), input, 0, 8)
  let before = datum(input, chaining_value, offset, 1024, #"42214739")

  is_none(checkpoint.step(before, input, 8))
}

test finish_rejects_early_remaining_above_limit() {
  let input = vector_input(1024)
  let before =
    base_datum(
      input,
      #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
    )

  !checkpoint.finish(before, input)
}

test finish_rejects_empty_remaining_segment() {
  let input = vector_input(1024)
  let digest =
    #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"
  let before = datum(input, blake3.initial_chaining_value(), 1024, 1024, digest)

  !checkpoint.finish(before, input)
}

test finish_rejects_wrong_prefix() {
  let input = vector_input(1024)
  let before = base_datum(input, #"00")
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
      expected_prefix: #"42214739",
    }

  !checkpoint.finish(before, input)
}

test finish_rejects_wrong_length() {
  let input = vector_input(1024)
  let before =
    datum(input, blake3.initial_chaining_value(), 512, 1023, #"42214739")

  !checkpoint.finish(before, input)
}
