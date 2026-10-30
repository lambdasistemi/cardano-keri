#!/usr/bin/env node
/* Mutate an isolated executable definition; compilation failures are setup
 * failures. Each target is an actual previously emitted consumer query. */
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {equal} from './registry-economic-core.mjs';
const root=path.resolve(import.meta.dirname,'..'),leanRoot=path.join(root,'lean');
const out=process.argv[2];if(!out)throw Error('receipt directory required');fs.mkdirSync(out,{recursive:true});
const lean=process.env.LEAN_BIN||'lean',sha=s=>createHash('sha256').update(s).digest('hex');
const corpus=JSON.parse(fs.readFileSync(path.join(import.meta.dirname,'consumer-corpus.json')));
const cells=[...corpus.fields,...corpus.journey.map(f=>f.consumer)];
const identity=fs.readFileSync(path.join(leanRoot,'CardanoKeri/ConsumerIdentity.lean'),'utf8');
const wire=fs.readFileSync(path.join(leanRoot,'CardanoKeri/ConsumerWire.lean'),'utf8');
const checkpoint=fs.readFileSync(path.join(leanRoot,'CardanoKeri/Checkpoint.lean'),'utf8');
const mutations=[
 ['network','authenticatedContextB','e.network == c.network','true','wrong-network'],
 ['release','authenticatedContextB','e.release == some c.release','true','unknown-release'],
 ...['applicationPolicy','applicationCredential','stateProgram','statePolicy'].map(field=>['release-'+field,'authenticatedContextB','e.release == some c.release',`(e.release.map (fun r => { r with ${field} := c.release.${field} })) == some c.release`,'release-'+({applicationPolicy:'application-policy',applicationCredential:'credential',stateProgram:'state-program',statePolicy:'state-policy'}[field])]),
 ['credential','consumableHoldingB','o.credential == c.release.applicationCredential','true','holding-credential'],
 ['quantity-zero','consumableHoldingB','AH.quantity o (representativeAsset i c) == 1','decide (AH.quantity o (representativeAsset i c) ≤ 1)','quantity-zero'],
 ['quantity-two','consumableHoldingB','AH.quantity o (representativeAsset i c) == 1','decide (AH.quantity o (representativeAsset i c) > 0)','quantity-two'],
 ['first-entry','consumableHoldingB','AH.quantity o (representativeAsset i c)','((o.assets.find? (fun entry => entry.1 == representativeAsset i c)).map (·.2)).getD 0','duplicate-entries'],
 ['policy','consumableHoldingB','AH.quantity o (representativeAsset i c)','((o.assets.filter (fun entry => entry.1.name == (representativeAsset i c).name)).map (·.2)).sum','wrong-policy'],
 ['name','consumableHoldingB','AH.quantity o (representativeAsset i c)','((o.assets.filter (fun entry => entry.1.policy == (representativeAsset i c).policy)).map (·.2)).sum','wrong-name'],
 ['datum-aid','consumableHoldingB','d.aid == c.aid','true','datum-other-aid'],
 ['datum-category','decoded','| _ => none','| _ => i.decode c.release 711','datum-root'],
 ['decoder','consumableHoldingB','| none => false','| none => true','datum-malformed'],
 ['frozen','consumableStateB','l.frozen == false','true','frozen','checkpoint'],
 ['poisoned','consumableStateB','l.poisoned == false','true','poisoned','checkpoint'],
 ['juvenility','consumableStateB','decide (l.bornAt + p.W ≤ now)','true','maturity-minus-one','checkpoint'],
 ['maturity-boundary','consumableStateB','decide (l.bornAt + p.W ≤ now)','decide (l.bornAt + p.W < now)','positive-anchor','checkpoint'],
 ['pending','consumableStateB','| .terminationPending _ => false','| .terminationPending _ => true','termination-booked','checkpoint'],
 ['terminal','consumableStateB','| .absent | .convicted => false','| .absent | .convicted => true','terminal-datum','checkpoint'],
 ['key','representativeAsset','(i.keyOf c.aid)','(i.keyOf (c.aid + 1))','positive-anchor'],
 ['registry','representativeAsset','(registryAsset i c)','{ policy := c.release.statePolicy, name := 0 }','positive-anchor'],
 ['seed-transaction','registryAsset','c.seed','{ c.seed with tx := 0 }','positive-anchor'],
 ['seed-index','registryAsset','c.seed','{ c.seed with index := c.seed.index + 1 }','positive-anchor'],
];
const probe=`import CardanoKeri.ConsumerWire
open Lean CardanoKeri.ConsumerIdentity
def main : IO Unit := do
  let input ← (← IO.getStdin).getLine
  let result := do
    let q : Wire.Query ← Lean.fromJson? (← Json.parse input)
    Wire.execute q
  IO.println (match result with
    | .ok verdict => Json.mkObj [("ok", toJson verdict)]
    | .error reason => Json.mkObj [("error", toJson reason)]).compress
`;
const base=path.join(out,'compiled-baseline');fs.cpSync(path.join(leanRoot,'.lake/build/lib/lean'),base,{recursive:true});
const results=[];
for(const [id,site,needle,replacement,target,owner]of [['baseline',null,null,null,'positive-anchor'],...mutations]){
 const dir=path.join(out,id);fs.mkdirSync(path.join(dir,'CardanoKeri'),{recursive:true});
 const replaced=new Set(['CardanoKeri/ConsumerIdentity.olean','CardanoKeri/ConsumerWire.olean',...(owner==='checkpoint'?['CardanoKeri/Checkpoint.olean']:[])]);
 for(const rel of fs.readdirSync(base,{recursive:true})){const src=path.join(base,rel);if(!fs.statSync(src).isFile()||!rel.endsWith('.olean')||replaced.has(rel))continue;const dest=path.join(dir,rel);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.symlinkSync(src,dest);}
 let source=owner==='checkpoint'?checkpoint:identity;
 if(site){const start=source.indexOf('def '+site+' '),next=source.indexOf('\ndef ',start+1);assert(start>=0,id+':site');const section=source.slice(start,next<0?source.length:next);assert.equal(section.split(needle).length,2,id+':unique-site');source=source.slice(0,start)+section.replace(needle,replacement)+source.slice(next<0?source.length:next);}
 fs.writeFileSync(path.join(dir,'CardanoKeri/ConsumerIdentity.lean'),owner==='checkpoint'?identity:source);
 fs.writeFileSync(path.join(dir,'CardanoKeri/ConsumerWire.lean'),wire);
 if(owner==='checkpoint')fs.writeFileSync(path.join(dir,'CardanoKeri/Checkpoint.lean'),source);
 fs.writeFileSync(path.join(dir,'Probe.lean'),probe);
 const env={...process.env,LEAN_PATH:[dir,path.join(leanRoot,'.lake/packages/singular/.lake/build/lib/lean'),path.join(leanRoot,'.lake/build/lib/lean')].join(':')};
 const commands=[];
 const call=(args,input)=>{const start=new Date().toISOString(),r=spawnSync(lean,args,{cwd:dir,env,input,encoding:'utf8',maxBuffer:32*1024*1024});const log=(r.stdout??'')+(r.stderr??'');const logName='command-'+commands.length+'.log';fs.writeFileSync(path.join(dir,logName),log);commands.push({argv:[lean,...args],start,end:new Date().toISOString(),exit:r.status,log:logName,sha256:sha(log)});fs.writeFileSync(path.join(dir,'commands.json'),JSON.stringify(commands,null,2));return r;};
 for(const module of [...(owner==='checkpoint'?['Checkpoint']:[]),'ConsumerIdentity','ConsumerWire']){const r=call(['-o','CardanoKeri/'+module+'.olean','CardanoKeri/'+module+'.lean']);if(r.status!==0)throw Error('SETUP-FAILED '+id+'/'+module);}
 const cell=cells.find(c=>c.name===target);assert(cell,id+':target');
 const r=call(['--run','Probe.lean'],JSON.stringify(cell.query)+'\n');if(r.status!==0)throw Error('SETUP-FAILED '+id+'/probe');
 const actual=JSON.parse(r.stdout),killed=!equal(actual,cell.result);if(id==='baseline')assert(!killed,'baseline');else assert(killed,'SURVIVED '+id);
 const result={id,site,target,sourceSha256:sha(source),expected:cell.result,actual,result:id==='baseline'?'BASELINE-PASS':'KILLED'};results.push(result);fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(result));
}
