#!/usr/bin/env node
// Generates the Aiken cases of the signed-byte layer of the conviction:
//   onchain/lib/cardano_keri/checkpoint/rival_bytes_vectors.ak
// from the keripy 1.3.5 fixtures committed under offchain/test/keri-fixtures
// (gen_fixtures.py). keripy is the oracle: every event, controller signature and
// witness receipt is its own, and the expected SAID is the one keripy computed.
// Per case: the previous establishment the rotation follows (from the
// inception), the decoded claim of the rotation, the wire evidence (exact bytes,
// value offsets, signatures, receipts) and keripy's SAID text.
//
//   node scripts/rival-bytes-vectors.mjs   # write the module; `aiken fmt` canonicalizes it
//
// Mapping, written once here: a qualified base64 value (key, digest, witness) is
// its 32 raw bytes; thresholds and numbers are the hexadecimal text keripy
// writes; offsets are computed from the exact bytes (value text after the opening
// quote), and the offset of the opening bracket of each of k, n, br and ba is
// added, so that a whole list can be bound to the bytes.
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

function offsets(text, ked) {
  const at = (label) => { const i = text.indexOf(`"${label}":`); if (i < 0 || text.indexOf(`"${label}":`, i + 1) >= 0) throw new Error(`label ${label}`); return i + label.length + 3; };
  const str = (label) => { const o = at(label); if (text[o] !== '"') throw new Error(`${label} not a string`); return o + 1; };
  const list = (label) => {
    const open = at(label);
    if (text[open] !== '[') throw new Error(`${label} not a list`);
    let cursor = open + 1;
    const items = ked[label].map((value) => { const o = text.indexOf(`"${value}"`, cursor); if (o < 0) throw new Error(`${label} item`); cursor = o + value.length + 2; return o + 1; });
    return { open, items };
  };
  return { t: str('t'), i: str('i'), s: str('s'), d: str('d'), kt: str('kt'), nt: str('nt'), bt: str('bt'), k: list('k'), n: list('n'), br: list('br'), ba: list('ba') };
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
  const o = offsets(text, ked);
  const sig = (s) => `(${s.index}, #"${s.sig_hex}")`;
  const sigs = family[sigKey].map(sig);
  const receipts = (receiptKey ? family[receiptKey] : []).map(sig);
  const aid = raw32(ked.i);
  const cut = ked.br.map(raw32);
  const add = ked.ba.map(raw32);
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
      cur_keys: ${bytesList(ked.k.map(raw32))},
      cur_threshold: ${threshold(ked.kt)},
      next_keys: ${bytesList(ked.n.map(raw32))},
      next_threshold: ${threshold(ked.nt)},
      toad: ${hex(ked.bt)},
      off_d: ${o.d},
      off_k_list: ${o.k.open},
      off_n_list: ${o.n.open},
      off_br_list: ${o.br.open},
      off_ba_list: ${o.ba.open},
    },
    evidence: AdvanceEvidence {
      event_bytes: #"${rot.raw_hex}",
      off_t: ${o.t},
      off_i: ${o.i},
      off_s: ${o.s},
      off_k: ${intList(o.k.items)},
      off_kt: ${o.kt},
      off_n: ${intList(o.n.items)},
      off_nt: ${o.nt},
      off_br: ${intList(o.br.items)},
      off_ba: ${intList(o.ba.items)},
      off_bt: ${o.bt},
      wit_cut: ${bytesList(cut)},
      wit_add: ${bytesList(add)},
      ctrl_sigs: [${sigs.join(', ')}],
      wit_receipts: [${receipts.join(', ')}],
    },
    said: "${rot.said}",
  }
`;
});

const header = `//// GENERATED by scripts/rival-bytes-vectors.mjs from the keripy 1.3.5 fixtures
//// under offchain/test/keri-fixtures/fixtures. DO NOT EDIT.
//// \`just check-rival-bytes-vectors\` regenerates it and rejects drift.
////
//// One signed rotation per case: the previous establishment it follows, its
//// decoded claim, the wire evidence (exact bytes, offsets, controller
//// signatures, witness receipts) and the SAID keripy computed for it. Nothing
//// here is derived by the code under test.

use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/rival.{Previous}
use cardano_keri/checkpoint/rival_evidence.{RivalClaim}
use cardano_keri/checkpoint/threshold.{Unweighted}

pub type Case {
  name: ByteArray,
  previous: Previous,
  claim: RivalClaim,
  evidence: AdvanceEvidence,
  said: ByteArray,
}
`;
writeFileSync(out, header + rows.join(''));
