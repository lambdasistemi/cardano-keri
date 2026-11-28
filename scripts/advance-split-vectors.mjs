#!/usr/bin/env node
// Generates the vectors of the two-policy advance (fact policy and change policy) for the current datum layout:
// the Plutus Data of each case (spent and successor datums, evidence, freeze payload, fact), and the asset names of
// the fact, of the change claim (for successor index 0 and 1, rotation and freeze) and of the checkpoint's token.
//
//   onchain/lib/cardano_keri/checkpoint/advance_split_vectors.ak
//   offchain/test/keri-fixtures/fixtures/advance-split-names.json   (the names and the serialised redeemers the Haskell encoders are compared with)
//
//   node scripts/advance-split-vectors.mjs            # write
//   node scripts/advance-split-vectors.mjs --check    # exit 1 when it drifts
//
// Input: offchain/test/keri-fixtures/fixtures/advance-split-cases.json, the Plutus Data trees of the advance
// vectors of the repository (`pos_adv_wit_2key`, `pos_adv_keep`, `pos_adv_wit_7key`) as datums and evidence,
// provenance in its `_provenance` field. The names are computed here, by the rules of the Plutus Data serialisation
// and an independent BLAKE2b-256 (`application-support.mjs`), never taken from the code under test.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { aiken, blake2b, concat, hex, root, unhex } from './application-support.mjs';

const cases = JSON.parse(readFileSync(join(root, 'offchain/test/keri-fixtures/fixtures/advance-split-cases.json'), 'utf8'));
const libPath = join(root, 'onchain/lib/cardano_keri/checkpoint/advance_split_vectors.ak');

const uint = (major, n) => {
  const x = BigInt(n);
  const bytes = x < 24n ? [major | Number(x)] : x < 256n ? [major | 24, Number(x)] : x < 65536n ? [major | 25, Number(x >> 8n), Number(x & 255n)] : x < 4294967296n ? [major | 26, ...[24n, 16n, 8n, 0n].map((s) => Number((x >> s) & 255n))] : [major | 27, ...[56n, 48n, 40n, 32n, 24n, 16n, 8n, 0n].map((s) => Number((x >> s) & 255n))];
  return Uint8Array.from(bytes);
};
const bytes = (h) => {
  const b = unhex(h);
  if (b.length <= 64) return concat(uint(0x40, b.length), b);
  const chunks = [];
  for (let i = 0; i < b.length; i += 64) chunks.push(concat(uint(0x40, Math.min(64, b.length - i)), b.subarray(i, i + 64)));
  return concat(Uint8Array.of(0x5f), ...chunks, Uint8Array.of(0xff));
};
const list = (items) => (items.length === 0 ? Uint8Array.of(0x80) : concat(Uint8Array.of(0x9f), ...items, Uint8Array.of(0xff)));
const enc = (t) => {
  if ('i' in t) return uint(0, t.i);
  if ('b' in t) return bytes(t.b);
  if ('l' in t) return list(t.l.map(enc));
  return concat(uint(0xc0, 121 + t.c), list(t.f.map(enc)));
};
const aikenOf = (t) => ('i' in t ? `builtin.i_data(${t.i})` : 'b' in t ? `builtin.b_data(#"${t.b}")` : 'l' in t ? `builtin.list_data([${t.l.map(aikenOf).join(', ')}])` : `builtin.constr_data(${t.c}, [${t.f.map(aikenOf).join(', ')}])`);
const I = (n) => ({ i: n }), B = (h) => ({ b: h }), C = (c, ...f) => ({ c, f }), L = (...l) => ({ l });
const text = (s) => Buffer.from(s).toString('hex');
const name = (t) => hex(blake2b(enc(t), 32));

// the fixed parameters of the vectors
const STATE_POLICY = '51'.repeat(28);
const REGISTRY_NAME = hex(blake2b(Uint8Array.from(Buffer.from('registry')), 32));
const CHECKPOINT_POLICY = 'cc'.repeat(28);
const CLAIM_TAG = text('cardano-keri/advance/v1');
const FACT_TAG = text('cardano-keri/signed/v1');
const OBSERVE_ADVANCE = 1, OBSERVE_FREEZE = 2;

const out = [];
const namesOut = {};
for (const [key, c] of Object.entries(cases)) {
  if (key.startsWith('_')) continue;
  const ref = C(0, B(c.txid), I(c.index));
  const fact = c.fact.f;
  const factName = name(L(B(FACT_TAG), B(hex(blake2b(unhex(fact[0].b), 32))), fact[1], fact[2], fact[3], fact[4], fact[5], fact[6]));
  const claim = (action, index) => name(C(0, B(CLAIM_TAG), I(action), B(CHECKPOINT_POLICY), ref, I(index)));
  const envelope = (action, payload) => C(0, C(0, I(action), B(CHECKPOINT_POLICY), C(0, ref)), payload);
  const issue = (action, payload, index) => hex(enc(C(0, L(C(0, envelope(action, payload), I(index))))));
  namesOut[key] = {
    txid: c.txid,
    index: c.index,
    checkpointPolicy: CHECKPOINT_POLICY,
    factName,
    changeNames: {
      advance_at_0: claim(OBSERVE_ADVANCE, 0), advance_at_1: claim(OBSERVE_ADVANCE, 1),
      freeze_at_0: claim(OBSERVE_FREEZE, 0), freeze_at_1: claim(OBSERVE_FREEZE, 1),
    },
    // the serialised redeemers: Issue of the fact; Issue of one claim at its successor index
    factIssueRedeemer: hex(enc(C(0, L(c.fact)))),
    changeIssueRedeemers: {
      advance_at_0: issue(OBSERVE_ADVANCE, c.evidence, 0), advance_at_1: issue(OBSERVE_ADVANCE, c.evidence, 1),
      freeze_at_0: issue(OBSERVE_FREEZE, c.freezePayload, 0), freeze_at_1: issue(OBSERVE_FREEZE, c.freezePayload, 1),
    },
    burnRedeemer: hex(enc(C(1))),
  };
  const tokenName = name(C(1, C(0, B(STATE_POLICY), B(REGISTRY_NAME)), B(text(c.aid))));
  const fn = (field, tree) => `pub fn ${key}_${field}() -> Data {\n  ${aikenOf(tree)}\n}\n`;
  out.push(`// ---- ${key} ----\n` + [
    fn('old_datum', c.oldDatum), fn('new_datum', c.newDatum), fn('frozen_datum', c.frozenOld), fn('evidence', c.evidence), fn('freeze_payload', c.freezePayload), fn('fact', c.fact),
  ].join('\n') + `\npub const ${key}_txid: ByteArray = #"${c.txid}"\n\npub const ${key}_index: Int = ${c.index}\n\npub const ${key}_token_name: ByteArray = #"${tokenName}"\n\npub const ${key}_fact_name: ByteArray = #"${factName}"\n\n` +
    [[OBSERVE_ADVANCE, 0, 'rotation_at_0'], [OBSERVE_ADVANCE, 1, 'rotation_at_1'], [OBSERVE_FREEZE, 0, 'freeze_at_0'], [OBSERVE_FREEZE, 1, 'freeze_at_1']].map(([a, i, label]) => `pub const ${key}_change_${label}: ByteArray = #"${claim(a, i)}"\n`).join('\n'));
}
const lib = `//// Vectors of the two-policy advance for the current datum layout, generated by
//// scripts/advance-split-vectors.mjs (never edited by hand): the Plutus Data of each case and the asset
//// names of the fact, of the change claim and of the checkpoint token, computed independently of the validators.
//// Fixed parameters: state policy ${STATE_POLICY}, registry name ${REGISTRY_NAME},
//// checkpoint policy ${CHECKPOINT_POLICY}.

use aiken/builtin

pub const state_policy: ByteArray = #"${STATE_POLICY}"

pub const registry_name: ByteArray = #"${REGISTRY_NAME}"

pub const checkpoint_policy: ByteArray = #"${CHECKPOINT_POLICY}"

${out.join('\n')}`;
const format = (nm, t) => {
  const work = mkdtempSync(join(tmpdir(), 'split-fmt-'));
  try { writeFileSync(join(work, nm), t); aiken(work, 'fmt', nm); return readFileSync(join(work, nm), 'utf8'); } finally { rmSync(work, { recursive: true, force: true }); }
};
const formatted = format('advance_split_vectors.ak', lib);
const namesPath = join(root, 'offchain/test/keri-fixtures/fixtures/advance-split-names.json');
const namesText = JSON.stringify(namesOut, null, 2) + '\n';
if (process.argv.includes('--check')) {
  const committed = existsSync(libPath) ? readFileSync(libPath, 'utf8') : '';
  if (committed !== formatted) { console.error(`${libPath} drifts from scripts/advance-split-vectors.mjs`); process.exit(1); }
  const committedNames = existsSync(namesPath) ? readFileSync(namesPath, 'utf8') : '';
  if (committedNames !== namesText) { console.error(`${namesPath} drifts from scripts/advance-split-vectors.mjs`); process.exit(1); }
  console.log('advance split vectors: no drift');
} else {
  writeFileSync(libPath, formatted);
  writeFileSync(namesPath, namesText);
  console.log(`wrote ${libPath}`);
}
