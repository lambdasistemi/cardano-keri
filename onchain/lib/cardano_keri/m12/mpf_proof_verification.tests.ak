//// #307 — permanent MPF proof-verification regressions (T307-002/T307-003/T307-004)
////
//// These two fixtures are the exact bytes of the immutable slice gate's
//// control fixture (fixture sha256
//// 97f5b3b80421894ed2848d29827f7fb10de468e164a58f9939791a0a51004714):
////
//// - under merkle-patricia-forestry v2.0.0 both tests compiled and failed
////   at `expect excluding(key, proof) == self.root` inside `insert` (the
////   historical `excluding()` rewind regression, fixed upstream in v2.1.0);
//// - under v2.1.0 both pass.
////
//// The module deliberately uses only the `insert`/`from_root` surface so
//// the same source compiles under both versions and the RED state fails at
//// the verifier assertion, never at resolution or compilation.
////
//// Selected by the focused fail-closed executable: `just mpf-proof-check`.

use aiken/merkle_patricia_forestry.{Branch, Fork, Leaf, Neighbor, Proof} as mpf

const leaf_fork_proof: Proof =
  [
    mpf.Branch {
      skip: 0,
      neighbors: #"d0feb802cc999c500ec58b8e78bdb1b11bcb8e217d404c2cfb416669a6b2c240cd0c58152bf064f0c7834dd72f69d12651739b32caaa3c986a87937f125b500f1426fccf2a456bce3c25b43206d9b429d56515580d086a959ca730325411b3aada6ac4d7221f787b97e1ce677fdadc412e824a9816281b1259b91addeb37bb2c",
    },
    mpf.Branch {
      skip: 0,
      neighbors: #"098745f495c99b7627f559ac8ed8165e2392e2261ef8990291f13705adf78fcf3dcca881d4b45aabe746e7041f743baaa831029e7890df9587858d8be5dce648e02f31fe2936417a393df8def15d7d0c021a66cdb33c3fdda941ae70614913cb116fd5e6c499b71e229b88f5106975cbe83a8c44d3619541d7ddd7eae0a355bc",
    },
    mpf.Branch {
      skip: 0,
      neighbors: #"9732c3266e468dd27c4bd16af5a6e60c1f556bf91700f51554cfa33aa26b8d30f33c27ab7c5c85ef006c78f56ecd7e8c77c5fadd7910e9b178801d554f244977026104fc4aede0864d405db792691c4e4534b06ae7f58366b640f13ecfa549afa046a157d2e9b6c0793a506942eb8ff50dfeb7c5e7a2a51814c4b3a4d6af6fa0",
    },
    mpf.Branch {
      skip: 0,
      neighbors: #"5f3065e998b5fa89bb33d9204546c5dba2b075adc542688dcc1773a490fa739ac69ff52c5f575e9f1912664c1ebef2f9498775350b0077a6b59fe012861c3715657146a239aaea12b3091054e5846771bba6f721b1835d025fa08d1fc5c9b1c40000000000000000000000000000000000000000000000000000000000000000",
    },
    mpf.Leaf {
      skip: 1,
      key: #"2b5b0ba7a99e17d9fde58f14dee61cccda9e3e9627b2ba2732ebed551ea9eaa4",
      value: #"3657998959985b7b75c734eb5b49d18cae9b353d00d811cb2c24ed6ed17b23d9",
    },
    mpf.Leaf {
      skip: 0,
      key: #"2b5b063719f4b7644c71adef1439c9aa78d34e684677dd61db0adffcc21797ec",
      value: #"4e397303e05277d98701446ee62f6f02bc013721fc12efba7300fb51ea935f9f",
    },
  ]

const terminal_fork_proof: Proof =
  [
    mpf.Branch {
      skip: 0,
      neighbors: #"d072e11c4f761d09ebe0c1df54b08d398977aa4e98e85e5e231f52dc32fdf8053861a5ea164ac3eb460e27f96ba934832bfc7b240dbf7be24d3fb7ae16f3e44fa965498aa2e219f45428bafc4f646a8f2b4d863bf730f802f81f4f713a465246cd28ad53627981fd212ebec41068fa0f4b0ae5e0e77af0143e296373c6c8f753",
    },
    mpf.Branch {
      skip: 0,
      neighbors: #"6c2cf6703c1b121726899e4f1de29cf483227d9e75d5d7948b62b5904c7f1011165b8313abcd4f1c33b85a5dabf8c5096039b3aba1c1fedda2e247810090173998f6f58a03bc17874bff8ba7eda08d25623911dff348f57da60b8545044dcbb175d27abc4c3e1b9aa0a3161ea0f8067ef39885c30399c164395b181747ba4f51",
    },
    mpf.Branch {
      skip: 0,
      neighbors: #"c5b1eb4266a20e13961f0b7b8f909a217141eecab5bbe3116665e382f87477fcf9a8a6a9e1e1cb7af32d1ffdf5c70643434337c3874d417de45f83e48f7c00afaf7180e918199dde712083a3f512483e89d756f25ddafe8b14b246499fe44dd3bda1f1a580cf7af9dd35c6ddfffa2ec8af0d41b00d7ca5ed25af8e54d4bef1f9",
    },
    mpf.Fork {
      skip: 1,
      neighbor: mpf.Neighbor {
        nibble: 12,
        prefix: #"",
        root: #"136bca071d530710ba622dfd66fe1afb859d4f42d45f29ce252e862a92eb10c2",
      },
    },
  ]

test leaf_fork_common_prefix() {
  mpf.insert(
    mpf.from_root(
      #"409bc367bec001f8c8af45fb86239d1f69763cb86e8e134c66bba15426cf176e",
    ),
    #"198d70e41146654a69e08c6682310a8c35816c8584431915a0eee4a62d39eda0",
    #"9e36f867a374be",
    leaf_fork_proof,
  ) == mpf.from_root(
    #"f19b7893c0ec34703790dadb8e3257196dcf7aabfa9426d68adf36a31a94ad9a",
  )
}

test terminal_fork_non_empty_prefix() {
  mpf.insert(
    mpf.from_root(
      #"76ff3670f2b81017d50354ca4a78792de31adbd23f456eec41d7a8c13fcdc91b",
    ),
    #"04811fc306a2021340b15ce6f025db1dc3d402f0829c7ee2100ca8fdd6ed10cd",
    #"0c43c3addce8b95e49eb0fb906",
    terminal_fork_proof,
  ) == mpf.from_root(
    #"a6eb3cdf9dd3da02d9463bd5cd68555ea11d6d5a77e2ece9ceb1cf6a5a9c7b27",
  )
}
