#!/usr/bin/env node
// Generates the Aiken tests of the checkpoint writer side:
//   onchain/lib/cardano_keri/checkpoint/datum_v2_vectors.ak   the version 2 datum
//   onchain/lib/cardano_keri/checkpoint/value_vectors.ak      the output's value
// from lean/checkpoint-datum-vectors.json and lean/checkpoint-value-vectors.json
// (the vectors the Lean modules `CardanoKeri.CheckpointDatum` and
// `CardanoKeri.CheckpointValue` produce).
//
//   node scripts/checkpoint-writer-vectors.mjs            # write the modules
//   node scripts/checkpoint-writer-vectors.mjs --check    # exit 1 when a module drifts
//
// The mapping of the Lean values onto Aiken values is written here, once, and
// restated in the header of each generated module:
//   datum (hex)                         -> byte string: the inline datum's CBOR
//   input.aid                           -> the UTF-8 bytes of the qualified CESR text
//   refundTo, keys, witnesses (hex)     -> byte strings
//   sn, epoch, bornAt, toad             -> integers (decimal strings beyond 2^53)
//   poisoned, frozen                    -> Bool
//   thresholds {unweighted n}           -> Unweighted(n)
//   thresholds {weighted [[[n,d]..]..]} -> Weighted([[Weight { num: n, den: d }, ..], ..])
//   form live / terminationPending      -> Live / TerminationPending
//   params                              -> integers passed as arguments
// A refused row is only its bytes: it has no input.
// The expected values are the Lean's, written out; the Aiken code is the
// thing under test.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const datumIn = resolve(root, 'lean/checkpoint-datum-vectors.json');
const valueIn = resolve(root, 'lean/checkpoint-value-vectors.json');
const dir = resolve(root, 'onchain/lib/cardano_keri/checkpoint');
const datumOut = resolve(dir, 'datum_v2_vectors.ak');
const valueOut = resolve(dir, 'value_vectors.ak');

const isHex = (s) => typeof s === 'string' && /^([0-9a-f]{2})*$/.test(s);
const utf8Hex = (s) => Buffer.from(s, 'utf8').toString('hex');
const big = (v) => BigInt(v);
const bool = (b) => (b ? 'True' : 'False');
const TWO64 = 18446744073709551616n;

const datum = JSON.parse(readFileSync(datumIn, 'utf8'));
const value = JSON.parse(readFileSync(valueIn, 'utf8'));

if (!Array.isArray(datum.accepted) || datum.accepted.length !== 7) throw new Error(`expected 7 accepted datum rows, found ${datum.accepted && datum.accepted.length}`);
if (!Array.isArray(datum.refused) || datum.refused.length !== 29) throw new Error(`expected 29 refused datum rows, found ${datum.refused && datum.refused.length}`);
if (!Array.isArray(value.held) || value.held.length !== 7) throw new Error(`expected 7 held value rows, found ${value.held && value.held.length}`);
if (!Array.isArray(value.registration) || value.registration.length !== 4) throw new Error(`expected 4 registration rows, found ${value.registration && value.registration.length}`);
const { registry, checkpoint } = value.params;
if (Object.keys(value.params).sort().join() !== 'checkpoint,registry') throw new Error('value params changed');
if (Object.keys(registry).sort().join() !== 'D,Mc' || Object.keys(checkpoint).sort().join() !== 'B,D') throw new Error('value params changed');
// the registry's deposit is the checkpoint's deposit and freeze bond together
if (registry.D !== checkpoint.D + checkpoint.B) throw new Error('registry D is not the checkpoint D + B');

const ident = (id) => {
  const name = id.replace(/-/g, '_');
  if (!/^[a-z][a-z0-9_]*$/.test(name)) throw new Error(`vector id is not an identifier: ${id}`);
  return name;
};

// ---------------------------------------------------------------------
// A small layout of Aiken expressions, after `aiken fmt`: a node is printed on
// one line when it fits in 80 columns, otherwise one element per line with a
// trailing comma.
// ---------------------------------------------------------------------
const lit = (text) => ({ k: 'lit', text });
const list = (items) => ({ k: 'list', items });
const rec = (name, fields) => ({ k: 'rec', name, fields });
const call = (name, args) => ({ k: 'call', name, args });
const flat = (n) => {
  switch (n.k) {
    case 'lit': return n.text;
    case 'list': return `[${n.items.map(flat).join(', ')}]`;
    case 'rec': return `${n.name} { ${n.fields.map(([f, v]) => `${f}: ${flat(v)}`).join(', ')} }`;
    case 'call': return `${n.name}(${n.args.map(flat).join(', ')})`;
    default: throw new Error(`unknown node ${n.k}`);
  }
};
const render = (n, indent, col, trail) => {
  const one = flat(n);
  if (col + one.length + trail <= 80 || n.k === 'lit' || (n.k === 'list' && n.items.length === 0)) return one;
  const pad = ' '.repeat(indent + 2);
  const close = ' '.repeat(indent);
  switch (n.k) {
    case 'list':
      return `[\n${n.items.map((i) => `${pad}${render(i, indent + 2, indent + 2, 1)},\n`).join('')}${close}]`;
    case 'rec':
      return `${n.name} {\n${n.fields.map(([f, v]) => `${pad}${f}: ${render(v, indent + 2, indent + 2 + f.length + 2, 1)},\n`).join('')}${close}}`;
    case 'call':
      return `${n.name}(\n${n.args.map((a) => `${pad}${render(a, indent + 2, indent + 2, 1)},\n`).join('')}${close})`;
    default: throw new Error(`unknown node ${n.k}`);
  }
};
// A function body whose value is `node`.
const body = (node) => `  ${render(node, 2, 2, 0)}\n`;

const hexLit = (h) => {
  if (!isHex(h)) throw new Error(`not hex: ${h}`);
  return lit(`#"${h}"`);
};
const int = (v) => lit(`${big(v)}`);

const thresholdNode = (t) => {
  if (t && t.unweighted !== undefined) return call('Unweighted', [int(t.unweighted)]);
  if (t && Array.isArray(t.weighted)) {
    return call('Weighted', [
      list(t.weighted.map((clause) => list(clause.map(([n, d]) => rec('Weight', [['num', int(n)], ['den', int(d)]]))))),
    ]);
  }
  throw new Error(`unknown threshold ${JSON.stringify(t)}`);
};

const keyMaterialNode = (k) =>
  rec('KeyMaterial', [
    ['cur_keys', list(k.curKeys.map(hexLit))],
    ['cur_threshold', thresholdNode(k.curThreshold)],
    ['next_keys', list(k.nextKeys.map(hexLit))],
    ['next_threshold', thresholdNode(k.nextThreshold)],
    ['witnesses', list(k.witnesses.map(hexLit))],
    ['toad', int(k.toad)],
  ]);

// The version 2 datum facts of an accepted row's input.
const factsNode = (id, input, keys) => {
  const s = input.state;
  const aid = hexLit(utf8Hex(input.aid));
  if (s.form === 'live') {
    return rec('Live', [
      ['aid', aid],
      ['sn', int(s.sn)],
      ['epoch', int(s.epoch)],
      ['poisoned', lit(bool(s.poisoned))],
      ['frozen', lit(bool(s.frozen))],
      ['born_at', int(s.bornAt)],
      ['refund_to', hexLit(s.refundTo)],
      ['keys', keys],
    ]);
  }
  if (s.form === 'terminationPending') {
    return rec('TerminationPending', [
      ['aid', aid],
      ['sn', int(s.sn)],
      ['epoch', int(s.epoch)],
      ['keys', keys],
    ]);
  }
  throw new Error(`${id}: unknown state form ${s.form}`);
};

// The Plutus Data of an accepted row's input, as an untyped tree built with
// the builtins; the Lean `datum` writes the same shape. Used for the rows the
// standard library cannot read (a tagged big number panics its
// `cbor.deserialise`); the test checks that it serialises to the row's bytes.
const dataNode = {
  c: (i, fields) => call('builtin.constr_data', [lit(`${i}`), list(fields)]),
  i: (v) => call('builtin.i_data', [int(v)]),
  b: (h) => call('builtin.b_data', [hexLit(h)]),
  l: (items) => call('builtin.list_data', [list(items)]),
};
const thresholdData = (t) => {
  if (t.unweighted !== undefined) return dataNode.c(0, [dataNode.i(t.unweighted)]);
  return dataNode.c(1, [dataNode.l(t.weighted.map((clause) => dataNode.l(clause.map(([n, d]) => dataNode.c(0, [dataNode.i(n), dataNode.i(d)])))))]);
};
const keysData = (k) =>
  dataNode.c(0, [
    dataNode.l(k.curKeys.map(dataNode.b)),
    thresholdData(k.curThreshold),
    dataNode.l(k.nextKeys.map(dataNode.b)),
    thresholdData(k.nextThreshold),
    dataNode.l(k.witnesses.map(dataNode.b)),
    dataNode.i(k.toad),
  ]);
const boolData = (b) => dataNode.c(b ? 1 : 0, []);
const rowData = (input) => {
  const s = input.state;
  const aid = dataNode.b(utf8Hex(input.aid));
  if (s.form === 'live') {
    return dataNode.c(1, [dataNode.c(0, [aid, dataNode.i(s.sn), dataNode.i(s.epoch), boolData(s.poisoned), boolData(s.frozen), dataNode.i(s.bornAt), dataNode.b(s.refundTo), keysData(input.keys)])]);
  }
  return dataNode.c(1, [dataNode.c(1, [aid, dataNode.i(s.sn), dataNode.i(s.epoch), keysData(input.keys)])]);
};
const needsConstruction = (input) => {
  const s = input.state;
  const ints = [s.sn, s.epoch, s.bornAt, input.keys.toad].filter((v) => v !== undefined).map(big);
  return ints.some((v) => v >= TWO64 || v < -TWO64);
};

// ---------------------------------------------------------------------
// The version 2 datum module
// ---------------------------------------------------------------------
const checkDatumRow = (r, accepted) => {
  if (!isHex(r.datum)) throw new Error(`${r.id}: datum`);
  if (accepted) {
    if (!r.input) throw new Error(`${r.id}: accepted row without input`);
    // The vector's own consistency, independent of any implementation.
    if (r.decoded.aid !== utf8Hex(r.input.aid)) throw new Error(`${r.id}: decoded aid is not the UTF-8 bytes of the CESR text`);
    if (r.consumer === undefined) throw new Error(`${r.id}: no consumer verdict`);
  } else {
    if (r.decoded !== null) throw new Error(`${r.id}: a refused row decodes`);
    if (r.consumer.accepted) throw new Error(`${r.id}: a refused row is accepted`);
  }
};

const datumHeader = `//// GENERATED by scripts/checkpoint-writer-vectors.mjs from
//// lean/checkpoint-datum-vectors.json. DO NOT EDIT.
//// \`just check-checkpoint-writer-vectors\` regenerates and rejects drift.
////
//// The version 2 checkpoint datum, one row of the Lean vectors at a time
//// (Lean \`CardanoKeri.CheckpointDatum\`). Per accepted row: the Aiken value
//// built from the row's input serialises to the row's datum bytes (layout),
//// the row's datum reads back into that value (reads back), and the writer's
//// read of the datum accepts it. A refused row is refused in one of two places.
//// Bytes that are not one whole \`Data\` never reach the writer: the ledger's
//// parse refuses them (Lean \`ofBytes?\`), stood in for here by
//// \`aiken/cbor.deserialise\`, and the row's \`refused_by_parse_\` test checks
//// that the parse returns nothing. Every other refused row is one whole \`Data\`:
//// its \`parses_\` test checks that the parse returns it, and its \`refused_\` test
//// checks that the writer's read does not accept it. The writer's read is the
//// typed read of a \`Data\` as the version 2 datum followed by
//// \`datum_v2_well_formed\`.
////
//// Mapping of the Lean values onto Aiken values (written once, in the
//// generator):
////   datum                       the inline datum's CBOR bytes
////   input.aid                   the UTF-8 bytes of the qualified CESR text
////   refundTo, keys, witnesses   byte strings
////   sn, epoch, bornAt, toad     integers
////   poisoned, frozen            Bool
////   threshold unweighted n      Unweighted(n)
////   threshold weighted          Weighted([[Weight { num, den }, ..], ..])
////   form live, terminationPending   Live, TerminationPending
////   data (row with a tagged big number)   the Data built with the builtins,
////                               checked to serialise to the row's bytes
`;

const datumModule = () => {
  const acc = datum.accepted.map((r) => (checkDatumRow(r, true), r));
  const ref = datum.refused.map((r) => (checkDatumRow(r, false), r));
  const seen = new Set();
  const names = (id) => {
    const n = ident(id);
    if (seen.has(n)) throw new Error(`duplicate vector id ${id}`);
    seen.add(n);
    return n;
  };
  let out = datumHeader;
  out += `
use aiken/builtin
use aiken/cbor
use cardano_keri/checkpoint/datum.{
  CheckpointDatum, CheckpointDatumV2, DatumValid, KeyMaterial, Live,
  TerminationPending, V2, datum_v2_well_formed,
}
use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}

/// The writer's read of a \`Data\`: the typed read as the version 2 datum, then
/// write-time validity. A \`Data\` of any other shape does not read.
fn writer_accepts(data: Data) -> Bool {
  expect V2(d): CheckpointDatum = data
  datum_v2_well_formed(d) == DatumValid
}

/// Whether the ledger's parse reads the bytes as one whole \`Data\`.
fn parses(datum: ByteArray) -> Bool {
  cbor.deserialise(datum) != None
}

/// The ledger's parse of datum bytes: one whole \`Data\`, or nothing.
fn parse(datum: ByteArray) -> Data {
  expect Some(data) = cbor.deserialise(datum)
  data
}
`;
  for (const r of acc) {
    const id = names(r.id);
    const input = r.input;
    const construct = needsConstruction(input);
    out += `
/// The key material of vector \`${r.id}\`.
pub fn keys_${id}() -> KeyMaterial {
${body(keyMaterialNode(input.keys))}}

/// The facts of vector \`${r.id}\`: ${r.note}.
pub fn facts_${id}() -> CheckpointDatumV2 {
${body(factsNode(r.id, input, call(`keys_${id}`, [])))}}
`;
    out += `
/// The Data of vector \`${r.id}\`${construct ? ', built here because the standard library\'s reader panics on a tagged big number' : ''}.
fn data_${id}() -> Data {
${body(construct ? rowData(input) : call('parse', [hexLit(r.datum)]))}}
`;
    const datumLit = `#"${r.datum}"`;
    out += `
/// Lean \`datum\`: the value built from the row's input serialises to the row's datum.
test layout_${id}() {
  cbor.serialise(V2(facts_${id}())) == ${datumLit}
}
`;
    out += `
/// Lean \`datum\`: the row's datum reads back into the value built from its input${construct ? ', and the built Data is the row\'s datum' : ''}.
test reads_back_${id}() {
  expect read: CheckpointDatum = data_${id}()
  read == V2(facts_${id}())${construct ? ` && cbor.serialise(data_${id}()) == ${datumLit}` : ''}
}
`;
    out += `
/// The writer's read accepts the row's datum.
test accepted_${id}() {
  writer_accepts(data_${id}())
}
`;
  }
  // The rows whose bytes are not one whole Data. The tests check the split:
  // a row put in the wrong class fails its own test.
  const byteLevel = new Set(['trailing-byte', 'truncated', 'empty', 'break-byte']);
  for (const id of byteLevel) if (!ref.some((r) => r.id === id)) throw new Error(`no refused row ${id}`);
  let tests = acc.length * 3;
  for (const r of ref) {
    const id = names(r.id);
    if (byteLevel.has(r.id)) {
      out += `
/// The parse refuses vector \`${r.id}\` (Lean \`ofBytes?\`): ${r.note}; there is no \`Data\` for the writer to read.
test refused_by_parse_${id}() {
  ${render(call('cbor.deserialise', [hexLit(r.datum)]), 2, 2, ' == None'.length)} == None
}
`;
      tests += 1;
    } else {
      out += `
/// Vector \`${r.id}\` is one whole \`Data\`: ${r.note}.
test parses_${id}() {
${body(call('parses', [hexLit(r.datum)]))}}

/// The writer's read does not accept vector \`${r.id}\`.
test refused_${id}() fail {
${body(call('writer_accepts', [call('parse', [hexLit(r.datum)])]))}}
`;
      tests += 2;
    }
  }
  return { text: out, tests };
};

// ---------------------------------------------------------------------
// The output's value module
// ---------------------------------------------------------------------
const valueHeader = `//// GENERATED by scripts/checkpoint-writer-vectors.mjs from
//// lean/checkpoint-value-vectors.json (and the same states' key material in
//// lean/checkpoint-datum-vectors.json). DO NOT EDIT.
//// \`just check-checkpoint-writer-vectors\` regenerates and rejects drift.
////
//// The lovelace a checkpoint output holds (Lean \`CardanoKeri.Checkpoint\`
//// \`State.heldValue\`, \`State.valueFloor\`, \`State.withValue\`) and the
//// registration carrier rule, one row of the Lean vectors at a time. The
//// parameters are the vectors' (\`params\`) and are passed as arguments.
////
//// Mapping of the Lean values onto Aiken values (written once, in the
//// generator):
////   params.registry.Mc, params.checkpoint.D, params.checkpoint.B
////                               integers, passed to every function
////   state (datum facts)         the datum module's facts of the same id; the
////                               pool is not a datum fact and is an argument
////   holdings[].reads            the pool the holding reads as, or None
////   holdings[].realizes         the holding reads as the row's own state
////   carrier outcome booked      Some(pool); refused: None
`;

const sameState = (id, a, b) => {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  keys.delete('pool');
  for (const k of keys) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) throw new Error(`${id}: the value vector's state differs from the datum vector's in ${k}`);
  }
};

const valueModule = () => {
  const datumIds = new Map(datum.accepted.map((r) => [r.id, r]));
  let out = valueHeader;
  out += `
use cardano_keri/checkpoint/datum.{CheckpointDatumV2, Live}
use cardano_keri/checkpoint/datum_v2_vectors as datum_vectors
use cardano_keri/checkpoint/value.{
  held_value, registration_pool, value_floor, with_value,
}

const registry_mc: Int = ${registry.Mc}

const checkpoint_d: Int = ${checkpoint.D}

const checkpoint_b: Int = ${checkpoint.B}

fn floor_of(facts: CheckpointDatumV2) -> Int {
  value_floor(registry_mc, checkpoint_d, checkpoint_b, facts)
}

fn held_of(facts: CheckpointDatumV2, pool: Int) -> Int {
  held_value(registry_mc, checkpoint_d, checkpoint_b, facts, pool)
}

fn read_at(facts: CheckpointDatumV2, lovelace: Int) -> Option<Int> {
  with_value(registry_mc, checkpoint_d, checkpoint_b, facts, lovelace)
}

fn book(carrier: Int) -> Option<Int> {
  registration_pool(registry_mc, checkpoint_d, checkpoint_b, carrier)
}
`;
  let tests = 0;
  const ids = new Set();
  const factsCall = (id) => call(`datum_vectors.facts_${id}`, []);
  const stmt = (prefix, node) => `  ${prefix}${render(node, 2, 2 + prefix.length, 0)}\n`;
  for (const h of value.held) {
    const id = ident(h.id);
    if (ids.has(id)) throw new Error(`duplicate held id ${h.id}`);
    ids.add(id);
    const drow = datumIds.get(h.id);
    if (!drow) throw new Error(`${h.id}: no datum vector of this id`);
    sameState(h.id, h.state, drow.input.state);
    const pool = h.state.form === 'live' ? big(h.state.pool) : 0n;
    out += `
/// Lean \`State.valueFloor\`: vector \`${h.id}\`.
test floor_${id}() {
${stmt('', call('floor_of', [factsCall(id)])).replace(/\n$/, '')} == ${big(h.valueFloor)}
}
`;
    out += `
/// Lean \`State.heldValue\`: vector \`${h.id}\`.
test held_${id}() {
${stmt('', call('held_of', [factsCall(id), lit(`${pool}`)])).replace(/\n$/, '')} == ${big(h.heldValue)}
}
`;
    tests += 2;
    if (h.state.form === 'terminationPending') {
      // A pending termination holds exactly the minimum ADA whatever pool is given.
      out += `
/// Lean \`pending_holds_minimum_ada\`: vector \`${h.id}\` holds ${big(h.heldValue)} whatever pool is given.
test held_${id}_ignores_pool() {
  let one = ${render(call('held_of', [factsCall(id), lit('1')]), 2, 2 + 'let one = '.length, 0)}
  let large = ${render(call('held_of', [factsCall(id), lit('5000000')]), 2, 2 + 'let large = '.length, 0)}
  one == ${big(h.heldValue)} && large == ${big(h.heldValue)}
}
`;
      tests += 1;
    }
    for (const holding of h.holdings) {
      const lovelace = big(holding.lovelace);
      let expected;
      if (holding.reads === null) expected = 'None';
      else expected = `Some(${holding.reads.form === 'live' ? big(holding.reads.pool) : 0n})`;
      // The reading realizes the row's state exactly when it is the held value.
      if (holding.realizes !== (lovelace === big(h.heldValue))) throw new Error(`${h.id}: realizes disagrees with the held value at ${lovelace}`);
      out += `
/// Lean \`State.withValue\`: vector \`${h.id}\` at ${lovelace} lovelace reads as ${holding.reads === null ? 'no state' : 'a state'}${holding.realizes ? " and realizes the row's state" : ''}.
test reads_${id}_at_${lovelace}() {
${stmt('let got = ', call('read_at', [factsCall(id), lit(`${lovelace}`)]))}  let realizes = got == Some(${pool})
  got == ${expected} && realizes == ${bool(holding.realizes)}
}
`;
      tests += 1;
    }
  }
  for (const r of value.registration) {
    const id = ident(r.id);
    if (ids.has(id)) throw new Error(`duplicate registration id ${r.id}`);
    ids.add(id);
    let expected;
    if (r.outcome.booked) {
      if (big(r.outcome.pool) !== big(r.pool0)) throw new Error(`${r.id}: booked pool is not the initial pool`);
      expected = `Some(${big(r.pool0)})`;
    } else {
      expected = 'None';
    }
    // The rule itself, independent of any implementation.
    const rule = big(r.carrierAda) >= BigInt(registry.Mc + checkpoint.D + checkpoint.B);
    if (rule !== r.outcome.booked) throw new Error(`${r.id}: the outcome is not the carrier rule`);
    out += `
/// Lean \`registration_holds_carrier\`: ${r.note}.
test registration_${id}() {
  book(${big(r.carrierAda)}) == ${expected}
}
`;
    tests += 1;
  }
  const c = value.connected;
  const first = value.held[0];
  out += `
/// The connected fixture's checkpoint: held by the carrier that booked it.
fn facts_connected() -> CheckpointDatumV2 {
${body(
  rec('Live', [
    ['aid', lit('#""')],
    ['sn', int(c.checkpoint.sn)],
    ['epoch', int(c.checkpoint.epoch)],
    ['poisoned', lit(bool(c.checkpoint.poisoned))],
    ['frozen', lit(bool(c.checkpoint.frozen))],
    ['born_at', int(c.checkpoint.bornAt)],
    ['refund_to', hexLit(c.checkpoint.refundTo)],
    ['keys', call(`datum_vectors.keys_${ident(first.id)}`, [])],
  ]),
)}}

/// Lean \`registration_holds_carrier\`: the connected fixture's carrier books its initial pool, and the registered checkpoint holds the carrier.
test connected_registration() {
  let held = held_of(facts_connected(), ${big(c.pool0)})
  book(${big(c.carrierAda)}) == Some(${big(c.pool0)}) && held == ${big(c.heldValue)} && held == ${big(c.holdingLovelace)}
}
`;
  tests += 1;
  return { text: out, tests };
};

const outputs = [
  { path: datumOut, ...datumModule() },
  { path: valueOut, ...valueModule() },
];

if (process.argv.includes('--check')) {
  let drifted = false;
  for (const o of outputs) {
    let current = '';
    try { current = readFileSync(o.path, 'utf8'); } catch { /* absent */ }
    if (current !== o.text) {
      console.error(`${o.path} drifted from the Lean vectors; run: node scripts/checkpoint-writer-vectors.mjs`);
      drifted = true;
    }
  }
  if (drifted) process.exit(1);
  console.log(`checkpoint writer vectors current (${outputs.map((o) => o.tests).join(' + ')} generated tests)`);
} else {
  for (const o of outputs) writeFileSync(o.path, o.text);
  console.log(`wrote ${outputs.map((o) => o.path).join(', ')} (${outputs.map((o) => o.tests).join(' + ')} generated tests)`);
}
