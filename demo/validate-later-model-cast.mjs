#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const [file,page] = process.argv.slice(2);
assert(file && ['d07','d09'].includes(page));
const [first,...rest] = readFileSync(file,'utf8').trimEnd().split('\n');
const header=JSON.parse(first), events=rest.map(JSON.parse);
assert.equal(header.version,2); assert.equal(header.width,80); assert.equal(header.height,24);
assert.equal(header.env?.SHELL,'/bin/bash'); assert(events.length>0);
assert(events.every(x=>Array.isArray(x)&&x[1]==='o'&&typeof x[2]==='string'));
const output=events.map(x=>x[2]).join('');
assert(!/\/nix\/store|AssertionError|FailureResponse|ClientError|CallStack|HasCallStack/.test(output));
assert(Math.max(...events.map(x=>x[2].length))<400);
for(const phrase of page==='d07' ?
  ['MODEL: parked epoch=1 sn=1','EXPECTED REFUSAL: intent-not-authorized',
    'MODEL: convicted','EXPECTED REFUSAL: no-duplicity-proof','No ledger close or conviction is claimed.'] :
  ['MODEL: 15 scenario files, 104 action steps','MODEL story 15:',
    'GATE RED:','This cast establishes fixture replay only.'])
  assert(output.includes(phrase),`cast is missing ${phrase}`);
console.log(JSON.stringify({cast:file,events:events.length,width:header.width,height:header.height}));
