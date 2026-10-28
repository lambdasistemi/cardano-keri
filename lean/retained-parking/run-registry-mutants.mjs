import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const repo = path.resolve(import.meta.dirname, '../..');
const campaign = path.resolve(process.argv[2] ?? '');
if (!process.argv[2] || fs.existsSync(campaign)) throw Error('provide a fresh campaign directory');
fs.mkdirSync(campaign, { recursive: true });
const lean = process.env.LEAN_BIN ?? 'lean';
const upstream = path.join(repo, 'lean/.lake/packages/singular/.lake/build/lib/lean');
const model = process.argv[3] ?? 'Registry';
if (!['Registry', 'Checkpoint', 'Samaritan'].includes(model)) throw Error('unknown model');
const fullSource = fs.readFileSync(path.join(repo, `lean/CardanoKeri/${model}.lean`), 'utf8');
// Economic mutations execute the exact definition prefix without importing
// its proof suffix. A proof elaboration failure cannot count as a runtime kill.
const source = model === 'Samaritan'
  ? fullSource.slice(0, fullSource.indexOf('/-- Given every nonnegative')) + '\nend CardanoKeri.Samaritan\n'
  : fullSource;
if (model === 'Samaritan' && !fullSource.includes('/-- Given every nonnegative')) throw Error('definition-prefix boundary missing');
const fixtures = fs.readFileSync(path.join(repo, 'lean/CardanoKeri/RegistryScenarioFixtures.lean'), 'utf8');
const cases = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, process.argv[4] ?? `${model.toLowerCase()}-mutants.json`)));
if (!cases.length || new Set(cases.map(c => c.id)).size !== cases.length) throw Error('invalid mutant inventory');
const sha = text => createHash('sha256').update(text).digest('hex');
fs.writeFileSync(path.join(campaign, 'source.json'), JSON.stringify({ model, fullSource: sha(fullSource), executedSource: sha(source), fixtures: sha(fixtures), manifest: sha(JSON.stringify(cases)) }, null, 2));
const results = [];
function run(c, baseline) {
  const id = baseline ? `baseline-${c.test}` : c.id;
  const dir = path.join(campaign, id);
  fs.mkdirSync(path.join(dir, 'CardanoKeri'), { recursive: true });
  if (model === 'Checkpoint') {
    for (const dependency of ['Registry', 'Duplicity', 'DuplicityExamples']) {
      fs.copyFileSync(path.join(repo, `lean/.lake/build/lib/lean/CardanoKeri/${dependency}.olean`),
        path.join(dir, `CardanoKeri/${dependency}.olean`));
    }
  }
  let mutated = source;
  if (!baseline) {
    if (source.split(c.before).length !== 2) throw Error(`${id}: source match must be unique`);
    mutated = source.replace(c.before, c.after);
  }
  fs.writeFileSync(path.join(dir, `CardanoKeri/${model}.lean`), mutated);
  fs.writeFileSync(path.join(dir, 'CardanoKeri/RegistryScenarioFixtures.lean'), fixtures);
  const test = fs.readFileSync(path.join(repo, `lean/${c.test}.lean`), 'utf8');
  fs.writeFileSync(path.join(dir, 'Subject.lean'), test);
  fs.writeFileSync(path.join(dir, 'identity.json'), JSON.stringify({ registry: sha(mutated), subject: sha(test) }, null, 2));
  const env = { ...process.env, LEAN_PATH: `${dir}:${path.join(repo, "lean/.lake/build/lib/lean")}:${upstream}` };
  function command(label, args) {
    fs.writeFileSync(path.join(dir, `${label}.command.json`), JSON.stringify({ command: lean, args, cwd: dir, LEAN_PATH: env.LEAN_PATH }, null, 2));
    const result = spawnSync(lean, args, { cwd: dir, env, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024 });
    fs.writeFileSync(path.join(dir, `${label}.log`), result.stdout + result.stderr);
    fs.writeFileSync(path.join(dir, `${label}.exit`), `${result.status}\n`);
    if (result.error || result.signal) throw Error(`${id}: setup/timeout ${label}`);
    return result;
  }
  for (const module of (model === 'Registry' ? ['Registry', 'RegistryScenarioFixtures'] : [model])) {
    const r = command(`build-${module}`, ['-o', `CardanoKeri/${module}.olean`, `CardanoKeri/${module}.lean`]);
    if (r.status !== 0) throw Error(`${id}: model/fixture compilation failed; not a semantic kill`);
  }
  if (command('elaborate-subject', ['Subject.lean']).status !== 0) throw Error(`${id}: subject failed compilation; not a semantic kill`);
  const r = command('execute', ['--run', 'Subject.lean', ...(c.args ?? [])]);
  if (baseline) {
    if (r.status !== 0) throw Error(`${id}: positive baseline failed`);
    results.push({ id, verdict: 'PASS', subject: c.test });
  } else {
    if (r.status === 0) throw Error(`${id}: SURVIVED`);
    if (!(r.stdout + r.stderr).includes(c.failure)) throw Error(`${id}: failed for an unbound reason`);
    results.push({ id, verdict: 'KILLED', owner: c.owner, failure: c.failure, subject: c.test });
  }
  fs.writeFileSync(path.join(campaign, 'results.json'), JSON.stringify(results, null, 2));
  console.log(`${id}: ${results.at(-1).verdict}`);
}
for (const test of new Set(cases.map(c => c.test))) run({ test }, true);
for (const c of cases) run(c, false);
console.log(`${model} semantic mutants: ${cases.length}/${cases.length}; every model, fixture and subject compiled`);
