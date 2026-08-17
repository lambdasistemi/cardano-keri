# Executable chain witness: signed `dip` and `drt` cross both V1 type gates

This extends the sealed `OFF-T-COLLISION-WITNESS.md` inception witness. It was
reproduced in the same pinned keripy 1.3.5 environment without modifying the
repository.

The delegated inception from that witness commits to next controller key
`DF-MVNF7Lz_RtunA3OewtsGAmKbvnpuxSQo2zcG1rcpO`. Holding that fixed, a
deterministic loop varied only the subsequent next-key commitment and created
genuine keripy `eventing.deltate(...)` events at child sequence number 1.

At trial 1055 it produced:

```text
event_type drt
said EFBLCdSOFTfZG-L6tL0rotpLj81fMsNZs769T3dizQ6U
raw_len 352
canonical_t_offset 30
collision_off_t 59
collision_context OFTfZG-L6tL0rotpLj81fMsNZs7
current_key DF-MVNF7Lz_RtunA3OewtsGAmKbvnpuxSQo2zcG1rcpO
next_digest EJJ8mNyN5skq19eFi2ELiXeGkc1mGHH5W72L6BKZAgxO
prior_event_said EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL
controller_signature AACWmxbETJHZCtUZCvwRcIPkvqUBCwZsyXE18PIFE4nVIbjf_kxOZ1PVJfSLmwLmVStrdJuCRbBho-FPBFoEyVwB
signature_verified True
raw_sha256 e5dab2bfd70cf103882b40c1453ba2da543268a3df5aeaa1e34346bfdacee447
```

The `rot` collision occurs inside the genuine delegated rotation's own SAID,
which the current advance validator deliberately leaves unchecked. The event
is:

```json
{"v":"KERI10JSON000160_","t":"drt","d":"EFBLCdSOFTfZG-L6tL0rotpLj81fMsNZs769T3dizQ6U","i":"EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL","s":"1","p":"EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL","kt":"1","k":["DF-MVNF7Lz_RtunA3OewtsGAmKbvnpuxSQo2zcG1rcpO"],"nt":"1","n":["EJJ8mNyN5skq19eFi2ELiXeGkc1mGHH5W72L6BKZAgxO"],"bt":"0","br":[],"ba":[],"a":[]}
```

The genuine state offsets are `off_i=91`, `off_s=142`, `off_kt=202`,
`off_k=[211]`, `off_nt=264`, `off_n=[273]`, `off_bt=326`, with empty
`off_br`, `off_ba`, `wit_cut`, and `wit_add`. Supplying `off_t=59` makes AE1
find `rot` while canonical `t="drt"` remains at offset 30.

Current `advance_predicate` checks those projected fields and valid controller
signatures over the bytes, but explicitly does not authenticate `d` or `p` and
does not check a delegator approval seal. Thus the reproduced `dip`/`drt` pair
demonstrates practical constructibility across both claimed V1 type
boundaries. Full transaction-envelope fixtures remain required before a
production fix, but no unproven cryptographic capability is needed for the
attacker-controlled portions.
