/* Exact source/story bindings. Fresh compiled enumeration is performed by the
 * scenario gate; this checker also rejects missing rows and changed clauses. */
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT,HERE,sha256} from './registry-corpus.mjs';
import {canonical,equal,checkScenario} from './registry-simulator-core.mjs';
export function checkSources({surface,clauses,markdown,stories,root=ROOT}) {
  assert.equal(surface.root,'CardanoKeri.Registry.stepFn');
  assert(surface.compiled.length>0&&surface.sources.length>0&&surface.definitions.length>0&&surface.decisions.length>0,'empty source census');
  for(const source of surface.sources)assert.equal(sha256(readFileSync(join(root,source.path))),source.sha256,'source drift '+source.module);
  const declarations=new Map(surface.definitions.map(d=>[d.declaration,d]));
  assert.equal(declarations.size,surface.definitions.length,'duplicate source declaration');
  for(const d of surface.definitions){assert.equal(sha256(d.source),d.sha256,'declaration digest '+d.declaration);assert(surface.compiled.some(c=>c.declaration===d.declaration&&c.module===d.module),'not compiled '+d.declaration);}
  assert.equal(clauses.version,3);assert.equal(clauses.clauses.length,15,'missing story clause');
  assert.equal(sha256(markdown),clauses.storiesMarkdownSha256,'changed reader clauses');
  assert.deepEqual(clauses.clauses.map(c=>c.story),Array.from({length:15},(_,i)=>i+1),'clause roster');
  let cells=0;
  for(const clause of clauses.clauses){
    const sc=stories.find(s=>s.scenario.id===clause.story);assert(sc,'missing scenario');
    assert.equal(sha256(sc.raw),clause.scenarioSha256,'scenario source drift '+clause.story);
    for(const key of ['given','when','then'])assert(typeof clause[key]==='string'&&clause[key].length>20&&markdown.includes(clause[key]),'missing complete '+key+' clause');
    const checked=checkScenario(sc.scenario);assert(checked.ok,checked.problems.join('; '));
    const targets=[];for(const[branch,steps]of [['trunk',sc.scenario.steps],...sc.scenario.forks.map(f=>[f.id,f.steps])])for(const[index,step]of steps.entries())targets.push({branch,index,action:Object.keys(step.action)[0],expectationSha256:sha256(JSON.stringify(step.expect.result))});
    assert(equal(targets,clause.cells),'missing, forged or reordered story result binding');cells+=targets.length;
    const actions=[...new Set(targets.map(c=>c.action))];
    assert.deepEqual(clause.anchors.map(a=>a.declaration),actions.map(a=>'CardanoKeri.Registry.'+a),'action source coverage');
    for(const anchor of clause.anchors)assert.equal(anchor.sha256,declarations.get(anchor.declaration)?.sha256,'action declaration drift');
  }
  assert.equal(cells,84,'whole story/fork census');
  return {clauses:clauses.clauses.length,cells,definitions:declarations.size,decisionSites:surface.decisions.length};
}
export function loadBindings() {
  return {surface:JSON.parse(readFileSync(join(HERE,'registry-model-surface.json'))),clauses:JSON.parse(readFileSync(join(HERE,'registry-simulator-clauses.json'))),markdown:readFileSync(join(HERE,'REGISTRY-STORIES.md'),'utf8'),stories:readdirSync(join(HERE,'registry-simulator-scenarios')).filter(f=>f.endsWith('.json')).sort().map(file=>{const raw=readFileSync(join(HERE,'registry-simulator-scenarios',file),'utf8');return{file,raw,scenario:JSON.parse(raw)};})};
}
export function bindingControls(bindings) {
  const controls=[
    ['missing story clause',x=>x.clauses.clauses.pop(),/missing story clause/],
    ['lost fork cell',x=>x.clauses.clauses[14].cells.pop(),/story result binding/],
    ['missing action anchor',x=>x.clauses.clauses[8].anchors.pop(),/action source coverage/],
    ['changed source clause',x=>{x.clauses.clauses[8].then='Parking burns the retained token.';},/complete then clause/],
    ['edited declaration digest',x=>{x.surface.definitions[0].sha256='0'.repeat(64);},/declaration digest/],
    ['empty source inventory',x=>{x.surface.compiled=[];},/empty source census/],
  ];
  for(const[name,mutate,reason]of controls){const bad=structuredClone(bindings);mutate(bad);assert.throws(()=>checkSources(bad),reason,name);}
  return controls.length;
}
