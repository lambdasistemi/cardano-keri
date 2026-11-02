//// The evidence the previous two-step freeze was accepted on, kept only so the
//// tests can build the transactions that freeze accepted and show each is now
//// refused. Nothing outside the tests reads this module.

use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, EventEvidence}
use cardano_keri/checkpoint/threshold.{Unweighted}

/// A tip whose next rotation was witnessed with one receipt.
pub const lag_tip: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: #"beaac6be961817c711dbfc5f2b682b59eac12ac258ee7353c438e2ff2c973718",
    cur_keys: [
      #"2ada8517531672dbeb18af8350113ec9d0e76ddf78f863f83e6cc6ccbdceaa28",
    ],
    cur_threshold: Unweighted(1),
    next_keys: [
      #"664a882fc4715bda1cb327c94514de4dd378456dda0790c7e10b68ab90a64252",
    ],
    next_threshold: Unweighted(1),
    witnesses: [
      #"048b4ce41b48c054bfa382b509f35ce8fe75168215a9d96914d13e08b0c1c248",
    ],
    toad: 1,
    seq: 0,
    native_sn: 0,
  }

pub const rotation_evidence: EventEvidence =
  EventEvidence {
    event_bytes: #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22726f74222c2264223a2245456c41534f6a6c7555357477505a5249376569786a5132712d3237585f6b6858446d66456250515776796c222c2269223a22454c36717872365747426648456476385879746f4b316e7177537243574f357a55385134347638736c7a6359222c2273223a2231222c2270223a22454c36717872365747426648456476385879746f4b316e7177537243574f357a55385134347638736c7a6359222c226b74223a2231222c226b223a5b224446677073757449354d75786970703337442d717a6c6272624e6250675a746e355479507235684c4e566270225d2c226e74223a2231222c226e223a5b224546514c3141446d305f417149594242754679554447396278496d744250446d526d4157384f6c5a4d45686e225d2c226274223a2231222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d",
    t: #"726f74",
    native_sn: 1,
    cesr_aid: #"beaac6be961817c711dbfc5f2b682b59eac12ac258ee7353c438e2ff2c973718",
    said: #"494048e8e5b94e6dc0f65123b7a2c63436abedbb5ff9215c399f11b3d05afca5",
    revealed_keys: [
      #"5829b2eb48e4cbb18a9a77ec3faace56eb6cd6cf819b67e53c8faf984b3556e9",
    ],
    next_keys: [
      #"540bd400e6d3f02a218041b85c940c6f5bc489ad04f0e6466016f0e959304867",
    ],
    cur_threshold: Unweighted(1),
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 1,
    ctrl_sigs: [
      (
        0,
        #"174cbab4598c7907ddcfe09a1b928317d89e02b4ded5e66cff075a5eea8a9b6f2d218af4babc65fd64c794af85f04d072b73c8e5ff7360de281675dd5ae4050f",
      ),
    ],
    wit_sigs: [
      (
        0,
        #"aa05eea539101d6792560bc1299d60a6e4895c346ffff2013b174e366b736e32b5948f6294357a676c5de78cdc531fef3f8c62feafffddabd58b4943939ba709",
      ),
    ],
  }

pub const rotation_wire: EnforcementEvidence =
  EnforcementEvidence {
    event_bytes: rotation_evidence.event_bytes,
    off_t: 30,
    off_i: 91,
    off_s: 142,
    off_d: 40,
    off_k: [211],
    off_kt: 202,
    off_n: [273],
    off_nt: 264,
    off_bt: 326,
    native_sn: rotation_evidence.native_sn,
    said: rotation_evidence.said,
    revealed_keys: rotation_evidence.revealed_keys,
    next_keys: rotation_evidence.next_keys,
    cur_threshold: rotation_evidence.cur_threshold,
    next_threshold: rotation_evidence.next_threshold,
    toad: rotation_evidence.toad,
    ctrl_sigs: rotation_evidence.ctrl_sigs,
    wit_sigs: rotation_evidence.wit_sigs,
  }
