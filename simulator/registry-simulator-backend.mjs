/* Immutable session tree shared by the Registry page and CLI. Nodes retain
 * whole model inputs and outputs; a new attempt creates a sibling branch. */
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { newSession, attempt, setEvidence, checkScenario } from './registry-simulator-core.mjs';
import { equal, toInternal, toWire } from './registry-economic-core.mjs';
const HERE = dirname(fileURLToPath(import.meta.url));
const SCENARIOS = readdirSync(join(HERE, 'registry-simulator-scenarios')).filter(f => f.endsWith('.json')).sort()
  .map(f => JSON.parse(readFileSync(join(HERE, 'registry-simulator-scenarios', f), 'utf8')));
/* @@BACKEND@@ */
function treeAddChild(tree, parent, entry) {
  if (!tree.nodes[parent]) throw Error('unknown parent');
  const nodes = tree.nodes.map(n => ({ ...n, children: [...n.children] }));
  const id = nodes.length;
  nodes.push({ id, parent, children: [], last: null, branch: null, ...entry });
  nodes[parent].children.push(id); nodes[parent].last = id;
  return { ...tree, nodes, cursor: id };
}
function playLoadedScenario(scenario) {
  const report = checkScenario(scenario);
  if (!report.ok) throw Error(report.problems.join('; '));
  let tree = { family: 'registry', story: scenario.id, storySc: scenario, cursor: 0,
    nodes: [{ id: 0, parent: null, children: [], last: null, branch: null, kind: 'origin', who: '', say: scenario.narrative,
      record: null, session: { ...newSession(scenario.params, scenario.config, scenario.env), now: 0 } }] };
  const play = (parent, step, branch = null, env = null) => {
    let before = tree.nodes[parent].session;
    before = setEvidence(before, step.env ?? env ?? scenario.env);
    const next = attempt(before, step.action);
    tree = treeAddChild(tree, parent, { ...next, step, branch, who: step.as, actorId: (step.as || '').toLowerCase().split(' ')[0], say: step.note, kind: 'story' });
    return tree.cursor;
  };
  const trunk = [0];
  for (const step of scenario.steps) trunk.push(play(trunk.at(-1), step));
  tree.trunkLeaf = trunk.at(-1);
  for (const fork of scenario.forks) {
    let parent = trunk[fork.at];
    fork.steps.forEach((step, i) => { parent = play(parent, step, i ? null : { id: fork.id, title: fork.title }, fork.env); });
  }
  for (let i = 0; i < trunk.length - 1; i++) tree.nodes[trunk[i]].last = trunk[i + 1];
  tree.punch = tree.trunkLeaf; tree.cursor = 0;
  return tree;
}
function playStory(id) {
  const scenario = SCENARIOS.find(s => String(s.id) === String(id));
  if (!scenario) throw Error('unknown story');
  return playLoadedScenario(scenario);
}
function dryRun(tree, action, nodeId = tree.cursor) { return attempt(tree.nodes[nodeId].session, action); }
function submit(tree, action, nodeId = tree.cursor) {
  const next = dryRun(tree, action, nodeId);
  return treeAddChild(tree, nodeId, { ...next, kind: 'attempt', who: 'You', say: Object.keys(action)[0] });
}
function replaceEvidence(tree, env, nodeId = tree.cursor) {
  const session = setEvidence(tree.nodes[nodeId].session, env);
  return treeAddChild(tree, nodeId, { session, record: null, kind: 'evidence', who: 'You', say: 'Evidence table changed' });
}
// The proposal clock is UI metadata only. Whole transaction intervals remain
// explicit action inputs, and moving this clock does not execute stepFn.
function moveSlot(tree, value, nodeId = tree.cursor) {
  const now = toInternal(value);
  if (typeof now !== 'bigint' || now < 0n) throw Error('invalid-proposal-slot');
  const before = tree.nodes[nodeId].session;
  if (now < toInternal(before.now ?? 0)) throw Error('proposal-slot-decreased');
  return treeAddChild(tree, nodeId, { session: { ...before, now: toWire(now) }, record: null, kind: 'time', who: 'You', say: 'Proposal interval moved' });
}
function editEvidence(tree, row, add = true, nodeId = tree.cursor) {
  const keys = Object.keys(row);
  if (keys.length !== 1 || !['inception', 'rotationFrom', 'duplicity', 'closeAuth'].includes(keys[0])) throw Error('invalid-evidence-row');
  const kind = keys[0], args = row[kind];
  if (!Array.isArray(args) || args.length !== (kind === 'inception' ? 1 : 2)) throw Error('invalid-evidence-row');
  const value = kind === 'inception' ? args[0] : args;
  const env = tree.nodes[nodeId].session.env;
  const rest = env[kind].filter(x => !equal(x, value));
  return replaceEvidence(tree, { ...env, [kind]: add ? [...rest, value] : rest }, nodeId);
}
function selectPath(tree, forkId, toEnd = false) {
  const nodes = tree.nodes.map(n => ({ ...n, children: [...n.children] }));
  let cursor = 0;
  if (forkId) {
    const node = nodes.find(n => n.branch?.id === forkId);
    if (!node) throw Error('unknown fork');
    cursor = node.id;
    if (toEnd) while (nodes[cursor].last !== null) cursor = nodes[cursor].last;
  } else if (toEnd) cursor = tree.trunkLeaf;
  for (let id = cursor; nodes[id].parent !== null; id = nodes[id].parent) nodes[nodes[id].parent].last = id;
  return { ...tree, nodes, cursor };
}
function projectJson(tree) {
  const path = [];
  for (let id = tree.cursor; id !== null; id = tree.nodes[id].parent) {
    const n = tree.nodes[id];
    path.unshift({ id, parent: n.parent, kind: n.kind, branch: n.branch, who: n.who, say: n.say,
      action: n.record?.action, ok: n.record ? !!n.record.result.ok : null, reason: n.record?.result.error,
      flow: n.record?.result.ok?.flow, state: n.session.state, evidence: n.session.env });
  }
  return { family: tree.family, wireVersion: 3, story: tree.story, cursor: tree.cursor, path };
}
/* @@BACKEND:END@@ */
export { playStory, playLoadedScenario, treeAddChild, dryRun, submit, replaceEvidence, moveSlot, editEvidence, selectPath, projectJson };
