#!/usr/bin/env node
/*
 * scenario-dsl-cli.mjs — runnable compiler adapter. Grammar rules live in
 * scenario-dsl.mjs; this file owns argv, stdin/stdout, output files and
 * file:line refusals. It does not write checked-in JSON unless --output
 * names a path.
 *
 *   node simulator/scenario-dsl-cli.mjs to-json --family checkpoint FILE.dsl
 *   node simulator/scenario-dsl-cli.mjs from-json --family checkpoint FILE.json
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import {
  GRAMMAR_VERSION,
  assertGrammarVersion,
  parseScenarioDsl,
  scenarioToDsl,
  scenarioFromDsl,
  ScenarioDslError,
} from './scenario-dsl.mjs';

assertGrammarVersion('1');

const FAMILIES = new Set(['checkpoint', 'registry']);

function usage() {
  return [
    'usage: scenario-dsl-cli.mjs to-json --family checkpoint|registry [--output PATH] [FILE|-]',
    '       scenario-dsl-cli.mjs from-json --family checkpoint|registry [--output PATH] [FILE|-]',
  ].join('\n');
}

function parseArgs(args) {
  const out = { cmd: null, family: null, output: null, input: null };
  const rest = args.slice();
  if (!rest.length) throw new Error(usage());
  out.cmd = rest.shift();
  if (out.cmd !== 'to-json' && out.cmd !== 'from-json') throw new Error(usage());
  while (rest.length) {
    const a = rest.shift();
    if (a === '--family') {
      if (!rest.length) throw new Error('--family needs a value');
      out.family = rest.shift();
    } else if (a === '--output' || a === '-o') {
      if (!rest.length) throw new Error('--output needs a path');
      out.output = rest.shift();
    } else if (a === '--help' || a === '-h') {
      throw new Error(usage());
    } else if (a.startsWith('-') && a !== '-') {
      throw new Error('unknown option ' + a + '\n' + usage());
    } else {
      if (out.input !== null) throw new Error('unexpected extra argument ' + a);
      out.input = a;
    }
  }
  if (!FAMILIES.has(out.family)) throw new Error('--family must be checkpoint or registry\n' + usage());
  return out;
}

function readInput(input, stdinText) {
  if (input === null || input === '-') {
    if (stdinText !== null && stdinText !== undefined) return { text: String(stdinText), name: 'stdin' };
    return { text: readFileSync(0, 'utf8'), name: 'stdin' };
  }
  return { text: readFileSync(input, 'utf8'), name: input };
}

export function runScenarioDslCli(argumentsList, stdinText, io) {
  const writeOut = (io && io.writeOut) || (s => { process.stdout.write(s); });
  const writeErr = (io && io.writeErr) || (s => { process.stderr.write(s); });
  let opts;
  try { opts = parseArgs(argumentsList.slice()); }
  catch (e) { writeErr(String(e.message || e) + '\n'); return 2; }
  try {
    const { text, name } = readInput(opts.input, stdinText);
    let out;
    if (opts.cmd === 'to-json') {
      const doc = parseScenarioDsl(text, name);
      if (doc.family !== opts.family) {
        throw new ScenarioDslError(name, doc.locations.family || 1, 1,
          `document family ${doc.family} does not match --family ${opts.family}`);
      }
      out = JSON.stringify(doc.scenario, null, 2) + '\n';
    } else {
      let sc;
      try { sc = JSON.parse(text); }
      catch (e) { throw new ScenarioDslError(name, 1, 1, 'input is not JSON: ' + e.message); }
      out = scenarioToDsl(opts.family, sc);
    }
    if (opts.output) writeFileSync(opts.output, out);
    else writeOut(out);
    return 0;
  } catch (e) {
    if (e instanceof ScenarioDslError) {
      writeErr(e.message + '\n');
      return 1;
    }
    writeErr(String(e && e.message ? e.message : e) + '\n');
    return 1;
  }
}

const here = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === here) {
  process.exit(runScenarioDslCli(process.argv.slice(2), null));
}

void GRAMMAR_VERSION;
void scenarioFromDsl;
