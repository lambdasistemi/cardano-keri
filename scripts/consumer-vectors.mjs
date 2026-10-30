#!/usr/bin/env node
// Generates onchain/lib/cardano_keri/consumer_corpus_vectors.ak from the
// `fields` queries of simulator/consumer-corpus.json (the Lean-checked corpus).
//
//   node scripts/consumer-vectors.mjs            # write the module
//   node scripts/consumer-vectors.mjs --check    # exit 1 when the module drifts
//
// The mapping of the Lean's natural-number model onto Aiken values is written
// here, once, and restated in the header of the generated module:
//   policy, credential, state program  -> 28-byte big-endian
//   transaction id                     -> 32-byte big-endian
//   asset name (hash output)           -> 32-byte big-endian
//   AID key                            -> 8-byte big-endian
//   code (list of naturals)            -> concatenation of 8-byte big-endian
//   credential                         -> script credential
//   assets                             -> Value, duplicate entries summed
//   datum application n                -> inline datum, integer n
//   datum root c                       -> inline datum, constructor 1 [c]
//   datum configuration (r,m,p,t,b)    -> inline datum, constructor 2 [..]
//   datum empty                        -> no datum
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const corpusPath = resolve(root, 'simulator/consumer-corpus.json');
const outPath = resolve(root, 'onchain/lib/cardano_keri/consumer_corpus_vectors.ak');
const WIDTH = 80;

const big = (v) => {
  if (typeof v === 'bigint') return v;
  if (typeof v === 'number' && !Number.isSafeInteger(v)) throw new Error(`unsafe integer: ${v}`);
  if (typeof v === 'number' || typeof v === 'string') return BigInt(v);
  throw new Error(`not a natural: ${JSON.stringify(v)}`);
};
const bytes = (v, width) => {
  const n = big(v);
  if (n < 0n || n >= 1n << BigInt(8 * width)) throw new Error(`natural ${n} does not fit ${width} bytes`);
  return n.toString(16).padStart(2 * width, '0');
};
const hex = (h) => ({ k: 'raw', s: `#"${h}"` });
const int = (v) => ({ k: 'raw', s: big(v).toString() });
const bool = (v) => ({ k: 'raw', s: v ? 'True' : 'False' });
const raw = (s) => ({ k: 'raw', s });
const rec = (name, fields) => ({ k: 'rec', name, fields });
const call = (name, args) => ({ k: 'call', name, args });
const list = (items) => ({ k: 'list', items });
const tuple = (items) => ({ k: 'tuple', items });

// --- Lean value -> Aiken node ------------------------------------------
const policy = (n) => hex(bytes(n, 28));
const name32 = (n) => hex(bytes(n, 32));
const credential = (n) => call('Script', [hex(bytes(n, 28))]);
const ref = (r) => rec('OutputReference', [
  ['transaction_id', hex(bytes(r.tx, 32))],
  ['output_index', int(r.index)],
]);
const release = (r) => rec('PublishedRelease', [
  ['application_policy', policy(r.applicationPolicy)],
  ['application_credential', credential(r.applicationCredential)],
  ['state_program', hex(bytes(r.stateProgram, 28))],
  ['state_policy', policy(r.statePolicy)],
]);
const token = (t) => rec('Token', [['policy', policy(t.policy)], ['name', name32(t.name)]]);
const code = (xs) => hex(xs.map((x) => bytes(x, 8)).join(''));
const hash = (h) => rec('Hash', [['epoch', int(h.epoch)], ['sn', int(h.sn)]]);
const only = (o, what) => {
  const ks = Object.keys(o);
  if (ks.length !== 1) throw new Error(`${what}: expected one constructor, got ${ks}`);
  return ks[0];
};
const preimage = (p) => {
  const c = only(p, 'preimage');
  if (c === 'state') return rec('StatePreimage', [['seed', ref(p.state.seed)]]);
  if (c === 'active') {
    return rec('ActivePreimage', [
      ['registry', token(p.active.registry)],
      ['key', hex(bytes(p.active.key, 8))],
    ]);
  }
  throw new Error(`preimage constructor not modelled: ${c}`);
};
const state = (s) => {
  if (s === 'absent') return raw('Absent');
  if (s === 'convicted') return raw('Convicted');
  const c = only(s, 'state');
  if (c === 'present') {
    const l = s.present.l;
    return call('Present', [rec('Live', [
      ['sn', int(l.sn)], ['epoch', int(l.epoch)],
      ['poisoned', bool(l.poisoned)], ['frozen', bool(l.frozen)],
      ['born_at', int(l.bornAt)], ['refund_to', int(l.refundTo)], ['pool', int(l.pool)],
    ])]);
  }
  if (c === 'parked') return call('Parked', [hash(s.parked.h)]);
  if (c === 'terminationPending') return call('TerminationPending', [hash(s.terminationPending.h)]);
  throw new Error(`state constructor not modelled: ${c}`);
};
const datum = (d) => {
  if (d === 'empty') return raw('NoDatum');
  const c = only(d, 'datum');
  if (c === 'application') return call('InlineDatum', [call('builtin.i_data', [int(d.application.data)])]);
  if (c === 'root') {
    return call('InlineDatum', [call('builtin.constr_data', [int(1), list([call('builtin.i_data', [int(d.root.commitment)])])])]);
  }
  if (c === 'configuration') {
    const p = d.configuration.parameters;
    const fields = ['registrationCost', 'minimumTip', 'processTime', 'retractTime', 'bookingWidth']
      .map((k) => call('builtin.i_data', [int(p[k])]));
    return call('InlineDatum', [call('builtin.constr_data', [int(2), list(fields)])]);
  }
  throw new Error(`datum constructor not modelled: ${c}`);
};
const value = (o) => {
  let v = call('assets.from_lovelace', [int(o.lovelace)]);
  for (const [a, q] of o.assets) v = call('assets.add', [v, policy(a.policy), name32(a.name), int(q)]);
  return v;
};
const output = (o) => rec('Output', [
  ['address', rec('Address', [['payment_credential', credential(o.credential)], ['stake_credential', raw('None')]])],
  ['value', value(o)],
  ['datum', datum(o.datum)],
  ['reference_script', raw('None')],
]);
const query = (q) => rec('Query', [
  ['tables', rec('Tables', [
    ['keys', list(q.tables.keys.map(([aid, key]) => tuple([int(aid), hex(bytes(key, 8))])))],
    ['codes', list(q.tables.codes.map(([p, c]) => tuple([preimage(p), code(c)])))],
    ['hashes', list(q.tables.hashes.map(([c, n]) => tuple([code(c), name32(n)])))],
    ['datums', list(q.tables.datums.map(([r, [d, dec]]) => tuple([
      release(r), call('builtin.i_data', [int(d)]),
      rec('DecodedDatum', [['aid', int(dec.aid)], ['state', state(dec.state)]]),
    ])))],
  ])],
  ['context', rec('Context', [
    ['network', int(q.context.network)], ['release', release(q.context.release)],
    ['seed', ref(q.context.seed)], ['aid', int(q.context.aid)],
  ])],
  ['environment', rec('Environment', [
    ['network', int(q.environment.network)],
    ['release', q.environment.release === null ? raw('None') : call('Some', [release(q.environment.release)])],
  ])],
  ['params', rec('Params', [['d', int(q.params.D)], ['b', int(q.params.B)], ['p', int(q.params.P)], ['w', int(q.params.W)]])],
  ['now', int(q.now)],
  ['output', output(q.holding)],
]);

// --- layout (the shape `aiken fmt` keeps) ------------------------------
const flat = (n) => {
  switch (n.k) {
    case 'raw': return n.s;
    case 'rec': return n.fields.length ? `${n.name} { ${n.fields.map(([f, v]) => `${f}: ${flat(v)}`).join(', ')} }` : n.name;
    case 'call': return `${n.name}(${n.args.map(flat).join(', ')})`;
    case 'list': return `[${n.items.map(flat).join(', ')}]`;
    case 'tuple': return `(${n.items.map(flat).join(', ')})`;
    default: throw new Error(n.k);
  }
};
const render = (n, indent, col, tail) => {
  const f = flat(n);
  if (col + f.length + tail <= WIDTH || n.k === 'raw') return f;
  const pad = ' '.repeat(indent + 2);
  const close = ' '.repeat(indent);
  const items = (xs, g) => xs.map((x) => `${pad}${g(x)},\n`).join('');
  const child = (a) => render(a, indent + 2, indent + 2, 1);
  switch (n.k) {
    case 'rec':
      return `${n.name} {\n${items(n.fields, ([fname, v]) => `${fname}: ${render(v, indent + 2, indent + 2 + fname.length + 2, 1)}`)}${close}}`;
    case 'call':
      return `${n.name}(\n${items(n.args, child)}${close})`;
    case 'list':
      return `[\n${items(n.items, child)}${close}]`;
    case 'tuple':
      return `(\n${items(n.items, child)}${close})`;
    default: throw new Error(n.k);
  }
};

// --- module ------------------------------------------------------------
const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));
if (corpus.schema !== 'cardano-keri.consumer.identity' || corpus.version !== 1) throw new Error('corpus schema');
if (corpus.fields.length !== 32) throw new Error(`expected 32 fields queries, found ${corpus.fields.length}`);

const ident = (rowName) => {
  const id = rowName.replace(/-/g, '_');
  if (!/^[a-z][a-z0-9_]*$/.test(id)) throw new Error(`row name is not an identifier: ${rowName}`);
  return id;
};

const header = `//// GENERATED by scripts/consumer-vectors.mjs from the \`fields\` queries of
//// simulator/consumer-corpus.json. DO NOT EDIT.
//// \`just check-consumer-vectors\` regenerates and rejects drift.
////
//// One function and one test per corpus row; the test carries the row's own
//// expected result: accepted, refused, or (result \`error\`) an interpretation
//// failure, which the test requires the predicate to raise and never reads as
//// a verdict. Test names are the corpus row names with \`-\` written \`_\`.
////
//// Interpretation: test interpretation, not the registry byte layout. The
//// corpus tables become \`Tables\`; a missing or ambiguous entry fails.
////
//// Mapping of the Lean model onto Aiken values (written once, in the
//// generator):
////   policy, credential, state program  28-byte big-endian natural
////   transaction id, asset name         32-byte big-endian natural
////   AID key                            8-byte big-endian natural
////   code (list of naturals)            concatenated 8-byte big-endian naturals
////   credential                         script credential
////   assets                             Value, duplicate entries summed
////   datum application n                inline datum, integer n
////   datum root c                       inline datum, constructor 1 [c]
////   datum configuration                inline datum, constructor 2 [fields]
////   datum empty                        no datum
////   environment release null           None (unresolved release)
`;

const consumerNames = ['Absent', 'ActivePreimage', 'Context', 'Convicted', 'DecodedDatum', 'Environment',
  'Hash', 'Live', 'Params', 'Parked', 'Present', 'PublishedRelease', 'StatePreimage', 'TerminationPending', 'Token'];
// import list wrapped the way `aiken fmt` keeps it
const importBlock = (module, names) => {
  const one = `use ${module}.{${names.join(', ')}}`;
  if (one.length <= WIDTH) return one;
  const lines = [];
  let cur = '  ';
  for (const n of names) {
    const piece = (cur.trim() ? ' ' : '') + n + ',';
    if ((cur + piece).length > WIDTH) { lines.push(cur); cur = '  ' + n + ','; } else cur += piece;
  }
  lines.push(cur);
  return `use ${module}.{\n${lines.join('\n')}\n}`;
};
const importsFor = (body) => `
use aiken/builtin
use cardano/address.{Address, Script}
use cardano/assets
use cardano/transaction.{InlineDatum, NoDatum, Output, OutputReference}
${importBlock('cardano_keri/consumer', consumerNames.filter((n) => new RegExp(`\\b${n}\\b`).test(body)).sort())}
use cardano_keri/consumer_table_interpretation.{Query, Tables, verdict}
`;

let body = '';
const counts = { accepted: 0, refused: 0, failure: 0 };
for (const row of corpus.fields) {
  const id = ident(row.name);
  const fn = `row_${id}`;
  const node = query(row.query);
  body += `\n/// Corpus row \`${row.name}\`.\npub fn ${fn}() -> Query {\n  ${render(node, 2, 2, 0)}\n}\n`;
  const r = row.result;
  if (r && r.ok === true) { counts.accepted++; body += `\ntest ${id}() {\n  verdict(${fn}())\n}\n`; }
  else if (r && r.ok === false) { counts.refused++; body += `\ntest ${id}() {\n  !verdict(${fn}())\n}\n`; }
  else if (r && r.error === 'incomplete-or-ambiguous-interpretation') {
    counts.failure++;
    body += `\ntest ${id}() fail {\n  expect _verdict: Bool = verdict(${fn}())\n  True\n}\n`;
  } else throw new Error(`row ${row.name}: unmodelled result ${JSON.stringify(r)}`);
}
body += `\n/// Rows by expected result: ${counts.accepted} accepted, ${counts.refused} refused, ${counts.failure} interpretation failures.\npub const accepted_rows: Int = ${counts.accepted}\n\npub const refused_rows: Int = ${counts.refused}\n\npub const failure_rows: Int = ${counts.failure}\n`;

const text = header + importsFor(body) + body;
if (process.argv.includes('--check')) {
  let current = '';
  try { current = readFileSync(outPath, 'utf8'); } catch { /* absent */ }
  if (current !== text) {
    console.error('consumer vectors drifted from simulator/consumer-corpus.json; run: node scripts/consumer-vectors.mjs');
    process.exit(1);
  }
  console.log(`consumer vectors current (${corpus.fields.length} rows: ${counts.accepted} accepted, ${counts.refused} refused, ${counts.failure} interpretation failures)`);
} else {
  writeFileSync(outPath, text);
  console.log(`wrote ${outPath} (${corpus.fields.length} rows: ${counts.accepted} accepted, ${counts.refused} refused, ${counts.failure} interpretation failures)`);
}
