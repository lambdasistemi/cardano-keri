import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

const root = dirname(fileURLToPath(import.meta.url));
const corpus = JSON.parse(readFileSync(join(root, 'statements-conformance.json'), 'utf8'));
const registry = JSON.parse(readFileSync(join(root, 'statements-refusals.json'), 'utf8'));
const provenance = JSON.parse(readFileSync(join(root, 'statements-provenance.json'), 'utf8'));
assert.equal(corpus.source, provenance.sourceCommit);
assert.equal(registry.sourceCommit, corpus.source);
const sha = file => createHash('sha256').update(readFileSync(file)).digest('hex');
assert.equal(sha(join(root, 'StatementsTraceDriver.lean')), provenance.fixture.driverSha256);
assert.equal(sha(join(root, 'StatementsSurface.lean')), provenance.fixture.surfaceDriverSha256);
assert.equal(Object.keys(provenance.theoremAxioms).length, 52);
assert.ok(Object.values(provenance.theoremAxioms).every(a => a.includes('sorryAx')));
assert.equal(new Set(registry.refusals.map(r => r.name)).size, registry.refusals.length);
assert.deepEqual([...new Set(corpus.cases.filter(c => c.result.status === 'refused').map(c => c.result.refusal))].sort(),
  registry.refusals.map(r => r.name).sort());
const operations = new Map();
for (const c of corpus.cases) {
  const op = c.call.action.action;
  if (!operations.has(op)) operations.set(op, new Set());
  operations.get(op).add(c.result.status === 'refused' ? 'refused'
    : typeof c.result.value === 'boolean' ? c.result.value : 'accepted');
}
for (const r of registry.refusals) {
  assert.deepEqual([...operations.get(r.operation)].sort(), ['accepted', 'refused'], r.operation);
}
for (const op of ['mirror.miss', 'credential.gate', 'delegation.ancestorWithin']) {
  assert.deepEqual([...operations.get(op)].sort(), [false, true], op);
}
const constructors = Object.values(provenance.compiledConstructors).flat().map(n =>
  n.replace('CardanoKeri.', '').replace('.HAction.', '.').replace('.Action.', '.').replace(/^[A-Z]/, c => c.toLowerCase()));
assert.equal(constructors.length, 16);
for (const op of constructors) assert.ok(operations.has(op), `missing compiled constructor ${op}`);
assert.equal(operations.size, 24);

function unique(rows, key, label) {
  assert.equal(new Set(rows.map(r => r[key])).size, rows.length, `duplicate ${label}`);
}
function tables(value) {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value)) { value.forEach(tables); return; }
  for (const [field, key] of [['hist', 'sn'], ['ckpt', 'aid'], ['reg', 'rid'], ['known', 'aid'], ['cage', 'key']]) {
    if (field in value) unique(value[field], key, field);
  }
  if ('revoked' in value) assert.equal(new Set(value.revoked).size, value.revoked.length, 'duplicate revoked SAID');
  Object.values(value).forEach(tables);
}
tables(corpus);
if (process.argv[2]) {
  assert.equal(sha(process.argv[2]), provenance.fixture.rawSha256, 'fresh trace hash differs from provenance');
  const generated = spawnSync(process.execPath, [join(root, 'extract-statements.mjs'), process.argv[2]], { encoding: 'utf8' });
  assert.equal(generated.status, 0, generated.stderr);
  assert.deepEqual(JSON.parse(generated.stdout), corpus, 'corpus differs from fresh statement execution');
}
if (process.argv[3]) {
  const surface = JSON.parse(readFileSync(process.argv[3], 'utf8'));
  assert.deepEqual(surface.constructors, provenance.compiledConstructors);
  assert.deepEqual(surface.statements, provenance.theoremAxioms);
}

const byName = name => structuredClone(corpus.cases.find(c => c.name === name).call);
const controls = [];
function control(name, value, valid, change = () => {}) { change(value); controls.push({ name, value, valid }); }
control('unknown-is-a-verdict', { status: 'unknown', missing: [{ object: 'tel', subject: 'issuer/registry' }] }, true);
control('unknown-needs-missing-evidence', { status: 'unknown', missing: [] }, false);
control('unknown-is-not-history-finality', { status: 'accepted', value: 'unknown' }, false);
control('unsupported-bis-kind', byName('mirror-open'), false, c => { c.action.w.tel.kind = 'bis'; });
control('missing-seal-index', byName('mirror-open'), false, c => { delete c.action.w.core.idx; });
control('negative-seal-index', byName('mirror-open'), false, c => { c.action.w.core.idx = -1; });
control('missing-seal-digest', byName('mirror-open'), false, c => { delete c.action.w.core.kel.seals[1].d; });
control('tel-sequence-is-not-hardcoded', byName('mirror-open'), true, c => { c.action.w.tel.s = 17; });
control('nonzero-dip-is-shaped-but-refused', byName('delegation-register-nonzero-sequence'), true);
control('missing-certificate-said', byName('delegation-register-child'), false, c => { delete c.state.certs[0].childSaid; });
control('known-parent-zero', byName('delegation-leave'), true, c => { c.state.known[0].value = { kind: 'delegated', parent: 0 }; });
control('plain-is-not-parent-zero', byName('delegation-leave'), false, c => { c.state.known[0].value = { kind: 'plain', parent: 0 }; });
control('nested-option-is-not-null', byName('delegation-leave'), false, c => { c.state.known[0].value = null; });
control('no-keri-resolver', byName('mirror-open'), false, c => { c.resolver = 'https://example.invalid'; });
control('no-secret-key', byName('delegation-mint'), false, c => { c.secretKey = 'not-an-input'; });
control('unsupported-action', byName('delegation-leave'), false, c => { c.action.action = 'delegation.erase'; });

const duplicate = byName('delegation-leave');
duplicate.state.known.push(structuredClone(duplicate.state.known[0]));
assert.throws(() => tables(duplicate), /duplicate known/);
const scratch = mkdtempSync(join(tmpdir(), 'keri-statement-shapes-'));
let cddlChecks = 0;
function validate(file, valid, name) {
  const r = spawnSync('cddl', [join(root, 'statements-model.cddl'), 'validate', file], { encoding: 'utf8' });
  assert.equal(r.error, undefined, `${name}: ${r.error}`);
  assert.equal(r.status, valid ? 0 : 1, `${name}: ${r.stderr}`);
  if (!valid) assert.match(r.stderr, /CDDL validation failure/, `${name}: wrong refusal layer`);
  cddlChecks++;
}
try {
  validate(join(root, 'statements-conformance.json'), true, 'corpus');
  for (const c of controls) {
    const file = join(scratch, c.name + '.json');
    writeFileSync(file, JSON.stringify(c.value));
    validate(file, c.valid, c.name);
  }
} finally { rmSync(scratch, { recursive: true, force: true }); }
console.log(JSON.stringify({ cases: corpus.cases.length, operations: operations.size,
  refusalNames: registry.refusals.length, cddlChecks, duplicateTableControl: 'rejected',
  freshLeanParity: Boolean(process.argv[2]) }));
