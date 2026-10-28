/* Fresh Lean generation shared by the build and replay gate. The caller owns
 * resource limits. Expected scenario outcomes never enter the Lean evaluator. */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
export const HERE = dirname(fileURLToPath(import.meta.url));
export const ROOT = resolve(HERE, '..');
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function freshCorpus(root = ROOT, build = true) {
  const lake = process.env.LAKE_BIN || 'lake';
  const run = args => execFileSync(lake, args, { cwd: resolve(root, 'lean'), encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 });
  if (build) run(['build', 'CardanoKeri.RegistryTraceWire']);
  const produce = driver => JSON.parse(run(['env', 'lean', '--run', driver]));
  const traces = produce('RegistryTraceDriver.lean');
  const boundaries = produce('RegistryBoundaryDriver.lean');
  const stories = produce('RegistryStoryDriver.lean');
  return { ...traces, boundaries: boundaries.cells, stories: stories.stories };
}
export function sourceBindings() {
  const sources = ['lean/CardanoKeri/Registry.lean', 'lean/CardanoKeri/RegistryTraceWire.lean',
    'lean/CardanoKeri/RegistryScenarioFixtures.lean', 'lean/RegistryTraceDriver.lean',
    'lean/RegistryBoundaryDriver.lean', 'lean/RegistryStoryDriver.lean',
    'simulator/registry-economic-core.mjs', 'simulator/registry-wire.mjs', 'simulator/registry-simulator-core.mjs'];
  return Object.fromEntries(sources.map(path => [path, sha256(readFileSync(resolve(ROOT, path)))]));
}
