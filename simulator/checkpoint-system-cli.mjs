#!/usr/bin/env node
/* Command-line adapter for the same connected system histories as the page. */
import {readFileSync} from 'node:fs';
import {replaySystem} from './checkpoint-system-core.mjs';
import {parseJsonExact} from './checkpoint-simulator-core.mjs';
try {
  const args=process.argv.slice(2);
  if(args.length!==2||args[0]!=='--trace')throw Error('usage: checkpoint-system-cli.mjs --trace NAME');
  const corpus=parseJsonExact(readFileSync(new URL('./checkpoint-system-corpus.json',import.meta.url),'utf8'));
  const trace=corpus.traces.find(t=>t.name===args[1]);if(!trace)throw Error('unknown system trace');
  const first=trace.cells[0],result=replaySystem(first.params,first.env,trace.cells.map(c=>c.command));
  console.log(JSON.stringify({name:trace.name,state:result.state,records:result.records}));
}catch(error){console.error(error.message);process.exitCode=1;}
