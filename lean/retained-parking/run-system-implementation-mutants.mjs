/* These are JavaScript implementation mutations, not Lean model mutations or
 * proof-interface controls. Each mutant must parse and execute the same valid
 * prefix, then admit the precisely bound otherwise-refused operation. */
import {readFileSync,writeFileSync,mkdirSync,existsSync,copyFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'../..'),campaign=process.argv[2];
if(!campaign||existsSync(campaign))throw Error('fresh campaign directory required');mkdirSync(campaign,{recursive:true});
const sha=value=>createHash('sha256').update(value).digest('hex');
const source=readFileSync(join(root,'simulator/checkpoint-system-core.mjs'),'utf8');
const cases=[
  {id:'own-request',before:'&&contains(receipt.transaction.transaction.inputs,association.reference)',after:''},
  {id:'stored-context',before:'const context=contextOf(row.origin),before=registryReplay(context,row.origin.registered,a.history);',after:'const context={...contextOf(row.origin),environment:{...row.origin.environment,duplicity:[[11,2]]}},before=registryReplay(context,row.origin.registered,a.history);'},
];
const files=['checkpoint-system-core.mjs','checkpoint-system-mutation-subject.mjs','checkpoint-system-corpus.json','checkpoint-simulator-core.mjs','registry-simulator-core.mjs','registry-economic-core.mjs','registry-wire.mjs'];
const results=[];
for(const test of cases)for(const baseline of [true,false]) {
  const id=(baseline?'baseline-':'')+test.id,dir=join(campaign,id);mkdirSync(dir);
  for(const file of files)copyFileSync(join(root,'simulator',file),join(dir,file));
  if(source.split(test.before).length!==2)throw Error('unique target required');
  const candidate=baseline?source:source.replace(test.before,test.after);writeFileSync(join(dir,files[0]),candidate);
  writeFileSync(join(dir,'bindings.json'),JSON.stringify(Object.fromEntries(files.map(f=>[f,sha(readFileSync(join(dir,f)))])),null,2));
  function run(label,args) {
    writeFileSync(join(dir,label+'.command.json'),JSON.stringify({command:process.execPath,args,cwd:dir}));
    const r=spawnSync(process.execPath,args,{cwd:dir,encoding:'utf8',timeout:120000});
    writeFileSync(join(dir,label+'.log'),r.stdout+r.stderr);writeFileSync(join(dir,label+'.exit'),String(r.status)+'\n');return r;
  }
  const syntax=run('compile',['--check',files[0]]);if(syntax.status!==0)throw Error(id+': setup failed');
  const result=run('execute',['checkpoint-system-mutation-subject.mjs',test.id]);
  if(baseline?result.status!==0:result.status!==1||!result.stderr.includes('SEMANTIC-REFUSAL:'+test.id))throw Error(id+': wrong outcome');
  results.push({id,verdict:baseline?'PASS':'KILLED',evidence:'implementation-runtime',sourceSha256:sha(candidate)});
  writeFileSync(join(campaign,'results.json'),JSON.stringify(results,null,2));console.log(id+': '+results.at(-1).verdict);
}
