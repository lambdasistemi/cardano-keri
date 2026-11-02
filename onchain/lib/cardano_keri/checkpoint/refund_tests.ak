use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{
  Address, Script, VerificationKey, from_script, from_verification_key,
  with_delegation_key, with_delegation_script,
}
use cardano_keri/checkpoint/refund.{ledger_bytes, payable}

const payment: ByteArray =
  #"53535353535353535353535353535353535353535353535353535353"

const stake: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

fn base(header: ByteArray) -> ByteArray {
  header |> bytearray.concat(payment) |> bytearray.concat(stake)
}

test payable_admits_every_base_and_enterprise_type_of_the_network() {
  and {
    payable(1, base(#"01")),
    payable(1, base(#"11")),
    payable(1, base(#"21")),
    payable(1, base(#"31")),
    payable(1, bytearray.concat(#"61", payment)),
    payable(1, bytearray.concat(#"71", payment)),
    payable(0, base(#"00")),
    payable(0, bytearray.concat(#"60", payment)),
  }
}

test payable_refuses_every_other_type_and_the_other_network() {
  and {
    !payable(1, bytearray.concat(#"41", payment) |> bytearray.concat(#"0102")),
    !payable(1, bytearray.concat(#"51", payment) |> bytearray.concat(#"0102")),
    !payable(1, bytearray.concat(#"81", payment)),
    !payable(1, bytearray.concat(#"e1", payment)),
    !payable(1, bytearray.concat(#"f1", payment)),
    !payable(1, base(#"00")),
    !payable(0, base(#"01")),
    !payable(1, bytearray.concat(#"60", payment)),
  }
}

test payable_refuses_the_wrong_size_for_the_type() {
  and {
    !payable(1, bytearray.concat(#"61", bytearray.take(payment, 27))),
    !payable(1, bytearray.concat(#"61", payment) |> bytearray.concat(#"00")),
    !payable(1, base(#"01") |> bytearray.concat(#"00")),
    !payable(1, bytearray.concat(#"01", payment)),
    !payable(1, #""),
  }
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

test ledger_bytes_is_payable_where_it_exists() {
  let addresses: List<Address> = [
    from_verification_key(payment),
    from_script(payment),
    from_verification_key(payment) |> with_delegation_key(stake),
    from_script(payment) |> with_delegation_script(stake),
  ]
  addresses != [] && list.all(
    addresses,
    fn(address) {
      when ledger_bytes(1, address) is {
        Some(bytes) -> payable(1, bytes)
        None -> False
      }
    },
  )
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
