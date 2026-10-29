#!/usr/bin/env node
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';import {equal} from './registry-economic-core.mjs';
const out=process.argv[2];if(!out)throw Error('receipt directory required');fs.mkdirSync(out,{recursive:true});
const source=fs.readFileSync(new URL('./consumer-core.mjs',import.meta.url),'utf8');
const corpus=JSON.parse(fs.readFileSync(new URL('./consumer-corpus.json',import.meta.url)));
const cells=[...corpus.fields,...corpus.journey.map(f=>f.consumer)],sha=s=>createHash('sha256').update(s).digest('hex');
const mutations=[
 ['network','network:e.network===c.network','network:true','wrong-network'],
 ['release','release:equal(e.release,c.release)','release:true','unknown-release'],
 ...['applicationPolicy','applicationCredential','stateProgram','statePolicy'].map(f=>['release-'+f,'release:equal(e.release,c.release)',`release:e.release!==null&&equal({...e.release,${f}:c.release.${f}},c.release)`,'release-'+({applicationPolicy:'application-policy',applicationCredential:'credential',stateProgram:'state-program',statePolicy:'state-policy'}[f])]),
 ['credential','credential:o.credential===c.release.applicationCredential','credential:true','holding-credential'],
 ['policy','equal(a,expectedAsset)','a.name===expectedAsset.name','wrong-policy'],
 ['name','equal(a,expectedAsset)','a.policy===expectedAsset.policy','wrong-name'],
 ['quantity-zero','quantity:quantity===1n','quantity:quantity<=1n','quantity-zero'],
 ['quantity-two','quantity:quantity===1n','quantity:quantity>0n','quantity-two'],
 ['first-entry',"o.assets.filter(([a])=>equal(a,expectedAsset)).reduce((n,[,v])=>n+v,0n)","o.assets.find(([a])=>equal(a,expectedAsset))?.[1]??0n",'duplicate-entries'],
 ['aid','aid:decoded?.aid===c.aid','aid:true','datum-other-aid'],
 ['datum-category','const decoded=o.datum?.application?','const decoded=true?','datum-root'],
 ['frozen','consumable(toWire(q.params),toWire(q.now),toWire(decoded.state))',"consumable(toWire(q.params),toWire(q.now),toWire(decoded.state?.present?{present:{l:{...decoded.state.present.l,frozen:false}}}:decoded.state))",'frozen'],
 ['poisoned','consumable(toWire(q.params),toWire(q.now),toWire(decoded.state))',"consumable(toWire(q.params),toWire(q.now),toWire(decoded.state?.present?{present:{l:{...decoded.state.present.l,poisoned:false}}}:decoded.state))",'poisoned'],
 ['age','consumable(toWire(q.params),toWire(q.now),toWire(decoded.state))',"consumable({...toWire(q.params),W:0},toWire(q.now),toWire(decoded.state))",'maturity-minus-one'],
 ['lifecycle','const ok=!failure&&lifecycle.ok','const ok=!failure','parked'],
 ['pending','const ok=!failure&&lifecycle.ok','const ok=!failure','termination-booked'],
 ['terminal','const ok=!failure&&lifecycle.ok','const ok=!failure','terminal-datum'],
 ['seed-transaction','statePreimage={state:{seed:c.seed}}','statePreimage={state:{seed:{...c.seed,tx:0n}}}','positive-anchor'],
 ['seed-index','statePreimage={state:{seed:c.seed}}','statePreimage={state:{seed:{...c.seed,index:1n}}}','positive-anchor'],
];
const results=[];
for(const [id,needle,replacement,target]of [['baseline',null,null,'positive-anchor'],...mutations]){
 const dir=path.resolve(out,id);fs.mkdirSync(dir,{recursive:true});
 for(const name of fs.readdirSync(import.meta.dirname))if(name.endsWith('.mjs')&&name!=='consumer-core.mjs')fs.symlinkSync(path.join(import.meta.dirname,name),path.join(dir,name));
 let code=source;if(needle){assert.equal(code.split(needle).length,2,'unique mutation '+id);code=code.replace(needle,replacement);}
 if(id==='datum-category')code=code.replace('raw===o.datum.application.data','raw===711n');
 fs.writeFileSync(path.join(dir,'consumer-core.mjs'),code);const cell=cells.find(c=>c.name===target);assert(cell,target);fs.writeFileSync(path.join(dir,'query.json'),JSON.stringify(cell.query));
 const command=['--input-type=module','-e',"import fs from 'node:fs';import {executeConsumer} from './consumer-core.mjs';console.log(JSON.stringify(executeConsumer(JSON.parse(fs.readFileSync('query.json')))));"],r=spawnSync(process.execPath,command,{cwd:dir,encoding:'utf8'});
 fs.writeFileSync(path.join(dir,'output.log'),(r.stdout??'')+(r.stderr??''));fs.writeFileSync(path.join(dir,'command.json'),JSON.stringify({argv:[process.execPath,...command],exit:r.status},null,2));assert.equal(r.status,0,'SETUP-FAILED '+id);
 const actual=JSON.parse(r.stdout),killed=!equal(actual,cell.result);if(id==='baseline')assert(!killed);else assert(killed,'SURVIVED '+id);
 const result={id,target,sourceSha256:sha(code),expected:cell.result,actual,result:id==='baseline'?'BASELINE-PASS':'KILLED'};results.push(result);fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(result));
}
