#!/usr/bin/env node
/*
 * checkpoint-simulator-cli.mjs — Node adapter over the checkpoint backend.
 * Owns argv, stdout/stderr and exit status. Tree and machine semantics stay
 * in checkpoint-simulator-backend.mjs.
 *
 *   node simulator/checkpoint-simulator-cli.mjs --story 1 --to-end --json
 *   node simulator/checkpoint-simulator-cli.mjs --story 1 --fork twice --to-end --json
 */

import { writeSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import {
  playStory,
  selectPath,
  projectJson,
} from './checkpoint-simulator-backend.mjs';

function usage() {
  return 'usage: checkpoint-simulator-cli.mjs --story N [--fork ID] [--to-end] [--json]';
}

function parseArgs(args) {
  const out = { story: null, fork: null, toEnd: false, json: false };
  const rest = args.slice();
  while (rest.length) {
    const a = rest.shift();
    if (a === '--story') {
      if (!rest.length) throw new Error('--story needs a value\n' + usage());
      out.story = rest.shift();
    } else if (a === '--fork') {
      if (!rest.length) throw new Error('--fork needs a value\n' + usage());
      out.fork = rest.shift();
    } else if (a === '--to-end') out.toEnd = true;
    else if (a === '--json') out.json = true;
    else if (a === '--help' || a === '-h') throw new Error(usage());
    else throw new Error('unknown option ' + a + '\n' + usage());
  }
  if (out.story === null) throw new Error('--story is required\n' + usage());
  return out;
}

/**
 * Run the checkpoint simulator CLI.
 * @param {string[]} argumentsList
 * @param {function(string): void} [writeOut]
 * @param {function(string): void} [writeErr]
 * @returns {number}
 */
export function runSimulatorCli(argumentsList, writeOut, writeErr) {
  const out = writeOut || (s => { writeSync(1, s); });
  const err = writeErr || (s => { writeSync(2, s); });
  let opts;
  try { opts = parseArgs(argumentsList.slice()); }
  catch (e) { err(String(e.message || e) + '\n'); return 2; }
  try {
    let tree = playStory(opts.story);
    tree = selectPath(tree, opts.fork, opts.toEnd);
    const projection = projectJson(tree);
    out(JSON.stringify(projection) + '\n');
    return 0;
  } catch (e) {
    err(String(e && e.message ? e.message : e) + '\n');
    return 1;
  }
}

const here = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === here) {
  process.exit(runSimulatorCli(process.argv.slice(2)));
}
