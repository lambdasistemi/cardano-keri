#!/usr/bin/env node
// Generates the Aiken cases of the signed-byte layer of the conviction:
//   onchain/lib/cardano_keri/checkpoint/rival_bytes_vectors.ak
// from the keripy 1.3.5 fixtures committed under offchain/test/keri-fixtures
// (gen_fixtures.py). keripy is the oracle: every event, controller signature and
// witness receipt is its own, and the expected SAID is the one keripy computed.
// Per case: the previous establishment the rotation follows (from the
// inception), the decoded claim of the rotation, the wire evidence (exact bytes,
// signatures, receipts) and keripy's SAID text.
//
//   node scripts/rival-bytes-vectors.mjs   # write the module; `aiken fmt` canonicalizes it
//
// Mapping, written once here: a qualified base64 value (key, digest, witness) is
// its 32 raw bytes; thresholds and numbers are the hexadecimal text keripy
// writes. No offsets are supplied to the code under test: the canonical field
// positions are derived there. The generator adds probe offsets (labels and the
// anchor list) that only the defensive tests use to build tampered bytes.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = resolve(root, 'offchain/test/keri-fixtures/fixtures');
const out = resolve(root, 'onchain/lib/cardano_keri/checkpoint/rival_bytes_vectors.ak');

// [fixture, name, inception key, rotation key, controller signatures key, receipts key]
const cases = [
  ['fork.json', 'fork_recorded', 'icp', 'rot_recorded', 'rot_recorded_sigs', null],
  ['fork.json', 'fork_rival', 'icp', 'rot_conflict', 'rot_conflict_sigs', null],
  ['fork_witnessed.json', 'fork_witnessed_recorded', 'icp', 'rot_recorded', 'rot_recorded_sigs', 'rot_recorded_witness_receipts'],
  ['fork_witnessed.json', 'fork_witnessed_rival', 'icp', 'rot_conflict', 'rot_conflict_sigs', 'rot_conflict_witness_receipts'],
  ['honest_2key.json', 'honest_2key_rotation', 'icp', 'rot', 'rot_sigs', null],
  ['advance.json#adv_wit_2key', 'advance_witnessed_2key', 'icp', 'rot', 'rot_sigs', 'rot_witness_receipts'],
];

const raw32 = (qb64) => {
  if (!/^[A-Za-z0-9_-]{44}$/.test(qb64)) throw new Error(`qb64 spelling ${qb64}`);
  const bytes = Buffer.from(`A${qb64.slice(1)}`, 'base64url');
  if (bytes.length !== 33 || bytes[0] !== 0) throw new Error(`qb64 padding ${qb64}`);
  return bytes.subarray(1).toString('hex');
};
const hex = (s) => { if (!/^[0-9a-f]+$/.test(s)) throw new Error(`hex text ${s}`); return parseInt(s, 16); };
const threshold = (s) => { if (typeof s !== 'string') throw new Error('weighted thresholds are not in these cases'); return `Unweighted(${hex(s)})`; };
const bytesList = (xs) => `[${xs.map((x) => `#"${x}"`).join(', ')}]`;
const intList = (xs) => `[${xs.join(', ')}]`;

function probes(text) {
  const at = (needle) => { const i = text.indexOf(needle); if (i < 0 || text.indexOf(needle, i + 1) >= 0) throw new Error(`probe ${needle}`); return i; };
  return { kt: at('"kt":'), s: at('"s":'), a: at('"a":') + 4, d: at('"d":"') + 5 };
}

const rows = cases.map(([file, name, icpKey, rotKey, sigKey, receiptKey]) => {
  const [fileName, sub] = file.split('#');
  const doc = JSON.parse(readFileSync(resolve(fixtures, fileName), 'utf8'));
  const family = sub ? doc[sub] : doc;
  const icp = family[icpKey].ked;
  const rot = family[rotKey];
  const text = Buffer.from(rot.raw_hex, 'hex').toString('latin1');
  const ked = JSON.parse(text);
  if (ked.t !== 'rot' || text.length !== rot.raw_len || ked.d !== rot.said) throw new Error(`${name} is not the fixture's rotation`);
  const o = probes(text);
  const sig = (s) => `(${s.index}, #"${s.sig_hex}")`;
  const sigs = family[sigKey].map(sig);
  const receipts = (receiptKey ? family[receiptKey] : []).map(sig);
  const aid = raw32(ked.i);
  if (ked.p.length !== 44) throw new Error('p spelling');
  if (text.slice(o.a, o.a + 1) !== '[' || !text.endsWith(']}')) throw new Error('anchor tail');
  return `
pub const ${name}: Case =
  Case {
    name: "${name}",
    previous: Previous {
      aid: #"${aid}",
      sn: ${hex(icp.s)},
      next_keys: ${bytesList(icp.n.map(raw32))},
      next_threshold: ${threshold(icp.nt)},
      witnesses: ${bytesList(icp.b.map(raw32))},
    },
    claim: RivalClaim {
      aid: #"${aid}",
      sn: ${hex(ked.s)},
      prior: "${ked.p}",
      cur_keys: ${bytesList(ked.k.map(raw32))},
      cur_threshold: ${threshold(ked.kt)},
      next_keys: ${bytesList(ked.n.map(raw32))},
      next_threshold: ${threshold(ked.nt)},
      toad: ${hex(ked.bt)},
      cuts: ${bytesList(ked.br.map(raw32))},
      adds: ${bytesList(ked.ba.map(raw32))},
    },
    event_bytes: #"${rot.raw_hex}",
    ctrl_sigs: [${sigs.join(', ')}],
    wit_receipts: [${receipts.join(', ')}],
    off_d: ${o.d},
    off_kt: ${o.kt},
    off_s: ${o.s},
    off_a: ${o.a},
    said: "${rot.said}",
  }
`;
});

const header = `//// GENERATED by scripts/rival-bytes-vectors.mjs from the keripy 1.3.5 fixtures
//// under offchain/test/keri-fixtures/fixtures. DO NOT EDIT.
//// \`just check-rival-bytes-vectors\` regenerates it and rejects drift.
////
//// One signed rotation per case: the previous establishment it follows, its
//// decoded claim, the wire evidence (exact bytes, controller
//// signatures, witness receipts) and the SAID keripy computed for it. Nothing
//// here is derived by the code under test.

use cardano_keri/checkpoint/rival.{Previous}
use cardano_keri/checkpoint/rival_evidence.{RivalClaim}
use cardano_keri/checkpoint/threshold.{Unweighted}

pub type Case {
  name: ByteArray,
  previous: Previous,
  claim: RivalClaim,
  event_bytes: ByteArray,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_receipts: List<(Int, ByteArray)>,
  /// Offsets used only to build tampered bytes in the defensive tests.
  off_d: Int,
  off_kt: Int,
  off_s: Int,
  off_a: Int,
  said: ByteArray,
}
`;
const names = cases.map((c) => c[1]);
const wrapped = [];
let line = '   ';
for (const n of names) {
  const piece = ` ${n},`;
  if ((line + piece).length > 80) { wrapped.push(line); line = '   '; }
  line += piece;
}
wrapped.push(line);
const all = `
pub const all: List<Case> =
  [
${wrapped.join('\n')}
  ]
`;
writeFileSync(out, header + rows.join('') + all);
