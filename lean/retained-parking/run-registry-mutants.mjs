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
if (!['Registry', 'Checkpoint', 'Samaritan', 'Application', 'ReaderStatus'].includes(model)) throw Error('unknown model');
// Models whose campaign rebuilds a vector module against the mutated model
// and checks the committed table: the vector module, the table, the manifest.
const vectorCampaigns = {
  Application: ['ApplicationVectors', 'application-vectors.json', 'application-mutants.json'],
  ReaderStatus: ['ReaderStatusVectors', 'reader-status-vectors.json', 'reader-status-mutants.json'] };
const vectorCampaign = vectorCampaigns[model];
const fullSource = fs.readFileSync(path.join(repo, `lean/CardanoKeri/${model}.lean`), 'utf8');
// Economic mutations execute the exact definition prefix without importing
// its proof suffix. A proof elaboration failure cannot count as a runtime kill.
const source = model === 'Samaritan'
  ? fullSource.slice(0, fullSource.indexOf('/-- Given every nonnegative')) + '\nend CardanoKeri.Samaritan\n'
  : fullSource;
if (model === 'Samaritan' && !fullSource.includes('/-- Given every nonnegative')) throw Error('definition-prefix boundary missing');
// The application campaign rebuilds its vectors against the mutated model and
// checks them against the committed table.
const fixtureModule = vectorCampaign ? vectorCampaign[0] : 'RegistryScenarioFixtures';
const fixtures = fs.readFileSync(path.join(repo, `lean/CardanoKeri/${fixtureModule}.lean`), 'utf8');
const subjectArgs = vectorCampaign ? [path.join(repo, 'lean', vectorCampaign[1])] : [];
const cases = JSON.parse(fs.readFileSync(path.join(import.meta.dirname,
  process.argv[4] ?? (vectorCampaign ? vectorCampaign[2] : `${model.toLowerCase()}-mutants.json`))));
if (!cases.length || new Set(cases.map(c => c.id)).size !== cases.length) throw Error('invalid mutant inventory');
const sha = text => createHash('sha256').update(text).digest('hex');
fs.writeFileSync(path.join(campaign, 'source.json'), JSON.stringify({ model, fullSource: sha(fullSource), executedSource: sha(source), fixtures: sha(fixtures), manifest: sha(JSON.stringify(cases)) }, null, 2));
const results = [];
function run(c, baseline) {
  const id = baseline ? `baseline-${c.test}` : c.id;
  const dir = path.join(campaign, id);
  fs.mkdirSync(path.join(dir, 'CardanoKeri'), { recursive: true });
  let mutated = source;
  if (!baseline) {
    if (source.split(c.before).length !== 2) throw Error(`${id}: source match must be unique`);
    mutated = source.replace(c.before, c.after);
  }
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
  // Lean resolves the package from the scratch directory. Stage the actual
  // project import closure there, rebuilding any importer of a changed module.
  const staged = new Map();
  const imports = text => [...text.matchAll(/^import (CardanoKeri\.[\w.]+)\s*$/gm)].map(match => match[1]);
  function stage(module) {
    if (staged.has(module)) return staged.get(module);
    const rel = module.replaceAll('.', '/');
    const name = module.slice('CardanoKeri.'.length);
    const input = name === model ? mutated : fs.readFileSync(path.join(repo, 'lean', rel + '.lean'), 'utf8');
    const dependencies = imports(input).map(stage);
    const rebuild = name === model || name === fixtureModule || dependencies.includes(true);
    fs.mkdirSync(path.dirname(path.join(dir, rel)), {recursive:true});
    if (rebuild) {
      fs.writeFileSync(path.join(dir, rel + '.lean'), input);
      if (command('build-' + name, ['-o', rel + '.olean', rel + '.lean']).status !== 0)
        throw Error(id + ': failed to compile ' + module + '; no semantic result');
    } else {
      fs.copyFileSync(path.join(repo, 'lean/.lake/build/lib/lean', rel + '.olean'), path.join(dir, rel + '.olean'),
        fs.constants.COPYFILE_FICLONE);
    }
    staged.set(module, rebuild);
    return rebuild;
  }
  for (const dependency of imports(test)) stage(dependency);
  if (!staged.get('CardanoKeri.' + model)) throw Error(id + ': subject does not import the mutated model');
  if (command('elaborate-subject', ['Subject.lean']).status !== 0) throw Error(`${id}: subject failed compilation; not a semantic kill`);
  const r = command('execute', ['--run', 'Subject.lean', ...(c.args ?? []), ...subjectArgs]);
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
