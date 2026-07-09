use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use blake3
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}

pub type Datum {
  input_commitment: ByteArray,
  cv: ByteArray,
  offset: Int,
  len: Int,
  expected_digest: ByteArray,
}

pub type Redeemer {
  Step { input: ByteArray, blocks: Int }
  Finish { input: ByteArray }
}

fn shape_is_valid(datum: Datum) -> Bool {
  let Datum { cv, offset, len, expected_digest, .. } = datum

  bytearray.length(cv) == 32 && offset >= 0 && offset <= len && offset % 64 == 0 && len <= 1024 && bytearray.length(
    expected_digest,
  ) == 32
}

fn input_matches(datum: Datum, input: ByteArray) -> Bool {
  let Datum { input_commitment, len, .. } = datum

  blake2b_256(input) == input_commitment && bytearray.length(input) == len
}

fn anchored_cv(datum: Datum) -> Bool {
  let Datum { cv, offset, .. } = datum

  offset > 0 || cv == blake3.initial_chaining_value()
}

fn digest_matches(digest: ByteArray, expected_digest: ByteArray) -> Bool {
  digest == expected_digest
}

pub fn step(datum: Datum, input: ByteArray, blocks: Int) -> Option<Datum> {
  let Datum { input_commitment, cv, offset, len, expected_digest } = datum
  let valid =
    shape_is_valid(datum) && input_matches(datum, input) && anchored_cv(datum) && blocks > 0 && blocks <= 8 && offset + blocks * 64 < len

  if valid {
    let blake3.Checkpoint { chaining_value, offset: next_offset } =
      blake3.absorb(cv, input, offset, blocks)

    Some(
      Datum {
        input_commitment,
        cv: chaining_value,
        offset: next_offset,
        len,
        expected_digest,
      },
    )
  } else {
    None
  }
}

pub fn finish(datum: Datum, input: ByteArray) -> Bool {
  let Datum { cv, offset, len, expected_digest, .. } = datum
  let remaining = len - offset

  if shape_is_valid(datum) && input_matches(datum, input) && remaining > 0 && remaining <= 512 {
    digest_matches(blake3.finish(cv, input, offset), expected_digest)
  } else {
    False
  }
}

fn has_continuing_output(
  datum: Datum,
  self: OutputReference,
  tx: Transaction,
) -> Bool {
  expect Some(spent) = find_input(tx.inputs, self)
  let Datum { input_commitment, cv, offset, len, expected_digest } = datum

  when
    list.find(
      tx.outputs,
      fn(output) {
        output.address == spent.output.address && output.value == spent.output.value && when
          output.datum
        is {
          InlineDatum(next_datum) ->
            if next_datum
            is Datum {
              input_commitment: next_input_commitment,
              cv: next_cv,
              offset: next_offset,
              len: next_len,
              expected_digest: next_expected_digest,
            }: Datum {
              next_input_commitment == input_commitment && next_cv == cv && next_offset == offset && next_len == len && next_expected_digest == expected_digest
            } else {
              False
            }
          _ -> False
        }
      },
    )
  is {
    Some(_) -> True
    None -> False
  }
}

validator checkpoint {
  spend(
    maybe_datum: Option<Datum>,
    redeemer: Redeemer,
    self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(datum) = maybe_datum

    when redeemer is {
      Step { input, blocks } ->
        when step(datum, input, blocks) is {
          Some(next_datum) -> has_continuing_output(next_datum, self, tx)
          None -> False
        }
      Finish { input } -> finish(datum, input)
    }
  }

  else(_) {
    fail
  }
}
