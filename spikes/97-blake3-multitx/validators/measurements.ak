use blake3
use cardano/address.{Address}
use cardano/assets.{Value}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use checkpoint

const input_1024 =
  #"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fa000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fa000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fa000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fa000102030405060708090a0b0c0d0e0f10111213"

const input_commitment =
  #"d75edc54bb5acee4cc8610568e82872ce79758afd38c51dfe6ccfab01c2d191f"

const cv512 =
  #"4e2364fbfbc6854ff5e99d42e206561a9602029b68a8902104ec6048414bfd94"

const expected_digest =
  #"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"

// Real BLAKE3 initial chaining value. Folded to a literal at compile time, so
// its construction is not charged to any measured validator cost. The
// `cv_initial_is_blake3_iv` test below pins it to `blake3.initial_chaining_value()`.
const cv_initial: ByteArray = blake3.initial_chaining_value()

test cv_initial_is_blake3_iv() {
  cv_initial == blake3.initial_chaining_value()
}

// ## Full-context fixtures
//
// All fixtures are top-level `const`s so their construction is folded at compile
// time and NOT charged to the measured validator cost.

// The datum being spent: offset 0 with the real initial chaining value, which
// `anchored_cv` requires at offset 0.
const before: checkpoint.Datum =
  checkpoint.Datum {
    input_commitment,
    cv: cv_initial,
    offset: 0,
    len: 1024,
    expected_digest,
  }

// The stepped datum expected in the continuing output (offset 512, cv512).
const next: checkpoint.Datum =
  checkpoint.Datum {
    input_commitment,
    cv: cv512,
    offset: 512,
    len: 1024,
    expected_digest,
  }

// The datum being spent by the Finish transaction (offset 512, cv512).
const finish_datum: checkpoint.Datum =
  checkpoint.Datum {
    input_commitment,
    cv: cv512,
    offset: 512,
    len: 1024,
    expected_digest,
  }

const addr: Address =
  address.from_verification_key(
    #"00000000000000000000000000000000000000000000000000000000",
  )

const val: Value = assets.from_lovelace(2_000_000)

const self_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 0,
  }

// Step transaction: one input at `self_ref` and one continuing output at the
// SAME address and value whose inline datum is the stepped datum `next`.
const tx_step: Transaction =
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: self_ref,
        output: Output {
          address: addr,
          value: val,
          datum: InlineDatum(before),
          reference_script: None,
        },
      },
    ],
    outputs: [
      Output {
        address: addr,
        value: val,
        datum: InlineDatum(next),
        reference_script: None,
      },
    ],
  }

// The Finish branch ignores the transaction, so an empty placeholder suffices.
const tx_finish: Transaction = transaction.placeholder

// Handler arguments, const-lifted so ONLY the `checkpoint.spend` call is charged
// to the measured cost (no `Some`/redeemer construction in the test bodies).
const maybe_before: Option<checkpoint.Datum> = Some(before)

const step_redeemer: checkpoint.Redeemer =
  checkpoint.Step { input: input_1024, blocks: 8 }

const maybe_finish: Option<checkpoint.Datum> = Some(finish_datum)

const finish_redeemer: checkpoint.Redeemer =
  checkpoint.Finish { input: input_1024 }

// ## Core-helper measurements (Step/Finish core BLAKE3 work only)

test measure_step_1024_offset0_absorb8() {
  expect Some(after) = checkpoint.step(before, input_1024, 8)

  after.offset == 512
}

test measure_finish_1024_offset512_after_8_blocks() {
  checkpoint.finish(finish_datum, input_1024)
}

// ## Full spend-validator context measurements
//
// These invoke the validator handler `checkpoint.spend`, so the measured cost
// includes the core BLAKE3 work PLUS (for Step) `find_input` + the output
// traversal and inline-datum decode of `has_continuing_output`.

test measure_step_full_context_1024_8blocks() {
  checkpoint.checkpoint.spend(maybe_before, step_redeemer, self_ref, tx_step)
}

test measure_finish_full_context_1024() {
  checkpoint.checkpoint.spend(
    maybe_finish,
    finish_redeemer,
    self_ref,
    tx_finish,
  )
}
