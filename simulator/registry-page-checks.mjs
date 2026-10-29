#!/usr/bin/env node
/* Actual inline production code driven through the retained player controls. */
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createWindow} from './checkpoint-simulator-minidom.mjs';
import {playStory} from './registry-simulator-backend.mjs';
import {equal,canonical} from './registry-economic-core.mjs';
import {checkScenario} from './registry-simulator-core.mjs';
import {parseScenarioDsl} from './scenario-dsl.mjs';
const read=name=>readFileSync(new URL(name,import.meta.url),'utf8');
export function checkPage(html, exhaustive=true) {
  const w=createWindow(html,{search:'?selftest=1'}),d=w.document,$=id=>d.getElementById(id),RS=w.RS;
  assert.equal(w.__errors.length,0,w.__errors.map(e=>e.stack).join('\n'));
  assert(w.__selftest?.ok,'page selftest: '+JSON.stringify(w.__selftest));
  for(const id of read('./registry-page-ids.txt').trim().split('\n'))assert($(id),'missing page id '+id);
  assert.equal(html.match(/<style>([\s\S]*?)<\/style>/)[1].trim(),read('./page-template/page.css').trim(),'shared stylesheet changed');
  const pick=id=>{$('story-picker').value=String(id);$('story-picker').dispatchEvent(new w.Event('change'));};
  pick(1);assert.equal(RS.app.story.id,1);assert(d.querySelector('#tree .node.punch .star'),'punchline');
  assert(d.querySelector('#next-moves .mover.spot .act.glow'),'story spotlight');
  assert(d.querySelector('#next-moves .mover.folded'),'folded cast');$('unfold').click();assert(!d.querySelector('#next-moves .mover.folded'));
  if(exhaustive)for(let id=1;id<=15;id++) {
    pick(id);const expected=playStory(id);
    assert.equal($('tree').querySelectorAll('.node').length,expected.nodes.length,'node census');
    for(const node of expected.nodes){d.querySelector(`#tree .node[data-node="${node.id}"]`).dispatchEvent(new w.Event('click'));
      assert.equal(RS.app.cursor,node.id,'tree click');assert(equal(RS.cur().state,node.session.state),`story ${id}/${node.id} complete state`);
      assert(!d.querySelector('#ledger .broken'),`story ${id}/${node.id} broken property`);
      if(node.record)assert(d.querySelector('#ledger [data-id="T7"].lit'),`story ${id}/${node.id} no exact oracle match`);
    }
  }
  pick(15);const fork=d.querySelector('#branches [data-fork="mixed-custody"]');assert(fork,'mixed custody continuation');fork.click();$('hist-last').click();
  assert.equal(RS.cur().state.terminations.length,0);assert.equal(RS.cur().state.trie.filter(([,l])=>l.known?.s==='terminal').length,2);
  const exported=RS.exportCurrentBranchDsl(),sc=parseScenarioDsl(exported).scenario;assert(checkScenario(sc).ok,'export full-result replay');
  RS.loadScenarioDsl(exported,'exported');assert(!/invalid|mismatch/.test($('dsl-diag').textContent),'export reload');
  $('btn-reset').click();assert.equal(RS.app.nodes.length,1);
  const ev=(actor,kind)=>{const btn=d.querySelector(`#next-moves .ev-quick[data-actor="${actor}"][data-ev="${kind}"]`);assert(btn,`evidence ${actor}/${kind}`);btn.click();};
  const move=(actor,kind)=>{const btn=d.querySelector(`#next-moves .act[data-actor="${actor}"][data-kind="${kind}"]`);assert(btn,`move ${actor}/${kind}`);btn.click();assert(!$('act-submit').disabled,'disabled submit');$('act-submit').click();assert(RS.node(RS.app.cursor).record?.result.ok,`refused ${kind}`);};
  ev('alice','inception');move('alice','bookRegistration');move('hal','fold');
  ev('alice','closeAuth');move('alice','park');assert.equal(RS.cur().state.carriers[0].st,'parked');
  const parked=canonical(RS.cur().state);$('slot-plusw').click();$('slot-plus1').click();assert.equal(canonical(RS.cur().state),parked,'proposal clock changed state');
  assert(/Only a convicted carrier/.test($('refused-list').textContent),'parked booking refusal explained');
  ev('alice','rotationFrom');move('alice','revive');assert.equal(RS.cur().state.carriers[0].k,2);
  ev('cora','duplicity');move('cora','convictCkpt');move('sam','bookTermination');
  assert.equal(RS.cur().state.terminations.length,1);move('hal','fold');assert.equal(RS.cur().state.trie[0][1].known.s,'terminal');
  assert.equal(RS.cur().state.carriers.length,0);assert.equal(RS.cur().state.terminations.length,0);
  pick('c:register');assert(! $('challenge').hidden);assert(!RS.app.challenge.won());assert(/recipient/.test($('challenge').textContent));
  const cb=d.querySelector('input[data-ev="closeAuth"][data-aid="11"][data-k="99"]');assert(cb);cb.checked=true;cb.dispatchEvent(new w.Event('change'));
  move('mallory','park');assert(RS.app.challenge.won(),'recipient premise challenge');
  $('hist-first').click();assert.equal(RS.app.cursor,0);$('hist-last').click();$('hist-prev').click();$('hist-next').click();
  $('scrub').value='0';$('scrub').dispatchEvent(new w.Event('input'));assert.equal(RS.app.cursor,0);
  const theme=d.documentElement.dataset.theme;$('btn-theme').click();assert.notEqual(d.documentElement.dataset.theme,theme);
  assert($('scene').querySelectorAll('[data-obj]').length>=10,'scene entities');
  assert.equal(w.__errors.length,0,w.__errors.map(e=>e.stack).join('\n'));
  return {stories:15,fullJourney:'register/fold/park/revive/convict/book/fold',dsl:'export/reload',controls:'tree/evidence/proposal-clock/challenge/theme'};
}
if(process.argv[1]===new URL(import.meta.url).pathname){try{console.log(JSON.stringify(checkPage(read('./registry-simulator.html'))));}catch(e){console.error(e.stack);process.exitCode=1;}}
