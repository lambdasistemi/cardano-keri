#!/usr/bin/env node
/* Real connected story observations plus deliberately fabricated conclusions.
 * These controls test the property checker; they are not model mutation kills. */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { THEOREMS, properties, oracleIndex, oracleResult } from './registry-properties.mjs';
import { playStory } from './registry-simulator-backend.mjs';
import { equal } from './registry-economic-core.mjs';
const corpus = JSON.parse(readFileSync(new URL('./registry-simulator-corpus.json', import.meta.url))), index = oracleIndex(corpus);
const samples = new Map(); let cells = 0;
const played = readdirSync(new URL('./registry-simulator-scenarios/', import.meta.url)).filter(f => f.endsWith('.json')).map(f => Number(f.slice(0, 2)));
for (const id of played) for (const node of playStory(id).nodes) if (node.record) {
  for (const [name, result] of Object.entries(properties(node.record))) {
    assert.notEqual(result.v, 'fails', `story ${id}, node ${node.id}, ${name}`);
    if (result.v === 'holds') samples.set(name, node.record);
  }
  assert.deepEqual(oracleResult(index, node.record), { found: true, agrees: true }); cells++;
}
const violations = {
  'pending-conviction': r => { r.result.ok.state.carriers.find(c => c.aid === r.action.convictCkpt.aid).k++; },
  'booking-custody': r => { r.result.ok.state.terminations.find(e => equal(e.booking.request.reference, r.action.bookTermination.booking.request.reference)).payload.keyState++; },
  'pending-frame': r => {
    const consumed = r.action.fold?.transaction.transaction.inputs.map(i => i.ref) ?? [];
    const kept = r.input.terminations.find(e => !consumed.some(ref => equal(ref, e.booking.request.reference)));
    r.result.ok.state.terminations = r.result.ok.state.terminations.filter(e => !equal(e, kept));
  },
  'local-frame': r => { r.result.ok.state.bindings.push([999, 1000]); },
  'configuration': r => { r.result.ok.state.gen++; },
  'binding-domain': r => { r.result.ok.state.bindings.push([999, 1000]); },
  'terminal': r => { const aid = r.input.trie.find(([,l]) => l.known?.s === 'terminal')[0]; r.result.ok.state.trie.find(([key]) => key === aid)[1].known.s = 'active'; },
  'fold-burn': r => { r.action.fold.transaction.singularMint.forEach(pair => { if (pair[1] < 0) pair[1] = 0; }); },
};
assert.deepEqual(Object.keys(violations).sort(), THEOREMS.map(t => t.id).sort(), 'control ownership census');
for (const theorem of THEOREMS) {
  assert(samples.has(theorem.id), 'unexhibited ' + theorem.id);
  const r = structuredClone(samples.get(theorem.id)); violations[theorem.id](r);
  assert.equal(properties(r)[theorem.id].v, 'fails', 'fabricated conclusion not detected: ' + theorem.id);
}
const wrong = structuredClone(samples.get('pending-conviction')); wrong.result.ok.flow.bookingFee++;
assert.deepEqual(oracleResult(index, wrong), { found: true, agrees: false }, 'oracle full-result control');
wrong.action.convictCkpt.aid = 999;
assert.deepEqual(oracleResult(index, wrong), { found: false }, 'oracle unlisted-input control');
console.log(`${cells} complete story results; ${THEOREMS.length} observations exhibited; eight fabricated-conclusion and two oracle controls detected.`);
