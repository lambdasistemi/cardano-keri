/* Compiled dependency census and exact source spans for the Registry adapter.
 * Generated helpers stay in the compiled census. Handwritten declarations
 * additionally carry source text; decision sites are not inferred from names. */
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT,sha256} from './registry-corpus.mjs';
export function freshSurface(root=ROOT) {
  const lake=process.env.LAKE_BIN||'lake',opts={cwd:join(root,'lean'),encoding:'utf8',maxBuffer:32*1024*1024};
  execFileSync(lake,['build','CardanoKeri.Registry'],opts);
  const graph=JSON.parse(execFileSync(lake,['env','lean','RegistrySurfaceDriver.lean'],opts));
  if(graph.root!=='CardanoKeri.Registry.stepFn'||!graph.declarations.length)throw Error('empty compiled surface');
  graph.declarations.sort((a,b)=>a.declaration.localeCompare(b.declaration));
  const modules=[...new Set(graph.declarations.map(d=>d.module))].sort();
  const sources=[],definitions=[],decisions=[];
  const names=new Set(graph.declarations.map(d=>d.declaration));
  for(const module of modules){
    const path=(module.startsWith('Singular.')?'lean/.lake/packages/singular/lean/':'lean/')+module.replaceAll('.','/')+'.lean';
    const text=readFileSync(join(root,path),'utf8'),lines=text.split('\n');
    sources.push({module,path,sha256:sha256(text)});
    const stack=[];
    for(let i=0;i<lines.length;i++){
      const ns=lines[i].match(/^namespace (\S+)/);if(ns){stack.push(ns[1]);continue;}
      if(/^end(?:\s|$)/.test(lines[i])){stack.pop();continue;}
      const decl=lines[i].match(/^(?:private )?(?:noncomputable )?(?:def|abbrev)\s+([^\s({:]+)/);if(!decl)continue;
      const name=[...stack,decl[1]].join('.');if(!names.has(name))continue;
      let j=i+1;while(j<lines.length&&!/^(?:private )?(?:noncomputable )?(?:def|abbrev|theorem|structure|inductive|instance|namespace|end)\b|^\/[-*!]/.test(lines[j]))j++;
      const source=lines.slice(i,j).join('\n').trim();definitions.push({declaration:name,module,line:i+1,sha256:sha256(source),source});
      const code=source.replace(/\/\-[\s\S]*?\-\//g,'').replace(/--[^\n]*/g,'');
      let occurrence=0;
      for(const match of code.matchAll(/(?:throw|return|some|\.error)\s+"([^"\n]+)"|refundRefusal[^"\n]*(?:\n[^"\n]*)?"([^"\n]+)"/g))decisions.push({declaration:name,occurrence:occurrence++,reason:match[1]||match[2]});
    }
  }
  return {version:1,root:graph.root,compiled:graph.declarations,sources,definitions,decisions};
}
