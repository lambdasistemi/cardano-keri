#!/usr/bin/env node
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {newSystem,attemptSystem,checkSystemCorpus,validateCommand,replaySystem} from './checkpoint-system-core.mjs';
import {equal} from './registry-economic-core.mjs';
import {SYSTEM_THEOREMS,systemProperties} from './checkpoint-system-properties.mjs';
const corpus=JSON.parse(readFileSync(new URL('./checkpoint-system-corpus.json',import.meta.url)));
const report=checkSystemCorpus(corpus);assert.deepEqual(report,{cells:33,accepted:22,refused:11});
const first=corpus.traces[0].cells[0],initial=newSystem(first.params,first.env);
const registered=attemptSystem(initial,first.command).session;
assert.equal(initial.state.aids.length,0,'mutated initial state');
assert.throws(()=>{registered.state.aids[0].origin.environment.duplicity.push([99,99]);},TypeError);
assert.throws(()=>attemptSystem(structuredClone(registered),first.command),/must-start-at-init/);
for(const trace of corpus.traces)assert(equal(replaySystem(trace.cells[0].params,trace.cells[0].env,trace.cells.map(c=>c.command)).state,trace.final));
const malformed=[
  x=>{x.register.context.extra=0;},
  x=>{x.register.context.environment.duplicity=[[11,-1]];},
  x=>{x.register.context.parameters.Mr=5;},
  x=>{x.register.certificate.transaction.extra=true;},
  x=>{x.register.certificate.history[0].bookRegistration.booking.request.contents.lovelace=0.5;},
  x=>{x.register.now=Number.MAX_SAFE_INTEGER+1;},
  x=>{x.register.aid='11';},
  x=>{x.extra={};},
];
for(const mutate of malformed){const command=structuredClone(first.command);mutate(command);assert.throws(()=>validateCommand(command),/invalid|unsupported|noncanonical/);}
const injected=structuredClone(corpus.traces[0].cells.find(c=>c.name==='complete').command);
injected.complete.environment=first.command.register.context.environment;
assert.throws(()=>validateCommand(injected),/invalid-system-wire/,'completion cannot replace stored context');
const other=corpus.traces[1].cells.find(c=>c.name==='other-valid-fold-cannot-complete-this-request');
assert.equal(other.result.error,'checkpoint-receipt-mismatch');
const stored=corpus.traces[2].cells.at(-1);assert.equal(stored.result.error,'keri-conviction-refused');
const shown=new Set();
for(const trace of corpus.traces)for(const cell of trace.cells)for(const[name,row]of Object.entries(systemProperties(cell))){assert(row.holds,name+': '+cell.name);if(row.exhibited)shown.add(name);}
assert.deepEqual([...shown].sort(),SYSTEM_THEOREMS.slice().sort(),'system property premise census');
const rotated=corpus.traces[0].cells.find(c=>c.name==='rotate'),bad=structuredClone(rotated.result);
bad.ok.state.aids[0].leaf='absent';
for(const name of ['T8_leaf_agrees_with_state','T8_edges_leave_the_leaf','T8_present_implies_registered','T8_leaf_states','T8_utxo_iff_active','T8_leaf_never_absent_again','T8_sysstep_partition'])assert.equal(systemProperties(rotated,bad)[name].holds,false,'fabricated system conclusion '+name);
// A deliberately inconsistent input is a checker control only, not a Reach
// witness or a semantic mutation of the model.
const wrongOrigin=structuredClone(first);wrongOrigin.input.aids=[{...first.result.ok.state.aids[0],leaf:'active'}];
assert.equal(systemProperties(wrongOrigin)['T8_mint_once'].holds,false,'fabricated mint premise check');
console.log(JSON.stringify({...report,schemaControls:malformed.length+1,immutableOrigin:true,initOnlySessions:true,systemProperties:shown.size,fabricatedCheckerControls:8}));
