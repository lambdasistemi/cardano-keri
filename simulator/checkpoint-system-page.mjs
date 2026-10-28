/* Page controller: actual connected certificates, separate from local play.
 * C/E/S/P are the byte-bound shared modules supplied by the page build. */
const element=id=>document.getElementById(id);
const picker=element('system-picker'),body=element('system-state'),editor=element('system-command');
let traceIndex=0,cursor=0,current=null,last=null;
const selected=()=>SYSTEM_CORPUS.traces[traceIndex];
const text=(id,value)=>{element(id).textContent=value;};
function rebuild() {
  const trace=selected(),first=trace.cells[0];
  current=S.newSystem(first.params,first.env);last=null;
  for(const cell of trace.cells.slice(0,cursor)) {
    const attempt=S.attemptSystem(current,cell.command);
    if(!E.equal(attempt.record.result,cell.result))throw Error('system-page-oracle:'+cell.name);
    current=attempt.session;last={cell,result:attempt.record.result};
  }
  draw();
}
function draw() {
  const trace=selected(),cell=trace.cells[cursor];
  text('system-position',`${cursor} / ${trace.cells.length} events`);
  element('system-prev').disabled=cursor===0;element('system-next').disabled=!cell;
  body.textContent=current.state.aids.length?current.state.aids.map(row=>{
    const kind=C.stateKind(row.state),held=C.held(current.params,row.state);
    const key=kind==='present'?row.state.present.l:row.state[kind]?.h;
    return `AID ${row.aid} · ${C.STATE_WORDS[C.stateWord(current.params,row.state)]} · registry ${row.leaf}\n`+
      `Output ${C.hasOutput(row.state)?'retained':'absent'} · representative ${C.representativeHeld(row.state)} · key ${key?`epoch ${key.epoch}, sequence ${key.sn}`:'none'}\n`+
      `Bonds D=${held.dreg}, B=${held.b}; pool=${held.pool} · origin ${row.origin?'fixed by registration receipt':'none'} · pending request ${row.pending?JSON.stringify(row.pending.reference):'none'}`;
  }).join('\n\n'):'Sys.init: every AID is absent; no origin or pending association.';
  text('system-result',last?`${last.cell?.name??'Edited command'}: ${last.result.ok?'accepted':'refused: '+last.result.error}`:'Choose Next to deliver the actual registration receipt.');
  const rows=last?.cell?P.systemProperties(last.cell,last.result):{};
  text('system-properties',Object.entries(rows).filter(([,r])=>r.exhibited).map(([n,r])=>(r.holds?'✓ ':'✗ ')+n).join('\n')||'No sampled system property is claimed before an event or for an edited command.');
  text('system-observation',JSON.stringify({state:current.state,checkpointFlow:last?.result.ok?.checkpointFlow??null,registryFlow:last?.result.ok?.registryFlow??null},null,2));
  editor.value=cell?JSON.stringify(cell.command,null,2):'';
}
for(const [i,trace] of SYSTEM_CORPUS.traces.entries()) {
  const option=document.createElement('option');option.value=String(i);option.textContent=trace.name.replaceAll('-',' ');picker.append(option);
}
picker.addEventListener('change',()=>{traceIndex=Number(picker.value);cursor=0;rebuild();});
element('system-next').addEventListener('click',()=>{if(cursor<selected().cells.length){cursor++;rebuild();}});
element('system-prev').addEventListener('click',()=>{if(cursor){cursor--;rebuild();}});
element('system-reset').addEventListener('click',()=>{cursor=0;rebuild();});
element('system-try').addEventListener('click',()=>{
  try {const command=C.parseJsonExact(editor.value),out=S.attemptSystem(current,command);current=out.session;last={result:out.record.result};draw();}
  catch(error){text('system-result','Input unsupported: '+error.message);}
});
window.CKS={checkCorpus:S.checkSystemCorpus,corpus:SYSTEM_CORPUS,newSystem:S.newSystem,attempt:S.attemptSystem,
  select:index=>{if(!Number.isInteger(index)||index<0||index>=SYSTEM_CORPUS.traces.length)throw Error('trace index');traceIndex=index;picker.value=String(index);cursor=0;rebuild();},
  seek:index=>{if(!Number.isInteger(index)||index<0||index>selected().cells.length)throw Error('event index');cursor=index;rebuild();},
  snapshot:()=>structuredClone({trace:traceIndex,cursor,state:current.state,last}),properties:P.systemProperties};
rebuild();
