#!/usr/bin/env node
// Generates onchain/lib/cardano_keri/consumer_checkpoint_datum_vectors.ak from
// lean/checkpoint-datum-vectors.json (the vectors the Lean version 2
// checkpoint datum module `CardanoKeri.CheckpointDatum` produces).
//
//   node scripts/checkpoint-datum-vectors.mjs            # write the module
//   node scripts/checkpoint-datum-vectors.mjs --check    # exit 1 when the module drifts
//
// The mapping of the Lean values onto Aiken values is written here, once, and
// restated in the header of the generated module:
//   datum (hex)                        -> byte string: the inline datum's CBOR
//   decoded.aid, state.refundTo (hex)  -> the Lean `pack` of those bytes: the
//                                         bijective base-256 numeral, least
//                                         significant digit first
//   sn, epoch, bornAt                  -> integers (decimal strings beyond 2^53)
//   poisoned, frozen                   -> Bool
//   decoded null                       -> None
//   consumer.now, consumer.accepted    -> the slot and the verdict
//   context aid                        -> the numeral of the qualified CESR text
//                                         of the row's AID (accepted rows), or of
//                                         the first identity vector's AID (refused
//                                         rows), as `contextFor` in the Lean
// The numerals are computed here, independently of the Aiken `pack`, so the
// generated vectors check the Aiken side.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const inPath = resolve(root, 'lean/checkpoint-datum-vectors.json');
const identityPath = resolve(root, 'lean/consumer-identity-vectors.json');
const outPath = resolve(root, 'onchain/lib/cardano_keri/consumer_checkpoint_datum_vectors.ak');

const isHex = (s) => typeof s === 'string' && /^([0-9a-f]{2})*$/.test(s);

// Lean `pack`: b0 + 1 + 256 * pack(rest); the empty string is 0.
const pack = (bs) => bs.reduceRight((acc, b) => BigInt(b) + 1n + 256n * acc, 0n);
const bytesOfHex = (h) => [...Buffer.from(h, 'hex')];
const utf8 = (s) => [...Buffer.from(s, 'utf8')];

const data = JSON.parse(readFileSync(inPath, 'utf8'));
const identity = JSON.parse(readFileSync(identityPath, 'utf8'));
if (!Array.isArray(data.accepted) || data.accepted.length !== 7) throw new Error(`expected 7 accepted rows, found ${data.accepted && data.accepted.length}`);
if (!Array.isArray(data.refused) || data.refused.length !== 29) throw new Error(`expected 29 refused rows, found ${data.refused && data.refused.length}`);
if (Object.keys(data.params).join() !== 'W') throw new Error('params changed');
const first = identity.vectors[0];
if (first.id !== 'transferable-aid') throw new Error('the first identity vector is not transferable-aid');
const refusedAid = pack(utf8(first.input.aid));

const ident = (id) => {
  const name = id.replace(/-/g, '_');
  if (!/^[a-z][a-z0-9_]*$/.test(name)) throw new Error(`vector id is not an identifier: ${id}`);
  return name;
};

const big = (v) => BigInt(v);
const bool = (b) => (b ? 'True' : 'False');

const decodedText = (id, d) => {
  if (d === null) return 'None';
  if (!isHex(d.aid)) throw new Error(`${id}: decoded aid`);
  const aid = pack(bytesOfHex(d.aid));
  const s = d.state;
  if (s.form === 'live') {
    if (!isHex(s.refundTo)) throw new Error(`${id}: refund`);
    if (big(s.pool) !== 0n) throw new Error(`${id}: the decoder reads no pool`);
    return `Some(
      DecodedDatum {
        aid: ${aid},
        state: Present(
          Live {
            sn: ${big(s.sn)},
            epoch: ${big(s.epoch)},
            poisoned: ${bool(s.poisoned)},
            frozen: ${bool(s.frozen)},
            born_at: ${big(s.bornAt)},
            refund_to: ${pack(bytesOfHex(s.refundTo))},
            pool: 0,
          },
        ),
      },
    )`;
  }
  if (s.form === 'terminationPending') {
    return `Some(
      DecodedDatum {
        aid: ${aid},
        state: TerminationPending(Hash { epoch: ${big(s.epoch)}, sn: ${big(s.sn)} }),
      },
    )`;
  }
  throw new Error(`${id}: unknown state form ${s.form}`);
};


// ---------------------------------------------------------------------
// A reader and a writer of Plutus Data, after the Lean `parse` / `cbor`,
// used for the rows the Aiken standard library cannot read (a tagged big
// number panics its `cbor.deserialise`). Every datum is read and written back;
// the generation fails when the written bytes differ from the committed ones.
// ---------------------------------------------------------------------
const beVal = (bs) => bs.reduce((acc, b) => acc * 256n + BigInt(b), 0n);
const hexOf = (bs) => Buffer.from(bs).toString('hex');

// Read one Data from a byte array at `pos`; returns [data, nextPos] or null.
const readData = (b, pos) => {
  if (pos >= b.length) return null;
  const first = b[pos];
  const major = first >> 5;
  const info = first & 31;
  if (first === 0x5f) {
    let p = pos + 1;
    const out = [];
    while (b[p] !== 0xff) {
      if (p >= b.length || b[p] >> 5 !== 2 || b[p] === 0x5f) return null;
      const h = readHead(b, p);
      if (!h || p + h.len + Number(h.n) > b.length) return null;
      out.push(...b.slice(p + h.len, p + h.len + Number(h.n)));
      p += h.len + Number(h.n);
    }
    return [{ k: 'bytes', v: out }, p + 1];
  }
  if (first === 0x9f) {
    let p = pos + 1;
    const out = [];
    while (b[p] !== 0xff) {
      const r = readData(b, p);
      if (!r) return null;
      out.push(r[0]);
      p = r[1];
    }
    return [{ k: 'list', v: out }, p + 1];
  }
  const h = readHead(b, pos);
  if (!h) return null;
  let p = pos + h.len;
  if (major === 0) return [{ k: 'int', v: h.n }, p];
  if (major === 1) return [{ k: 'int', v: -1n - h.n }, p];
  if (major === 2) {
    if (p + Number(h.n) > b.length) return null;
    return [{ k: 'bytes', v: b.slice(p, p + Number(h.n)) }, p + Number(h.n)];
  }
  if (major === 4) {
    const out = [];
    for (let i = 0n; i < h.n; i++) {
      const r = readData(b, p);
      if (!r) return null;
      out.push(r[0]);
      p = r[1];
    }
    return [{ k: 'list', v: out }, p];
  }
  if (major === 6) {
    const tag = Number(h.n);
    if (tag === 2 || tag === 3) {
      const r = readData(b, p);
      if (!r || r[0].k !== 'bytes') return null;
      const n = beVal(r[0].v);
      return [{ k: 'int', v: tag === 2 ? n : -1n - n }, r[1]];
    }
    const r = readData(b, p);
    if (!r || r[0].k !== 'list') return null;
    if (tag >= 121 && tag < 128) return [{ k: 'constr', i: tag - 121, v: r[0].v }, r[1]];
    if (tag >= 1280 && tag < 1401) return [{ k: 'constr', i: tag - 1280 + 7, v: r[0].v }, r[1]];
    return null;
  }
  return null;
};
const readHead = (b, pos) => {
  const info = b[pos] & 31;
  if (info < 24) return { n: BigInt(info), len: 1 };
  const w = { 24: 1, 25: 2, 26: 4, 27: 8 }[info];
  if (w === undefined || pos + 1 + w > b.length) return null;
  return { n: beVal(b.slice(pos + 1, pos + 1 + w)), len: 1 + w };
};
const head = (major, n) => {
  const m = major << 5;
  if (n < 24n) return [m | Number(n)];
  const w = n < 256n ? 1 : n < 65536n ? 2 : n < 4294967296n ? 4 : 8;
  const code = { 1: 24, 2: 25, 4: 26, 8: 27 }[w];
  const out = [m | code];
  for (let i = w - 1; i >= 0; i--) out.push(Number((n >> BigInt(8 * i)) & 255n));
  return out;
};
const minimalBe = (n) => {
  const out = [];
  for (let x = n; x > 0n; x >>= 8n) out.unshift(Number(x & 255n));
  return out.length ? out : [0];
};
const bstr = (bs) => {
  if (bs.length <= 64) return [...head(2, BigInt(bs.length)), ...bs];
  const out = [0x5f];
  for (let i = 0; i < bs.length; i += 64) out.push(...head(2, BigInt(Math.min(64, bs.length - i))), ...bs.slice(i, i + 64));
  return [...out, 0xff];
};
const intBytes = (n) => {
  if (n >= 0n) return n < 18446744073709551616n ? head(0, n) : [0xc2, ...bstr(minimalBe(n))];
  const m = -1n - n;
  return m < 18446744073709551616n ? head(1, m) : [0xc3, ...bstr(minimalBe(m))];
};
const listBytes = (items) => (items.length === 0 ? [0x80] : [0x9f, ...items.flatMap(writeData), 0xff]);
const writeData = (d) => {
  switch (d.k) {
    case 'int': return intBytes(d.v);
    case 'bytes': return bstr(d.v);
    case 'list': return listBytes(d.v);
    case 'constr': {
      const tag = d.i < 7 ? 121 + d.i : 1280 + (d.i - 7);
      if (d.i >= 128) throw new Error('constructor index beyond the vectors');
      return [...head(6, BigInt(tag)), ...listBytes(d.v)];
    }
    default: throw new Error(`cannot write a ${d.k}`);
  }
};
const hasBigNumber = (d) =>
  (d.k === 'int' && (d.v >= 18446744073709551616n || d.v < -18446744073709551616n)) ||
  ((d.k === 'list' || d.k === 'constr') && d.v.some(hasBigNumber));

// The Aiken statements that build a Data, one short statement each.
const buildData = (d) => {
  const stmts = [];
  let n = 0;
  const fresh = (p) => `${p}${n++}`;
  const emit = (x) => {
    if (x.k === 'int') { const v = fresh('n'); stmts.push(`let ${v} = builtin.i_data(${x.v})`); return v; }
    if (x.k === 'bytes') { const v = fresh('b'); const one = `let ${v} = builtin.b_data(#"${hexOf(x.v)}")`; stmts.push(one.length + 2 > 80 ? `let ${v} = builtin.b_data(\n    #"${hexOf(x.v)}",\n  )` : one); return v; }
    if (x.k !== 'list' && x.k !== 'constr') throw new Error(`cannot build a ${x.k}`);
    const names = x.v.map(emit);
    let tail = fresh('t');
    stmts.push(`let ${tail}: List<Data> = []`);
    for (let i = names.length - 1; i >= 0; i--) {
      const t = fresh('t');
      stmts.push(`let ${t} = [${names[i]}, ..${tail}]`);
      tail = t;
    }
    const v = fresh(x.k === 'list' ? 'l' : 'c');
    stmts.push(x.k === 'list' ? `let ${v} = builtin.list_data(${tail})` : `let ${v} = builtin.constr_data(${x.i}, ${tail})`);
    return v;
  };
  const root = emit(d);
  return { stmts, root };
};

// The Lean theorems (lean/CardanoKeri/CheckpointDatumGoals.lean) each row
// exhibits, named in the doc comment of its tests. Accepted rows exhibit the
// written-datum theorems; a refused row exhibits the refusal theorem of its
// change.
const refusedTheorem = {
  'version-1': 'version_one_refused',
  'version-3': 'wrong_version_refused',
  'version-no-field': 'version_arity_refused',
  'version-two-fields': 'version_arity_refused',
  'unknown-form': 'unknown_form_refused',
  'live-seven-fields': 'live_arity_refused',
  'live-nine-fields': 'live_arity_refused',
  'pending-five-fields': 'pending_arity_refused',
  'pending-negative-epoch': 'pending_fields_typed',
  'not-a-constructor': 'decode_accepts_only_written',
  'trailing-byte': 'decode_accepts_only_written',
  'truncated': 'decode_accepts_only_written',
  'empty': 'decode_accepts_only_written',
  'break-byte': 'decode_accepts_only_written',
};
const liveFieldRows = ['aid-integer', 'sn-negative', 'epoch-bytes', 'poisoned-not-boolean', 'poisoned-boolean-with-field', 'frozen-integer', 'born-at-negative', 'refund-integer', 'keys-list', 'keys-five-fields', 'key-integer', 'threshold-unknown-form', 'weight-one-field', 'witnesses-map', 'toad-bytes'];
for (const id of liveFieldRows) refusedTheorem[id] = 'live_fields_typed';
const decodeTheorems = (r) => {
  if (r.accepted) return '`decodeData_datum`, `decode_written`';
  if (!refusedTheorem[r.id]) throw new Error(`${r.id}: no refusal theorem named for this row`);
  return [...new Set([refusedTheorem[r.id], 'decode_accepts_only_written'])].map((t) => `\`${t}\``).join(', ');
};
// An accepted or refused written datum: the consumer's verdict is the iff. A
// refused row's datum is not written, so its decoder result is none and the
// consumer theorem for a decoder rejection applies (`CardanoKeri.ConsumerGoals`).
const verdictTheorems = (r) => {
  if (r.accepted) return '`written_holding_iff`';
  return r.id === 'version-1' ? '`version_one_holding_refused`' : '`malformed_datum_refused`';
};

const rows = [
  ...data.accepted.map((r) => ({ ...r, accepted: true })),
  ...data.refused.map((r) => ({ ...r, accepted: false })),
];
const seen = new Set();
const vectorFn = (r) => {
  const id = ident(r.id);
  if (seen.has(id)) throw new Error(`duplicate vector id ${r.id}`);
  seen.add(id);
  if (!isHex(r.datum)) throw new Error(`${r.id}: datum`);
  if (!Number.isSafeInteger(r.consumer.now) || r.consumer.now < 0) throw new Error(`${r.id}: now`);
  if (typeof r.consumer.accepted !== 'boolean') throw new Error(`${r.id}: accepted`);
  let aid;
  if (r.accepted) {
    if (!r.input) throw new Error(`${r.id}: accepted row without input`);
    // The vector's own consistency, independent of any implementation.
    const text = Buffer.from(utf8(r.input.aid)).toString('hex');
    if (r.decoded.aid !== text) throw new Error(`${r.id}: decoded aid is not the UTF-8 bytes of the CESR text`);
    aid = pack(utf8(r.input.aid));
  } else {
    if (r.decoded !== null) throw new Error(`${r.id}: a refused row decodes`);
    if (r.consumer.accepted) throw new Error(`${r.id}: a refused row is accepted`);
    aid = refusedAid;
  }
  let construction = 'None';
  let constructionFn = '';
  {
    const bytes = bytesOfHex(r.datum);
    const read = readData(bytes, 0);
    if (read && read[1] === bytes.length) {
      if (hexOf(writeData(read[0])) !== r.datum) throw new Error(`${r.id}: the datum does not round-trip through the Lean serialisation`);
      if (hasBigNumber(read[0])) {
        const { stmts, root } = buildData(read[0]);
        constructionFn = `/// The Data of vector \`${r.id}\`, built here because the standard library's
/// reader panics on a tagged big number; the generator checked that it
/// serialises back to the committed bytes.
fn construction_${id}() -> Data {
${stmts.map((x) => '  ' + x).join('\n')}
  ${root}
}

`;
        construction = `Some(construction_${id}())`;
      }
    }
  }
  return {
    id,
    decodeTheorems: decodeTheorems(r),
    verdictTheorems: verdictTheorems(r),
    text: constructionFn + `/// Vector \`${r.id}\`: ${r.note}.
pub fn vector_${id}() -> DatumVector {
  DatumVector {
    datum: #"${r.datum}",
    construction: ${construction},
    decoded: ${decodedText(r.id, r.decoded)},
    aid: ${aid},
    now: ${r.consumer.now},
    accepted: ${bool(r.consumer.accepted)},
  }
}
`,
  };
};

const header = `//// GENERATED by scripts/checkpoint-datum-vectors.mjs from
//// lean/checkpoint-datum-vectors.json. DO NOT EDIT.
//// \`just check-checkpoint-datum-vectors\` regenerates and rejects drift.
////
//// One function per vector, and for each vector two tests: the decoder
//// returns the row's \`decoded\` (or \`None\`), and the consumer predicate on the
//// concrete identity bytes and this decoder returns the row's verdict. The
//// expected values are the Lean's, written out; the Aiken decoder is the thing
//// under test.
////
//// Mapping of the Lean values onto Aiken values (written once, in the
//// generator):
////   datum                            the inline datum's CBOR bytes; the tests
////                                    read them with \`aiken/cbor.deserialise\`,
////                                    which stands in for the ledger's parse
////   aid, refund_to                   the Lean \`pack\` of the byte string: the
////                                    bijective base-256 numeral, computed by
////                                    the generator
////   aid (context)                    the numeral of the qualified CESR text of
////                                    the AID the consumer was fixed on
////   construction                     Some(Data) for a datum with a tagged big
////                                    number, which the standard library's reader
////                                    cannot read; None otherwise
////   decoded null                     None
`;

const vs = rows.map(vectorFn);
if (vs.length !== 36) throw new Error(`expected 36 vectors, found ${vs.length}`);
let body = '';
for (const v of vs) body += `\n${v.text}`;
body += `\n/// Every vector, in file order: the accepted rows, then the refused rows.\npub fn vectors() -> List<DatumVector> {\n  [\n${vs.map((v) => `    vector_${v.id}(),\n`).join('')}  ]\n}\n`;
for (const v of vs) {
  body += `\n/// Lean ${v.decodeTheorems}: the decoder returns the row's result.\ntest decode_${v.id}() {\n  decode_ok(vector_${v.id}())\n}\n`;
  body += `\n/// Lean ${v.verdictTheorems}: the consumer's verdict on a genuine holding is the row's.\ntest verdict_${v.id}() {\n  verdict_ok(vector_${v.id}())\n}\n`;
}

const imports = `
use aiken/builtin
use cardano_keri/consumer.{
  DecodedDatum, Hash, Live, Present, TerminationPending,
}
use cardano_keri/consumer_checkpoint_datum_check.{
  DatumVector, decode_ok, verdict_ok,
}
`;

const text = header + imports + body;
if (process.argv.includes('--check')) {
  let current = '';
  try { current = readFileSync(outPath, 'utf8'); } catch { /* absent */ }
  if (current !== text) {
    console.error('checkpoint datum vectors drifted from lean/checkpoint-datum-vectors.json; run: node scripts/checkpoint-datum-vectors.mjs');
    process.exit(1);
  }
  console.log(`checkpoint datum vectors current (${vs.length} vectors, ${vs.length * 2} generated tests)`);
} else {
  writeFileSync(outPath, text);
  console.log(`wrote ${outPath} (${vs.length} vectors, ${vs.length * 2} generated tests)`);
}
