use aiken/primitive/bytearray
use cardano/address.{
  Address, Script, VerificationKey, from_script, from_verification_key,
  with_delegation_key, with_delegation_script,
}
use cardano_keri/checkpoint/refund.{ledger_bytes}

const payment: ByteArray =
  #"53535353535353535353535353535353535353535353535353535353"

const stake: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

fn base(header: ByteArray) -> ByteArray {
  header |> bytearray.concat(payment) |> bytearray.concat(stake)
}

test ledger_bytes_of_an_enterprise_address() {
  and {
    ledger_bytes(1, from_verification_key(payment)) == Some(
      bytearray.concat(#"61", payment),
    ),
    ledger_bytes(1, from_script(payment)) == Some(
      bytearray.concat(#"71", payment),
    ),
    ledger_bytes(0, from_verification_key(payment)) == Some(
      bytearray.concat(#"60", payment),
    ),
  }
}

test ledger_bytes_of_a_base_address_for_each_credential_pair() {
  and {
    ledger_bytes(
      1,
      from_verification_key(payment) |> with_delegation_key(stake),
    ) == Some(base(#"01")),
    ledger_bytes(1, from_script(payment) |> with_delegation_key(stake)) == Some(
      base(#"11"),
    ),
    ledger_bytes(
      1,
      from_verification_key(payment) |> with_delegation_script(stake),
    ) == Some(base(#"21")),
    ledger_bytes(1, from_script(payment) |> with_delegation_script(stake)) == Some(
      base(#"31"),
    ),
  }
}

test ledger_bytes_has_nothing_for_a_pointer_stake_part() {
  let pointer = Address {
    payment_credential: VerificationKey(payment),
    stake_credential: Some(
      address.Pointer {
        slot_number: 1,
        transaction_index: 2,
        certificate_index: 3,
      },
    ),
  }
  ledger_bytes(1, pointer) == None && Script(payment) != VerificationKey(
    payment,
  )
}
