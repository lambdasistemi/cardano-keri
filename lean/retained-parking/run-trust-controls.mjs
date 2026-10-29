/* Self-falsification of the compiled, module-owned axiom inventory. A private
 * declaration in an imported owned module must be inspected too. Setup errors
 * are distinct from the expected trust rejection. Keep every source and log. */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const repo = path.resolve(import.meta.dirname, '../..');
const directory = process.argv[2];
if (!directory || fs.existsSync(directory)) throw Error('provide a fresh receipt directory');
fs.mkdirSync(directory, { recursive: true });
const lean = process.env.LEAN_BIN || 'lean';
const library = path.join(repo, 'lean/.lake/build/lib/lean');
const upstream = path.join(repo, 'lean/.lake/packages/singular/.lake/build/lib/lean');
const source = fs.readFileSync(path.join(repo, 'lean/AxiomInventory.lean'), 'utf8');
const sha = value => createHash('sha256').update(value).digest('hex');
const files = fs.readdirSync(library, { recursive: true }).filter(file => file.endsWith('.olean'));
fs.writeFileSync(path.join(directory, 'inputs.json'), JSON.stringify({ inventory: sha(source), compiled: Object.fromEntries(files.map(file => [file, sha(fs.readFileSync(path.join(library, file)))])) }, null, 2));
const cases = [
  { id: 'standard-only', module: 'def harmless : True := True.intro\n', expected: null },
  { id: 'private-custom-axiom', module: 'private axiom hiddenAssumption : False\ndef consequence : False := hiddenAssumption\n', expected: 'unapproved axiom' },
  { id: 'imported-sorry', module: 'def unsupported : False := by sorry\n', expected: 'unapproved axiom sorryAx' },
  { id: 'emptied-enumerator', module: 'def harmless : True := True.intro\n', expected: 'empty compiled declaration inventory', empty: true },
];
for (const control of cases) {
  const dir = path.join(directory, control.id); fs.mkdirSync(dir, { recursive: true });
  // Compiled imports are copied without rewriting their source. Only the new control module is compiled.
  for (const file of files) { const target = path.join(dir, file); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.copyFileSync(path.join(library, file), target, fs.constants.COPYFILE_FICLONE); }
  const module = `namespace CardanoKeri.TrustControl\n${control.module}end CardanoKeri.TrustControl\n`;
  fs.writeFileSync(path.join(dir, 'CardanoKeri/TrustControl.lean'), module);
  let inventory = `import CardanoKeri.TrustControl\n${source}`;
  if (control.empty) {
    if (inventory.split('|>.filter owns').length !== 2) throw Error('enumerator edit target drifted');
    inventory = inventory.replace('|>.filter owns', '|>.filter (fun _ => false)');
  }
  fs.writeFileSync(path.join(dir, 'Inventory.lean'), inventory);
  const env = { ...process.env, LEAN_PATH: `${dir}:${library}:${upstream}` };
  const run = (name, args) => {
    fs.writeFileSync(path.join(dir, `${name}.command.json`), JSON.stringify({ command: lean, args, cwd: dir, LEAN_PATH: env.LEAN_PATH }));
    const result = spawnSync(lean, args, { cwd: dir, env, encoding: 'utf8', timeout: 600000, maxBuffer: 32 * 1024 * 1024 });
    fs.writeFileSync(path.join(dir, `${name}.log`), result.stdout + result.stderr);
    fs.writeFileSync(path.join(dir, `${name}.exit`), `${result.status}\n`);
    if (result.error || result.signal) throw Error(`${control.id}: infrastructure failure`);
    return result;
  };
  if (run('compile-control', ['-o', 'CardanoKeri/TrustControl.olean', 'CardanoKeri/TrustControl.lean']).status !== 0) throw Error(`${control.id}: setup compilation failed`);
  const result = run('inventory', ['Inventory.lean']);
  if (control.expected) {
    if (result.status === 0 || !(result.stdout + result.stderr).includes(control.expected)) throw Error(`${control.id}: control failed for the wrong reason`);
  } else if (result.status !== 0 || !/^INVENTORY [1-9][0-9]*$/m.test(result.stdout)) throw Error('positive inventory failed');
  console.log(`${control.id}: ${control.expected ? 'REJECTED as intended' : 'PASS'}`);
}
console.log('Trust controls: one positive and three intended rejections; all control modules compiled.');
