/* Runtime subject for two implementation mutations. The unchanged commands
 * come from actual Lean certificate execution, including accepted prefixes. */
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {newSystem,attemptSystem} from './checkpoint-system-core.mjs';
import {equal} from './registry-economic-core.mjs';
const corpus=JSON.parse(readFileSync(new URL('./checkpoint-system-corpus.json',import.meta.url)));
const names={
  'own-request':'other-valid-fold-cannot-complete-this-request',
  'stored-context':'booking-history-cannot-replace-stored-environment',
};
const name=names[process.argv[2]];assert(name,'unknown subject');
const trace=corpus.traces.find(t=>t.cells.some(c=>c.name===name));
let current=newSystem(trace.cells[0].params,trace.cells[0].env);
for(const cell of trace.cells) {
  assert(equal(current.state,cell.input),'prefix disconnected');
  const next=attemptSystem(current,cell.command);
  if(cell.name===name){assert.equal(!!next.record.result.ok,false,'SEMANTIC-REFUSAL:'+process.argv[2]);assert(equal(next.record.result,cell.result));console.log('PASS '+process.argv[2]);break;}
  assert(equal(next.record.result,cell.result),'prefix changed');current=next.session;
}
