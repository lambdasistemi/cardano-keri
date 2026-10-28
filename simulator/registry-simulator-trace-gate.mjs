#!/usr/bin/env node
/* Fresh complete Lean results, committed/embedded equality and actual production
 * replay. --selftest also checks corrupt corpora, a live guard mutation and a
 * cold source copy. Compile/setup failures never count as semantic controls. */
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,cpSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import {freshCorpus,ROOT,HERE,sha256,sourceBindings} from './registry-corpus.mjs';
import {checkCorpus,equal} from './registry-simulator-core.mjs';
import {properties} from './registry-properties.mjs';
import {createWindow} from './checkpoint-simulator-minidom.mjs';
export function embedded(html) {
  const m=html.match(/const REGISTRY_LEAN_TRACES_V3 = ([\s\S]*?);\nconst REGISTRY_LEAN_TRACES_SHA256 = '([a-f0-9]{64})';/);
  assert(m,'missing embedded corpus');assert.equal(sha256(m[1]),m[2],'embedded digest');
  return JSON.parse(m[1]);
}
function verify(fresh,committed,page) {
  assert(equal(fresh,committed),'fresh/committed complete corpus mismatch');
  const emb=embedded(page);assert(equal(fresh,emb),'fresh/embedded complete corpus mismatch');
  const report=checkCorpus(fresh);assert(report.ok,report.reasons.join('; '));
  for(const trace of fresh.traces)for(const cell of trace.cells)for(const [id,p] of Object.entries(properties(cell)))assert.notEqual(p.v,'fails',`${trace.name}/${cell.name}: ${id}`);
  const w=createWindow(page);assert.equal(w.__errors.length,0,w.__errors.map(e=>e.stack).join('\n'));
  const fromPage=w.RS.checkCorpus(emb);assert(fromPage.ok,fromPage.reasons.join('; '));
  return report;
}
async function selftest(fresh,page) {
  const temp=mkdtempSync(join(process.env.TMPDIR||tmpdir(),'registry-trace-v3-'));
  console.log('Preserved control directory: '+temp);
  const reject=(name,mutate,pattern)=>{
    const bad=structuredClone(fresh);mutate(bad);const report=checkCorpus(bad);
    writeFileSync(join(temp,name+'.json'),JSON.stringify(bad));
    assert(!report.ok&&report.reasons.some(r=>pattern.test(r)),`${name}: wrong result ${JSON.stringify(report)}`);
    console.log('REJECTED '+name+': '+report.reasons.find(r=>pattern.test(r)));
  };
  reject('empty',c=>{c.traces=[];c.grid=[];c.stories=[];},/trace roster/);
  reject('wrong-version',c=>{c.version=99;},/schema/);
  reject('missing-forks',c=>{c.stories.forEach(s=>{s.forks=[];});},/fork census/);
  reject('truncated-boundaries',c=>c.boundaries.pop(),/boundary census/);
  reject('disconnected-history',c=>{c.traces[0].cells[1].input.gen++;},/disconnected input/);
  const forged=structuredClone(fresh);forged.boundaries.find(c=>c.result.ok).result.ok.state.gen++;
  const raw=JSON.stringify(forged),forgedPage=page.replace(/const REGISTRY_LEAN_TRACES_V3 = [\s\S]*?;\nconst REGISTRY_LEAN_TRACES_SHA256 = '[a-f0-9]{64}';/,`const REGISTRY_LEAN_TRACES_V3 = ${raw};\nconst REGISTRY_LEAN_TRACES_SHA256 = '${sha256(raw)}';`);
  assert.throws(()=>verify(forged,forged,forgedPage),/result mismatch/,'coherent hashes must not hide a false result');
  writeFileSync(join(temp,'coherent-forged-page.html'),forgedPage);console.log('REJECTED coherent false result by replay');
  assert.throws(()=>embedded(page.replace(/REGISTRY_LEAN_TRACES_SHA256 = '[a-f0-9]{64}'/,"REGISTRY_LEAN_TRACES_SHA256 = '"+'0'.repeat(64)+"'")),/embedded digest/);
  const mutant=join(temp,'mutant');mkdirSync(mutant);
  for(const file of ['registry-simulator-core.mjs','registry-economic-core.mjs','registry-wire.mjs'])cpSync(join(HERE,file),join(mutant,file));
  const path=join(mutant,'registry-simulator-core.mjs'),source=readFileSync(path,'utf8'),needle="require(a.expectedGen === s.gen, 'keri-generation-mismatch');";
  assert(source.includes(needle),'guard mutation target');writeFileSync(path,source.replace(needle,''));
  const core=await import(pathToFileURL(path)); // Failure here is setup, not a kill.
  const stale=fresh.boundaries.find(c=>c.result.error==='keri-generation-mismatch')||fresh.traces.flatMap(t=>t.cells).find(c=>c.result.error==='keri-generation-mismatch');
  assert(stale,'no stale generation witness');const result=core.stepFn(stale.params,stale.env,stale.action,stale.input);
  assert(result.ok,'guard mutation must admit the exact otherwise-valid stale fold');
  assert(!core.checkCorpus(fresh).ok,'guard mutation survived corpus');console.log('REJECTED generation guard removal: stale fold accepted by mutant');
  const cold=join(temp,'cold');
  cpSync(join(ROOT,'lean'),join(cold,'lean'),{recursive:true,filter:src=>!src.split('/').includes('.lake')});
  cpSync(join(HERE,'registry-simulator-scenarios'),join(cold,'simulator','registry-simulator-scenarios'),{recursive:true});
  let failure='';try{freshCorpus(cold,false);}catch(e){failure=String(e.stdout??'')+String(e.stderr??'')+e.message;}
  writeFileSync(join(temp,'cold-without-build.log'),failure);
  assert(/unknown module prefix|does not exist|\.olean|unknown package/.test(failure),'cold failure must name missing compiled imports');
  const rebuilt=freshCorpus(cold,true);writeFileSync(join(temp,'cold-rebuilt.json'),JSON.stringify(rebuilt));
  assert(equal(rebuilt,fresh),'cold complete output mismatch');console.log('PASS cold rebuild equals fresh output; no-build attempt rejected for missing imports');
}
if(process.argv[1]===new URL(import.meta.url).pathname){
 try{
  const fresh=freshCorpus(),committed=JSON.parse(readFileSync(join(HERE,'registry-simulator-corpus.json'))),page=readFileSync(join(HERE,'registry-simulator.html'),'utf8');
  const report=verify(fresh,committed,page);
  if(process.argv.includes('--selftest'))await selftest(fresh,page);
  console.log(JSON.stringify({ok:true,...report,sha256:sha256(JSON.stringify(fresh)),sources:sourceBindings()}));
 }catch(e){console.error(e.stack);process.exitCode=1;}
}
