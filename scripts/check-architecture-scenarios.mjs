// Check what the architecture chapter actually publishes and promises.
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseScenarioDsl, scenarioToDsl } from '../simulator/scenario-dsl.mjs';
import * as checkpoint from '../simulator/checkpoint-simulator-core.mjs';
import * as registry from '../simulator/registry-simulator-core.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const directory = join(root, 'docs/architecture/scenarios');
const names = ['register', 'rotate', 'consume', 'duplicate'];
const read = path => readFileSync(path, 'utf8');
// These are the chapter's observable promises, independent of scenario text.
const outcomes = {
  register: { story: 3881, steps: [
    { expect: { verdict: 'not-present' } },
    { expect: { ok: true, live: { sn: 0, refundTo: 1, pool: 10 }, verdict: 'juvenile' } },
    { slot: 9, expect: { verdict: 'juvenile' } },
    { slot: 10, expect: { verdict: 'consumable' } },
  ], forks: [{ id: 'twice', steps: [{ expect: { ok: false, reason: 'already-present' } }] }] },
  rotate: { story: 3882, steps: [
    { expect: { ok: true } }, { expect: { verdict: 'consumable' } },
    { expect: { ok: true, live: { sn: 1, epoch: 1, pool: 8 }, flow: { hunter: { addr: 2, pool: 2 } }, verdict: 'consumable' } },
  ], forks: [{ id: 'twice', steps: [{ expect: { ok: false, reason: 'no-witnessed-rotation' } }] }] },
  consume: { story: 3883, steps: [
    { expect: { ok: true } }, { expect: { verdict: 'consumable' } },
    { expect: { ok: true, live: { sn: 1, pool: 8 } } },
    { slot: 13, expect: { verdict: 'consumable' } },
    { slot: 14, expect: { ok: true, live: { epoch: 1, poisoned: true }, verdict: 'poisoned' } },
    { slot: 24, expect: { verdict: 'poisoned' } },
  ] },
  duplicate: { id: 3884, slug: 'architecture-duplicate', steps: [
    { expect: { ok: true, flow: { deposited: 1002 } } },
    { expect: { ok: true, flow: { locked: [{ aid: 11, value: 1000 }], tips: { addr: 3, value: 2 } } } },
    { expect: { ok: true } }, { expect: { ok: false, reason: 'already-registered' } },
    { expect: { ok: true, flow: { refunds: [{ addr: 4, value: 1000 }], tips: { addr: 6, value: 2 } } } },
  ], forks: [{ id: 'sam-too-early', steps: [{ expect: { ok: false, reason: 'not-rejectable' } }] }],
  expectFinal: { leaves: [{ aid: 11, status: { active: 0 } }], ckpts: [{ aid: 11, ckpt: { token: 0, k: 0, st: 'live' } }], requests: [], nextToken: 1 } },
};

function includes(actual, expected, path) {
  if (Array.isArray(expected)) assert.equal(actual?.length, expected.length, `${path}: extent`);
  if (expected !== null && typeof expected === 'object') {
    for (const [key, value] of Object.entries(expected)) includes(actual?.[key], value, `${path}.${key}`);
  } else assert.equal(actual, expected, `${path}: documented outcome missing or changed`);
}

function verifyScenario(name, text) {
  const { family, scenario } = parseScenarioDsl(text, `${name}.dsl`);
  assert.equal(family, name === 'duplicate' ? 'registry' : 'checkpoint', `${name}: simulator family`);
  includes(scenario, outcomes[name], name);
  const result = (family === 'checkpoint' ? checkpoint : registry).checkScenario(scenario, name);
  assert.deepEqual(result.problems, [], `${name}: replay`);
  return result.timeline.length + (family === 'checkpoint'
    ? result.forks.reduce((count, fork) => count + fork.timeline.length, 0)
    : Object.values(result.forkTimelines).reduce((count, timeline) => count + timeline.length, 0));
}

function verifySources(sources) {
  assert.deepEqual(Object.keys(sources).sort(), [...names].sort(), 'exact scenario set');
  return names.reduce((count, name) => count + verifyScenario(name, sources[name]), 0);
}

function decodeHtml(text) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#39': "'" };
  return text.replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, key) =>
    entities[key] ?? String.fromCodePoint(key[1].toLowerCase() === 'x' ? parseInt(key.slice(2), 16) : Number(key.slice(1))));
}

function verifyRendered(html, sources) {
  const blocks = [...html.matchAll(/<pre\b[^>]*>\s*(?:<span><\/span>)?<code\b[^>]*>([\s\S]*?)<\/code>\s*<\/pre>/g)]
    .map(match => decodeHtml(match[1].replace(/<[^>]*>/g, '')))
    .filter(text => /^grammar:/m.test(text));
  assert.equal(blocks.length, names.length, 'rendered scenario extent');
  for (const [i, name] of names.entries()) {
    // SuperFences drops the final newline; every other character must survive.
    assert.equal(blocks[i].replace(/\n?$/, '\n'), sources[name], `${name}: rendered copy text differs`);
    verifyScenario(name, blocks[i]);
  }
}

function selftest(sources) {
  const rejects = (label, run, reason) => {
    assert.throws(run, reason, `${label}: negative control survived`);
    console.log(`REJECTED ${label}`);
  };
  rejects('missing scenario', () => verifySources(Object.fromEntries(Object.entries(sources).slice(1))), /exact scenario set/);
  rejects('malformed DSL', () => verifyScenario('register', sources.register.replace('grammar: 1', 'grammar: 999')), /grammar/i);
  const changed = parseScenarioDsl(sources.rotate).scenario;
  changed.steps[2].action.rotate.payee = 4;
  rejects('payment sent to wrong actor', () => verifyScenario('rotate', scenarioToDsl('checkpoint', changed)), /replay/);
  const stripped = parseScenarioDsl(sources.consume).scenario;
  delete stripped.steps[5].expect;
  rejects('removed consumer assertion', () => verifyScenario('consume', scenarioToDsl('checkpoint', stripped)), /documented outcome/);
  const wrongFork = parseScenarioDsl(sources.duplicate).scenario;
  wrongFork.forks[0].steps[0].now = 25;
  rejects('early rejection branch now succeeds', () => verifyScenario('duplicate', scenarioToDsl('registry', wrongFork)), /replay/);
  const html = names.map(name => `<pre><code>${sources[name].replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</code></pre>`).join('');
  verifyRendered(html, sources);
  rejects('rendered copy corruption', () => verifyRendered(html.replace('pool0: 10', 'pool0: 11'), sources), /rendered copy text/);
  rejects('duplicate displayed scenario', () => verifyRendered(html + `<pre><code>${sources.register}</code></pre>`, sources), /rendered scenario extent/);
}

try {
  const args = process.argv.slice(2);
  const self = args.includes('--selftest');
  if (self) args.splice(args.indexOf('--selftest'), 1);
  assert.ok(args.length === 0 || (args.length === 2 && args[0] === '--site'), 'usage: check-architecture-scenarios.mjs [--selftest] [--site PATH]');
  const files = readdirSync(directory).filter(file => file.endsWith('.dsl'));
  const sources = Object.fromEntries(files.map(file => [file.slice(0, -4), read(join(directory, file))]));
  const steps = verifySources(sources);
  const markdown = read(join(root, 'docs/architecture/follow-one-identity.md'));
  const snippets = [...markdown.matchAll(/^--8<-- "docs\/architecture\/scenarios\/(\w+)\.dsl"$/gm)].map(match => match[1]);
  assert.deepEqual(snippets, names, 'exact chapter snippet bindings');
  for (const name of names) assert.ok(markdown.includes(`](scenarios/${name}.dsl)`), `${name}: download link missing`);
  if (self) selftest(sources);
  if (args.length) {
    const site = resolve(args[1]);
    verifyRendered(read(join(site, 'architecture/follow-one-identity/index.html')), sources);
    for (const name of names) {
      const download = read(join(site, `architecture/scenarios/${name}.dsl`));
      assert.equal(download, sources[name], `${name}: downloaded file differs`);
      verifyScenario(name, download);
    }
    console.log('PASS rendered copy text and downloads match all four replayed sources');
  }
  console.log(`PASS architecture: ${names.length} scenarios, ${steps} trunk and fork steps`);
} catch (error) {
  console.error(error.stack);
  process.exitCode = 1;
}
