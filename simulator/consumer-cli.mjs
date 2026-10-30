#!/usr/bin/env node
/* Simulator adapter only. Does not implement the ckeri CLI or a ledger reader. */
import fs from 'node:fs';
import {executeConsumer,checkConsumerCorpus} from './consumer-core.mjs';
import {checkConsumerProperties} from './consumer-properties.mjs';
import {parseJsonExact} from './checkpoint-simulator-core.mjs';
const [mode,file]=process.argv.slice(2);
try{
 const input=parseJsonExact(fs.readFileSync(file??0,'utf8'));
 if(mode==='query')console.log(JSON.stringify(executeConsumer(input)));
 else if(mode==='replay')console.log(JSON.stringify({replay:checkConsumerCorpus(input),properties:checkConsumerProperties(input)}));
 else throw Error('usage: consumer-cli.mjs query|replay [FILE]');
}catch(e){console.error(e.message);process.exitCode=1;}
