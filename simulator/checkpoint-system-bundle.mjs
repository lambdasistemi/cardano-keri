/* Deterministic browser bundle of the actual shared system interpreter. */
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const read=f=>readFileSync(new URL(f,import.meta.url),'utf8');
const names={
  './checkpoint-simulator-core.mjs':'C','./registry-economic-core.mjs':'E',
  './checkpoint-conviction.mjs':'Judgment','./registry-wire.mjs':'W','./registry-simulator-core.mjs':'R',
  './checkpoint-system-core.mjs':'S','./checkpoint-system-properties.mjs':'P','./consumer-core.mjs':'U','./consumer-properties.mjs':'V',
};
function moduleScript(file, sources) {
  const raw=read(file);sources[file]=hash(raw);const exported=[];
  for(const m of raw.matchAll(/^export (?:function|class|const) ([A-Za-z_]\w*)/gm))exported.push(m[1]);
  for(const m of raw.matchAll(/^export (?:const )?\{([^}]+)\}/gm))exported.push(...m[1].split(',').map(x=>x.trim()));
  const body=raw.replace(/^import\s+(.+?)\s+from\s+['"]([^'"]+)['"];?\s*$/gm,(_,what,spec)=>{
    if(!names[spec])throw Error('unknown system dependency '+spec);
    return what.startsWith('* as ')?(what.slice(5)===names[spec]?'':`const ${what.slice(5)}=${names[spec]};`):`const ${what}=${names[spec]};`;
  }).replace(/^export \{[^}]+\};?\s*$/gm,'').replace(/^export /gm,'');
  if(/^import |^export /m.test(body)||!exported.length)throw Error('unsupported module '+file);
  return `const ${names['./'+file]}=(()=>{\n${body}\nreturn {${[...new Set(exported)].join(',')}};})();\n`;
}

export function evidenceBundle() {
  const sources = {};
  const body = ['registry-economic-core.mjs','checkpoint-conviction.mjs','registry-wire.mjs']
    .map(file => moduleScript(file, sources)).join('');
  return `/* Evidence source bindings: ${JSON.stringify(sources)} */
const [checkpointEconomics, checkpointEvidence, checkpointWire] = (() => {
${body}return [E, Judgment, W];
})();
`;
}
export function systemBundle() {
  const sources={};
  let script='(()=>{\n';
  const core=read('checkpoint-simulator-core.mjs');sources['checkpoint-simulator-core.mjs']=hash(core);
  const exports=core.match(/export \{([\s\S]*?)\};/)[1];
  script+=`const C={${exports}};\n`;
  script += 'const E=checkpointEconomics, Judgment=checkpointEvidence, W=checkpointWire;\n';
  for(const file of ['registry-simulator-core.mjs','checkpoint-system-core.mjs','checkpoint-system-properties.mjs','consumer-core.mjs','consumer-properties.mjs']) {
    script += moduleScript(file, sources);
  }
  const corpus=read('checkpoint-system-corpus.json');sources['checkpoint-system-corpus.json']=hash(corpus);
  const page=read('checkpoint-system-page.mjs');sources['checkpoint-system-page.mjs']=hash(page);
  const consumer=read('consumer-corpus.json'),consumerPage=read('consumer-page.mjs');
  sources['consumer-corpus.json']=hash(consumer);sources['consumer-page.mjs']=hash(consumerPage);
  script+=`const CONSUMER_CORPUS=${consumer.trim()};\n(()=>{${consumerPage}})();\n`;
  script+=`const SYSTEM_CORPUS=${corpus.trim()};\n${page}\n})();\n`;
  return `/* System source bindings: ${JSON.stringify(sources)} */\n${script}`;
}
