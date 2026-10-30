import fs from 'node:fs';import {createHash} from 'node:crypto';
import {CONSUMER_PROPERTIES} from './consumer-properties.mjs';
const sha=s=>createHash('sha256').update(s).digest('hex');
const root=new URL('../',import.meta.url);
export function consumerBindings(corpus){
 const files=['lean/lakefile.lean','lean/lake-manifest.json','lean/ConsumerTraceDriver.lean',
 ...fs.readdirSync(new URL('lean/CardanoKeri/',root)).filter(f=>f.startsWith('Consumer')&&f.endsWith('.lean')).map(f=>'lean/CardanoKeri/'+f),
 'lean/CardanoKeri/Checkpoint.lean','lean/CardanoKeri/CheckpointSystemEvidence.lean',
 'simulator/consumer-core.mjs','simulator/consumer-properties.mjs','simulator/consumer-cli.mjs','simulator/consumer-corpus.json'];
 const sources=Object.fromEntries(files.sort().map(f=>[f,sha(fs.readFileSync(new URL(f,root)))]));
 const stories=JSON.parse(fs.readFileSync(new URL('lean/retained-parking/theorem-stories.json',root))).rows.filter(r=>r.path.endsWith('/ConsumerGoals.lean'));
 const expected=CONSUMER_PROPERTIES.map(r=>'CardanoKeri.ConsumerIdentity.'+r.theorem);
 if(stories.length!==26||stories.some(r=>!expected.includes(r.declaration)||!['Given','when','then'].every(w=>r.sourceStory.toLowerCase().includes(w.toLowerCase()))))throw Error('consumer-theorem-story-census');
 return {version:1,singular:'d69ab005c3b710aeebf033d3c5cd08c56feb5643',sources,
  properties:CONSUMER_PROPERTIES.map(r=>({id:r.id,declaration:expected[CONSUMER_PROPERTIES.indexOf(r)],statementSha256:stories.find(s=>s.declaration.endsWith('.'+r.theorem)).statementSha256})),
  roster:{fields:corpus.fields.map(c=>c.name),journey:corpus.journey.map(c=>c.name),controls:corpus.checks.map(c=>c[0]),events:corpus.events.map(c=>c.name),association:corpus.associationEvents.map(c=>c.name)},
  limits:['Finite sampled properties; universal theorems are checked by Lean.','Fixture codec and hash, no Cardano byte vectors.','Current observer and two production implementation layers remain required.']};
}
