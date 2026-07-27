//// Auto-generated Aiken Close vectors for #117 — DO NOT EDIT.
//// Haskell owns message/address bytes, signatures, and verdicts.
//// Regenerate with `just gen-close-vectors`; drift is forbidden.

use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano_keri/checkpoint/close.{CloseContext, CloseEvidence}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}

pub const golden_refund_address_cbor: ByteArray =
  #"d8799fd8799f581c44444444444444444444444444444444444444444444444444444444ffd8799fd8799fd87a9f581c55555555555555555555555555555555555555555555555555555555ffffffff"

pub const golden_message_cbor_2key: ByteArray =
  #"d8799f582063617264616e6f2d6b6572692f636865636b706f696e742f636c6f73652f763101581ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc5820c2361ae6e0e735e83aaf94c3d6376854ba7808da9757eb7a20c5a6439b55b2685820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5820d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1030509d8799fd8799f581c44444444444444444444444444444444444444444444444444444444ffd8799fd8799fd87a9f581c55555555555555555555555555555555555555555555555555555555ffffffffff"

pub const pos_2key_context: CloseContext =
  CloseContext {
    network_id: 1,
    checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
    spent_index: 3,
    old: CheckpointDatumV1 {
      cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      cur_keys: [
        #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
        #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
      ],
      cur_threshold: Unweighted(2),
      next_keys: [
        #"7777777777777777777777777777777777777777777777777777777777777777",
      ],
      next_threshold: Unweighted(1),
      witnesses: [],
      toad: 0,
      seq: 5,
      native_sn: 9,
    },
  }

pub const pos_2key_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
      (
        1,
        #"f1f24c065632359a9bd08b968377847500904c3d313105ab1ef8bfd8d862dd75c69cb59999e8eeefd9903c7ee8bf81b8f5008196ec3007e5d73538a2a571f103",
      ),
    ],
  }

pub const pos_gleif7_context: CloseContext =
  CloseContext {
    network_id: 1,
    checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
    spent_index: 3,
    old: CheckpointDatumV1 {
      cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      cur_keys: [
        #"0380fcebe3b1b3d0d6a196c6059c92975cf446f03c69bf089c0d0d7be611063e",
        #"87d4034a197c50e9133f3a97c81d45a28a23744bea198bf7896060d40c502ddc",
        #"6b6431d375e8db08b1f9e3c5c0c1dc71cd186e7ad155c03dd1e07cf32d1bcf51",
        #"f9f02712abf08ee233d729b47d76f4e789dc4cf46d6e9fae8c020dd6323806f6",
        #"9d3e1ade7c4c87e2a1c4b1595f38ae404a13f5736b8a241a17c4750ab43cc935",
        #"0db754920b399dafec84660f7f516138a6d509523ce5532d19ff3e4b1b41a22b",
        #"f50a4c9bf688e8ce210f8109e8247fc81ef20f8d4a029500d4ceb7be0e23becb",
      ],
      cur_threshold: Weighted(
        [
          [
            Weight { num: 1, den: 3 },
            Weight { num: 1, den: 3 },
            Weight { num: 1, den: 3 },
            Weight { num: 1, den: 3 },
            Weight { num: 1, den: 3 },
            Weight { num: 1, den: 3 },
            Weight { num: 1, den: 3 },
          ],
        ],
      ),
      next_keys: [
        #"7777777777777777777777777777777777777777777777777777777777777777",
      ],
      next_threshold: Unweighted(1),
      witnesses: [],
      toad: 0,
      seq: 5,
      native_sn: 9,
    },
  }

pub const pos_gleif7_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        0,
        #"cd33d8943c2a353aa9289b018188d0556009b013d341904a63f49812a6a587765c2254830bd0f191a3715fdc049944d0e5b7c35fab681a6d80c8755c2f0bf401",
      ),
      (
        1,
        #"04b645e9cd5a9707ccbb83fce95963017695675bbb94f53b4c6023ccf0fd7a4a07d5fd183c9950f8ebcf92e6b52ec87668091a6ca1509def947331dc5bab3e07",
      ),
      (
        2,
        #"e4bae41c207b99fd4f072488555ca8164a67c6ecd258a67364c147006b6a0087ff76c6e906f1595f801c73f09959a7b1dbb4c292c92d1d12bf4373798a0edf0a",
      ),
    ],
  }

pub const neg_malformed_old_context: CloseContext =
  CloseContext {
    network_id: 1,
    checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
    spent_index: 3,
    old: CheckpointDatumV1 {
      cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      cur_keys: [
        #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
        #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
      ],
      cur_threshold: Unweighted(2),
      next_keys: [
        #"7777777777777777777777777777777777777777777777777777777777777777",
      ],
      next_threshold: Unweighted(1),
      witnesses: [],
      toad: 0,
      seq: 5,
      native_sn: 9,
    },
  }

pub const neg_below_threshold_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
    ],
  }

pub const neg_bad_index_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        -1,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
    ],
  }

pub const neg_out_of_range_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        99,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
    ],
  }

pub const neg_duplicate_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
    ],
  }

pub const neg_wrong_key_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
      (
        1,
        #"695ff1356207585dc39ead38504a2350bf88ad5cf0f6dc31835f9919c476c3f32cdeeb7dae4d9fe6adcdc104f264acbebf4920793190723c97fc3a55de6c6407",
      ),
    ],
  }

pub const neg_mutated_contexts: List<CloseContext> =
  [
    CloseContext {
      network_id: 0,
      checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
      spent_index: 3,
      old: CheckpointDatumV1 {
        cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 9,
      },
    },
    CloseContext {
      network_id: 1,
      checkpoint_policy_id: #"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
      spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
      spent_index: 3,
      old: CheckpointDatumV1 {
        cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 9,
      },
    },
    CloseContext {
      network_id: 1,
      checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
      spent_index: 3,
      old: CheckpointDatumV1 {
        cesr_aid: #"abababababababababababababababababababababababababababababababab",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 9,
      },
    },
    CloseContext {
      network_id: 1,
      checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      spent_txid: #"d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2",
      spent_index: 3,
      old: CheckpointDatumV1 {
        cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 9,
      },
    },
    CloseContext {
      network_id: 1,
      checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
      spent_index: 4,
      old: CheckpointDatumV1 {
        cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 9,
      },
    },
    CloseContext {
      network_id: 1,
      checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
      spent_index: 3,
      old: CheckpointDatumV1 {
        cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 6,
        native_sn: 9,
      },
    },
    CloseContext {
      network_id: 1,
      checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      spent_txid: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
      spent_index: 3,
      old: CheckpointDatumV1 {
        cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        cur_keys: [
          #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
          #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
        ],
        cur_threshold: Unweighted(2),
        next_keys: [
          #"7777777777777777777777777777777777777777777777777777777777777777",
        ],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 10,
      },
    },
  ]

pub const neg_redirected_evidence: CloseEvidence =
  CloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: None,
    },
    ctrl_sigs: [
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
      (
        1,
        #"f1f24c065632359a9bd08b968377847500904c3d313105ab1ef8bfd8d862dd75c69cb59999e8eeefd9903c7ee8bf81b8f5008196ec3007e5d73538a2a571f103",
      ),
    ],
  }

pub const neg_fresh_outref_context: CloseContext =
  CloseContext {
    network_id: 1,
    checkpoint_policy_id: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    spent_txid: #"e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1",
    spent_index: 0,
    old: CheckpointDatumV1 {
      cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      cur_keys: [
        #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
        #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
      ],
      cur_threshold: Unweighted(2),
      next_keys: [
        #"7777777777777777777777777777777777777777777777777777777777777777",
      ],
      next_threshold: Unweighted(1),
      witnesses: [],
      toad: 0,
      seq: 5,
      native_sn: 9,
    },
  }
