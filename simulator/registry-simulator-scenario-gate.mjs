#!/usr/bin/env node
/* Story, source, checker, CLI and actual page gates for Registry wire v3.
 * The separate trace gate performs fresh Lean oracle generation and cold-copy
 * replay. Source bindings never substitute for those behavioral comparisons. */
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,cpSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync,spawnSync} from 'node:child_process';
import {ROOT,HERE,sha256} from './registry-corpus.mjs';
import {equal} from './registry-simulator-core.mjs';
import {freshSurface} from './registry-model-surface.mjs';
import {loadBindings,checkSources,bindingControls} from './registry-source-checks.mjs';
import {checkPage} from './registry-page-checks.mjs';
import {checkGuardCoverage} from './registry-guard-coverage.mjs';
const run=file=>execFileSync(process.execPath,[join(HERE,file)],{cwd:ROOT,encoding:'utf8',maxBuffer:32*1024*1024}).trim();
function selftest(bindings,page){
  const count=bindingControls(bindings);
  assert.throws(()=>checkPage(page.replace('id="hist-next"','id="removed-next"'),false),/null|missing page id/,'missing player control');
  const handler="$('act-submit').addEventListener('click', submitPending);";
  assert(page.includes(handler),'submit mutation target');
  assert.throws(()=>checkPage(page.replace(handler,"$('act-submit').addEventListener('click', () => {});"),false),/refused bookRegistration/,'disabled submit control');
  const temp=mkdtempSync(join(process.env.TMPDIR||tmpdir(),'registry-scenario-v3-'));
  console.log('Preserved checker control: '+temp);
  for(const file of ['registry-properties.mjs','registry-property-checks.mjs','registry-economic-core.mjs','registry-wire.mjs','registry-simulator-core.mjs','registry-simulator-backend.mjs','registry-simulator-corpus.json'])cpSync(join(HERE,file),join(temp,file));
  cpSync(join(HERE,'registry-simulator-scenarios'),join(temp,'registry-simulator-scenarios'),{recursive:true});
  const path=join(temp,'registry-properties.mjs'),source=readFileSync(path,'utf8'),needle="conclusion() ? 'holds' : 'fails'";
  assert(source.includes(needle));writeFileSync(path,source.replace(needle,"'holds'"));
  const setup=spawnSync(process.execPath,['--check',path],{encoding:'utf8'});assert.equal(setup.status,0,setup.stderr);
  const control=spawnSync(process.execPath,[join(temp,'registry-property-checks.mjs')],{encoding:'utf8'});
  writeFileSync(join(temp,'checker.log'),control.stdout+control.stderr);writeFileSync(join(temp,'checker.exit'),String(control.status)+'\n');
  assert.equal(control.status,1,'lying property survived');assert(/fabricated conclusion not detected/.test(control.stderr),'checker failed for unrelated reason');
  console.log(`${count} source/story controls, two page-control failures and one compiled lying-property control detected.`);
}
try{
  const bindings=loadBindings(),surface=freshSurface();
  assert(equal(surface,bindings.surface),'compiled executable/source surface drift');
  assert.equal(sha256(readFileSync(join(HERE,'registry-model-surface.json'))),bindings.clauses.surfaceSha256,'clause model-surface digest');
  const sources=checkSources(bindings);
  execFileSync(process.env.LAKE_BIN||'lake',['-d',join(ROOT,'lean'),'build','CardanoKeri.RegistryAdapterFacts'],{encoding:'utf8',maxBuffer:32*1024*1024});
  const corpus=JSON.parse(readFileSync(join(HERE,'registry-simulator-corpus.json')));
  const coverage=JSON.parse(readFileSync(join(HERE,'registry-guard-coverage.json')));
  const guards=checkGuardCoverage(surface,corpus,coverage);
  if(process.argv.includes('--selftest')) {
    const bad=structuredClone(coverage);bad.rows.pop();
    assert.throws(()=>checkGuardCoverage(surface,corpus,bad),/coverage\/source\/corpus drift/,'missing refusal coverage row');
  }
  for(const file of ['registry-retained-checks.mjs','registry-property-checks.mjs'])console.log(run(file));
  console.log(execFileSync(process.execPath,[join(HERE,'registry-simulator-build.mjs'),'--check'],{encoding:'utf8'}).trim());
  const page=readFileSync(join(HERE,'registry-simulator.html'),'utf8');
  console.log(JSON.stringify(checkPage(page)));
  if(process.argv.includes('--selftest'))selftest(bindings,page);
  console.log(JSON.stringify({ok:true,...sources,...guards,compiledDeclarations:surface.compiled.length,sourceModules:surface.sources.length}));
}catch(error){console.error(error.stack);process.exitCode=1;}
