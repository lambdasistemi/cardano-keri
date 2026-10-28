#!/usr/bin/env node
/* Deterministic, dependency-free inlining of the shared modules and the existing
 * page template. The first stylesheet, player tree and element IDs remain the
 * common simulator contract. Fresh Lean generation is a separate trace gate. */
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { checkCorpus, checkScenario } from './registry-simulator-core.mjs';
const HERE = dirname(fileURLToPath(import.meta.url));
const option = (flag, fallback) => { const i = process.argv.indexOf(flag); return i < 0 ? join(HERE, fallback) : process.argv[i + 1]; };
const HTML = option('--html', 'registry-simulator.html'), DOCS = option('--docs', '../docs/simulator/registry/index.html');
const read = path => readFileSync(path, 'utf8');
const hash = value => createHash('sha256').update(value).digest('hex');
const sources = {};
function moduleBody(file, variable, dependencies, exports, override = null) {
  const path = override || join(HERE, file), raw = read(path);
  sources[file] = hash(raw);
  const body = raw.replace(/^import (.*?) from ['"]([^'"]+)['"];\n/gm, (_, names, specifier) => {
    const ref = dependencies[specifier]; if (!ref) throw Error('unknown inline dependency ' + specifier);
    return names.startsWith('* as ') ? (names.slice(5) === ref ? '' : `const ${names.slice(5)} = ${ref};\n`) : `const ${names} = ${ref};\n`;
  }).replace(/^export (?=(?:const|function|class)\b)/gm, '').replace(/^export \{[^}]+\};?\s*$/gm, '');
  if (/^import |^export /m.test(body)) throw Error('unsupported inline module syntax ' + file);
  return `/* @@MODULE:${variable}@@ sha256=${sources[file]} */\nconst ${variable} = (() => {\n${body}\nreturn { ${exports.join(', ')} };\n})();\n/* @@MODULE:${variable}:END@@ */\n`;
}
const modules = [
  ['registry-economic-core.mjs', 'E', {}, ['toInternal','toWire','canonical','equal','ModelRefusal','known','trieGet','fnv1a','rootOf','applicationName','readyTag','singularTag','ordinary','foldMembers','balanced','bookRegistration','bookTermination','foldAccepted','retractionAccepted','rejectionAccepted']],
  ['registry-wire.mjs', 'Wire', {'./registry-economic-core.mjs':'E'}, ['decodeInput','validateState','validateConfig','validateEnv','validateResult']],
  ['registry-simulator-core.mjs', 'Core', {'./registry-economic-core.mjs':'E','./registry-wire.mjs':'Wire'}, ['SCHEMA','VERSION','canonical','equal','stepFn','init','validateState','checkCell','checkCorpus','replayScenario','checkScenario','newSession','attempt','setEvidence'], option('--core','registry-simulator-core.mjs')],
  ['registry-fixtures.mjs', 'B', {'./registry-economic-core.mjs':'E','./registry-wire.mjs':'Wire'}, ['registrationAction','terminationAction','foldAction','retractionAction','rejectionAction']],
  ['registry-offers.mjs', 'Offers', {'./registry-fixtures.mjs':'B','./registry-economic-core.mjs':'E','./registry-wire.mjs':'Wire'}, ['NAMES','nameOf','CAST','ACTOR_ORDER','actionTag','dataOf','describeAction','offersFor']],
  ['registry-properties.mjs', 'Properties', {'./registry-economic-core.mjs':'E'}, ['THEOREMS','properties','corpusCells','oracleIndex','oracleResult']],
];
let script = "'use strict';\n" + modules.map(args => moduleBody(...args)).join('\n');
const dir = option('--scenarios','registry-simulator-scenarios');
const scenarios = readdirSync(dir).filter(f=>f.endsWith('.json')).sort().map(f=>JSON.parse(read(join(dir,f))));
if (scenarios.length !== 15 || scenarios.some((s,i)=>s.id!==i+1)) throw Error('incomplete story roster');
for (const sc of scenarios) { const r=checkScenario(sc); if(!r.ok) throw Error(r.problems.join('; ')); }
const rawCorpus = read(option('--corpus','registry-simulator-corpus.json')).trim(), corpus = JSON.parse(rawCorpus);
const report=checkCorpus(corpus);if(!report.ok)throw Error(report.reasons.join('; '));
script += `const SCENARIOS = ${JSON.stringify(scenarios)};\nconst REGISTRY_LEAN_TRACES_V3 = ${rawCorpus};\nconst REGISTRY_LEAN_TRACES_SHA256 = '${hash(rawCorpus)}';\n`;
const backend=read(option('--backend','registry-simulator-backend.mjs'));
const backendBody=backend.match(/\/\* @@BACKEND@@ \*\/\n([\s\S]*?)\/\* @@BACKEND:END@@ \*\//)?.[1];
if(!backendBody)throw Error('backend markers missing');
sources['registry-simulator-backend.mjs']=hash(backend);
script += `const Backend = (()=>{ const {newSession,attempt,setEvidence,checkScenario}=Core; const {equal,toInternal,toWire}=E;\n${backendBody}\nreturn { playStory,playLoadedScenario,treeAddChild,dryRun,submit,replaceEvidence,moveSlot,editEvidence,selectPath,projectJson };})();\n`;
const dsl=read(join(HERE,'scenario-dsl.mjs'));sources['scenario-dsl.mjs']=hash(dsl);
script += '/* @@DSL@@ */\n' + dsl.match(/\/\* @@DSL@@ \*\/\n([\s\S]*?)\/\* @@DSL:END@@ \*\//)[1] + '/* @@DSL:END@@ */\n';
script += '\nconst {canonical,equal,stepFn,attempt,newSession,checkScenario,checkCorpus}=Core;\nconst {NAMES,nameOf,CAST,ACTOR_ORDER,actionTag,dataOf,describeAction,offersFor}=Offers;\nconst {THEOREMS,properties,oracleIndex,oracleResult}=Properties;\nlet {playStory,playLoadedScenario,moveSlot}=Backend;\nconst {dryRun,submit,replaceEvidence,editEvidence}=Backend;\n';
const page=read(join(HERE,'registry-page.mjs'));sources['registry-page.mjs']=hash(page);script += page;
const template=read(option('--template','registry-page-template.html'));
sources['registry-page-template.html']=hash(template);
if(template.split('<!-- @@REGISTRY_SCRIPT@@ -->').length!==2)throw Error('template marker missing or repeated');
// Uploaded story text cannot close a script element in the generated page.
const rendered=template.replace('<!-- @@REGISTRY_SCRIPT@@ -->',`<script>\n/* Source bindings: ${JSON.stringify(sources)} */\n${script.replace(/<\/script/gi,'<\\/script')}\n</script>`);
if(process.argv.includes('--check')) {
  for(const target of [HTML,DOCS])if(!existsSync(target)||read(target)!==rendered)throw Error('stale generated page: '+target);
  console.log(`PASS: ${Object.keys(sources).length} bound sources; 15 stories; ${report.cells} complete corpus cells; byte-identical published page.`);
} else {
  for(const target of [HTML,DOCS]){mkdirSync(dirname(target),{recursive:true});writeFileSync(target,rendered);}
  console.log(`Generated Registry wire v3 page: ${report.cells} corpus cells.`);
}
