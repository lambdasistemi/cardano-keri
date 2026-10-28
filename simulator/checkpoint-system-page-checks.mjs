#!/usr/bin/env node
import assert from 'node:assert/strict';
import{readFileSync}from'node:fs';
import{createWindow}from'./checkpoint-simulator-minidom.mjs';
import{equal}from'./registry-economic-core.mjs';
export function checkSystemPage(html) {
  const w=createWindow(html),d=w.document,$=id=>d.getElementById(id);
  assert.equal(w.__errors.length,0,w.__errors.map(e=>e.stack).join('\n'));
  assert(w.CKS,'associated system controller missing');
  let cells=0;
  const pick=i=>{$('system-picker').value=String(i);$('system-picker').dispatchEvent(new w.Event('change'));};
  for(const[i,trace]of w.CKS.corpus.traces.entries()) {
    pick(i);assert(equal(w.CKS.snapshot().state,trace.initial));
    for(const cell of trace.cells) {
      assert(!$('system-next').disabled);$('system-next').click();
      const got=w.CKS.snapshot();assert(equal(got.last.result,cell.result),`${trace.name}/${cell.name} full result`);
      assert(equal(got.state,cell.result.ok?.state??cell.input),'displayed complete state');
      assert(!/\[object Object\]|undefined/.test($('system-state').textContent),'unrendered state');
      if(cell.result.ok?.state.aids.some(r=>r.state.terminationPending))assert(/Pending custody/.test($('system-state').textContent));
      cells++;
    }
    assert($('system-next').disabled);$('system-prev').click();assert.equal(w.CKS.snapshot().cursor,trace.cells.length-1);
    $('system-next').click();assert(equal(w.CKS.snapshot().state,trace.final));
  }
  pick(0);$('system-try').click();assert.equal(w.CKS.snapshot().state.aids.length,1,'try actual registration');
  $('system-command').value='{"local":{"aid":11,"now":0,"action":{"register":{"refund":1,"pool0":0}}}}';
  $('system-try').click();assert(/refused: checkpoint-registration-receipt-required/.test($('system-result').textContent));
  const before=w.CKS.snapshot().state;$('system-command').value='{"bad":1}';$('system-try').click();
  assert(/^Input unsupported:/.test($('system-result').textContent));assert(equal(w.CKS.snapshot().state,before));
  $('system-reset').click();assert.equal(w.CKS.snapshot().state.aids.length,0);
  assert.equal(w.__errors.length,0,w.__errors.map(e=>e.stack).join('\n'));
  return {traces:4,cells,controls:'select/next/previous/reset/edited-command/schema-error',fullObservations:true};
}
if(process.argv[1]===new URL(import.meta.url).pathname){try{console.log(JSON.stringify(checkSystemPage(readFileSync(new URL('./checkpoint-simulator.html',import.meta.url),'utf8'))));}catch(e){console.error(e.stack);process.exitCode=1;}}
