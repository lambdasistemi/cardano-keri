#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const file = process.argv[2];
assert(file, 'usage: validate-identity-model-cast.mjs FILE.cast');
const [first,...rest] = readFileSync(file,'utf8').trimEnd().split('\n');
const header = JSON.parse(first);
assert.equal(header.version,2);
assert.equal(header.width,80);
assert.equal(header.height,24);
assert.equal(header.env?.SHELL,'/bin/bash');
const events=rest.map(JSON.parse);
assert(events.length>0 && events.every(x=>Array.isArray(x)&&x[1]==='o'&&typeof x[2]==='string'));
const output=events.map(x=>x[2]).join('');
assert(!/\/nix\/store|AssertionError|FailureResponse|ClientError|CallStack|HasCallStack/.test(output));
assert(Math.max(...events.map(x=>x[2].length))<400);
for(const phrase of ['MODEL ACCEPTED: AID 11 active','EXPECTED REFUSAL: already-registered',
  'MODEL ACCEPTED: sn=1','MODEL ACCEPTED: frozen=true','pool=1',
  'They do not prove CK to Singular mapping or devnet behavior.'])
  assert(output.includes(phrase),`cast is missing ${phrase}`);
console.log(JSON.stringify({cast:file,events:events.length,width:header.width,height:header.height}));
