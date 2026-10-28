#!/usr/bin/env node
/* Fresh proof-producing Lean certificates, both actual consumers and corruption
 * controls. A build failure is setup failure, never a semantic mutation kill. */
import assert from 'node:assert/strict';
import{readFileSync,writeFileSync,mkdtempSync,cpSync}from'node:fs';
import{execFileSync}from'node:child_process';
import{join,resolve}from'node:path';
import{tmpdir}from'node:os';
import{createHash}from'node:crypto';
import{checkSystemCorpus}from'./checkpoint-system-core.mjs';
import{equal}from'./registry-economic-core.mjs';
import{checkSystemPage}from'./checkpoint-system-page-checks.mjs';
const root=resolve(import.meta.dirname,'..'),here=import.meta.dirname;
const sha=s=>createHash('sha256').update(s).digest('hex');
const sources=['lean/CardanoKeri/Checkpoint.lean','lean/CardanoKeri/CheckpointCertificate.lean','lean/CardanoKeri/CheckpointSystemEvidence.lean','lean/CardanoKeri/CheckpointSystemWire.lean','lean/CardanoKeri/CheckpointSystemFixtures.lean','lean/CardanoKeri/RegistryReplay.lean','lean/CardanoKeri/CheckpointReceiptCheck.lean','lean/CheckpointSystemDriver.lean',...['checkpoint-system-core.mjs','checkpoint-system-properties.mjs','checkpoint-system-page.mjs','checkpoint-system-bundle.mjs','checkpoint-system-cli.mjs','registry-simulator-core.mjs','registry-economic-core.mjs','registry-wire.mjs','checkpoint-simulator-core.mjs'].map(f=>'simulator/'+f)];
function fresh(base=root,build=true) {
  const run=args=>execFileSync(process.env.LAKE_BIN||'lake',args,{cwd:join(base,'lean'),encoding:'utf8',maxBuffer:128*1024*1024});
  if(build)run(['build','CardanoKeri.CheckpointSystemFixtures']);
  return JSON.parse(run(['env','lean','--run','CheckpointSystemDriver.lean']));
}
try {
  const corpus=fresh(),committed=JSON.parse(readFileSync(join(here,'checkpoint-system-corpus.json')));
  assert(equal(corpus,committed),'fresh/committed complete system corpus mismatch');
  const result=checkSystemCorpus(corpus),page=checkSystemPage(readFileSync(join(here,'checkpoint-simulator.html'),'utf8'));
  for(const trace of corpus.traces) {
    const out=JSON.parse(execFileSync(process.execPath,[join(here,'checkpoint-system-cli.mjs'),'--trace',trace.name],{encoding:'utf8',maxBuffer:64*1024*1024}));
    assert(equal(out.state,trace.final),'CLI complete final');
    assert(equal(out.records,trace.cells.map(c=>({input:c.input,command:c.command,result:c.result}))),'CLI complete records');
  }
  if(process.argv.includes('--selftest')) {
    const work=mkdtempSync(join(process.env.TMPDIR||tmpdir(),'checkpoint-system-trace-'));console.log('Control artifacts: '+work);
    for(const[name,change,expected]of[
      ['empty',c=>c.traces=[],/schema\/roster/],
      ['version',c=>c.version++,/schema\/roster/],
      ['missing-trace',c=>c.traces.pop(),/schema\/roster/],
      ['empty-trace',c=>c.traces[0].cells=[],/empty-system-trace/],
      ['disconnected',c=>c.traces[0].cells[1].input.aids=[],/system-disconnected/],
      ['false-success',c=>c.traces[1].cells[5].result=c.traces[1].cells[6].result,/system-result-mismatch/],
      ['false-context',c=>c.traces[0].cells[0].result.ok.state.aids[0].origin.environment.duplicity=[],/system-result-mismatch/],
      ['false-final',c=>c.traces[0].final.aids=[],/system-final-mismatch/],
    ]) {
      const bad=structuredClone(corpus);change(bad);writeFileSync(join(work,name+'.json'),JSON.stringify(bad));
      assert.throws(()=>checkSystemCorpus(bad),expected,name);console.log('REJECTED '+name);
    }
    const cold=join(work,'cold');cpSync(join(root,'lean'),join(cold,'lean'),{recursive:true,filter:p=>!p.split('/').includes('.lake')});
    let failure='';try{fresh(cold,false);}catch(e){failure=String(e.stdout??'')+String(e.stderr??'')+e.message;}
    writeFileSync(join(work,'cold-no-build.log'),failure);assert(/unknown module prefix|\.olean|does not exist|unknown package/.test(failure),'cold failure names missing compiled imports');
    const rebuilt=fresh(cold);writeFileSync(join(work,'cold-rebuilt.json'),JSON.stringify(rebuilt));assert(equal(rebuilt,corpus),'cold full system output');
    console.log('PASS cold rebuild equals fresh complete output');
  }
  console.log(JSON.stringify({...result,page,cliTraces:4,corpusSha256:sha(JSON.stringify(corpus)),sources:Object.fromEntries(sources.map(f=>[f,sha(readFileSync(join(root,f)))]))}));
}catch(e){console.error(e.stack);process.exitCode=1;}
