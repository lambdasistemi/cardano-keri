#!/usr/bin/env node
// Resolve reviewed source bindings against both trees. Keep the comparison usable
// offline with the recorded January commit, and check its published tip in CI.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {entryPoints, januaryRevision, rules} from '../lean/conformance/rules.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const target = path.join(root, 'lean/VALIDATOR-CONFORMANCE.md');
const git = (...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
const args = process.argv.slice(2);
if (args.some(flag => !['--write', '--check', '--published'].includes(flag)) ||
    args.includes('--write') === args.includes('--check')) {
  throw Error('Use --write or --check, optionally with --published to refresh the January review ref.');
}
const github = 'https://github.com/lambdasistemi/cardano-keri';
let january = januaryRevision;
if (args.includes('--published')) {
  git('fetch', '--quiet', '--no-tags', 'origin', 'refs/pull/592/head');
  january = git('rev-parse', 'FETCH_HEAD').trim();
  if (january !== januaryRevision) throw Error('Review updated January source ' + january +
    ', update januaryRevision in lean/conformance/rules.mjs, then regenerate.');
}
const sources = new Map();
const januaryFiles = new Set(git('ls-tree', '-r', '--name-only', january).trimEnd().split('\n'));
function read(tree, file) {
  const key = tree + ':' + file;
  if (!sources.has(key)) {
    const present = tree === 'main' ? existsSync(path.join(root, file)) : januaryFiles.has(file);
    sources.set(key, !present ? null : tree === 'main' ? readFileSync(path.join(root, file), 'utf8') :
      git('show', january + ':' + file));
  }
  return sources.get(key);
}
function link(tree, file, line) {
  const location = tree === 'main' ? '../' + file : github + '/blob/' + january + '/' + file;
  return '[' + path.basename(file) + ' L' + line + '](' + location + '#L' + line + ')';
}
function resolve(tree, site) {
  const source = read(tree, site.path);
  if (source === null) throw Error('Missing ' + tree + ':' + site.path);
  const hits = source.split('\n').flatMap((line, i) => line.trimStart().startsWith(site.text) ? [i + 1] : []);
  if (hits.length !== 1) throw Error(tree + ':' + site.path + ' has ' + hits.length + ' matches for ' + site.text);
  return link(tree, site.path, hits[0]) + (site.note ? ' (' + site.note + ')' : '');
}
function assess(tree, rule) {
  const assessment = {...rule, ...rule[tree]};
  const model = assessment.models.find(s => read(tree, s.path)?.split('\n').some(line => line.trimStart().startsWith(s.text)));
  if (!model) throw Error('No model source for ' + rule.rule + ' on ' + tree);
  const text = resolve(tree, model) + '<br>' + assessment.status + '. ' + assessment.sites.map(s => resolve(tree, s)).join(', ');
  return {coverage: assessment.coverage, text};
}
const ticketLinks = numbers => numbers.map(n => '[#' + n + '](' + github + '/issues/' + n + ')').join(', ');
function projection(tree) {
  const producer = 'lean/ConsumerTraceDriver.lean';
  const consumer = 'scripts/consumer-vectors.mjs';
  const corpus = JSON.parse(read(tree, 'simulator/consumer-corpus.json'));
  const source = read(tree, consumer);
  const accepted = /corpus\.version !== (\d+)/.exec(source);
  if (!accepted) throw Error('Review the consumer schema check on ' + tree);
  const ver = corpus.version;
  const schema = corpus.schema;
  const declaration = '("schema", toJson "' + schema + '"), ("version", toJson (' + ver + ' : Nat))';
  const gate = 'if (corpus.schema !== ' + JSON.stringify(schema).replaceAll('"', "'") + ' || corpus.version !== ';
  const matches = ver === Number(accepted[1]);
  const text = (matches ? 'Schema matches' : 'not enforced: projection stops before generating Aiken') +
    '. Producer v' + ver + ' (' + corpus.fields.length + ' field cases), consumer v' + accepted[1] + '. ' +
    resolve(tree, {path: producer, text: declaration}) + ', ' + resolve(tree, {path: consumer, text: gate});
  return {coverage: matches ? 'enforced' : 'missing', text};
}
const assessed = rules.map(rule => ({
  ...rule, main: assess('main', rule), january: assess('january', rule),
}));
assessed.push({
  rule: 'Project every consumer identity case into the Aiken suite.', tickets: [576, 569],
  main: projection('main'), january: projection('january'),
});
function formatRow(row) {
  const gap = [row.main, row.january].some(cell => cell.coverage !== 'enforced');
  if (gap && !row.tickets.length && !row.noTicket) {
    throw Error('Name the tracking issue or set noTicket explicitly for: ' + row.rule);
  }
  const tracking = ticketLinks(row.tickets) || (gap ? 'None exists; ticket needed' : 'None (no open enforcement gap)');
  return '| ' + [row.rule, row.main.text, row.january.text, tracking].join(' | ') + ' |';
}
function countLine(tree, label) {
  const totals = {enforced: 0, partial: 0, missing: 0};
  for (const row of assessed) {
    const coverage = row[tree].coverage;
    if (!Object.hasOwn(totals, coverage)) throw Error('Unknown coverage for ' + row.rule);
    totals[coverage]++;
  }
  return '**' + label + '**: ' + totals.enforced + ' enforced, ' + totals.partial + ' partly enforced, ' +
    totals.missing + ' not enforced (' + (totals.partial + totals.missing) + ' open of ' + assessed.length + ').';
}
const registrationOnMain = read('main','lean/CardanoKeri/ApplicationInceptionPrefix.lean') === null
  ? 'Main’s application model currently retains the economic inception premise. The standalone #590 draft supplies the signed opening.'
  : 'Main’s application model includes the indexed signed inception opening.';
const differences = [];
const mainRotation = read('main','lean/CardanoKeri/Duplicity.lean');
if (!mainRotation.includes('0 < n && n <=')) differences.push('zero signing threshold (#596)');
if (!mainRotation.includes('def Threshold.fitsNextKeys')) differences.push('declared next rule (#595)');
if (!mainRotation.includes('signed.event.cuts.all prior.witnesses.contains')) differences.push('witness changes (#598)');
if (!mainRotation.includes('context.accepted.event.eventDigest ≠ rival.event.eventDigest')) differences.push('signed digest identity (#573)');
const entries = entryPoints.map(s => resolve('main', s)).join(', ');
const janEntries = entryPoints.map(s => resolve('january', s)).join(', ');
function fingerprint(tree) {
  const hash = createHash('sha256');
  for (const [file, source] of [...sources].sort(([a],[b]) => a.localeCompare(b))) {
    if (file.startsWith(tree + ':') && source !== null) hash.update(file.slice(tree.length + 1)).update('\0').update(source).update('\0');
  }
  return hash.digest('hex').slice(0,16);
}
const output = [
  '# Validator conformance', '', countLine('main', 'Main'), '', countLine('january', 'January'), '',
  'The December target is structural registration decoding and admission of key-derived identifiers. The first inventory covers registration, ordinary advance, conviction and the consumer-vector projection. Each cell links the Lean decision or premise and the Aiken decision that implements it or still needs to change. A source-level match describes that decision only. Transaction execution and budgets require separate evidence.', '',
  'Main is the checkout containing this report. January is the published [prefix-model draft](' + github + '/pull/592) at `' + january +
  '`. Both columns inspect the validator sources in their own tree. The January column excludes unpublished validator work.', '',
  '| Rule | Main model and enforcement | January model and enforcement | Tracking |', '| --- | --- | --- | --- |',
  ...assessed.map(formatRow), '',
  registrationOnMain + ' The January rotation model includes the #595, #596 and #598 corrections.' +
    (differences.length ? ' Main still differs on ' + differences.join(', ') + '.' : '') +
    ' A ticket alongside an enforced advance decision can track the corresponding model or conviction correction. The schema row is a build-time check. The #576 validator work carries the v2 conversion for the #569 model. #343 delivered the original v1 consumer.', '',
  'Booking and observer entry points on main: ' + entries + '.', '',
  'Booking and observer entry points in January: ' + janEntries + '.', '',
  'Source fingerprints: main `' + fingerprint('main') + '`, January `' + fingerprint('january') + '`.', '',
  'To refresh after a merge, run `node scripts/validator-conformance.mjs --write --published`. Review changed decisions in `lean/conformance/rules.mjs` and commit the regenerated table. The Lean traceability check regenerates and compares the report on every PR and main push. For offline verification with the recorded January Git object, run `node scripts/validator-conformance.mjs --check`.', '',
].join('\n');
if (args.includes('--write')) writeFileSync(target, output);
else if (readFileSync(target, 'utf8') !== output) throw Error('Stale validator conformance table; review bindings and regenerate');
console.log('Checked ' + assessed.length + ' conformance rules on main and January ' + january.slice(0,8));
