#!/usr/bin/env node
// Generates the deposit vectors of the Lean deposit intent (#517), for both layers:
//   onchain/lib/cardano_keri/checkpoint/deposit_vectors.ak
//   offchain/test/Cardano/KERI/AID/Checkpoint/DepositVectors.hs
// from lean/checkpoint-deposit-vectors.json and, for the signed fixture of the
// connected rotation, offchain/test/keri-fixtures/fixtures/advance.json.
//
//   node scripts/checkpoint-deposit-vectors.mjs            # write the modules
//   node scripts/checkpoint-deposit-vectors.mjs --check    # exit 1 when a module drifts
//
// What is generated
//   requirements   the rows of `requirements`: the spent state, the observed
//                  facts, the required preimage the Lean prints, the candidate
//                  preimage, and whether the candidate is the required intent.
//   authorizations the rows of `authorizations`: a threshold over the three new
//                  keys, the signatures with their symbolic signers resolved to
//                  test keys and signed over the named requirement's candidate
//                  preimage, and whether the deposit is taken.
//   fixture        the intents and signatures of the connected rotation of the
//                  Advance vector `adv_wit_2key` (signed with the seeds the
//                  fixture bundle exports), for the cases that run the spend arm
//                  and the observer over one transaction.
//
// Controls
//   The script encodes every intent itself (a small Plutus Data CBOR writer),
//   never reads an encoding from the code under test, and fails when its bytes
//   differ from the Lean's on any `intents` row, any `requirements` row's
//   required and candidate preimages, or any `authorizations` row's signed bytes.
//   A signature is Ed25519 (deterministic) by a test key whose seed is the
//   SHA-256 of "cardano-keri/deposit-vectors/<signer>"; each generated
//   signature is verified before it is emitted.
//
// The signed bytes are protocol surface: the Lean prints them, this script
// reproduces them, the validators must agree.
import { createHash, createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const input = resolve(root, 'lean/checkpoint-deposit-vectors.json');
const advanceInput = resolve(root, 'offchain/test/keri-fixtures/fixtures/advance.json');
const aikenOut = resolve(root, 'onchain/lib/cardano_keri/checkpoint/deposit_vectors.ak');
const aikenTestsOut = resolve(root, 'onchain/validators/checkpoint_register_deposit_vector_tests.ak');
const haskellOut = resolve(root, 'offchain/test/Cardano/KERI/AID/Checkpoint/DepositVectors.hs');

// ---------------------------------------------------------------------
// Plutus Data CBOR, as the Lean `cbor` writes it
// ---------------------------------------------------------------------
const hex = (b) => Buffer.from(b).toString('hex');
const unhex = (s) => Buffer.from(s, 'hex');

const head = (major, n) => {
  n = BigInt(n);
  if (n < 24n) return Buffer.from([(major << 5) | Number(n)]);
  if (n < 256n) return Buffer.from([(major << 5) | 24, Number(n)]);
  if (n < 65536n) return Buffer.from([(major << 5) | 25, Number(n >> 8n), Number(n & 255n)]);
  if (n < 4294967296n) {
    const b = Buffer.alloc(5);
    b[0] = (major << 5) | 26;
    b.writeUInt32BE(Number(n), 1);
    return b;
  }
  const b = Buffer.alloc(9);
  b[0] = (major << 5) | 27;
  b.writeBigUInt64BE(n, 1);
  return b;
};
const bstr = (bytes) => {
  if (bytes.length <= 64) return Buffer.concat([head(2, bytes.length), bytes]);
  const chunks = [];
  for (let i = 0; i < bytes.length; i += 64) chunks.push(bstr(bytes.subarray(i, i + 64)));
  return Buffer.concat([Buffer.from([0x5f]), ...chunks, Buffer.from([0xff])]);
};
const int = (v) => {
  v = BigInt(v);
  if (v < 0n) throw new Error('negative integers do not occur in an intent');
  if (v < 18446744073709551616n) return head(0, v);
  let h = v.toString(16);
  if (h.length % 2) h = `0${h}`;
  return Buffer.concat([Buffer.from([0xc2]), bstr(unhex(h))]);
};
const constr0 = (fields) => Buffer.concat([Buffer.from([0xd8, 0x79, 0x9f]), ...fields, Buffer.from([0xff])]);

const domainTag = 'cardano-keri/checkpoint/deposit/v1';

/** The intent as the Plutus Data the validator signs: constructor 0, eight fields. */
const intentBytes = (i) =>
  constr0([
    bstr(unhex(i.domain)),
    int(i.networkId),
    bstr(unhex(i.checkpointPolicy)),
    constr0([bstr(unhex(i.spentRef.transactionId)), int(i.spentRef.outputIndex)]),
    bstr(unhex(i.aid)),
    int(i.newSn),
    int(i.newEpoch),
    int(i.deposit),
  ]);

// ---------------------------------------------------------------------
// Test keys
// ---------------------------------------------------------------------
const pkcs8Prefix = unhex('302e020100300506032b657004220420');
const keyFromSeed = (seed) => {
  const privateKey = createPrivateKey({ key: Buffer.concat([pkcs8Prefix, seed]), format: 'der', type: 'pkcs8' });
  const publicKey = createPublicKey(privateKey).export({ format: 'der', type: 'spki' }).subarray(-32);
  return { privateKey, publicKey };
};
const seedOf = (name) => createHash('sha256').update(`cardano-keri/deposit-vectors/${name}`).digest();
const testKeys = {};
for (const name of ['new-0', 'new-1', 'new-2', 'old-0', 'old-1']) testKeys[name] = keyFromSeed(seedOf(name));
const signWith = (key, message) => {
  const signature = sign(null, message, key.privateKey);
  if (!verify(null, message, createPublicKey(key.privateKey), signature)) throw new Error('a generated signature does not verify');
  return signature;
};

// ---------------------------------------------------------------------
// The Lean rows
// ---------------------------------------------------------------------
const lean = JSON.parse(readFileSync(input, 'utf8'));
if (lean.params.B !== 2000000) throw new Error(`the vectors assume B = 2,000,000; the Lean has ${JSON.stringify(lean.params)}`);
if (lean.layout.DepositIntent.indexOf('constructor 0') !== 0) throw new Error('the intent layout changed');

const sameBytes = (what, got, want) => {
  if (hex(got) !== want) throw new Error(`${what}: this script encodes ${hex(got)}, the Lean prints ${want}`);
};

// Control 1: the encoder against every preimage the Lean prints.
for (const row of lean.intents) sameBytes(`intents/${row.id}`, intentBytes(row.intent), row.preimage);
for (const row of lean.requirements) {
  sameBytes(`requirements/${row.id} required`, intentBytes(requiredFor(row)), row.requiredPreimage);
  sameBytes(`requirements/${row.id} candidate`, intentBytes(row.candidate), row.candidatePreimage);
}

/** The intent the Lean requires for a requirement row's spent state and observed facts. */
function requiredFor(row) {
  const { spent, observed, newSn } = row.input;
  return {
    domain: hex(Buffer.from(domainTag, 'utf8')),
    networkId: observed.networkId,
    checkpointPolicy: observed.checkpointPolicy,
    spentRef: observed.spentRef,
    aid: observed.aid,
    newSn,
    newEpoch: BigInt(spent.epoch) + 1n,
    deposit: spent.frozen ? lean.params.B : 0,
  };
}
// Control 2: the required intent this script derives from the spent state equals
// the one the Lean derives (the row's own required preimage), on every row.
for (const row of lean.requirements) {
  if (hex(intentBytes(requiredFor(row))) !== row.requiredPreimage) throw new Error(`requirements/${row.id}: the required intent derived here differs from the Lean's`);
}

// The Lean's B is a parameter (the vectors use 2,000,000); the deployed freeze
// bond has a mechanical floor of 5,000,000 lovelace, so the rows that run through
// the validators are re-derived at that bond. An amount is B, one off B, or 0 and
// keeps that relation to B. The encoder is the Lean's (controls 1-3), only the
// parameter moves; the verbatim Lean preimages stay in the modules as byte rows.
const deployB = 5000000;
const scaleDeposit = (d) => {
  const dd = BigInt(d);
  const leanB = BigInt(lean.params.B);
  if (dd === 0n) return 0;
  if (dd === leanB || dd === leanB - 1n || dd === leanB + 1n) return Number(dd - leanB) + deployB;
  throw new Error(`the deposit amount ${d} is neither 0 nor within one of B`);
};
const atDeployment = (intent) => ({ ...intent, deposit: scaleDeposit(intent.deposit) });
const rowsById = new Map(lean.requirements.map((r) => [r.id, r]));
const signAll = (signer, preimage, position) => ({ position, signature: signWith(testKeys[signer], unhex(preimage)) });

const requirements = lean.requirements.map((row) => {
  const candidate = hex(intentBytes(atDeployment(row.candidate)));
  const required = hex(intentBytes(atDeployment(requiredFor(row))));
  return {
    id: row.id,
    accepted: row.accepted,
    note: row.note,
    spent: row.input.spent,
    observed: row.input.observed,
    newSn: row.input.newSn,
    required,
    candidate,
    leanRequired: row.requiredPreimage,
    leanCandidate: row.candidatePreimage,
    // two of the three new keys sign the candidate: the threshold of the tested datum is two
    candidateSignatures: [signAll('new-0', candidate, 0), signAll('new-1', candidate, 1)],
    requiredSignatures: [signAll('new-0', required, 0), signAll('new-1', required, 1)],
  };
});

const candidates = lean.requirements.map((row) => ({ id: row.id, note: row.note, intent: row.candidate, preimage: row.candidatePreimage }));
const intents = lean.intents.map((row) => ({ id: row.id, note: row.note, intent: row.intent, preimage: row.preimage }));

const thresholdOf = (t) => {
  if ('count' in t) return { kind: 'unweighted', required: t.count.required };
  const clauses = t.weighted.clauses.map((clause) => clause.map((w) => ({ num: w.key.weight.numerator, den: w.key.weight.denominator })));
  return { kind: 'weighted', clauses };
};

const authorizations = lean.authorizations.map((row) => {
  const signatures = row.signatures.map((s) => {
    const source = rowsById.get(s.over);
    if (!source) throw new Error(`authorizations/${row.id}: unknown row ${s.over}`);
    return signAll(s.signer, hex(intentBytes(atDeployment(source.candidate))), s.position);
  });
  // Control 3: the signed bytes the Lean prints for the row are the required
  // intent of the row's own spent state and observed facts.
  const own = requiredFor({ input: row.input });
  sameBytes(`authorizations/${row.id} signedBytes`, intentBytes(own), row.signedBytes);
  return {
    id: row.id,
    authorized: row.authorized,
    note: row.note,
    threshold: thresholdOf(row.threshold),
    countedPositions: row.countedPositions,
    signedBytes: hex(intentBytes(atDeployment(own))),
    spent: row.input.spent,
    observed: row.input.observed,
    newSn: row.input.newSn,
    signatures,
    signers: row.signatures.map((s) => s.signer),
  };
});

// ---------------------------------------------------------------------
// The signed fixture of the connected rotation
// ---------------------------------------------------------------------
// The spent checkpoint and the rotation are the Advance vector adv_wit_2key. The
// network, policy and spent output follow the freeze fixture the validator tests
// share: network 1, policy 0xcc x 28, the vector's spent output (0xd1 x 32, 0).
const bundle = JSON.parse(readFileSync(advanceInput, 'utf8')).adv_wit_2key;
const rot = JSON.parse(Buffer.from(bundle.rot.raw_hex, 'hex').toString('utf8'));
const seeds = bundle.signer_seeds;
const rotationKeys = seeds.rotation_current.map((s) => keyFromSeed(unhex(s.seed_hex)));
const inceptionKeys = seeds.inception_current.map((s) => keyFromSeed(unhex(s.seed_hex)));
const fixtureFacts = {
  networkId: 1,
  checkpointPolicy: 'cc'.repeat(28),
  spentRef: { transactionId: 'd1'.repeat(32), outputIndex: 0 },
  aid: hex(Buffer.from(rot.i, 'utf8')),
  newSn: BigInt(`0x${rot.s}`),
  spentEpoch: 0,
};
const fixtureIntent = (over) => {
  const f = { ...fixtureFacts, ...over };
  return {
    domain: hex(Buffer.from(domainTag, 'utf8')),
    networkId: f.networkId,
    checkpointPolicy: f.checkpointPolicy,
    spentRef: f.spentRef,
    aid: f.aid,
    newSn: f.newSn,
    newEpoch: f.spentEpoch + 1,
    deposit: f.deposit,
  };
};
const B = 5000000; // the freeze fixture's bond: B = 5 Lean units of 1,000,000
const fixtureCases = [
  // [name, intent, signers (keys), positions]
  ['frozen', fixtureIntent({ deposit: B }), rotationKeys, [0, 1]],
  ['unfrozen', fixtureIntent({ deposit: 0 }), rotationKeys, [0, 1]],
  ['frozen-names-zero', fixtureIntent({ deposit: 0 }), rotationKeys, [0, 1]],
  ['unfrozen-names-bond', fixtureIntent({ deposit: B }), rotationKeys, [0, 1]],
  ['other-output', fixtureIntent({ deposit: B, spentRef: { transactionId: 'd1'.repeat(32), outputIndex: 1 } }), rotationKeys, [0, 1]],
  ['other-network', fixtureIntent({ deposit: B, networkId: 0 }), rotationKeys, [0, 1]],
  ['other-sn', fixtureIntent({ deposit: B, newSn: fixtureFacts.newSn + 1n }), rotationKeys, [0, 1]],
  ['old-epoch', fixtureIntent({ deposit: B, spentEpoch: -1 }), rotationKeys, [0, 1]],
  ['signed-by-old-keys', fixtureIntent({ deposit: B }), inceptionKeys, [0, 1]],
].map(([name, intent, keys, positions]) => {
  const preimage = hex(intentBytes(intent));
  const message = unhex(preimage);
  return { name, preimage, signatures: positions.map((p) => ({ position: p, signature: signWith(keys[p], message) })) };
});
// Control 4: the fixture's required intents are the Lean's shape: the frozen and
// unfrozen required preimages differ only in the amount.
if (fixtureCases[0].preimage === fixtureCases[1].preimage) throw new Error('the frozen and unfrozen fixture intents coincide');
const rotationVerkeys = rotationKeys.map((k) => hex(k.publicKey));
const inceptionVerkeys = inceptionKeys.map((k) => hex(k.publicKey));

// ---------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------
const q = (s) => JSON.stringify(s);
const bytes = (h) => `#"${h}"`;
const sigPairs = (sigs) => `[${sigs.map((s) => `(${s.position}, ${bytes(hex(s.signature))})`).join(', ')}]`;
const aikenThreshold = (t) =>
  t.kind === 'unweighted'
    ? `Unweighted(${t.required})`
    : `Weighted([${t.clauses.map((c) => `[${c.map((w) => `Weight { num: ${w.num}, den: ${w.den} }`).join(', ')}]`).join(', ')}])`;
const bool = (b) => (b ? 'True' : 'False');
const keyList = ['new-0', 'new-1', 'new-2'].map((n) => hex(testKeys[n].publicKey));
const oldKeyList = ['old-0', 'old-1'].map((n) => hex(testKeys[n].publicKey));

const aikenSpent = (s) =>
  `Spent { sn: ${s.sn}, epoch: ${s.epoch}, born_at: ${s.bornAt}, refund_to: ${bytes(s.refundTo)}, pool: ${s.pool}, frozen: ${bool(s.frozen)}, poisoned: ${bool(s.poisoned)}, topped_up: ${bool(s.toppedUp)} }`;
const aikenFacts = (o) =>
  `Facts { network_id: ${o.networkId}, policy: ${bytes(o.checkpointPolicy)}, tx_id: ${bytes(o.spentRef.transactionId)}, output_index: ${o.spentRef.outputIndex}, aid: ${bytes(o.aid)} }`;

const aikenIntents = (list) =>
  list
    .map(
      (i) => `    Intent {
      id: @${q(i.id)},
      domain: ${bytes(i.intent.domain)},
      network_id: ${i.intent.networkId},
      policy: ${bytes(i.intent.checkpointPolicy)},
      tx_id: ${bytes(i.intent.spentRef.transactionId)},
      output_index: ${i.intent.spentRef.outputIndex},
      aid: ${bytes(i.intent.aid)},
      new_sn: ${i.intent.newSn},
      new_epoch: ${i.intent.newEpoch},
      deposit: ${i.intent.deposit},
      preimage: ${bytes(i.preimage)},
    },`,
    )
    .join('\n');

const hsIntents = (list) =>
  list
    .map(
      (i, k) => `    ${k === 0 ? '[' : ','} VectorIntent
        { viId = ${q(i.id)}
        , viDomain = hex ${hsBytes(i.intent.domain)}
        , viNetworkId = ${i.intent.networkId}
        , viPolicy = hex ${hsBytes(i.intent.checkpointPolicy)}
        , viTxId = hex ${hsBytes(i.intent.spentRef.transactionId)}
        , viOutputIndex = ${i.intent.spentRef.outputIndex}
        , viAid = hex ${hsBytes(i.intent.aid)}
        , viNewSn = ${i.intent.newSn}
        , viNewEpoch = ${i.intent.newEpoch}
        , viDeposit = ${i.intent.deposit}
        , viPreimage = hex ${hsBytes(i.preimage)}
        }`,
    )
    .join('\n');

const aiken = `//// GENERATED by scripts/checkpoint-deposit-vectors.mjs from
//// lean/checkpoint-deposit-vectors.json and the Advance vector adv_wit_2key. DO NOT EDIT.
//// \`just check-checkpoint-deposit-vectors\` regenerates and rejects drift.
////
//// The rows of the Lean deposit vectors with their signatures. A signature is
//// Ed25519 by a test key (seed: SHA-256 of "cardano-keri/deposit-vectors/<signer>")
//// over the preimage the row names; the connected rotation's signatures are by
//// the seeds the Advance fixture bundle exports. The preimages are the Lean's.

use cardano_keri/checkpoint/threshold.{Threshold, Unweighted, Weight, Weighted}

/// The spent checkpoint state of a row (the Lean \`Live\` it names).
pub type Spent {
  sn: Int,
  epoch: Int,
  born_at: Int,
  refund_to: ByteArray,
  pool: Int,
  frozen: Bool,
  poisoned: Bool,
  topped_up: Bool,
}

/// What the validator observes: the network it is applied to, the policy and
/// the output reference of the spent checkpoint, and the AID its datum carries.
pub type Facts {
  network_id: Int,
  policy: ByteArray,
  tx_id: ByteArray,
  output_index: Int,
  aid: ByteArray,
}

/// A \`requirements\` row: the intent the validator requires, a candidate intent,
/// whether the candidate is the required one, and the signatures of two of the
/// three new keys over each.
pub type Requirement {
  id: String,
  accepted: Bool,
  spent: Spent,
  facts: Facts,
  new_sn: Int,
  required: ByteArray,
  candidate: ByteArray,
  lean_required: ByteArray,
  lean_candidate: ByteArray,
  candidate_signatures: List<(Int, ByteArray)>,
  required_signatures: List<(Int, ByteArray)>,
}

/// An \`authorizations\` row: the threshold the rotation declares over the three
/// new keys, the signatures (each over the preimage its row names), and whether
/// the deposit is taken.
pub type Authorization {
  id: String,
  authorized: Bool,
  spent: Spent,
  facts: Facts,
  new_sn: Int,
  threshold: Threshold,
  signed_bytes: ByteArray,
  signatures: List<(Int, ByteArray)>,
}

/// An \`intents\` row: the fields of an intent and the bytes the Lean prints for
/// them (the parameter B of those rows is the Lean's 2,000,000).
pub type Intent {
  id: String,
  domain: ByteArray,
  network_id: Int,
  policy: ByteArray,
  tx_id: ByteArray,
  output_index: Int,
  aid: ByteArray,
  new_sn: Int,
  new_epoch: Int,
  deposit: Int,
  preimage: ByteArray,
}

/// The connected rotation's cases: the preimage and the signatures of the
/// rotation's new keys (or, for \`signed-by-old-keys\`, of the spent keys).
pub type Signed {
  name: String,
  preimage: ByteArray,
  signatures: List<(Int, ByteArray)>,
}

/// The verification keys of the test signers new-0, new-1, new-2.
pub const new_keys: List<ByteArray> =
  [${keyList.map(bytes).join(', ')}]

/// The verification keys of the test signers old-0, old-1.
pub const old_keys: List<ByteArray> =
  [${oldKeyList.map(bytes).join(', ')}]

/// The verification keys of the connected rotation (the Advance vector's new keys).
pub const rotation_keys: List<ByteArray> =
  [${rotationVerkeys.map(bytes).join(', ')}]

/// The verification keys of the connected rotation's spent checkpoint.
pub const spent_keys: List<ByteArray> =
  [${inceptionVerkeys.map(bytes).join(', ')}]

/// The AID the connected rotation carries, its qualified CESR text bytes.
pub const rotation_aid: ByteArray = ${bytes(fixtureFacts.aid)}

pub const requirements: List<Requirement> =
  [
${requirements
  .map(
    (r) => `    Requirement {
      id: @${q(r.id)},
      accepted: ${bool(r.accepted)},
      spent: ${aikenSpent(r.spent)},
      facts: ${aikenFacts(r.observed)},
      new_sn: ${r.newSn},
      required: ${bytes(r.required)},
      candidate: ${bytes(r.candidate)},
      lean_required: ${bytes(r.leanRequired)},
      lean_candidate: ${bytes(r.leanCandidate)},
      candidate_signatures: ${sigPairs(r.candidateSignatures)},
      required_signatures: ${sigPairs(r.requiredSignatures)},
    },`,
  )
  .join('\n')}
  ]

pub const authorizations: List<Authorization> =
  [
${authorizations
  .map(
    (a) => `    Authorization {
      id: @${q(a.id)},
      authorized: ${bool(a.authorized)},
      spent: ${aikenSpent(a.spent)},
      facts: ${aikenFacts(a.observed)},
      new_sn: ${a.newSn},
      threshold: ${aikenThreshold(a.threshold)},
      signed_bytes: ${bytes(a.signedBytes)},
      signatures: ${sigPairs(a.signatures)},
    },`,
  )
  .join('\n')}
  ]

pub const intents: List<Intent> =
  [
${aikenIntents(intents)}
  ]

/// The candidate intent of every \`requirements\` row, with the bytes the Lean prints
/// for it (the parameter B of those rows is the Lean's 2,000,000).
pub const candidate_intents: List<Intent> =
  [
${aikenIntents(candidates)}
  ]

pub const fixture: List<Signed> =
  [
${fixtureCases
  .map(
    (c) => `    Signed {
      name: @${q(c.name)},
      preimage: ${bytes(c.preimage)},
      signatures: ${sigPairs(c.signatures)},
    },`,
  )
  .join('\n')}
  ]
`;

const hsBytes = (h) => `"${h}"`;
const hsSigs = (sigs) => `[${sigs.map((s) => `(${s.position}, hex ${hsBytes(hex(s.signature))})`).join(', ')}]`;
const hsThreshold = (t) =>
  t.kind === 'unweighted'
    ? `Unweighted ${t.required}`
    : `Weighted [${t.clauses.map((c) => `[${c.map((w) => `Weight ${w.num} ${w.den}`).join(', ')}]`).join(', ')}]`;
const hsBool = bool;
const hsFacts = (o) =>
  `VectorFacts {vfNetworkId = ${o.networkId}, vfPolicy = hex ${hsBytes(o.checkpointPolicy)}, vfTxId = hex ${hsBytes(o.spentRef.transactionId)}, vfOutputIndex = ${o.spentRef.outputIndex}, vfAid = hex ${hsBytes(o.aid)}}`;
const hsSpent = (s) =>
  `VectorSpent {vsSn = ${s.sn}, vsEpoch = ${s.epoch}, vsBornAt = ${s.bornAt}, vsRefundTo = hex ${hsBytes(s.refundTo)}, vsPool = ${s.pool}, vsFrozen = ${hsBool(s.frozen)}, vsPoisoned = ${hsBool(s.poisoned)}, vsToppedUp = ${hsBool(s.toppedUp)}}`;

const haskell = `{- |
Module      : Cardano.KERI.AID.Checkpoint.DepositVectors
Description : The Lean deposit vectors with their signatures

GENERATED by scripts/checkpoint-deposit-vectors.mjs from
lean/checkpoint-deposit-vectors.json. DO NOT EDIT.
\`just check-checkpoint-deposit-vectors\` regenerates and rejects drift.

The same rows the Aiken module @deposit_vectors@ carries: the required and
candidate preimages the Lean prints, the signatures of two of the three new
test keys over each, and the authorization rows with their thresholds. A
signature is Ed25519 by a test key whose seed is the SHA-256 of
@cardano-keri/deposit-vectors/<signer>@; the connected rotation's are by the
seeds the Advance fixture bundle exports.
-}
module Cardano.KERI.AID.Checkpoint.DepositVectors (
    VectorSpent (..),
    VectorFacts (..),
    VectorRequirement (..),
    VectorAuthorization (..),
    VectorIntent (..),
    VectorSigned (..),
    newKeys,
    oldKeys,
    rotationKeys,
    spentKeys,
    rotationAid,
    vectorRequirements,
    vectorAuthorizations,
    vectorIntents,
    vectorCandidateIntents,
    vectorFixture,
) where

import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC

-- | The spent checkpoint state of a row.
data VectorSpent = VectorSpent
    { vsSn :: Integer
    , vsEpoch :: Integer
    , vsBornAt :: Integer
    , vsRefundTo :: ByteString
    , vsPool :: Integer
    , vsFrozen :: Bool
    , vsPoisoned :: Bool
    , vsToppedUp :: Bool
    }
    deriving stock (Show, Eq)

-- | What the validator observes.
data VectorFacts = VectorFacts
    { vfNetworkId :: Integer
    , vfPolicy :: ByteString
    , vfTxId :: ByteString
    , vfOutputIndex :: Integer
    , vfAid :: ByteString
    }
    deriving stock (Show, Eq)

-- | A requirements row.
data VectorRequirement = VectorRequirement
    { vrId :: String
    , vrAccepted :: Bool
    , vrSpent :: VectorSpent
    , vrFacts :: VectorFacts
    , vrNewSn :: Integer
    , vrRequired :: ByteString
    , vrCandidate :: ByteString
    , vrLeanRequired :: ByteString
    , vrLeanCandidate :: ByteString
    , vrCandidateSignatures :: [(Int, ByteString)]
    , vrRequiredSignatures :: [(Int, ByteString)]
    }
    deriving stock (Show, Eq)

-- | An authorizations row.
data VectorAuthorization = VectorAuthorization
    { vaId :: String
    , vaAuthorized :: Bool
    , vaSpent :: VectorSpent
    , vaFacts :: VectorFacts
    , vaNewSn :: Integer
    , vaThreshold :: Threshold
    , vaSignedBytes :: ByteString
    , vaSignatures :: [(Int, ByteString)]
    }
    deriving stock (Show, Eq)

-- | An intents row: the fields and the bytes the Lean prints for them.
data VectorIntent = VectorIntent
    { viId :: String
    , viDomain :: ByteString
    , viNetworkId :: Integer
    , viPolicy :: ByteString
    , viTxId :: ByteString
    , viOutputIndex :: Integer
    , viAid :: ByteString
    , viNewSn :: Integer
    , viNewEpoch :: Integer
    , viDeposit :: Integer
    , viPreimage :: ByteString
    }
    deriving stock (Show, Eq)

-- | A case of the connected rotation.
data VectorSigned = VectorSigned
    { vgName :: String
    , vgPreimage :: ByteString
    , vgSignatures :: [(Int, ByteString)]
    }
    deriving stock (Show, Eq)

hex :: String -> ByteString
hex s = either (error . ("hex: " <>)) id (convertFromBase Base16 (BC.pack s))

-- | The verification keys of the test signers new-0, new-1, new-2.
newKeys :: [ByteString]
newKeys = [${keyList.map((k) => `hex ${hsBytes(k)}`).join(', ')}]

-- | The verification keys of the test signers old-0, old-1.
oldKeys :: [ByteString]
oldKeys = [${oldKeyList.map((k) => `hex ${hsBytes(k)}`).join(', ')}]

-- | The verification keys of the connected rotation.
rotationKeys :: [ByteString]
rotationKeys = [${rotationVerkeys.map((k) => `hex ${hsBytes(k)}`).join(', ')}]

-- | The verification keys of the connected rotation's spent checkpoint.
spentKeys :: [ByteString]
spentKeys = [${inceptionVerkeys.map((k) => `hex ${hsBytes(k)}`).join(', ')}]

-- | The AID the connected rotation carries.
rotationAid :: ByteString
rotationAid = hex ${hsBytes(fixtureFacts.aid)}

vectorRequirements :: [VectorRequirement]
vectorRequirements =
${requirements
  .map(
    (r, i) => `    ${i === 0 ? '[' : ','} VectorRequirement
        { vrId = ${q(r.id)}
        , vrAccepted = ${hsBool(r.accepted)}
        , vrSpent = ${hsSpent(r.spent)}
        , vrFacts = ${hsFacts(r.observed)}
        , vrNewSn = ${r.newSn}
        , vrRequired = hex ${hsBytes(r.required)}
        , vrCandidate = hex ${hsBytes(r.candidate)}
        , vrLeanRequired = hex ${hsBytes(r.leanRequired)}
        , vrLeanCandidate = hex ${hsBytes(r.leanCandidate)}
        , vrCandidateSignatures = ${hsSigs(r.candidateSignatures)}
        , vrRequiredSignatures = ${hsSigs(r.requiredSignatures)}
        }`,
  )
  .join('\n')}
    ]

vectorAuthorizations :: [VectorAuthorization]
vectorAuthorizations =
${authorizations
  .map(
    (a, i) => `    ${i === 0 ? '[' : ','} VectorAuthorization
        { vaId = ${q(a.id)}
        , vaAuthorized = ${hsBool(a.authorized)}
        , vaSpent = ${hsSpent(a.spent)}
        , vaFacts = ${hsFacts(a.observed)}
        , vaNewSn = ${a.newSn}
        , vaThreshold = ${hsThreshold(a.threshold)}
        , vaSignedBytes = hex ${hsBytes(a.signedBytes)}
        , vaSignatures = ${hsSigs(a.signatures)}
        }`,
  )
  .join('\n')}
    ]

vectorIntents :: [VectorIntent]
vectorIntents =
${hsIntents(intents)}
    ]

-- | The candidate intent of every requirements row, with the bytes the Lean prints for it.
vectorCandidateIntents :: [VectorIntent]
vectorCandidateIntents =
${hsIntents(candidates)}
    ]

vectorFixture :: [VectorSigned]
vectorFixture =
${fixtureCases
  .map(
    (c, i) => `    ${i === 0 ? '[' : ','} VectorSigned
        { vgName = ${q(c.name)}
        , vgPreimage = hex ${hsBytes(c.preimage)}
        , vgSignatures = ${hsSigs(c.signatures)}
        }`,
  )
  .join('\n')}
    ]
`;

// ---------------------------------------------------------------------
// The Aiken row tests
// ---------------------------------------------------------------------
const ident = (id) => id.replace(/-/g, '_');
const byteTests = [
  `/// The generated rows cover what the Lean prints: no row is lost.
test lean_byte_rows_cover_the_committed_vectors() {
  and {
    list.length(vec.intents) == ${intents.length},
    list.length(vec.candidate_intents) == ${candidates.length},
    list.length(vec.requirements) == ${requirements.length},
    deposit_domain == #"${hex(Buffer.from(domainTag, 'utf8'))}",
  }
}
`,
  ...intents.map(
    (r, i) => `/// Intents row ${r.id}: ${r.note}.
test intent_${ident(r.id)}_is_the_lean_bytes() {
  intent_is_the_lean_bytes(${i})
}
`,
  ),
  ...requirements.map(
    (r, i) => `/// Requirements row ${r.id}: its candidate intent serialises to the Lean's bytes.
test requirement_${ident(r.id)}_candidate_is_the_lean_bytes() {
  candidate_is_the_lean_bytes(${i})
}

/// Requirements row ${r.id}: the intent required of its state serialises to the Lean's bytes.
test requirement_${ident(r.id)}_required_is_the_lean_bytes() {
  required_is_the_lean_bytes(${i})
}
`,
  ),
].join('\n');

const rowTests = [
  ...requirements.map(
    (r, i) => `/// Requirements row ${r.id}: ${r.note}.
test requirement_${ident(r.id)}()${r.accepted ? '' : ' fail'} {
  candidate_taken(${i})
}
`,
  ),
  ...authorizations.map(
    (a, i) => `/// Authorizations row ${a.id}: ${a.note}.
test authorization_${ident(a.id)}()${a.authorized ? '' : ' fail'} {
  authorized(${i})
}
`,
  ),
].join('\n');

const aikenTests = `//// GENERATED by scripts/checkpoint-deposit-vectors.mjs from
//// lean/checkpoint-deposit-vectors.json. DO NOT EDIT.
//// \`just check-checkpoint-deposit-vectors\` regenerates and rejects drift.
////
//// One test per row of the Lean deposit vectors, run through the checkpoint
//// spend arm alone. A \`requirements\` row signs its candidate intent with two of
//// the three new test keys: the required intent is taken, any other is
//// refused. An \`authorizations\` row presents its signatures over the intent of
//// its row: the deposit is taken exactly when the Lean says so. The amounts are
//// re-derived at the deployed freeze bond (5,000,000): the Lean's B is a
//// parameter and the rows keep their relation to it. A refused row is a
//// \`fail\` test; the accepted rows are its controls (the same states, the
//// required intents, signatures that satisfy every row's threshold).

use aiken/collection/list
use cardano/transaction.{OutputReference}
use cardano_keri/checkpoint/deposit.{
  DepositIntent, deposit_domain, intent_bytes, required_intent,
}
use cardano_keri/checkpoint/deposit_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint_register
use deposit_fixture.{Case, vector_case}
use freeze_fixture.{
  advance_hash, d_reg, enforcement_hash, entitlement_hash, freeze_bond, premium,
}
use registry_fixture.{registry_name, state_policy}

fn run_spend(c: Case) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    state_policy(),
    registry_name(),
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    c.network,
    d_reg,
    freeze_bond,
    premium,
    None,
    c.redeemer,
    c.own_ref,
    c.tx,
  )
}

fn requirement(index: Int) -> vec.Requirement {
  expect Some(row) = list.at(vec.requirements, index)
  row
}

fn authorization(index: Int) -> vec.Authorization {
  expect Some(row) = list.at(vec.authorizations, index)
  row
}

/// The Lean's freeze bond in the intents and requirements rows, whose bytes
/// are asserted as the Lean prints them.
const lean_bond: Int = 2_000_000

fn intent_of(row: vec.Intent) -> DepositIntent {
  DepositIntent {
    domain: row.domain,
    network_id: row.network_id,
    checkpoint_policy: row.policy,
    spent_ref: OutputReference {
      transaction_id: row.tx_id,
      output_index: row.output_index,
    },
    aid: row.aid,
    new_sn: row.new_sn,
    new_epoch: row.new_epoch,
    deposit: row.deposit,
  }
}

fn nth_intent(rows: List<vec.Intent>, index: Int) -> vec.Intent {
  expect Some(row) = list.at(rows, index)
  row
}

/// An intents row serialises to the bytes the Lean prints for it.
fn intent_is_the_lean_bytes(index: Int) -> Bool {
  let row = nth_intent(vec.intents, index)
  intent_bytes(intent_of(row)) == row.preimage
}

/// A requirements row's candidate serialises to the bytes the Lean prints.
fn candidate_is_the_lean_bytes(index: Int) -> Bool {
  let row = nth_intent(vec.candidate_intents, index)
  intent_bytes(intent_of(row)) == row.preimage
}

/// The intent the validator requires on a requirements row, at the Lean's
/// bond and with the epoch the rotation opens, serialises to the bytes the
/// Lean prints.
fn required_is_the_lean_bytes(index: Int) -> Bool {
  let row = requirement(index)
  intent_bytes(
    required_intent(
      row.facts.network_id,
      row.facts.policy,
      OutputReference {
        transaction_id: row.facts.tx_id,
        output_index: row.facts.output_index,
      },
      row.facts.aid,
      row.new_sn,
      row.spent.epoch + 1,
      if row.spent.frozen {
        lean_bond
      } else {
        0
      },
    ),
  ) == row.lean_required
}

/// A requirements row: two of the three new keys sign its candidate intent.
fn candidate_taken(index: Int) -> Bool {
  let row = requirement(index)
  run_spend(
    vector_case(
      row.spent,
      row.facts,
      row.new_sn,
      Unweighted(2),
      row.candidate_signatures,
    ),
  )
}

/// An authorizations row: its signatures, its threshold, its state.
fn authorized(index: Int) -> Bool {
  let row = authorization(index)
  run_spend(
    vector_case(row.spent, row.facts, row.new_sn, row.threshold, row.signatures),
  )
}

${byteTests}\n${rowTests}`;

// The modules are compared after `aiken fmt` and `fourmolu`; the drift check ignores
// layout: whitespace and the trailing commas the formatter adds or removes.
// Layout only: whitespace between two word characters separates tokens (`Weight 1 2`
// is not `Weight 12`) and is kept as one mark; every other whitespace is dropped.
const normalize = (text) =>
  text
    .replace(/(?<=\w)\s+(?=\w)/g, '\u0001')
    .replace(/\s+/g, '')
    .replace(/,(?=[\])}])/g, '');

const outputs = [
  [aikenOut, aiken, true],
  [aikenTestsOut, aikenTests, true],
  [haskellOut, haskell, true],
];
if (process.argv.includes('--check')) {
  let drift = false;
  for (const [path, text, layoutFree] of outputs) {
    let current = '';
    try {
      current = readFileSync(path, 'utf8');
    } catch {
      /* absent */
    }
    const same = layoutFree ? normalize(current) === normalize(text) : current === text;
    if (!same) {
      console.error(`drift: ${path}`);
      drift = true;
    }
  }
  if (drift) process.exit(1);
  console.log(`deposit vector modules up to date (${requirements.length} requirements, ${authorizations.length} authorizations, ${fixtureCases.length} fixture cases)`);
} else {
  for (const [path, text] of outputs) writeFileSync(path, text);
  console.log(`wrote ${requirements.length} requirements, ${authorizations.length} authorizations, ${fixtureCases.length} fixture cases`);
}
