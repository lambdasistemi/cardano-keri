#!/usr/bin/env node
/*
 * checkpoint-simulator-backend.mjs — session-tree and free-play over the
 * checkpoint core. Importable under plain Node. The @@BACKEND@@ slice is
 * inlined into checkpoint-simulator.html; it uses the inlined core and the
 * embedded SCENARIOS / LEAN_CORPUS and must not touch the DOM.
 *
 * Stable exports: playStory, playChallenge, offersFor, dryRun, submit,
 * moveSlot, addEvidence, removeEvidence, selectPath, projectJson.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  newSession, addEvidence as sessionAddEvidence, removeEvidence as sessionRemoveEvidence,
  setSlot, attempt, checkScenario, liveOf, hashOf, closeIntent, actionKind, step,
  explain, consumable, isNat, CAST,
} from './checkpoint-simulator-core.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCENARIOS = readdirSync(join(HERE, 'checkpoint-simulator-scenarios'))
  .filter(f => f.endsWith('.json')).sort()
  .map(f => JSON.parse(readFileSync(join(HERE, 'checkpoint-simulator-scenarios', f), 'utf8')));
const LEAN_CORPUS = JSON.parse(readFileSync(join(HERE, 'checkpoint-simulator-corpus.json'), 'utf8'));
const addEvidence = sessionAddEvidence;
const removeEvidence = sessionRemoveEvidence;

/* @@BACKEND@@ */
const DEFAULT_PARAMS = { D: 1000, B: 5, P: 2, W: 10 };
const WHO = { alice: 'Alice', hal: 'Hal', cora: 'Cora', mallory: 'Mallory', treasury: 'The treasury', friend: 'A sponsor', rival: 'A rival hunter', anyone: 'A sponsor', time: 'Time', you: 'You' };
const CHALLENGE_SPECS = {
  steal: { title: 'Steal the 1000', actor: 'mallory',
    env: [{ rotationTo: [0, 0, 1] }, { rotationTo: [1, 1, 2] }, { rotationTo: [2, 2, 3] }] },
};
function copyTree(tree) {
  return {
    family: tree.family, story: tree.story, challenge: tree.challenge, actor: tree.actor,
    cursor: tree.cursor, punch: tree.punch,
    nodes: tree.nodes.map(n => ({ ...n, children: n.children.slice(), branch: n.branch ? { ...n.branch } : n.branch })),
  };
}
function originTree(session, say, extra) {
  const node0 = { id: 0, parent: null, children: [], last: null, session, record: null, who: '', say, kind: 'origin', branch: null };
  return { family: 'checkpoint', story: null, challenge: null, actor: 'alice', cursor: 0, punch: null, nodes: [node0], ...extra };
}
function treeAddChild(tree, parentId, entry) {
  const nodes = tree.nodes.map(n => ({ ...n, children: n.children.slice(), branch: n.branch ? { ...n.branch } : n.branch }));
  const parent = nodes[parentId];
  if (!parent) throw new Error('unknown node ' + parentId);
  const id = nodes.length;
  const n = { id, parent: parentId, children: [], last: null, branch: null, ...entry };
  nodes.push(n);
  parent.children.push(id);
  parent.last = id;
  return { ...tree, nodes, cursor: id };
}
function sessionAt(tree, nodeId) {
  const id = nodeId === undefined || nodeId === null ? tree.cursor : nodeId;
  const n = tree.nodes[id];
  if (!n || !n.session) throw new Error('unknown node ' + id);
  return n.session;
}
function storyIdOf(sc) { return sc.id !== undefined && sc.id !== null ? sc.id : sc.story; }
function findScenario(storyId) {
  const want = String(storyId);
  return SCENARIOS.find(s => String(storyIdOf(s)) === want) || null;
}
function buildStoryTree(sc) {
  const r = checkScenario(sc, 'story ' + storyIdOf(sc), LEAN_CORPUS);
  let tree = originTree(newSession(sc.params, { corpus: LEAN_CORPUS }),
    'Nothing on chain for this AID. Step through the story with › ; ⋔ chips switch branch.',
    { story: storyIdOf(sc), actor: 'alice' });
  const entry = (t, extra) => ({ session: t.session, record: t.record, who: WHO[t.step.who] || t.step.who,
    say: t.step.say + (t.step.slot !== undefined ? ` (slot ${t.step.slot})` : ''),
    kind: t.record ? 'story' : (t.step.evidence ? 'evidence' : 'time'),
    step: t.step, evRow: t.step.evidence && t.step.evidence.add ? t.step.evidence.add[0] : null, ...extra });
  const trunkIds = [0];
  let pid = 0;
  for (const t of r.timeline) {
    if (t.step.hidden) { trunkIds.push(pid); continue; }
    tree = treeAddChild(tree, pid, entry(t));
    pid = tree.cursor;
    trunkIds.push(pid);
  }
  let punch = Number.isInteger(sc.punchline) && trunkIds[sc.punchline + 1] !== undefined ? trunkIds[sc.punchline + 1] : null;
  if (punch === null) for (const id of trunkIds) { const n = tree.nodes[id]; if (n.record && n.record.ok) punch = id; }
  for (const fk of r.forks) {
    let fid = trunkIds[fk.at + 1];
    fk.timeline.forEach((t, i) => {
      tree = treeAddChild(tree, fid, entry(t, i === 0 ? { branch: { id: fk.id, title: fk.title } } : {}));
      fid = tree.cursor;
    });
  }
  for (let i = 0; i + 1 < trunkIds.length; i++) tree.nodes[trunkIds[i]].last = trunkIds[i + 1];
  const end = tree.nodes[trunkIds[trunkIds.length - 1]];
  end.trunkEnd = true;
  end.last = null;
  if (r.problems.length) tree.nodes[0].say = 'This story does not play as written: ' + r.problems.join(' · ');
  tree.cursor = 0;
  tree.punch = punch;
  tree.storySc = sc;
  return tree;
}
function playLoadedScenario(sc) { return buildStoryTree(sc); }
function playStory(storyId) {
  const sc = findScenario(storyId);
  if (!sc) throw new Error('unknown story ' + storyId);
  return buildStoryTree(sc);
}
function playChallenge(challengeId) {
  const c = CHALLENGE_SPECS[challengeId];
  if (!c) throw new Error('unknown challenge ' + challengeId);
  let sess = newSession(DEFAULT_PARAMS, { corpus: LEAN_CORPUS });
  for (const r of c.env) sess = addEvidence(sess, r);
  return originTree(sess, 'Nothing on chain for this AID. ★ ' + c.title + ': every move below is yours to try.',
    { challenge: challengeId, actor: c.actor });
}
function reopenSn(sess) {
  const c = hashOf(sess.state); if (!c) return 1;
  const cands = sess.env.rotationTo.filter(r => r[0] === c.epoch && r[1] === c.sn && r[2] > c.sn).map(r => r[2]).sort((a, b) => a - b);
  return cands.length ? cands[0] : c.sn + 1;
}
function nextSn(sn0) {
  const l = liveOf(sn0.state);
  if (!l) return 1;
  const cands = sn0.env.rotationTo.filter(r => r[0] === l.epoch && r[1] === l.sn && r[2] > l.sn).map(r => r[2]).sort((a, b) => a - b);
  return cands.length ? cands[0] : l.sn + 1;
}
function offersFor(actorId, tree, nodeId) {
  const sess = sessionAt(tree, nodeId);
  const l = liveOf(sess.state);
  const e = l ? l.epoch : 0, sn = l ? l.sn : 0, sn2 = nextSn(sess);
  const keri = [], chain = [];
  const ev = (label, row, hint) => keri.push({ label, row, hint });
  const act = (kind, label, action) => chain.push({ kind, label, action });
  const hs = hashOf(sess.state);
  const ke = hs ? hs.epoch : e, ksn = hs ? hs.sn : sn;
  switch (actorId) {
    case 'alice':
      if (hs) ev('kli rotate from the parked key state: sn ' + hs.sn + ' → ' + (hs.sn + 1) + ', receipted by the witnesses', { rotationTo: [hs.epoch, hs.sn, hs.sn + 1] }, 'a witnessed rotation from exactly the key state the leaf holds, later than its sequence');
      else ev('kli rotate: sn ' + sn + ' → ' + (sn + 1) + ', receipted by the witnesses', { rotationTo: [e, sn, sn + 1] }, 'a valid witnessed rotation from the current keys');
      ev('my next keys sign: keep the bonds, refund address → 1 (Alice)', { intentAuthorized: [e + 1, 'keep', 1] }, 'the keys the rotation reveals sign the intent and the address (D-038)');
      ev('my next keys sign: deposit (unfreeze)', { intentAuthorized: [e + 1, 'deposit', null] }, 'the keys the rotation reveals sign the deposit (D-038)');
      ev('my next keys sign: leave, premium to me', { intentAuthorized: [e + 1, closeIntent(1), null] }, 'the keys the rotation reveals sign the close, its payee and the address (D-036, D-038, D-039)');
      ev('my next keys sign: leave, premium to Hal', { intentAuthorized: [e + 1, closeIntent(2), null] }, 'the reap can be landed by a hunter: the message names who is paid');
      ev('key holders sign at threshold (quorum, epoch ' + e + ')', { quorum: [e] }, 'the current quorum signs a Cardano-side preimage');
      act('rotate', 'land my rotation, keep the bonds', { rotate: { "sn'": sn2, op: 'keep', payee: 1, "refund'": null } });
      act('rotate', 'land my rotation, deposit (unfreeze; on full bonds a keep)', { rotate: { "sn'": sn2, op: 'deposit', payee: 1, "refund'": null } });
      act('poison', 'poison this epoch', 'poison');
      act('close', 'leave: my rotation as the reap — the premium to me, everything else to my refund address, the token burned, the leaf parked with the hash', { close: { "sn'": sn2, payee: 1, "refund'": null } });
      act('topUp', 'add to my pool', { topUp: { x: 5 } });
      act('register', 'register my inception (refund to me)', { register: { refund: 1, pool0: 10 } });
      act('reopen', 'revive my parked identity with a rotation from its key state (refund to me)', { reopen: { "sn'": reopenSn(sess), refund: 1, pool0: 10 } });
      break;
    case 'hal':
      act('rotate', 'land Alice’s rotation, paid P to Hal', { rotate: { "sn'": sn2, op: 'keep', payee: 2, "refund'": null } });
      act('close', 'land her reap, paid P to Hal (needs her signed message naming me)', { close: { "sn'": sn2, payee: 2, "refund'": null } });
      act('freeze', 'freeze her on the old keys, take B', { freeze: { "sn'": sn2, payee: 2 } });
      act('reopen', 'revive her from the registry with her later public rotation (refund to Alice)', { reopen: { "sn'": reopenSn(sess), refund: 1, pool0: 10 } });
      break;
    case 'cora':
      ev('obtain a second receipted rotation at sequence ' + ksn + (hs ? ' (the parked key state)' : ''), { duplicityAt: [ke, ksn] }, 'two rotations at the key state’s sequence, both receipted');
      act('convict', hs ? 'convict the parked identity: the mark, nothing to seize' : 'convict, D to Cora', { convict: { payee: 3 } });
      break;
    case 'mallory':
      ev('steal the current keys (sign as quorum, epoch ' + ke + ')', { quorum: [ke] }, 'with the current keys she signs at threshold');
      ev('steal the next keys too (rotate ' + ksn + ' → ' + (ksn + 1) + ')', { rotationTo: [ke, ksn, ksn + 1] }, 'control by KERI’s own rule');
      act('poison', 'poison with the stolen keys', 'poison');
      act('close', 'reap with the stolen keys, premium to Mallory: the bonds still go to Alice’s refund address', { close: { "sn'": sn2, payee: 4, "refund'": null } });
      act('close', 'copy Hal’s reap with myself as payee', { close: { "sn'": sn2, payee: 4, "refund'": null } });
      ev('forge the close message with the stolen next keys (payee Mallory)', { intentAuthorized: [ke + 1, closeIntent(4), null] }, 'with the next keys she can sign the message too');
      act('rotate', 'rotate with the stolen next keys, paid to Mallory', { rotate: { "sn'": sn2, op: 'keep', payee: 4, "refund'": null } });
      act('register', 'register Alice’s inception myself, at an epoch whose keys I hold (refund to Mallory)', { register: { refund: 4, pool0: 10 } });
      act('reopen', 'revive her parked identity to myself (needs a rotation from the parked key state)', { reopen: { "sn'": reopenSn(sess), refund: 4, pool0: 10 } });
      break;
    case 'anyone':
      act('register', 'register her inception for her (refund to Alice)', { register: { refund: 1, pool0: 10 } });
      act('register', 'register her inception, refund to myself (a donation at her first rotation)', { register: { refund: 6, pool0: 10 } });
      act('topUp', 'top up her pool', { topUp: { x: 5 } });
      act('reopen', 'revive her parked identity for her (refund to Alice)', { reopen: { "sn'": reopenSn(sess), refund: 1, pool0: 10 } });
      break;
  }
  return { keri, chain };
}
function dryRun(tree, action, nodeId) {
  const sess = sessionAt(tree, nodeId);
  const r = step(sess.params, sess.env, action, sess.now, sess.state);
  if (r.ok) return { ok: true, res: r };
  const rec = { ok: false, reason: r.reason, field: r.field, kind: actionKind(action), action, pre: sess.state, slot: sess.now, now: sess.now };
  return { ok: false, res: r, why: explain(rec, sess) };
}
function opResult(tree, ok, extra) {
  return { tree, ok, cursor: tree.cursor, ...extra };
}
function submit(tree, actorId, action, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  t.cursor = at;
  const sess = t.nodes[at].session;
  const out = attempt(sess, action, sess.now);
  const who = (typeof CAST !== 'undefined' && CAST[actorId] && CAST[actorId].name) || WHO[actorId] || actorId;
  const next = treeAddChild(t, at, {
    session: out.session, record: out.record, who, actorId,
    say: (actionKind(action) || 'action') + ' at slot ' + sess.now + '.', kind: 'free',
  });
  next.actor = actorId || t.actor;
  return opResult(next, !!out.record.ok, { record: out.record, node: next.nodes[next.cursor] });
}
function moveSlot(tree, targetSlot, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  const sess = t.nodes[at].session;
  const mv = setSlot(sess, targetSlot);
  if (!mv.ok) return opResult(t, false, { reason: mv.reason });
  if (targetSlot === sess.now) return opResult(t, true);
  const next = treeAddChild(t, at, { session: mv.session, record: null, who: 'Time', say: `Slot ${targetSlot}.`, kind: 'time' });
  return opResult(next, true);
}
function treeAddEvidence(tree, evidenceRow, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  const sess = t.nodes[at].session;
  let nextSess;
  try { nextSess = addEvidence(sess, evidenceRow); }
  catch (e) { return opResult(t, false, { reason: 'invalid-evidence' }); }
  const next = treeAddChild(t, at, {
    session: nextSess, record: null, who: 'You',
    say: 'Evidence added: ' + JSON.stringify(evidenceRow) + '.', kind: 'evidence', evRow: evidenceRow,
  });
  return opResult(next, true);
}
function treeRemoveEvidence(tree, evidenceRow, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  const sess = t.nodes[at].session;
  let nextSess;
  try { nextSess = removeEvidence(sess, evidenceRow); }
  catch (e) { return opResult(t, false, { reason: 'invalid-evidence' }); }
  const next = treeAddChild(t, at, {
    session: nextSess, record: null, who: 'You',
    say: 'Evidence removed: ' + JSON.stringify(evidenceRow) + '.', kind: 'evidence', evRow: evidenceRow, removed: true,
  });
  return opResult(next, true);
}
function selectPath(tree, forkId, toEnd) {
  const t = copyTree(tree);
  if (forkId !== undefined && forkId !== null && forkId !== '') {
    const start = t.nodes.find(n => n.branch && String(n.branch.id) === String(forkId));
    if (!start) throw new Error('unknown fork ' + forkId);
    let id = start.id;
    if (toEnd) {
      while (t.nodes[id].children.length) {
        const n = t.nodes[id];
        const nx = n.last !== null ? n.last : n.children[0];
        n.last = nx;
        id = nx;
      }
    }
    for (let n = id; t.nodes[n].parent !== null; n = t.nodes[n].parent) t.nodes[t.nodes[n].parent].last = n;
    t.cursor = id;
    return t;
  }
  let id = 0;
  if (toEnd) {
    for (;;) {
      const n = t.nodes[id];
      if (!n.children.length || n.trunkEnd) break;
      const nx = n.last !== null ? n.last : n.children[0];
      if (nx === null || nx === undefined) break;
      id = nx;
    }
  }
  t.cursor = id;
  return t;
}
function selectedFork(tree) {
  for (let id = tree.cursor; id !== null && tree.nodes[id]; id = tree.nodes[id].parent) {
    if (tree.nodes[id].branch && tree.nodes[id].branch.id) return tree.nodes[id].branch.id;
  }
  return null;
}
function branchAt(tree, id) {
  for (let n = id; n !== null && tree.nodes[n]; n = tree.nodes[n].parent) {
    if (tree.nodes[n].branch) return tree.nodes[n].branch;
  }
  return null;
}
function compactLamps(rec) {
  if (!rec) return null;
  const src = rec.lamps || rec.theorems;
  if (!src) return null;
  const out = {};
  for (const id of Object.keys(src)) {
    const x = src[id];
    if (!x) continue;
    if (x.exhibited) out[id] = { exhibited: true, holds: !!x.holds };
    else if (x.v === 'holds' || x.v === 'fails') out[id] = { exhibited: true, holds: x.v === 'holds' };
  }
  return Object.keys(out).length ? out : null;
}
function projectJson(tree) {
  const t = copyTree(tree);
  const ids = [];
  for (let n = t.cursor; n !== null && t.nodes[n]; n = t.nodes[n].parent) ids.unshift(n);
  const path = ids.map(id => {
    const n = t.nodes[id], rec = n.record, sess = n.session;
    let verdict = null;
    try { if (sess) verdict = consumable(sess.params, sess.now, sess.state).verdict; } catch (e) { verdict = null; }
    return {
      id: n.id, parent: n.parent, kind: n.kind, branch: branchAt(t, n.id), slot: sess ? sess.now : null,
      who: n.who, say: n.say, action: rec ? rec.action : undefined, ok: rec ? rec.ok : null,
      reason: rec && rec.reason ? rec.reason : undefined,
      flow: rec && rec.flow, state: sess ? sess.state : null, verdict,
      lamps: compactLamps(rec),
    };
  });
  return {
    family: t.family, story: t.story, challenge: t.challenge, fork: selectedFork(t),
    cursor: t.cursor, path,
  };
}
/* @@BACKEND:END@@ */

export {
  playStory, playChallenge, offersFor, dryRun, submit, moveSlot,
  treeAddEvidence as addEvidence, treeRemoveEvidence as removeEvidence,
  selectPath, projectJson, playLoadedScenario,
};
