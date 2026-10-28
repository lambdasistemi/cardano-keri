/* Deterministic browser bundle of the actual shared system interpreter. */
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const read=f=>readFileSync(new URL(f,import.meta.url),'utf8');
export function systemBundle() {
  const sources={},names={
    './checkpoint-simulator-core.mjs':'C','./registry-economic-core.mjs':'E',
    './registry-wire.mjs':'W','./registry-simulator-core.mjs':'R',
    './checkpoint-system-core.mjs':'S','./checkpoint-system-properties.mjs':'P',
  };
  let script='(()=>{\n';
  const core=read('checkpoint-simulator-core.mjs');sources['checkpoint-simulator-core.mjs']=hash(core);
  const exports=core.match(/export \{([\s\S]*?)\};/)[1];
  script+=`const C={${exports}};\n`;
  for(const file of ['registry-economic-core.mjs','registry-wire.mjs','registry-simulator-core.mjs','checkpoint-system-core.mjs','checkpoint-system-properties.mjs']) {
    const raw=read(file);sources[file]=hash(raw);const exported=[];
    for(const m of raw.matchAll(/^export (?:function|class|const) ([A-Za-z_]\w*)/gm))exported.push(m[1]);
    for(const m of raw.matchAll(/^export (?:const )?\{([^}]+)\}/gm))exported.push(...m[1].split(',').map(x=>x.trim()));
    const body=raw.replace(/^import\s+(.+?)\s+from\s+['"]([^'"]+)['"];?\s*$/gm,(_,what,spec)=>{
      if(!names[spec])throw Error('unknown system dependency '+spec);
      return what.startsWith('* as ')?(what.slice(5)===names[spec]?'':`const ${what.slice(5)}=${names[spec]};`):`const ${what}=${names[spec]};`;
    }).replace(/^export \{[^}]+\};?\s*$/gm,'').replace(/^export /gm,'');
    if(/^import |^export /m.test(body)||!exported.length)throw Error('unsupported module '+file);
    script+=`const ${names['./'+file]}=(()=>{\n${body}\nreturn {${[...new Set(exported)].join(',')}};})();\n`;
  }
  const corpus=read('checkpoint-system-corpus.json');sources['checkpoint-system-corpus.json']=hash(corpus);
  const page=read('checkpoint-system-page.mjs');sources['checkpoint-system-page.mjs']=hash(page);
  script+=`const SYSTEM_CORPUS=${corpus.trim()};\n${page}\n})();\n`;
  return `/* System source bindings: ${JSON.stringify(sources)} */\n${script}`;
}
