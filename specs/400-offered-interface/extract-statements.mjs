// Representation adapter only: results are computed by StatementsTraceDriver.lean.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const source = JSON.parse(readFileSync(process.argv[2], 'utf8'));
assert.equal(source.profile, 'statements-model-v1');
assert.equal(source.source, '4906cfaed34e43405b04d3cc8746bd6388fc8452');

function action(family, value) {
  if (family === 'query') return value;
  const name = typeof value === 'string' ? value : Object.keys(value)[0];
  const p = typeof value === 'string' ? {} : { ...value[name] };
  if ("sn'" in p) { p.sn = p["sn'"]; delete p["sn'"]; }
  if ("toad'" in p) { p.toad = p["toad'"]; delete p["toad'"]; }
  if (family === 'mirror' && name === 'history') {
    p.historyAction = action('history', p.a); delete p.a;
  }
  if (family === 'credential' && name === 'mirror') {
    p.mirrorAction = action('mirror', p.a); delete p.a;
  }
  return { action: `${family}.${name}`, ...p };
}

const cases = source.cases.map(({ name, family, oracle, call, result }) => {
  const a = action(family, call.action);
  return { name, oracle, call: { ...call, action: a }, result: result === null
    ? { status: 'refused', refusal: `${a.action}-refused` }
    : { status: 'accepted', value: result } };
});
assert.equal(new Set(cases.map(c => c.name)).size, cases.length);
const operations = new Set(cases.map(c => c.call.action.action));
const refused = new Set(cases.filter(c => c.result.status === 'refused').map(c => c.result.refusal));
console.error(JSON.stringify({ cases: cases.length, operations: operations.size, refusalNames: refused.size }));
console.log(JSON.stringify({ ...source, cases }));
