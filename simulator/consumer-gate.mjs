#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {checkConsumerCorpus,executeConsumer} from './consumer-core.mjs';
import {CONSUMER_PROPERTIES,checkConsumerProperties} from './consumer-properties.mjs';
import {consumerBindings} from './consumer-bindings.mjs';
import {equal} from './registry-economic-core.mjs';
const root=path.resolve(import.meta.dirname,'..'),lean=path.join(root,'lean');
const lake=process.env.LAKE_BIN||'lake';
const run=args=>execFileSync(lake,args,{cwd:lean,encoding:'utf8',maxBuffer:128*1024*1024});
run(['build','CardanoKeri.ConsumerControls']);
const raw=run(['env','lean','--run','ConsumerTraceDriver.lean']);
const corpus=JSON.parse(raw),result=checkConsumerCorpus(corpus);
const target=path.join(import.meta.dirname,'consumer-corpus.json');
if(process.argv.includes('--write'))fs.writeFileSync(target,raw);
else assert(equal(corpus,JSON.parse(fs.readFileSync(target))),'fresh consumer corpus drift');
const properties=checkConsumerProperties(corpus);
for(const row of CONSUMER_PROPERTIES){const forged=structuredClone(corpus);row.breakWitness(forged);assert.equal(row.holds(forged),false,'property falsifier '+row.id);}
const bindingPath=path.join(import.meta.dirname,'consumer-model-bindings.json'),bindings=consumerBindings(corpus);
if(process.argv.includes('--write'))fs.writeFileSync(bindingPath,JSON.stringify(bindings,null,2)+'\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(bindingPath)),bindings,'consumer source/story/roster binding drift');
const replay=JSON.parse(execFileSync(process.execPath,[path.join(import.meta.dirname,'consumer-cli.mjs'),'replay',target],{encoding:'utf8'}));assert.equal(replay.properties.length,26);
const anchor=corpus.fields.find(c=>c.name==='positive-anchor');assert(anchor?.result.ok,'missing positive anchor');
for(const [name,change]of [
  ['result',c=>c.fields[0].result.ok=!c.fields[0].result.ok],
  ['empty',c=>c.fields=[]],
  ['context',c=>c.fields[0].query.context.seed.tx++],
  ['precision',c=>c.fields[0].query.holding.assets[0][0].name=Number(c.fields[0].query.holding.assets[0][0].name)],
]){const bad=structuredClone(corpus);change(bad);assert.throws(()=>checkConsumerCorpus(bad),undefined,name);}
for(const queryCell of [anchor,...corpus.fields.filter(c=>['wrong-policy','quantity-two','genuine-rival-registry','unknown-release','table-missing-code'].includes(c.name))]){
const queryOut=execFileSync(lake,['env','lean','--run','ConsumerTraceDriver.lean','--query'],{cwd:lean,input:JSON.stringify(queryCell.query)+'\n',encoding:'utf8'});
assert(equal(JSON.parse(queryOut),executeConsumer(queryCell.query)),'generic query parity '+queryCell.name);
const cli=execFileSync(process.execPath,[path.join(import.meta.dirname,'consumer-cli.mjs'),'query'],{input:JSON.stringify(queryCell.query),encoding:'utf8'});assert(equal(JSON.parse(cli),JSON.parse(queryOut)),'CLI query parity');
}
if(process.argv.includes('--selftest')){
 const cold=fs.mkdtempSync(path.join(os.tmpdir(),'consumer-cold-'));fs.cpSync(lean,path.join(cold,'lean'),{recursive:true,filter:p=>!p.split(path.sep).includes('.lake')});
 let failed=false;try{execFileSync(lake,['env','lean','--run','ConsumerTraceDriver.lean'],{cwd:path.join(cold,'lean'),encoding:'utf8',stdio:'pipe'});}catch(e){failed=/unknown module prefix|olean|unknown package|does not exist/.test(String(e.stdout)+String(e.stderr));fs.writeFileSync(path.join(cold,'missing-imports.log'),String(e.stdout)+String(e.stderr));}assert(failed,'cold no-build must fail on imports');
 execFileSync(lake,['build','CardanoKeri.ConsumerControls'],{cwd:path.join(cold,'lean'),encoding:'utf8',maxBuffer:128*1024*1024});
 const rebuilt=execFileSync(lake,['env','lean','--run','ConsumerTraceDriver.lean'],{cwd:path.join(cold,'lean'),encoding:'utf8',maxBuffer:128*1024*1024});fs.writeFileSync(path.join(cold,'rebuilt.json'),rebuilt);assert(equal(JSON.parse(rebuilt),corpus),'cold complete consumer corpus');console.log('PASS cold consumer rebuild; receipts '+cold);
}
console.log(JSON.stringify({...result,corpusSha256:createHash('sha256').update(raw).digest('hex'),corruptionControls:4,properties:properties.length,propertyFalsifiers:26,genericQueries:6,cliReplay:true}));
