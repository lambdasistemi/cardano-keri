#!/usr/bin/env node
// Bind every theorem in the lifecycle/transport revision to its source story
// and complete formal Given/Then. Compilation checks the actual propositions;
// this census detects dropped stories and stale statement/source identities.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'../..');
const hash=x=>createHash('sha256').update(x).digest('hex');
const dir=path.join(root,'lean/CardanoKeri');
const files=fs.readdirSync(dir).filter(f=>/^(AbandonmentExamples|Attestation|Application|Checkpoint|InceptionPrefix|Registry|Consumer|Reader|ConcreteConvictionGoals|Samaritan).*\.lean$/.test(f)).sort();
function separator(text, wanted) {
  let depth = 0;
  let letBinding = false;
  // A let in the result type has its own assignment before the proof begins.
  for (const token of text.matchAll(/"(?:\\.|[^"\\])*"|--[^\n]*|\b(?:let|have)\b|:=|[(){}\[\]:]/g)) {
    const value = token[0];
    if ('({['.includes(value)) depth++;
    else if (')}]'.includes(value)) depth--;
    else if (depth === 0) {
      if (value === 'let' || value === 'have') letBinding = true;
      else if (value === ':=' && letBinding) letBinding = false;
      else if (value === wanted) return token.index;
    }
  }
  throw Error('missing top-level ' + wanted);
}
export function collect(){
  const sources={},rows=[];
  for(const file of files){
    const relative='lean/CardanoKeri/'+file,text=fs.readFileSync(path.join(root,relative),'utf8');sources[relative]=hash(text);
    const stack=[];
    const events=[...text.matchAll(/^(?:(namespace|section)\s*([^\n]*)|(mutual)$|end(?:\s+[^\n]*)?|(?:@\[[^\]\n]+\][ \t]+)*(private )?theorem\s+([^\s({:]+))/gm)];
    for(const ev of events){
      if(ev[1]){stack.push({kind:ev[1],name:ev[2].trim()});continue;}
      if(ev[3]){stack.push({kind:'mutual',name:''});continue;}
      if(ev[0].startsWith('end')){stack.pop();continue;}
      const tail=text.slice(ev.index),assignment=separator(tail,':='),statement=tail.slice(0,assignment).trim();
      const rest=statement.slice(ev[0].length),colon=separator(rest,':');
      const before=text.slice(0,ev.index).trimEnd();let narrative='';
      if(before.endsWith('-/')){const open=before.lastIndexOf('/--');if(open>=0&&before.indexOf('-/',open)===before.length-2)narrative=before.slice(open+3,-2).trim();}
      const declaration=[...stack.filter(s=>s.kind==='namespace').map(s=>s.name),ev[5]].join('.');
      const given=rest.slice(0,colon).trim(),then=rest.slice(colon+1).trim();
      rows.push({declaration,path:relative,line:text.slice(0,ev.index).split('\n').length,
        statement,statementSha256:hash(statement),sourceStory:narrative,
        story:{given:given||'No additional local parameters; use the definitions in this module.',
          when: file==='InceptionPrefix.lean'?'Check the signed inception and its prefix in the indexed booking, or read its kind from the delivered datum.':file.startsWith('Application')?'Evaluate the KERI application judgement on the application-held observation, booking, spend or approval named by this theorem.':file.startsWith('Consumer')?'Evaluate the exact consumer holding, naming premises or bounded joint bridge named by this theorem.':file.startsWith('Reader')?'Read the answer the reader gives on the evidence, or the chain state the evidence is about, named by this theorem.':file.startsWith('Registry')?'Observe the Registry transition, projection or custody relation named by this theorem.':file==='Samaritan.lean'?'Observe the booking split or accepted fold accounting named by this theorem.':'Observe the local Checkpoint or associated system relation named by this theorem.',
          then},storySha256:hash(JSON.stringify({narrative,given,then}))});
    }
  }
  assert(rows.length>200,'empty or truncated theorem census');assert.equal(new Set(rows.map(r=>r.declaration)).size,rows.length,'duplicate declaration');
  return {version:1,scope:'Current lifecycle and transport theorem source stories with complete formal binders and conclusions; no production correspondence claim',singular:'d69ab005c3b710aeebf033d3c5cd08c56feb5643',sources,rows};
}
const target=path.join(import.meta.dirname,'theorem-stories.json'),current=collect();
if(process.argv.includes('--write'))fs.writeFileSync(target,JSON.stringify(current,null,2)+'\n');
else {assert.deepEqual(JSON.parse(fs.readFileSync(target)),current,'theorem story/source/statement drift');
  const resultType = 'let tip := read checkpoint\n  let event := read tip\n  valid event = true';
  assert.equal(separator(resultType + ' := by decide', ':='), resultType.length + 1);
  const missing=structuredClone(current);missing.rows.pop();assert.notDeepEqual(missing,current);
  const altered=structuredClone(current);altered.rows[0].story.then='True';assert.notDeepEqual(altered,current);
}
console.log(JSON.stringify({theorems:current.rows.length,sourceModules:Object.keys(current.sources).length,sourceNarratives:current.rows.filter(r=>r.sourceStory).length,completeFormalContracts:current.rows.length}));
