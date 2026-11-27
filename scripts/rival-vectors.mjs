#!/usr/bin/env node
// Generates the Aiken tests of the conviction predicate:
//   onchain/lib/cardano_keri/checkpoint/rival_vectors.ak
// from two vendored outputs of the draft Lean model (specs/573-conviction/model,
// see PIN.md there): the 17 rows of the rival validity vectors and the
// rotation admission cases (#595 own next threshold, #596 zero signing, #598
// witness changes). The model is draft #582 at
// 95d97298200630f4afb376d0e06a77245664966e with #592 at
// b4f62b653d70653ba022a82fb935ced131b853db on top; each vendored copy is checked
// against its digest below.
//
//   node scripts/rival-vectors.mjs   # write the module; `aiken fmt` then canonicalizes it
//
// Mapping of the model's decoded values onto Aiken values, written once here:
//   key, aid, witness identity n   -> the 32 bytes of n, big endian (`key_of`);
//                                    aids and witnesses use disjoint ranges
//   previous next-key identity n   -> `next_key_digest(key_of(n))`, the KERI `n`
//                                    entry for that key (`commitment_of`)
//   threshold count r / weighted   -> Unweighted(r) / Weighted([[Weight{num,den}]])
//   event digest (text)            -> its bytes, compared and never derived here
//   a signature or receipt         -> the signer identity, kept only when it is
//                                    verified AND bound to the rival's own event
//                                    (the model's `verifiedSigners`); on chain this
//                                    is the Ed25519 check over the signed bytes
// Rotation admission cases are judged as a rival of a valid first-seen sibling
// (the case's own context): the tip is the case's identifier at epoch one and its
// sequence, carrying the case's predecessor, with the first-seen event's digest.
// A case whose threshold has a nested group is not representable on chain and is
// listed in the generated header, not generated.
// Dropped: the tip's key material (its agreement with the spent datum is a
// separate layer) and `delegated` (every row has it false; the V1 profile
// registers non-delegated identifiers only). A nested group threshold has no
// on-chain representation and stops the generator: that is a recorded gap,
// not a row to skip.
// The expected verdicts are the Lean's, read from the rows; the Aiken code is
// the thing under test.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const input = resolve(root, 'specs/573-conviction/model/checkpoint-rival-validity-vectors.json');
const admissionInput = resolve(root, 'specs/573-conviction/model/rotation-admission.json');
const admissionSha256 = '397a542b4229ae6684bec0fcbfa418bff6269936f37de3160ca14bc184513d61';
const out = resolve(root, 'onchain/lib/cardano_keri/checkpoint/rival_vectors.ak');
const pinnedSha256 = '2f7e5f504119bd8ba7fa2afaf67bff6e34d698ee84c49aa7a374b376e4d150aa';

const raw = readFileSync(input);
if (createHash('sha256').update(raw).digest('hex') !== pinnedSha256) throw new Error('vendored rows differ from the pinned draft');
const rows = JSON.parse(raw.toString('utf8'));
if (!Array.isArray(rows) || rows.length !== 17) throw new Error(`expected 17 rows, found ${rows.length}`);

const admissionRaw = readFileSync(admissionInput);
if (createHash('sha256').update(admissionRaw).digest('hex') !== admissionSha256) throw new Error('vendored admission cases differ from the pinned model');
const admissionDoc = JSON.parse(admissionRaw.toString('utf8'));
const admission = admissionDoc.rotations;
const signingCases = admissionDoc.thresholds;
if (!Array.isArray(signingCases) || signingCases.length !== 4) throw new Error('expected 4 signing cases');
if (!Array.isArray(admission) || admission.length !== 21) throw new Error(`expected 21 admission cases, found ${admission.length}`);

const stable = (v) => JSON.stringify(v, (_, x) => (x && typeof x === 'object' && !Array.isArray(x)
  ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, x[k]])) : x));
const ints = (xs) => `[${xs.join(', ')}]`;
const text = (s) => `"${s}"`;
if (rows.some((r) => /[^A-Za-z0-9 _.\/-]/.test(r.name))) throw new Error('row name spelling');
const ident = (name) => `row_${name.replace(/[^a-z0-9]+/g, '_')}`;

function threshold(t) {
  if (t.count) return `Unweighted(${t.count.required})`;
  if (t.weighted) {
    const clauses = t.weighted.clauses.map((clause) => `[${clause.map((w) => {
      if (!w.key) throw new Error('nested group threshold has no on-chain representation');
      return `Weight { num: ${w.key.weight.numerator}, den: ${w.key.weight.denominator} }`;
    }).join(', ')}]`);
    return `Weighted([${clauses.join(', ')}])`;
  }
  throw new Error(`threshold shape ${stable(t)}`);
}

function previous(p) {
  if (p === null) return 'None';
  if (p.delegated) throw new Error('delegated predecessor');
  return `Some(PreviousIds { aid: ${p.aid}, sn: ${p.sn}, next_keys: ${ints(p.nextKeys)}, next_threshold: ${threshold(p.nextThreshold)}, witnesses: ${ints(p.witnesses)} })`;
}

function bound(list, event) {
  return list.filter((s) => s.verified && stable(s.event) === stable(event)).map((s) => s.signer);
}

function rival(r) {
  const e = r.event;
  return `RivalIds { aid: ${e.aid}, sn: ${e.sn}, is_rotation: ${e.kind === 'rotation' ? 'True' : 'False'}, structure_ok: ${r.structureVerified ? 'True' : 'False'}, keys: ${ints(e.keys)}, next_key_count: ${e.nextKeys.length}, threshold: ${threshold(e.threshold)}, next_threshold: ${threshold(e.nextThreshold)}, cuts: ${ints(e.cuts)}, adds: ${ints(e.adds)}, toad: ${e.witnessThreshold}, signers: ${ints(bound(r.signatures, e))}, receipts: ${ints(bound(r.receipts, e))}, event_digest: ${text(e.eventDigest)} }`;
}

// The admission cases as rows of the same shape; those with a nested group are skipped and named.
const skipped = [];
const admissionRows = [];
for (const c of admission) {
  const row = {
    name: `adm ${c.name.toLowerCase()}`,
    input: {
      tip: { aid: c.rotation.event.aid, epoch: 1, sn: c.rotation.event.sn, previous: c.prior, writer: { eventDigest: c.context.accepted.event.eventDigest } },
      rival: c.rotation,
    },
    expectedRotationValid: c.expected,
    expectedConvictionAccepted: c.expected,
  };
  try { previous(row.input.tip.previous); rival(row.input.rival); } catch (e) { skipped.push(c.name); continue; }
  admissionRows.push(row);
}

const header = `//// GENERATED by scripts/rival-vectors.mjs from the vendored outputs of the draft
//// Lean model (checkpoint-rival-validity-vectors.json, sha256 ${pinnedSha256}).
//// DO NOT EDIT.
//// \`just check-rival-vectors\` regenerates it and rejects drift.
////
//// One generated test per row and verdict. The model's decoded identities are
//// carried into bytes by \`key_of\` and \`commitment_of\`; the tip's key material
//// and the delegated flag are dropped (see the generator header). The rows are
//// the oracle: expected verdicts come from the model, never from the code
//// under test. DRAFT: the model revision is a draft until it lands on main.
////
//// Model pin: #582 95d97298 with #592 b4f62b65 (specs/573-conviction/model/PIN.md).
//// Rotation admission cases (sha256 ${admissionSha256}) are rows named \`adm_*\`;
//// not generated, for a nested group threshold with no on-chain form: ${skipped.join(', ')}.

use aiken/builtin
use aiken/collection/list
use cardano_keri/checkpoint/message.{next_key_digest}
use cardano_keri/checkpoint/rival.{
  Previous, Rotation, Tip, conviction_accepts, rotation_valid, satisfied,
}
use cardano_keri/checkpoint/threshold.{
  Threshold, Unweighted, Weight, Weighted,
}

/// The 32 bytes of a model identity.
pub fn key_of(n: Int) -> ByteArray {
  builtin.integer_to_bytearray(True, 32, n)
}

/// An aid is named in a range disjoint from the keys and witnesses.
pub fn aid_of(n: Int) -> ByteArray {
  key_of(1000 + n)
}

/// The next-key commitment of a key: its KERI \`n\` entry.
pub fn commitment_of(n: Int) -> ByteArray {
  next_key_digest(key_of(n))
}

pub type PreviousIds {
  aid: Int,
  sn: Int,
  next_keys: List<Int>,
  next_threshold: Threshold,
  witnesses: List<Int>,
}

pub type RivalIds {
  aid: Int,
  sn: Int,
  is_rotation: Bool,
  structure_ok: Bool,
  keys: List<Int>,
  next_key_count: Int,
  threshold: Threshold,
  next_threshold: Threshold,
  cuts: List<Int>,
  adds: List<Int>,
  toad: Int,
  signers: List<Int>,
  receipts: List<Int>,
  event_digest: ByteArray,
}

pub type TipIds {
  aid: Int,
  epoch: Int,
  sn: Int,
  previous: Option<PreviousIds>,
  writer_digest: ByteArray,
}

pub type Row {
  name: ByteArray,
  tip: TipIds,
  rival: RivalIds,
  expected_rotation_valid: Option<Bool>,
  expected_accepted: Bool,
}

pub fn previous_of(p: PreviousIds) -> Previous {
  Previous {
    aid: aid_of(p.aid),
    sn: p.sn,
    next_keys: list.map(p.next_keys, commitment_of),
    next_threshold: p.next_threshold,
    witnesses: list.map(p.witnesses, key_of),
  }
}

pub fn rotation_of(r: RivalIds) -> Rotation {
  Rotation {
    aid: aid_of(r.aid),
    sn: r.sn,
    is_rotation: r.is_rotation,
    structure_ok: r.structure_ok,
    keys: list.map(r.keys, key_of),
    next_key_count: r.next_key_count,
    threshold: r.threshold,
    next_threshold: r.next_threshold,
    cuts: list.map(r.cuts, key_of),
    adds: list.map(r.adds, key_of),
    toad: r.toad,
    signers: list.map(r.signers, key_of),
    receipts: list.map(r.receipts, key_of),
    event_digest: r.event_digest,
  }
}

pub fn tip_of(t: TipIds) -> Tip {
  Tip {
    aid: aid_of(t.aid),
    epoch: t.epoch,
    sn: t.sn,
    previous: when t.previous is {
      Some(p) -> Some(previous_of(p))
      None -> None
    },
    writer_digest: t.writer_digest,
  }
}
`;

const rowConst = (r) => `
pub const ${ident(r.name)}: Row =
  Row {
    name: ${text(r.name)},
    tip: TipIds { aid: ${r.input.tip.aid}, epoch: ${r.input.tip.epoch}, sn: ${r.input.tip.sn}, previous: ${previous(r.input.tip.previous)}, writer_digest: ${text(r.input.tip.writer.eventDigest)} },
    rival: ${rival(r.input.rival)},
    expected_rotation_valid: ${r.expectedRotationValid === null ? 'None' : `Some(${r.expectedRotationValid ? 'True' : 'False'})`},
    expected_accepted: ${r.expectedConvictionAccepted ? 'True' : 'False'},
  }
`;

const rowTests = (r) => {
  const id = ident(r.name);
  const name = id.replace(/^row_/, '');
  const accepted = `
test ${name}_conviction_verdict() {
  let row = ${id}
  conviction_accepts(tip_of(row.tip), rotation_of(row.rival)) == row.expected_accepted
}
`;
  if (r.expectedRotationValid === null) return accepted;
  return `
test ${name}_rotation_verdict() {
  let row = ${id}
  expect Some(previous) = row.tip.previous
  expect Some(expected) = row.expected_rotation_valid
  rotation_valid(previous_of(previous), rotation_of(row.rival)) == expected
}
${accepted}`;
};

// The signing masks of the model's thresholds export: for each case and each of the
// 2^keyCount subsets of signing keys, the actual signing rule must agree with the
// model on whether the subset satisfies the count (mask bit i set = key i signed).
const maskTests = signingCases.flatMap((c) => {
  if (!(c.keyCount >= 1) || !c.expectedMasks.every((m) => Number.isInteger(m) && m >= 0 && m < 2 ** c.keyCount)) throw new Error(`signing case ${c.name}`);
  return Array.from({ length: 2 ** c.keyCount }, (_, mask) => {
    const positions = Array.from({ length: c.keyCount }, (_, i) => i).filter((i) => (mask >> i) & 1);
    return `
test signing_${c.name.toLowerCase()}_mask_${mask}() {
  satisfied(Unweighted(${c.threshold}), ${c.keyCount}, [${positions.join(', ')}]) == ${c.expectedMasks.includes(mask) ? 'True' : 'False'}
}
`;
  });
});
if (maskTests.length !== 22) throw new Error(`expected 22 masks, generated ${maskTests.length}`);

const all = [...rows, ...admissionRows];
const body = header + all.map(rowConst).join('') + all.map(rowTests).join('') + maskTests.join('');

writeFileSync(out, body);
