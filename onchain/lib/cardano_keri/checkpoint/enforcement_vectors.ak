//// Auto-generated Aiken enforcement vectors for #116 — DO NOT EDIT.
////
//// Regenerate with `just gen-enforcement-vectors` (runs
//// offchain/app/GenEnforcementVectors.hs over the committed keripy
//// fixtures). Each scenario is the tip datum + decoded evidence the
//// EnforcementSpec builds from the same JSON; offset-bearing scenarios
//// also carry the ratified EnforcementEvidence wire value.
//// enforcement_tests.ak asserts binder/predicate Haskell parity, plus
//// the TombstoneV1 codec golden. `just
//// check-enforcement-vectors` forbids drift.

use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, EventEvidence}
use cardano_keri/checkpoint/threshold.{Unweighted}

/// TombstoneV1 { cesr_aid: 0xaa*32, convicted_at_native_sn: 1,
/// evidence_said: 0xcc*32 } canonical CBOR (byte-parity golden)
pub const golden_tombstone: ByteArray =
  #"d8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa015820ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccff"

/// fork: rot_conflict double-signs the rot_recorded tip -> ConvictValid
pub const fork_convict_tip: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: #"fb442d0b050570133d187479e3b092cc0e46d06598ee207155bc0147a9525d7c",
    cur_keys: [
      #"c3f0fbee3789c4a7b50d7a2a3e41371f9c3bbeeca921027fa116686ea26e2be4",
    ],
    cur_threshold: Unweighted(1),
    next_keys: [
      #"b8390f52b394b3cf4c2dd8894c54354aeee511d616b110a0447bbd380444f798",
    ],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 1,
    native_sn: 1,
  }

pub const fork_convict_evidence: EventEvidence =
  EventEvidence {
    event_bytes: #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22726f74222c2264223a2245467a4f684f6e594f6d413249334e78425a6b4e51436d354475783871326b436e647937646c617465585270222c2269223a22455074454c517346425841545052683065654f776b73774f5274426c6d4f34676356573841556570556c3138222c2273223a2231222c2270223a22455074454c517346425841545052683065654f776b73774f5274426c6d4f34676356573841556570556c3138222c226b74223a2231222c226b223a5b22444d50772d2d34336963536e745131364b6a35424e782d634f3737737153454366364557614736696269766b225d2c226e74223a2231222c226e223a5b2245484c613871735f6446324c726d7a2d595935516f69393663714e31436f4e7a684936534530746f51303771225d2c226274223a2230222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d",
    t: #"726f74",
    native_sn: 1,
    cesr_aid: #"fb442d0b050570133d187479e3b092cc0e46d06598ee207155bc0147a9525d7c",
    said: #"5cce84e9d83a603623737105990d4029b90eec7cab69029ddcbb7656ad797469",
    revealed_keys: [
      #"c3f0fbee3789c4a7b50d7a2a3e41371f9c3bbeeca921027fa116686ea26e2be4",
    ],
    next_keys: [
      #"72daf2ab3f745d8bae6cfe618e50a22f7a72a3750a8373848e92134b68434eea",
    ],
    cur_threshold: Unweighted(1),
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    ctrl_sigs: [
      (
        0,
        #"89131eb6298da2468e6ff8494b2d09a82adc7495a5dab278da0632c9a1127cb8d3a69e7d5f3cf8aadfb919b3f94fa4f8932f00cc139c0ae3118cc09e9c527202",
      ),
    ],
    wit_sigs: [],
  }

pub const fork_convict_wire: EnforcementEvidence =
  EnforcementEvidence {
    event_bytes: fork_convict_evidence.event_bytes,
    off_t: 30,
    off_i: 91,
    off_s: 142,
    off_d: 40,
    off_k: [211],
    off_kt: 202,
    off_n: [273],
    off_nt: 264,
    off_bt: 326,
    native_sn: fork_convict_evidence.native_sn,
    said: fork_convict_evidence.said,
    revealed_keys: fork_convict_evidence.revealed_keys,
    next_keys: fork_convict_evidence.next_keys,
    cur_threshold: fork_convict_evidence.cur_threshold,
    next_threshold: fork_convict_evidence.next_threshold,
    toad: fork_convict_evidence.toad,
    ctrl_sigs: fork_convict_evidence.ctrl_sigs,
    wit_sigs: fork_convict_evidence.wit_sigs,
  }

/// fork_witnessed: witnessed rot_conflict double-signs the witnessed rot_recorded tip -> ConvictValid
pub const fork_witnessed_convict_tip: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: #"bf1924e1e0d2e93a67065696153161e4a440337cc08b50678287e774f447e07e",
    cur_keys: [
      #"f1e8386db5cf69655f4e59c2e470a0ca921689683b3f932434a4097590fdc8e5",
    ],
    cur_threshold: Unweighted(1),
    next_keys: [
      #"a5e56b435dbebe4c1b62e8b287de72ebdcd7df2b00fea35d1a362156c8877ff1",
    ],
    next_threshold: Unweighted(1),
    witnesses: [
      #"4a6b1f2f8a0f421df7e62ee02f46c29caf98f5e3d660305f6f74a7b781b17263",
    ],
    toad: 1,
    seq: 1,
    native_sn: 1,
  }

pub const fork_witnessed_convict_evidence: EventEvidence =
  EventEvidence {
    event_bytes: #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22726f74222c2264223a22454e4f4e785a54744c725239725f5a4863386d4a4248572d345f39655230464d35327942474e30726879754f222c2269223a22454c385a4a4f486730756b365a775a576c6855785965536b51444e38774974515a344b4835335430522d422d222c2273223a2231222c2270223a22454c385a4a4f486730756b365a775a576c6855785965536b51444e38774974515a344b4835335430522d422d222c226b74223a2231222c226b223a5b224450486f4f4732317a326c6c5830355a777552776f4d7153466f6c6f4f7a2d544a44536b435857515f636a6c225d2c226e74223a2231222c226e223a5b224546596d6f79657566375f7176524f4e4e655267326978596a763674434368425264767247774e6867526749225d2c226274223a2231222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d",
    t: #"726f74",
    native_sn: 1,
    cesr_aid: #"bf1924e1e0d2e93a67065696153161e4a440337cc08b50678287e774f447e07e",
    said: #"d38dc594ed2eb47daff64773c9890475bee3ff5e47414ce76c8118dd2b872b8e",
    revealed_keys: [
      #"f1e8386db5cf69655f4e59c2e470a0ca921689683b3f932434a4097590fdc8e5",
    ],
    next_keys: [
      #"5626a327ae7fbfeabd138d35e460da2c588efead08284145dbeb1b0361811808",
    ],
    cur_threshold: Unweighted(1),
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 1,
    ctrl_sigs: [
      (
        0,
        #"42791eec52b7c028dfe604121b794b16fc46979d9ca972c0c96aa71e7cd00b206aa83ea829ae457e5054f07f3c0503f6d7bd1fa7c4d8e927a046a83ae2d6bc04",
      ),
    ],
    wit_sigs: [
      (
        0,
        #"1f0904d4082918a69647d4feb7868990e2c42ae741cac5e493d1c74ab48c0d520a76c7c3f4b8dec17e85906361ad2b8108ef13b8684fd1cb1609b073b87a4c0d",
      ),
    ],
  }

pub const fork_witnessed_convict_wire: EnforcementEvidence =
  EnforcementEvidence {
    event_bytes: fork_witnessed_convict_evidence.event_bytes,
    off_t: 30,
    off_i: 91,
    off_s: 142,
    off_d: 40,
    off_k: [211],
    off_kt: 202,
    off_n: [273],
    off_nt: 264,
    off_bt: 326,
    native_sn: fork_witnessed_convict_evidence.native_sn,
    said: fork_witnessed_convict_evidence.said,
    revealed_keys: fork_witnessed_convict_evidence.revealed_keys,
    next_keys: fork_witnessed_convict_evidence.next_keys,
    cur_threshold: fork_witnessed_convict_evidence.cur_threshold,
    next_threshold: fork_witnessed_convict_evidence.next_threshold,
    toad: fork_witnessed_convict_evidence.toad,
    ctrl_sigs: fork_witnessed_convict_evidence.ctrl_sigs,
    wit_sigs: fork_witnessed_convict_evidence.wit_sigs,
  }

/// fork_witnessed F3b: the witnessed AID's OWN honest rot_recorded as evidence -> ConvictInvalid(CvNoConflict)
pub const fork_witnessed_honest_tip: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: #"bf1924e1e0d2e93a67065696153161e4a440337cc08b50678287e774f447e07e",
    cur_keys: [
      #"f1e8386db5cf69655f4e59c2e470a0ca921689683b3f932434a4097590fdc8e5",
    ],
    cur_threshold: Unweighted(1),
    next_keys: [
      #"a5e56b435dbebe4c1b62e8b287de72ebdcd7df2b00fea35d1a362156c8877ff1",
    ],
    next_threshold: Unweighted(1),
    witnesses: [
      #"4a6b1f2f8a0f421df7e62ee02f46c29caf98f5e3d660305f6f74a7b781b17263",
    ],
    toad: 1,
    seq: 1,
    native_sn: 1,
  }

pub const fork_witnessed_honest_evidence: EventEvidence =
  EventEvidence {
    event_bytes: #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22726f74222c2264223a2245457836797a6b454243476f6c67655274472d577335415f6a2d545f37744b69334a6b6e5530554955687259222c2269223a22454c385a4a4f486730756b365a775a576c6855785965536b51444e38774974515a344b4835335430522d422d222c2273223a2231222c2270223a22454c385a4a4f486730756b365a775a576c6855785965536b51444e38774974515a344b4835335430522d422d222c226b74223a2231222c226b223a5b224450486f4f4732317a326c6c5830355a777552776f4d7153466f6c6f4f7a2d544a44536b435857515f636a6c225d2c226e74223a2231222c226e223a5b22454b586c61304e647672354d47324c6f736f666563757663313938724150366a58526f324956624968335f78225d2c226274223a2231222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d",
    t: #"726f74",
    native_sn: 1,
    cesr_aid: #"bf1924e1e0d2e93a67065696153161e4a440337cc08b50678287e774f447e07e",
    said: #"4c7acb39040421a8960791b46f96b3903f8fe4ffeed2a2dc9927534508521ad8",
    revealed_keys: [
      #"f1e8386db5cf69655f4e59c2e470a0ca921689683b3f932434a4097590fdc8e5",
    ],
    next_keys: [
      #"a5e56b435dbebe4c1b62e8b287de72ebdcd7df2b00fea35d1a362156c8877ff1",
    ],
    cur_threshold: Unweighted(1),
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 1,
    ctrl_sigs: [
      (
        0,
        #"848bc55cb246ec99c22f05a4f7e737d736dcf3055dc3c31d8b51ae32b7df61ea64b21bb5b08778dd25b0be3c06307dd7146b2d78dc1e6373519edbce42431d01",
      ),
    ],
    wit_sigs: [
      (
        0,
        #"c5ecde0b9e4244dd63e4518a2e81dc06232c0c2056c6c7a7e771a851b0c7d0d3f1fcca67aef8bb92d826d2ec50953b05656567c8f3998b297bc19c36462ba40b",
      ),
    ],
  }

pub const fork_witnessed_honest_wire: EnforcementEvidence =
  EnforcementEvidence {
    event_bytes: fork_witnessed_honest_evidence.event_bytes,
    off_t: 30,
    off_i: 91,
    off_s: 142,
    off_d: 40,
    off_k: [211],
    off_kt: 202,
    off_n: [273],
    off_nt: 264,
    off_bt: 326,
    native_sn: fork_witnessed_honest_evidence.native_sn,
    said: fork_witnessed_honest_evidence.said,
    revealed_keys: fork_witnessed_honest_evidence.revealed_keys,
    next_keys: fork_witnessed_honest_evidence.next_keys,
    cur_threshold: fork_witnessed_honest_evidence.cur_threshold,
    next_threshold: fork_witnessed_honest_evidence.next_threshold,
    toad: fork_witnessed_honest_evidence.toad,
    ctrl_sigs: fork_witnessed_honest_evidence.ctrl_sigs,
    wit_sigs: fork_witnessed_honest_evidence.wit_sigs,
  }

/// honest_2key: rot vs its own reflected state -> ConvictInvalid(CvNoConflict)
pub const honest2_convict_tip: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e5",
    cur_keys: [
      #"31ef2cde2e41026aa942d27564996aa6a676cd04d61f4a43069d893a34781ea6",
      #"c47da7b5b68d6a1d2e8eadaa506b02d95a961338d95af2692478b6c559a477e9",
    ],
    cur_threshold: Unweighted(2),
    next_keys: [
      #"a91bff25b40e897065d2bed9f023a2c4be1573cc60037c3b5497fb0b219fdd22",
      #"bab291120e8a0f90293073da154611ef1a2e7a99cc33d159bf5393ee2054342b",
    ],
    next_threshold: Unweighted(2),
    witnesses: [],
    toad: 0,
    seq: 1,
    native_sn: 1,
  }

pub const honest2_convict_evidence: EventEvidence =
  EventEvidence {
    event_bytes: #"7b2276223a224b45524931304a534f4e3030303162655f222c2274223a22726f74222c2264223a22454f646670303942756e586e4b6a5571666c367772333937544b73774c4d56514a6a586435545357546c314e222c2269223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2273223a2231222c2270223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c226b74223a2232222c226b223a5b22444448764c4e347551514a7171554c536457535a6171616d647330453168394b5177616469546f306542366d222c22444d5239703757326a576f644c6f3674716c427241746c616c684d3432567279615352347473565a70486670225d2c226e74223a2232222c226e223a5b22454b6b625f795730446f6c775a644b2d3266416a6f73532d4658504d59414e384f3153582d7773686e393069222c22454c71796b52494f69672d514b54427a32685647456538614c6e715a7a445052576239546b2d346756445172225d2c226274223a2230222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d",
    t: #"726f74",
    native_sn: 1,
    cesr_aid: #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e5",
    said: #"e75fa74f41ba75e72a352a7e5eb0af7f7b4cab302cc5502635dde534964e5d4d",
    revealed_keys: [
      #"31ef2cde2e41026aa942d27564996aa6a676cd04d61f4a43069d893a34781ea6",
      #"c47da7b5b68d6a1d2e8eadaa506b02d95a961338d95af2692478b6c559a477e9",
    ],
    next_keys: [
      #"a91bff25b40e897065d2bed9f023a2c4be1573cc60037c3b5497fb0b219fdd22",
      #"bab291120e8a0f90293073da154611ef1a2e7a99cc33d159bf5393ee2054342b",
    ],
    cur_threshold: Unweighted(2),
    next_threshold: Unweighted(2),
    witnesses: [],
    toad: 0,
    ctrl_sigs: [
      (
        0,
        #"ecc31f24fab231192758c2d49e911502c3d7198f1ba7a8591c422907663294de9540fce848f0a8cf473902cbdc3c5edacac8e54ceb6049408ffed0aefb16f70d",
      ),
      (
        1,
        #"1eade38f7a881b3889cd69960aaa14570f2d897fa1af8014931a099f96d46f69bc5529b0372c5f16d9c373af706ca788a7a65983c552d0961ae317896fa6ca08",
      ),
    ],
    wit_sigs: [],
  }
