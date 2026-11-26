#!/usr/bin/env node
// Generates the parity vectors of the booking attestation: the claim of a
// booking with its wrapped initial datum, the name that digests it, the Issue
// redeemer with the evidence of each request, and the Burn redeemer.
//
//   onchain/lib/cardano_keri/application/attestation_vectors.ak
//       tests that run the validators' own functions and types over the vectors
//   offchain/test/keri-fixtures/fixtures/attestation-vectors.json
//       the same vectors for the Haskell encoder and hash, which the
//       specification in offchain/test/Cardano/KERI/AID/Checkpoint reads
//
//   node scripts/attestation-vectors.mjs            # write both files
//   node scripts/attestation-vectors.mjs --check    # exit 1 when either drifts
//
// Needs `aiken` (the pinned compiler) to canonicalise the Aiken module.
//
// The expected bytes are written here, from the rules of the Plutus Data
// serialisation (definite short items, indefinite lists and constructor fields,
// byte strings of more than 64 bytes in chunks of 64) and an independent BLAKE2b-256
// (`application-support.mjs`), never taken from the code under test, so a change of
// either implementation differs from this file and drifts, whichever side moved.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { aiken, blake2b, concat, hex, root, unhex } from './application-support.mjs';

const libPath = join(root, 'onchain/lib/cardano_keri/application/attestation_vectors.ak');
const jsonPath = join(root, 'offchain/test/keri-fixtures/fixtures/attestation-vectors.json');

// --- Plutus Data trees: {i: n} {b: hex} {c: n, f: [...]} {l: [...]} -------------
const I = (n) => ({ i: n });
const B = (h) => ({ b: h });
const C = (n, ...f) => ({ c: n, f });
const L = (...l) => ({ l });

const uint = (major, n) => {
  const v = BigInt(n);
  const head = (m, x) => (x < 24n ? [m | Number(x)] : x < 256n ? [m | 24, Number(x)] : x < 65536n ? [m | 25, Number(x >> 8n), Number(x & 255n)] : x < 4294967296n ? [m | 26, ...[24n, 16n, 8n, 0n].map((s) => Number((x >> s) & 255n))] : [m | 27, ...[56n, 48n, 40n, 32n, 24n, 16n, 8n, 0n].map((s) => Number((x >> s) & 255n))]);
  if (v >= 1n << 64n) throw new Error('integer too large for this encoder');
  return Uint8Array.from(head(major << 5, v));
};
const bytes = (h) => {
  const b = unhex(h);
  if (b.length <= 64) return concat(uint(2, b.length), b);
  const chunks = [];
  for (let i = 0; i < b.length; i += 64) chunks.push(concat(uint(2, Math.min(64, b.length - i)), b.subarray(i, i + 64)));
  return concat(Uint8Array.of(0x5f), ...chunks, Uint8Array.of(0xff));
};
const list = (items) => (items.length === 0 ? Uint8Array.of(0x80) : concat(Uint8Array.of(0x9f), ...items, Uint8Array.of(0xff)));
const enc = (t) => {
  if ('i' in t) return uint(0, t.i);
  if ('b' in t) return bytes(t.b);
  if ('l' in t) return list(t.l.map(enc));
  if (t.c > 6) throw new Error('constructor above 6 is not needed here');
  return concat(uint(6, 121 + t.c), list(t.f.map(enc)));
};
const aikenOf = (t) => {
  if ('i' in t) return `builtin.i_data(${t.i})`;
  if ('b' in t) return `builtin.b_data(#"${t.b}")`;
  if ('l' in t) return `builtin.list_data([${t.l.map(aikenOf).join(', ')}])`;
  return `builtin.constr_data(${t.c}, [${t.f.map(aikenOf).join(', ')}])`;
};

// --- the vectors ---------------------------------------------------------------
const TAG = Buffer.from('cardano-keri/book-registration/v1').toString('hex');
const app = 'c0'.repeat(28);
const ascii = (s) => Buffer.from(s).toString('hex');
// A version 2 live checkpoint datum wrapped as the codec writes it: constructor 1 holding
// constructor 0 with the AID text, sn, epoch, the three flags, the refund bytes and the key material.
const wrapped = C(1, C(0,
  B(ascii('D' + 'A'.repeat(43))), I(0), I(0), C(0), C(0), I(10), B('60' + '77'.repeat(28)), C(0),
  C(0, L(B('11'.repeat(32)), B('12'.repeat(32))), C(0, I(2)), L(B('13'.repeat(32))), C(0, I(1)), L(), I(0))));
const claims = [
  { name: 'a small datum, an index and a deposit', application: app, index: 3, datum: C(1, B(ascii('initial')), I(7)), deposit: 1009000000 },
  { name: 'a wrapped initial datum', application: app, index: 0, datum: wrapped, deposit: 1009000000 },
  { name: 'a wide index and a wide deposit', application: app, index: 300, datum: wrapped, deposit: 5000000000000 },
];
const evidenceOf = (e) => C(0,
  B(e.event_bytes), I(e.off_t), I(e.off_i), I(e.off_s), L(...e.off_k.map(I)), I(e.off_kt), L(...e.off_n.map(I)), I(e.off_nt), L(...e.off_b.map(I)), I(e.off_bt),
  L(...e.ctrl_sigs.map(([k, s]) => L(I(k), B(s)))), L(...e.wit_receipts.map(([k, s]) => L(I(k), B(s)))));
const evidence = {
  event_bytes: ascii('icp'), off_t: 1, off_i: 2, off_s: 3, off_k: [4], off_kt: 5, off_n: [6], off_nt: 7, off_b: [8], off_bt: 9,
  ctrl_sigs: [[0, 'a1'.repeat(64)]], wit_receipts: [[1, 'b1'.repeat(64)]],
};
const otherEvidence = {
  event_bytes: ascii('icq'), off_t: 11, off_i: 12, off_s: 13, off_k: [14, 15], off_kt: 16, off_n: [17], off_nt: 18, off_b: [], off_bt: 19,
  ctrl_sigs: [[1, 'a2'.repeat(64)], [2, 'b2'.repeat(64)]], wit_receipts: [],
};
// Event bytes longer than 64 bytes are written in chunks of 64: the case the short ones do not reach.
const longEvidence = { ...evidence, event_bytes: 'ee'.repeat(100), off_k: [4, 300] };
const issues = [
  { name: 'two requests of distinct evidence', application: app, entries: [{ index: 3, evidence }, { index: 5, evidence: otherEvidence }] },
  { name: 'one request whose event bytes are longer than 64 bytes', application: app, entries: [{ index: 300, evidence: longEvidence }] },
];

const claimTree = (c) => C(0, B(TAG), B(c.application), I(c.index), c.datum, I(c.deposit));
const issueTree = (x) => C(0, B(x.application), L(...x.entries.map((e) => C(0, I(e.index), evidenceOf(e.evidence)))));
const burnTree = C(1);

const vectors = {
  claims: claims.map((c) => {
    const claim = enc(claimTree(c));
    return { ...c, claim: hex(claim), assetName: hex(blake2b(claim, 32)) };
  }),
  issues: issues.map((x) => ({ ...x, redeemer: hex(enc(issueTree(x))) })),
  burn: { redeemer: hex(enc(burnTree)) },
};
if (vectors.burn.redeemer !== 'd87a80') throw new Error('Burn is not constructor one with no field');

// --- the Aiken module -----------------------------------------------------------
const aikenEvidence = (e) => `RegistrationEvidence {
        event_bytes: #"${e.event_bytes}",
        off_t: ${e.off_t},
        off_i: ${e.off_i},
        off_s: ${e.off_s},
        off_k: [${e.off_k.join(', ')}],
        off_kt: ${e.off_kt},
        off_n: [${e.off_n.join(', ')}],
        off_nt: ${e.off_nt},
        off_b: [${e.off_b.join(', ')}],
        off_bt: ${e.off_bt},
        ctrl_sigs: [${e.ctrl_sigs.map(([k, s]) => `(${k}, #"${s}")`).join(', ')}],
        wit_receipts: [${e.wit_receipts.map(([k, s]) => `(${k}, #"${s}")`).join(', ')}],
      }`;
const lib = `//// Parity vectors of the booking attestation, generated by
//// scripts/attestation-vectors.mjs (never edited by hand).
////
//// The claim of a booking, the name that digests it, the Issue redeemer with
//// the evidence of each request and the Burn redeemer, run through the
//// validators' own function and types. The Haskell encoder reads the same
//// vectors from offchain/test/keri-fixtures/fixtures/attestation-vectors.json.

use aiken/builtin
use cardano_keri/application/attestation.{
  BookedRequest, Burn, Issue, attestation_claim, attestation_name,
}
use cardano_keri/checkpoint/registration.{RegistrationEvidence}

${vectors.claims.map((c, k) => `/// The claim of ${c.name}.
test claim_${k}_has_the_vector_bytes() {
  builtin.serialise_data(
    attestation_claim(#"${c.application}", ${c.index}, ${aikenOf(c.datum)}, ${c.deposit}),
  ) == #"${c.claim}"
}

/// The name that digests it.
test claim_${k}_has_the_vector_name() {
  attestation_name(#"${c.application}", ${c.index}, ${aikenOf(c.datum)}, ${c.deposit}) == #"${c.assetName}"
}
`).join('\n')}
${vectors.issues.map((x, k) => `/// The Issue redeemer of ${x.name}.
test issue_${k}_has_the_vector_bytes() {
  let redeemer: Data =
    Issue {
      application_policy: #"${x.application}",
      entries: [${x.entries.map((e) => `BookedRequest { request_index: ${e.index}, evidence: ${aikenEvidence(e.evidence)} }`).join(', ')}],
    }
  builtin.serialise_data(redeemer) == #"${x.redeemer}"
}
`).join('\n')}
/// The Burn redeemer.
test burn_has_the_vector_bytes() {
  let redeemer: Data = Burn
  builtin.serialise_data(redeemer) == #"${vectors.burn.redeemer}"
}
`;

const format = (name, text) => {
  const work = mkdtempSync(join(tmpdir(), 'attestation-fmt-'));
  try {
    writeFileSync(join(work, name), text);
    aiken(work, 'fmt', name);
    return readFileSync(join(work, name), 'utf8');
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
};

const json = `${JSON.stringify({ note: 'generated by scripts/attestation-vectors.mjs; claims and redeemers are Plutus Data CBOR hex, datum and evidence are the inputs', ...vectors }, null, 2)}\n`;
const outputs = [
  [libPath, format('attestation_vectors.ak', lib)],
  [jsonPath, json],
];
if (process.argv.includes('--check')) {
  let drift = false;
  for (const [path, text] of outputs) {
    const committed = existsSync(path) ? readFileSync(path, 'utf8') : '';
    if (committed !== text) {
      console.error(`${path} drifts from scripts/attestation-vectors.mjs`);
      drift = true;
    }
  }
  if (drift) process.exit(1);
  console.log('attestation vectors: no drift');
} else {
  for (const [path, text] of outputs) writeFileSync(path, text);
  console.log(`wrote ${outputs.map(([path]) => path).join(', ')}`);
}
