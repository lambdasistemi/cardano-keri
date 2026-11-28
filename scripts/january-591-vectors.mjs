#!/usr/bin/env node
// The advance journeys of #591: the Plutus Data (spent datum, successor datum, evidence, fact) of R01, the ordinary
// rotation, and R17, the abandonment rotation, each with its own predecessor inception, in the schema of
// advance-split-cases.json.
//
//   node scripts/january-591-vectors.mjs            # write
//   node scripts/january-591-vectors.mjs --check    # exit 1 when it drifts
//
// Input: offchain/test/keri-fixtures/fixtures/january-591/{R01,R17}: the exact signed bytes and keripy's attachments.
// Independent controls, before anything is written: the evidence bytes of the predicate input are the signed bytes of
// rotation.json; each indexed signature verifies (Ed25519) over those bytes under the key at its index; the successor
// commitments and threshold are those the signed event declares (`n`, `nt`); the spent commitments are those the
// predecessor inception declares; the receipt list is empty.
import { createPublicKey, verify } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { root } from './application-support.mjs';

const dir = join(root, 'offchain/test/keri-fixtures/fixtures/january-591');
const target = join(root, 'offchain/test/keri-fixtures/fixtures/january-591-cases.json');
const expectedTarget = join(root, 'onchain/lib/cardano_keri/checkpoint/january_591_expected.ak');

const I = (i) => ({ i });
const B = (b) => ({ b });
const L = (l) => ({ l });
const C = (c, f) => ({ c, f });
const hexOf = (buf) => Buffer.from(buf).toString('hex');
const unreduced = (n) => C(0, [I(n)]);

// a qb64 primitive of one code character: the code character is the padding of a 33-byte value
const qb64 = (text) => {
  const raw = Buffer.from('A' + text.slice(1), 'base64url');
  if (raw.length !== 33 || raw[0] !== 0) throw new Error('not a one-character-code primitive: ' + text);
  return raw.subarray(1);
};

const ints = (s) => (s.trim() === '' ? [] : s.split(',').map((x) => Number(x.trim())));
const hexes = (s) => [...s.matchAll(/#"([0-9a-f]*)"/g)].map((m) => m[1]);
const pairs = (s) => [...s.matchAll(/\((\d+), #"([0-9a-f]+)"\)/g)].map((m) => [Number(m[1]), m[2]]);

const section = (text, start, end) => {
  const a = text.indexOf(start);
  const b = text.indexOf(end, a);
  if (a < 0 || b < 0) throw new Error('section ' + start);
  return text.slice(a, b);
};
const field = (s, name) => {
  const m = s.match(new RegExp(`\\n\\s*${name}: ([^\\n]*),\\n`));
  if (!m) throw new Error('field ' + name);
  return m[1];
};
const threshold = (s) => {
  const m = s.match(/^Unweighted\((\d+)\)$/);
  if (!m) throw new Error('threshold ' + s);
  return Number(m[1]);
};

const build = (name) => {
  const base = join(dir, name);
  const rotationText = readFileSync(join(base, 'rotation.json'), 'utf8');
  const rotation = JSON.parse(rotationText);
  const inception = JSON.parse(readFileSync(join(base, 'predecessor-icp.json'), 'utf8'));
  const ak = readFileSync(join(base, 'aiken-advance-input.ak'), 'utf8');
  const spentS = section(ak, 'let spent', 'let new');
  const newS = section(ak, 'let new', 'let e =');
  const evS = section(ak, 'let e =', 'let v =');

  // the signed bytes are the evidence's bytes
  const eventBytes = hexes(field(evS, 'event_bytes'))[0];
  if (eventBytes !== hexOf(Buffer.from(rotationText, 'utf8'))) throw new Error(name + ': evidence bytes are not the signed rotation');

  const curKeys = rotation.k.map((k) => hexOf(qb64(k)));
  const nextKeys = rotation.n.map((n) => hexOf(qb64(n)));
  const spentNext = inception.n.map((n) => hexOf(qb64(n)));
  const spentKeys = inception.k.map((k) => hexOf(qb64(k)));
  const sameLists = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  if (!sameLists(hexes(field(newS, 'cur_keys')), curKeys)) throw new Error(name + ': revealed keys');
  if (!sameLists(hexes(field(newS, 'next_keys')), nextKeys)) throw new Error(name + ': successor commitments');
  if (!sameLists(hexes(field(spentS, 'next_keys')), spentNext)) throw new Error(name + ': spent commitments');
  const nextThreshold = Number(rotation.nt);
  if (threshold(field(newS, 'next_threshold')) !== nextThreshold) throw new Error(name + ': successor threshold');
  if (threshold(field(spentS, 'next_threshold')) !== Number(inception.nt)) throw new Error(name + ': spent threshold');
  const curThreshold = Number(rotation.kt);
  if (threshold(field(newS, 'cur_threshold')) !== curThreshold) throw new Error(name + ': signing threshold');
  if (field(evS, 'wit_receipts') !== '[]') throw new Error(name + ': the receipt list must be empty');

  // each indexed signature verifies under the key at its index over the signed bytes
  const sigs = pairs(field(evS, 'ctrl_sigs'));
  const spki = (raw) => Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(raw, 'hex')]);
  for (const [index, sig] of sigs) {
    const ok = verify(null, Buffer.from(eventBytes, 'hex'), createPublicKey({ key: spki(curKeys[index]), format: 'der', type: 'spki' }), Buffer.from(sig, 'hex'));
    if (!ok) throw new Error(name + ': signature ' + index + ' does not verify');
  }
  if (sigs.length !== curThreshold) throw new Error(name + ': expected every key to sign');

  const evidence = C(0, [
    B(eventBytes),
    I(Number(field(evS, 'off_t'))), I(Number(field(evS, 'off_i'))), I(Number(field(evS, 'off_s'))),
    L(ints(field(evS, 'off_k').slice(1, -1)).map(I)),
    I(Number(field(evS, 'off_kt'))),
    L(ints(field(evS, 'off_n').slice(1, -1)).map(I)),
    I(Number(field(evS, 'off_nt'))),
    L(ints(field(evS, 'off_br').slice(1, -1)).map(I)),
    L(ints(field(evS, 'off_ba').slice(1, -1)).map(I)),
    I(Number(field(evS, 'off_bt'))),
    L(hexes(field(evS, 'wit_cut')).map(B)),
    L(hexes(field(evS, 'wit_add')).map(B)),
    L(sigs.map(([i, s]) => L([I(i), B(s)]))),
    L([]),
  ]);

  const keyMaterial = (keys, kt, next, nt) => C(0, [L(keys.map(B)), unreduced(kt), L(next.map(B)), unreduced(nt), L([]), I(0)]);
  const aid = Buffer.from(inception.i, 'ascii').toString('hex');
  const live = (sn, epoch, frozen, keys) =>
    C(1, [C(0, [B(aid), I(sn), I(epoch), C(0, []), C(frozen ? 1 : 0, []), I(1795490558000), B('60' + 'aa'.repeat(28)), C(0, []), keys])]);
  const spentKeysMaterial = keyMaterial(spentKeys, Number(inception.kt), spentNext, Number(inception.nt));
  const newKeysMaterial = keyMaterial(curKeys, curThreshold, nextKeys, nextThreshold);
  const fact = C(0, [B(eventBytes), L(curKeys.map(B)), unreduced(curThreshold), L([]), I(0), L(spentNext.map(B)), unreduced(Number(inception.nt)),
    L(sigs.map(([i, s]) => L([I(i), B(s)]))), L([])]);
  // what a structural read of the signed body must give: decoded by JSON.parse and located by indexOf, not by the
  // code under test
  const nMark = rotationText.indexOf('"n":[') + 5;
  let cursor = nMark;
  const nStarts = rotation.n.map((digest) => {
    const at = rotationText.indexOf('"' + digest + '"', cursor) + 1;
    cursor = at + digest.length;
    return at;
  });
  const ntString = typeof rotation.nt === 'string';
  const ntStart = rotationText.indexOf(ntString ? '"nt":"' : '"nt":') + (ntString ? 6 : 5);
  const ntValue = ntString ? rotation.nt : JSON.stringify(rotation.nt);
  const projection = { body: eventBytes, ntStart, ntValue, nStarts, nValues: rotation.n };
  return {
    txid: 'd1'.repeat(32),
    index: 0,
    aid: inception.i,
    oldDatum: live(0, 0, false, spentKeysMaterial),
    newDatum: live(1, 1, false, newKeysMaterial),
    frozenOld: live(0, 0, true, spentKeysMaterial),
    evidence,
    freezePayload: C(0, [newKeysMaterial, I(1), evidence]),
    fact,
    expect: { nextKeys, nextThreshold, spentNextKeys: spentNext },
    projection,
  };
};

// The rotation body of R01 with a seal that spells the abandonment fields: its top-level `nt` and `n` declare two
// commitments and threshold 2, and a nested object of `a` spells `"nt":"0","n":[],"bt":"0"` in compact form.
const crafted = (() => {
  const text = readFileSync(join(dir, 'R01/rotation.json'), 'utf8');
  const seal = '{"nt":"0","n":[],"bt":"0"}';
  const body = text.replace('"a":[]}', '"a":[' + seal + ']}');
  if (body === text) throw new Error('the seal was not placed');
  const size = body.length.toString(16).padStart(6, '0');
  const sized = body.replace(/KERI10JSON[0-9a-f]{6}_/, 'KERI10JSON' + size + '_');
  const at = sized.lastIndexOf(seal);
  return { body: sized, offNt: at + 7, offBt: at + seal.indexOf('"bt":"') + 6 };
})();

// Two bodies outside the supported profile: a space after a colon, and a second `nt` after `n`.
const outsideProfile = (() => {
  const text = readFileSync(join(dir, 'R01/rotation.json'), 'utf8');
  const spaced = text.replace('"nt":"2"', '"nt": "2"');
  const repeated = text.replace('],"bt":"0"', '],"nt":"0","bt":"0"');
  if (spaced === text || repeated === text) throw new Error('profile controls were not placed');
  return { spaced, repeated };
})();

// Framing controls of the whole body: a repeated top-level declaration after `a`, an `a` that is not closed, a second
// closing brace, and (valid) a seal whose string holds an escaped quote.
const framing = (() => {
  const text = readFileSync(join(dir, 'R01/rotation.json'), 'utf8');
  const variant = (replacement) => {
    const body = text.replace('"a":[]}', replacement);
    if (body === text) throw new Error('framing control was not placed');
    return body;
  };
  return {
    trailingPair: variant('"a":[],"nt":"0","n":[]}'),
    unbalanced: variant('"a":[}'),
    trailingBrace: variant('"a":[]}}'),
    escapedSeal: variant('"a":[{"x":"q\\"r"}]}'),
  };
})();

// Scalar controls of the final value: valid numbers and escapes, and matched malformed ones. The value is the whole of `a`.
const scalars = (() => {
  const text = readFileSync(join(dir, 'R01/rotation.json'), 'utf8');
  const value = (v) => {
    const body = text.replace('"a":[]}', '"a":' + v + '}');
    if (body === text) throw new Error('scalar control was not placed');
    return body;
  };
  return {
    validNumbers: value('[{"n":-1.5e+3,"m":0,"k":10,"j":-0}]'),
    validEscapes: value('["\\u00e9\\n\\"\\\\\\/"]'),
    minusOnly: value('-'),
    fractionWithoutDigits: value('1.'),
    exponentWithoutDigits: value('1e+'),
    signedPoint: value('-.5'),
    leadingZero: value('01'),
    invalidEscape: value('"\\x"'),
    shortUnicodeEscape: value('"\\u12"'),
    rawControl: value('"a\u0001b"'),
  };
})();

// Text controls of the compact JSON profile: raw UTF-8 in the final value (its strings, member names and nested values) and in the
// strings that precede it. The bodies are built from bytes: a malformed encoding cannot be spelled as a JavaScript string.
const encodings = (() => {
  const base = readFileSync(join(dir, 'R01/rotation.json'), 'utf8');
  const marker = '"a":[]}';
  const at = base.indexOf(marker);
  if (at < 0) throw new Error('text control was not placed');
  const bytes = (...parts) => Buffer.concat(parts.map((x) => (typeof x === 'string' ? Buffer.from(x, 'utf8') : Buffer.from(x))));
  const last = (...value) => bytes(base.slice(0, at) + '"a":', ...value, '}');
  const inFirstDigest = (...inserted) => {
    const open = '"n":["';
    const where = base.indexOf(open);
    if (where < 0) throw new Error('prefix text control was not placed');
    const start = where + open.length + 4;
    return bytes(base.slice(0, start), ...inserted, base.slice(start));
  };
  // every length and boundary of well-formed UTF-8, as one string
  const wellFormed = [[0xc2, 0x80], [0xdf, 0xbf], [0xe0, 0xa0, 0x80], [0xed, 0x9f, 0xbf], [0xee, 0x80, 0x80], [0xef, 0xbf, 0xbf], [0xf0, 0x90, 0x80, 0x80], [0xf4, 0x8f, 0xbf, 0xbf]];
  const malformed = {
    isolatedContinuation: [0x80],
    isolatedLastContinuation: [0xbf],
    overlongTwo: [0xc0, 0x80],
    overlongTwoLast: [0xc1, 0xbf],
    truncatedTwo: [0xc3],
    truncatedThree: [0xe2, 0x82],
    overlongThree: [0xe0, 0x80, 0x80],
    surrogate: [0xed, 0xa0, 0x80],
    overlongFour: [0xf0, 0x80, 0x80, 0x80],
    abovePlane: [0xf4, 0x90, 0x80, 0x80],
    leadFive: [0xf5, 0x80, 0x80, 0x80],
    leadFe: [0xfe],
    leadFf: [0xff],
    badContinuation: [0xc3, 0x28],
  };
  const last_ = (value) => last(value);
  return {
    valid: last('["', 'é€😀', '"]'),
    validNames: last('[{"', 'é€😀', '":"', 'é', '"}]'),
    validBoundaries: last('[{"k":"', ...wellFormed.map((b) => Buffer.from(b)), '"}]'),
    malformedValues: Object.values(malformed).map((b) => last('["a', Buffer.from(b), 'b"]')),
    malformedName: last('[{"a', Buffer.from(malformed.isolatedContinuation), '":1}]'),
    malformedSurrogateName: last('[{"', Buffer.from(malformed.surrogate), '":1}]'),
    malformedNested: last('[["a', Buffer.from(malformed.isolatedContinuation), '"]]'),
    prefixValid: inFirstDigest('é'),
    prefixMalformed: Object.values(malformed).map((b) => inFirstDigest(Buffer.from(b))),
  };
})();

// Independent control: a strict UTF-8 decoder accepts every valid body and refuses every malformed one, so the controls are what they
// claim to be before any validator reads them.
{
  const strict = new TextDecoder('utf-8', {fatal: true});
  const decodes = (buf) => { try { strict.decode(buf); return true; } catch { return false; } };
  const valid = [encodings.valid, encodings.validNames, encodings.validBoundaries, encodings.prefixValid];
  const malformed = [...encodings.malformedValues, encodings.malformedName, encodings.malformedSurrogateName, encodings.malformedNested, ...encodings.prefixMalformed];
  if (!valid.every(decodes)) throw new Error('a valid text control is not valid UTF-8');
  if (malformed.some(decodes)) throw new Error('a malformed text control is valid UTF-8');
}

const out = {
  text_pair: { valid: hexOf(encodings.validBoundaries), malformed: hexOf(encodings.malformedValues[0]) },
  scalar_pair: { valid: Buffer.from(scalars.validNumbers, 'utf8').toString('hex'), malformed: Buffer.from(scalars.minusOnly, 'utf8').toString('hex') },
  trailing_pair: { body: Buffer.from(framing.trailingPair, 'utf8').toString('hex') },
  nested_seal: { body: Buffer.from(crafted.body, 'utf8').toString('hex'), offNt: crafted.offNt, offBt: crafted.offBt },
  _provenance:
    'R01 and R17 of offchain/test/keri-fixtures/fixtures/january-591: each rotation with its own predecessor inception, the exact signed bytes, indexed controller signatures and an empty receipt list. Generated by scripts/january-591-vectors.mjs.',
  r01: build('R01'),
  r17: build('R17'),
};
const text = JSON.stringify(out, null, 1) + '\n';

// the structural expectations as an Aiken module, for the validators' own tests
const aikenText = (t) => JSON.stringify(t);
const aikenList = (xs) => xs;
// a constant as `aiken fmt` lays it out: on one line when it fits in 80 columns, else after the `=` on a line of its own
// (a list, one element per line, when it does not fit there either)
const constant = (name, type, value) => {
  const head = `pub const ${name}: ${type} =`;
  const inline = Array.isArray(value) ? '[' + value.join(', ') + ']' : value;
  if ((head + ' ' + inline).length <= 80) return head + ' ' + inline;
  if (Array.isArray(value) && ('  ' + inline).length > 80) return head + '\n  [\n' + value.map((v) => '    ' + v + ',').join('\n') + '\n  ]';
  return head + '\n  ' + inline;
};
const expectedFor = (name, c) => {
  const q = c.projection;
  return [
    constant(`${name}_body`, 'ByteArray', '#"' + q.body + '"'),
    constant(`${name}_nt_start`, 'Int', String(q.ntStart)),
    constant(`${name}_nt_value`, 'ByteArray', aikenText(q.ntValue)),
    constant(`${name}_n_starts`, 'List<Int>', aikenList(q.nStarts.map(String))),
    constant(`${name}_n_values`, 'List<ByteArray>', aikenList(q.nValues.map(aikenText))),
  ].join('\n\n');
};
const expectedText = [
  '//// The top-level `nt` and `n` of the signed rotation bodies of #591 (R01 and R17), decoded by',
  '//// scripts/january-591-vectors.mjs from the exact signed bytes (JSON.parse and indexOf), not by the validators;',
  '//// and a body whose seal spells the abandonment fields. Generated: do not edit.',
  '',
  expectedFor('r01', out.r01),
  '',
  expectedFor('r17', out.r17),
  '',
  constant('nested_seal_body', 'ByteArray', '#"' + Buffer.from(crafted.body, 'utf8').toString('hex') + '"'),
  '',
  constant('nested_seal_off_nt', 'Int', String(crafted.offNt)),
  '',
  constant('nested_seal_off_bt', 'Int', String(crafted.offBt)),
  '',
  constant('spaced_body', 'ByteArray', '#"' + Buffer.from(outsideProfile.spaced, 'utf8').toString('hex') + '"'),
  '',
  constant('trailing_pair_body', 'ByteArray', '#"' + Buffer.from(framing.trailingPair, 'utf8').toString('hex') + '"'),
  '',
  constant('unbalanced_a_body', 'ByteArray', '#"' + Buffer.from(framing.unbalanced, 'utf8').toString('hex') + '"'),
  '',
  constant('trailing_brace_body', 'ByteArray', '#"' + Buffer.from(framing.trailingBrace, 'utf8').toString('hex') + '"'),
  '',
  constant('escaped_seal_body', 'ByteArray', '#"' + Buffer.from(framing.escapedSeal, 'utf8').toString('hex') + '"'),
  '',
  constant('valid_numbers_body', 'ByteArray', '#"' + Buffer.from(scalars.validNumbers, 'utf8').toString('hex') + '"'),
  '',
  constant('valid_escapes_body', 'ByteArray', '#"' + Buffer.from(scalars.validEscapes, 'utf8').toString('hex') + '"'),
  '',
  constant('minus_only_body', 'ByteArray', '#"' + Buffer.from(scalars.minusOnly, 'utf8').toString('hex') + '"'),
  '',
  constant('fraction_without_digits_body', 'ByteArray', '#"' + Buffer.from(scalars.fractionWithoutDigits, 'utf8').toString('hex') + '"'),
  '',
  constant('exponent_without_digits_body', 'ByteArray', '#"' + Buffer.from(scalars.exponentWithoutDigits, 'utf8').toString('hex') + '"'),
  '',
  constant('signed_point_body', 'ByteArray', '#"' + Buffer.from(scalars.signedPoint, 'utf8').toString('hex') + '"'),
  '',
  constant('leading_zero_body', 'ByteArray', '#"' + Buffer.from(scalars.leadingZero, 'utf8').toString('hex') + '"'),
  '',
  constant('invalid_escape_body', 'ByteArray', '#"' + Buffer.from(scalars.invalidEscape, 'utf8').toString('hex') + '"'),
  '',
  constant('short_unicode_escape_body', 'ByteArray', '#"' + Buffer.from(scalars.shortUnicodeEscape, 'utf8').toString('hex') + '"'),
  '',
  constant('raw_control_body', 'ByteArray', '#"' + Buffer.from(scalars.rawControl, 'utf8').toString('hex') + '"'),
  '',
  constant('valid_text_body', 'ByteArray', '#"' + hexOf(encodings.valid) + '"'),
  '',
  constant('valid_text_names_body', 'ByteArray', '#"' + hexOf(encodings.validNames) + '"'),
  '',
  constant('valid_text_boundaries_body', 'ByteArray', '#"' + hexOf(encodings.validBoundaries) + '"'),
  '',
  constant('malformed_text_bodies', 'List<ByteArray>', [...encodings.malformedValues, encodings.malformedName, encodings.malformedSurrogateName, encodings.malformedNested].map((b) => '#"' + hexOf(b) + '"')),
  '',
  constant('prefix_valid_text_body', 'ByteArray', '#"' + hexOf(encodings.prefixValid) + '"'),
  '',
  constant('prefix_malformed_text_bodies', 'List<ByteArray>', encodings.prefixMalformed.map((b) => '#"' + hexOf(b) + '"')),
  '',
  constant('repeated_nt_body', 'ByteArray', '#"' + Buffer.from(outsideProfile.repeated, 'utf8').toString('hex') + '"'),
  '',
].join('\n');
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== text || readFileSync(expectedTarget, 'utf8') !== expectedText) {
    console.error('january-591-cases.json or january_591_expected.ak drifts from the fixtures');
    process.exit(1);
  }
  console.log('january-591-cases.json and january_591_expected.ak match the fixtures');
} else {
  writeFileSync(target, text);
  writeFileSync(expectedTarget, expectedText);
  console.log('wrote ' + target + ' and ' + expectedTarget);
}
