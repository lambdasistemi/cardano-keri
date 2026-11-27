#!/usr/bin/env node
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {newSystem,attemptSystem,checkSystemCorpus,validateCommand,replaySystem} from './checkpoint-system-core.mjs';
import {equal} from './registry-economic-core.mjs';
import {SYSTEM_THEOREMS,systemProperties} from './checkpoint-system-properties.mjs';
const corpus=JSON.parse(readFileSync(new URL('./checkpoint-system-corpus.json',import.meta.url)));
const report=checkSystemCorpus(corpus);assert.deepEqual(report,{cells:79,accepted:55,refused:24});
const first=corpus.traces[0].cells[0],initial=newSystem(first.params,first.env,corpus.traces[0].deployment);
const registered=attemptSystem(initial,first.command).session;
assert.equal(initial.state.aids.length,0,'mutated initial state');
assert.throws(()=>{registered.state.aids[0].origin.environment.convictions.push({});},TypeError);
assert.throws(()=>attemptSystem(structuredClone(registered),first.command),/must-start-at-init/);
for(const trace of corpus.traces)assert(equal(replaySystem(trace.cells[0].params,trace.cells[0].env,trace.deployment,trace.cells.map(c=>c.command)).state,trace.final));
const malformed=[
  x=>{x.register.context.extra=0;},
  x=>{x.register.context.environment.convictions[0].output.index=-1;},
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
const other=corpus.traces.find(t=>t.name==='same-context-other-request').cells.find(c=>c.name==='other-valid-fold-cannot-complete-this-request');
assert.equal(other.result.error,'checkpoint-receipt-mismatch');
const stored=corpus.traces.find(t=>t.name==='stored-origin-environment').cells.at(-1);assert.equal(stored.result.error,'keri-conviction-refused');
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
// A conviction whose commitment stays open, and a reveal before its window.
const convict=corpus.traces[0].cells.find(c=>c.name==='convict'),kept=structuredClone(convict.result);
kept.ok.state.commitments=convict.input.commitments;
assert.equal(systemProperties(convict,kept)['sys_conviction_consumes_commitment'].holds,false,'fabricated commitment burn check');
const reveal=corpus.traces.find(t=>t.name==='system-premises').cells.find(c=>c.name==='open-commitment');
const early=structuredClone(reveal);early.command={reveal:{marker:1,now:4}};early.input=reveal.result.ok.state;early.result={ok:{...reveal.result.ok,state:{...reveal.result.ok.state,commitments:[]}}};
assert.equal(systemProperties(early,early.result)['commitment_closes_in_or_after_window'].holds,false,'fabricated commitment window check');
// A step that changes the deployment, a top-up that burns an open commitment, a
// conviction accepted on a commitment of another deployment, and a conviction
// consuming a commitment in a system of another deployment.
const moved=structuredClone(rotated.result);moved.ok.state.deployment=rotated.input.deployment+1;
assert.equal(systemProperties(rotated,moved)['sys_step_keeps_deployment'].holds,false,'fabricated deployment change check');
const follows=corpus.traces.find(t=>t.name==='commitment-follows-the-key-state'),topUp=follows.cells.find(c=>c.name==='top-up');
assert.equal(systemProperties(topUp)['sys_commitment_survives_key_state_step'].exhibited,true,'the top-up runs with a commitment open');
const burnt=structuredClone(topUp.result);burnt.ok.state.commitments=[];
assert.equal(systemProperties(topUp,burnt)['sys_commitment_survives_key_state_step'].holds,false,'fabricated commitment survival check');
const elsewhere=corpus.traces.find(t=>t.name==='another-deployment'),foreign=elsewhere.cells.find(c=>c.name==='convict-with-the-other-deployment-commitment-refused');
assert.equal(foreign.result.error,'checkpoint-commitment-not-open');
assert.equal(systemProperties(foreign,elsewhere.cells.at(-1).result)['sys_conviction_refused_for_other_deployment'].holds,false,'fabricated other-deployment acceptance check');
const misplaced=structuredClone(convict);misplaced.input.deployment=convict.input.deployment+1;
assert.equal(systemProperties(misplaced)['sys_conviction_consumes_commitment'].holds,false,'fabricated commitment deployment check');
// The same commands in the other deployment: the first deployment's commitment convicts there no more.
const home=corpus.traces.find(t=>t.name==='another-deployment');
assert(replaySystem(home.cells[0].params,home.cells[0].env,corpus.traces[0].deployment,home.cells.slice(0,5).map(c=>c.command)).records.at(-1).result.ok,'the refused conviction is accepted in the commitment\'s own deployment');
const bookedFacts = 'registration_installs_booked_facts';
const differentBonds = {...first.params, B: first.params.B + 1};
const differentDeploymentTerms = newSystem(differentBonds, first.env, corpus.traces[0].deployment);
const bondResult = attemptSystem(differentDeploymentTerms, first.command).record.result;
assert.equal(bondResult.error, 'checkpoint-registration-facts-mismatch');
assert.equal(systemProperties({...first, params: differentBonds})[bookedFacts].holds, false);
for (const field of ['bornAt', 'refundTo', 'pool']) {
  const changed = structuredClone(first.result);
  changed.ok.state.aids[0].state.present.l[field]++;
  assert.equal(systemProperties(first, changed)[bookedFacts].holds, false, field);
}
const scopeTrace = corpus.traces.find(trace => trace.name === 'identity-bound-authorizations');
for (const cell of scopeTrace.cells.filter(cell => cell.name.startsWith('foreign-'))) {
  assert.equal(cell.result.error, 'checkpoint-local-refused', cell.name);
  const fabricated = {ok: {state: cell.input}};
  assert.equal(systemProperties(cell, fabricated).local_event_uses_own_authorization.holds, false, cell.name);
}
const writerControl = (change, commands) => {
  const env = structuredClone(first.env);
  change(env[0][1].writers);
  return replaySystem(first.params, env, corpus.traces[0].deployment, commands).records.at(-1).result;
};
const registrationOnly = [first.command];
const firstRotation = [first.command, rotated.command];
assert.equal(writerControl(w => w.inceptions[0].datum++, registrationOnly).error, 'checkpoint-inception-writer-mismatch');
assert.equal(writerControl(w => w.inceptions[0].signed.signatures = [], registrationOnly).error, 'checkpoint-inception-writer-mismatch');
assert.equal(writerControl(w => w.rotations = [], firstRotation).error, 'checkpoint-rotation-writer-mismatch');
assert.equal(writerControl(w => w.rotations[0].signed.signatures = [], firstRotation).error, 'checkpoint-rotation-writer-mismatch');
const observed = writerControl(() => {}, firstRotation).ok.state.aids[0];
assert.deepEqual(observed.writer.rotation.previous, observed.origin.inception);
assert.equal(observed.writer.rotation.event.event.sn, observed.state.present.l.sn);
// Each change describes an accepted last rotation. The conviction must still
// match that writer, including the witnesses accumulated along its history.
const journey = corpus.traces.find(trace => trace.name === 'retained-associated-completion');
const comparedPrefix = journey.cells.slice(0, journey.cells.findIndex(cell => cell.name === 'convict') + 1);
const writerChanges = {
  'current keys': event => event.keys.push(19),
  'current threshold': event => { event.threshold = {weighted: {clauses: [[{key: {weight: {numerator:1,denominator:1}}}]]}}; },
  'next keys': event => { event.nextKeys = [19]; },
  'next threshold': event => { event.nextThreshold = {count: {required: 2}}; },
  witnesses: event => { event.adds = [19]; },
  'witness threshold': event => { event.adds = [19]; event.witnessThreshold = 1; }
};
for (const [field, change] of Object.entries(writerChanges)) {
  const evidence = structuredClone(first.env);
  const signed = evidence[0][1].writers.rotations.at(-1).signed;
  change(signed.event);
  for (const signature of signed.signatures) signature.event = signed.event;
  if (signed.event.witnessThreshold > 0) signed.receipts = [{signer:19,event:signed.event,verified:true}];
  const replay = replaySystem(first.params, evidence, journey.deployment, comparedPrefix.map(cell => cell.command));
  assert(replay.records.slice(0, -1).every(record => record.result.ok), field + ': changed writer must be reachable');
  assert.equal(replay.records.at(-1).result.error, 'checkpoint-rotation-writer-mismatch', field);
}
console.log(JSON.stringify({...report,schemaControls:malformed.length+1,immutableOrigin:true,initOnlySessions:true,systemProperties:shown.size,fabricatedCheckerControls:21}));
