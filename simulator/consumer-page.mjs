/* Uses the same U consumer interpreter as the CLI and model replay. */
const el=id=>document.getElementById(id),put=(id,x)=>{el(id).textContent=x;};
let cursor=0,field=null,query=null;
const stories={
 'registered-juvenile':'The actual genesis and registration folds delivered Alice’s holding. The juvenility window still blocks payment.',
 'registered-mature':'Alice’s holding reaches its maturity boundary. Every identity and lifecycle clause now passes.',
 'frozen':'The output and exact representative remain held. The frozen checkpoint cannot authorize payment.',
 'rotate-keep-unpaid-frozen':'This unpaid rotation keeps the frozen state; newer keys alone do not restore the bond.',
 'rotate-deposit-unpaid':'The depositing rotation restores eligibility without changing the exact representative.',
 'poisoned':'Poison blocks consumer use while the output remains held.',
 'mature':'After its rotations the checkpoint is live and mature; the treasury can use it. There is no owner exit: it stays live until it is convicted.',
 'termination-pending':'Conviction makes the checkpoint ineligible. Its representative is still in pending custody.',
 'termination-booked':'The actual termination booking is associated with this origin. Booking alone does not retire it.',
 'retired-after-matching-fold':'The matching economic fold is consumed by system completion. The full identity fold burns the active asset. Re-registration and later local rotations are refused.'
};
function verdict(q){
 const r=U.consumerVerdict(q);
 put('consumer-result',r.error?'Unsupported interpretation: '+r.error:r.ok?'Treasury accepts this holding.':'Treasury refuses: '+r.verdict+'.');
 const list=el('consumer-summary');list.replaceChildren();
 for(const [label,value]of [['Network / release',r.clauses?`${r.clauses.network?'match':'mismatch'} / ${r.clauses.release?'match':'unresolved or mismatch'}`:'unsupported'],['Exact representative quantity',r.quantity??'unknown'],['Checkpoint eligibility',r.lifecycle?.verdict??'no decoded checkpoint']]){
  const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=label;dd.textContent=String(value);list.append(dt,dd);
 }
 return r;
}
function draw(){
 const frame=CONSUMER_CORPUS.journey[cursor],cell=field??frame.consumer;
 query=structuredClone(cell.query);
 put('consumer-position',`${cursor+1} / ${CONSUMER_CORPUS.journey.length} observations`);
 el('consumer-prev').disabled=cursor===0;el('consumer-next').disabled=cursor===CONSUMER_CORPUS.journey.length-1;
 put('consumer-story',field?'Candidate variation: '+field.name.replaceAll('-',' '):stories[frame.name]??'Authorized update: the asset and registration origin remain fixed while the checkpoint state changes.');
 const r=verdict(query);
 put('consumer-context',JSON.stringify({trusted:query.context,environment:query.environment,expectedAsset:r.expectedAsset},null,2));
 el('consumer-holding').value=JSON.stringify(query.holding,null,2);
 put('consumer-evidence',JSON.stringify(field?{query,result:cell.result}:{observation:frame,events:CONSUMER_CORPUS.events,genesis:CONSUMER_CORPUS.genesis,registrationFold:CONSUMER_CORPUS.registrationFold,terminationFold:CONSUMER_CORPUS.terminationFold,associationEvents:CONSUMER_CORPUS.associationEvents},null,2));
}
for(const cell of CONSUMER_CORPUS.fields){const option=document.createElement('option');option.value=cell.name;option.textContent=cell.name.replaceAll('-',' ');el('consumer-case').append(option);}
function seek(n){if(!Number.isInteger(n)||n<0||n>=CONSUMER_CORPUS.journey.length)throw Error('observation index');cursor=n;field=null;el('consumer-case').value='';draw();}
el('consumer-prev').onclick=()=>seek(cursor-1);el('consumer-next').onclick=()=>seek(cursor+1);el('consumer-reset').onclick=()=>seek(0);
el('consumer-case').onchange=()=>{field=CONSUMER_CORPUS.fields.find(c=>c.name===el('consumer-case').value)??null;draw();};
el('consumer-try').onclick=()=>{try{const holding=C.parseJsonExact(el('consumer-holding').value);verdict({...query,holding});}catch(e){put('consumer-result','Unsupported input: '+e.message);}};
window.CKC={corpus:CONSUMER_CORPUS,checkCorpus:U.checkConsumerCorpus,execute:U.executeConsumer,seek,
 show:open=>{el('consumer-player').open=open;},snapshot:()=>structuredClone({cursor,field:field?.name??null,query,result:U.executeConsumer(query)})};
put('consumer-properties',V.checkConsumerProperties(CONSUMER_CORPUS).map(r=>'✓ '+r.id+' '+r.theorem).join('\n'));
draw();if(new URLSearchParams(location.search).get('story')==='11')el('consumer-player').open=true;
