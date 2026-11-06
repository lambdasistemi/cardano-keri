#!/usr/bin/env node
// Generates the freeze cases of the Lean checkpoint corpus, for both layers:
//   onchain/validators/checkpoint_register_freeze_corpus_tests.ak
//   offchain/test/Cardano/KERI/AID/Checkpoint/FreezeCorpus.hs
// from simulator/checkpoint-simulator-corpus.json (the boundary grid that
// `lean/CheckpointTraceDriver.lean` prints: every state against every action
// under two oracles).
//
//   node scripts/checkpoint-freeze-vectors.mjs            # write the modules
//   node scripts/checkpoint-freeze-vectors.mjs --check    # exit 1 when a module drifts
//
// A cell is kept when its action is `freeze`. Its expected verdict is the
// Lean's: `result: null` is a refusal, anything else is an accepted step, and
// an accepted step's state and flow are checked here against the model's own
// clause (the successor is the same live state frozen; the hunter receives
// exactly the freeze bond B).
//
// Mapping of the Lean values onto the ledger values (restated in each header):
//   present state l             a live version 2 datum: `poisoned`, `frozen`, `toppedUp`
//   l.pool (Lean units)         lovelace: pool x 1,000,000 (P = 2, B = 5, D = 1000)
//   sn' against l.sn            earlier / equal / later; the later case is the
//                               genuine witnessed rotation, the other two
//                               re-label the spent checkpoint so that rotation
//                               is not later than it
//   env.rotationTo (epoch, sn, sn')  the rotation is evidenced; when absent the
//                               evidence carries no signature and no receipt
//   terminationPending          a termination-pending datum
//   absent, convicted           no checkpoint output exists to spend: not
//                               realizable as a transaction, counted and skipped
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const input = resolve(root, 'simulator/checkpoint-simulator-corpus.json');
const aikenOut = resolve(root, 'onchain/validators/checkpoint_register_freeze_corpus_tests.ak');
const haskellOut = resolve(root, 'offchain/test/Cardano/KERI/AID/Checkpoint/FreezeCorpus.hs');

const corpus = JSON.parse(readFileSync(input, 'utf8'));
const { params, grid } = corpus;
if (JSON.stringify(Object.keys(params).sort()) !== JSON.stringify(['B', 'D', 'P', 'W'])) throw new Error('corpus params changed');
if (params.P !== 2 || params.B !== 5 || params.D !== 1000) throw new Error(`the fixture amounts assume P=2, B=5, D=1000; the corpus has ${JSON.stringify(params)}`);

const bool = (b) => (b ? 'True' : 'False');
const hsBool = (b) => (b ? 'True' : 'False');

const freezeAction = (a) => (typeof a === 'object' && a !== null && 'freeze' in a ? a.freeze : null);
const actionsByIndex = grid.actions.map(freezeAction);
if (actionsByIndex.every((a) => a === null)) throw new Error('the corpus grid has no freeze action');

// The model's own clause for an accepted freeze, restated and compared to the
// corpus's recorded result.
const sameLive = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// The top-up mark does not decide a freeze: the Lean gives a topped-up state
// the verdict of the same state not topped up, and an accepted freeze keeps the
// mark. Both are asserted below for every topped-up cell, which is then emitted
// like any other.
const unmarked = (s) => (typeof s === 'object' && s !== null && 'present' in s ? { present: { l: { ...s.present.l, toppedUp: false } } } : s);
const cellAt = (s, a, e) => grid.cells.find((c) => c.s === s && c.a === a && c.e === e);
const cells = [];
const skipped = [];
let markedEmitted = 0;
let accepted = 0;
let refused = 0;
for (const cell of grid.cells) {
  const act = actionsByIndex[cell.a];
  if (act === null) continue;
  const state = grid.states[cell.s];
  const env = grid.envs[cell.e];
  if (typeof state === 'object' && 'present' in state && state.present.l.toppedUp === true) {
    const twin = grid.states.findIndex((s) => JSON.stringify(s) === JSON.stringify(unmarked(state)));
    const other = twin < 0 ? undefined : cellAt(twin, cell.a, cell.e);
    if (!other) throw new Error(`topped-up cell ${cell.s}/${cell.a}/${cell.e} has no cell for the same state not topped up`);
    if ((cell.result === null) !== (other.result === null)) throw new Error(`topped-up cell ${cell.s}/${cell.a}/${cell.e}: the top-up mark changes the freeze verdict`);
    if (cell.result !== null && cell.result.state.present.l.toppedUp !== true) throw new Error(`topped-up cell ${cell.s}/${cell.a}/${cell.e}: a freeze cleared the top-up mark`);
    markedEmitted += 1;
  }
  if (state === 'absent' || state === 'convicted') {
    skipped.push(`${typeof state === 'string' ? state : 'state'} state ${cell.s}, sn' ${act["sn'"]}, env ${cell.e}`);
    continue;
  }
  const snPrime = act["sn'"];
  const isPending = typeof state === 'object' && 'terminationPending' in state;
  const live = isPending ? null : state.present.l;
  const hash = isPending ? state.terminationPending.h : { epoch: live.epoch, sn: live.sn };
  const evidenced = env.rotationTo.some(([e, s, n]) => e === hash.epoch && s === hash.sn && n === snPrime);
  const verdict = cell.result !== null;
  // The model's guards, recomputed from the cell alone: the corpus must say
  // what the Lean's `freeze` clause says.
  const expected = !isPending && evidenced && live.sn < snPrime && live.pool < params.P && live.frozen === false && live.poisoned === false;
  if (expected !== verdict) throw new Error(`cell ${JSON.stringify(cell)} disagrees with the freeze clause`);
  if (verdict) {
    const { flow, state: after } = cell.result;
    if (!sameLive(after, { present: { l: { ...live, frozen: true } } })) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: successor is not the same live state frozen`);
    if (!flow.hunter || flow.hunter.b !== params.B || flow.hunter.pool !== 0 || flow.hunter.dreg !== 0) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: the hunter does not receive exactly B`);
    if (flow.bIn !== 0 || flow.poolIn !== 0 || flow.dregIn !== 0 || flow.refund !== null || flow.convictor !== null) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: a freeze moves value other than the hunter's bond`);
  }
  const relation = snPrime < hash.sn ? -1 : snPrime === hash.sn ? 0 : 1;
  cells.push({
    name: `cell_${isPending ? 'pending' : 'present'}_s${cell.s}_sn${snPrime}_${evidenced ? 'rotation' : 'norotation'}`,
    stateIndex: cell.s,
    pending: isPending,
    poisoned: isPending ? false : live.poisoned,
    frozen: isPending ? false : live.frozen,
    toppedUp: isPending ? false : live.toppedUp,
    pool: isPending ? 0 : live.pool,
    snPrime,
    relation,
    evidenced,
    verdict,
  });
  if (verdict) accepted += 1;
  else refused += 1;
}

// Non-vacuity: the grid is 24 live states (12 with the top-up mark set) and 1
// pending, three requested sequence numbers, two oracles; both verdicts occur,
// and the accepted cells are exactly the ones with a short pool, unfrozen,
// unpoisoned, a later sequence number and the rotation evidenced (one pool
// value x one sn' x one oracle), with the mark clear and with the mark set.
if (cells.length !== 150) throw new Error(`expected 150 realizable freeze cells, found ${cells.length}`);
if (markedEmitted !== 72) throw new Error(`expected 72 topped-up freeze cells, found ${markedEmitted}`);
if (skipped.length !== 12) throw new Error(`expected 12 unrealizable freeze cells, found ${skipped.length}`);
if (accepted !== 2) throw new Error(`expected exactly 2 accepted freeze cells, found ${accepted}`);
if (refused !== 148) throw new Error(`expected 148 refused freeze cells, found ${refused}`);
const names = new Set(cells.map((c) => c.name));
if (names.size !== cells.length) throw new Error('cell names are not unique');

// ---------------------------------------------------------------------
// The Aiken module
// ---------------------------------------------------------------------
const aikenCell = (c) => {
  const call = c.pending
    ? `corpus_freeze_pending(${bool(c.evidenced)})`
    : `corpus_freeze(${bool(c.poisoned)}, ${bool(c.frozen)}, ${bool(c.toppedUp)}, ${c.pool}, ${c.relation}, ${bool(c.evidenced)})`;
  const what = c.pending
    ? `termination pending`
    : `live, poisoned ${bool(c.poisoned)}, frozen ${bool(c.frozen)}, topped up ${bool(c.toppedUp)}, pool ${c.pool}`;
  return `/// Lean grid state ${c.stateIndex} (${what}) x freeze(sn' = ${c.snPrime}) x ${c.evidenced ? 'the rotation evidenced' : 'no rotation evidenced'}: ${c.verdict ? 'accepted' : 'refused'}.
test ${c.name}()${c.verdict ? '' : ' fail'} {
  run(${call})
}
`;
};

const aiken = `//// GENERATED by scripts/checkpoint-freeze-vectors.mjs from
//// simulator/checkpoint-simulator-corpus.json. DO NOT EDIT.
//// \`just check-checkpoint-freeze-vectors\` regenerates and rejects drift.
////
//// The freeze cells of the Lean corpus's boundary grid (parameters \`P = ${params.P}\`,
//// \`B = ${params.B}\`, \`D = ${params.D}\`), one test per cell: every live state
//// (poisoned, frozen and the top-up mark each clear and set, the pool at one below, exactly and one above
//// the premium), the termination-pending state, a requested sequence number
//// earlier than, equal to and later than the state's, under an oracle that
//// evidences the rotation and one that does not. A refused cell is a \`fail\`
//// test, an accepted cell passes.
////
//// Mapping of the Lean values onto the ledger values:
////   live state              a live version 2 datum with that poisoned / frozen
////   pool (Lean units)       lovelace: pool x 1,000,000 (premium 2,000,000, bond 5,000,000)
////   sn' against the state's sn
////                           earlier / equal / later: the later case is the genuine
////                           witnessed rotation; the other two re-label the spent
////                           checkpoint so that rotation is not later than it
////   rotationTo evidenced    the rotation evidence; when it is not, the evidence
////                           carries no signature and no receipt
////   termination pending     a termination-pending datum
////   absent, convicted       no checkpoint output to spend: ${skipped.length} cells, not realizable
////                           as a transaction

use cardano/transaction.{Transaction}
use checkpoint_observer
use checkpoint_register
use freeze_fixture.{
  Freeze, advance_hash, corpus_freeze, corpus_freeze_pending, d_reg,
  enforcement_hash, entitlement_hash, freeze_bond, freeze_redeemer,
  lifecycle_hash, migration_hash, network_id, premium, spent_ref,
}

fn run_spend(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    None,
    redeemer,
    spent_ref(),
    tx,
  )
}

fn run(f: Freeze) -> Bool {
  run_spend(freeze_redeemer(f.hunter_output_index), f.tx) && checkpoint_observer.observer_advance.withdraw(
    0,
    f.observed,
    0,
    f.tx,
  )
}

${cells.map(aikenCell).join('\n')}`;

// ---------------------------------------------------------------------
// The Haskell module
// ---------------------------------------------------------------------
const hsCell = (c) => `    , CorpusCell
        { ccName = "${c.name}"
        , ccPending = ${hsBool(c.pending)}
        , ccPoisoned = ${hsBool(c.poisoned)}
        , ccFrozen = ${hsBool(c.frozen)}
        , ccToppedUp = ${hsBool(c.toppedUp)}
        , ccPool = ${c.pool}
        , ccSnRelation = ${c.relation}
        , ccRotationEvidenced = ${hsBool(c.evidenced)}
        , ccAccepted = ${hsBool(c.verdict)}
        }`;

const haskell = `{- |
Module      : Cardano.KERI.AID.Checkpoint.FreezeCorpus
Description : The freeze cells of the Lean checkpoint corpus

GENERATED by scripts/checkpoint-freeze-vectors.mjs from
simulator/checkpoint-simulator-corpus.json. DO NOT EDIT.
\`just check-checkpoint-freeze-vectors\` regenerates and rejects drift.

The same ${cells.length} cells the Aiken module
@checkpoint_register_freeze_corpus_tests@ runs: parameters @P = ${params.P}@,
@B = ${params.B}@, @D = ${params.D}@, every live state, the pending state, a requested
sequence number earlier than, equal to and later than the state's, under an
oracle that evidences the rotation and one that does not. Pools are in Lean
units; the expected verdict is the Lean's.
-}
module Cardano.KERI.AID.Checkpoint.FreezeCorpus (
    CorpusCell (..),
    corpusP,
    corpusB,
    corpusCells,
) where

-- | One freeze cell.
data CorpusCell = CorpusCell
    { ccName :: String
    , ccPending :: Bool
    -- ^ the state is a termination pending
    , ccPoisoned :: Bool
    , ccFrozen :: Bool
    , ccToppedUp :: Bool
    -- ^ the top-up mark of the live state; a freeze keeps it
    , ccPool :: Integer
    -- ^ the Lean pool, in Lean units
    , ccSnRelation :: Int
    -- ^ the requested sequence number against the state's: -1, 0 or 1
    , ccRotationEvidenced :: Bool
    , ccAccepted :: Bool
    }
    deriving stock (Show, Eq)

-- | The Lean premium @P@, in Lean units.
corpusP :: Integer
corpusP = ${params.P}

-- | The Lean freeze bond @B@, in Lean units.
corpusB :: Integer
corpusB = ${params.B}

corpusCells :: [CorpusCell]
corpusCells =
${cells.map((c, i) => (i === 0 ? '    [ ' + hsCell(c).slice(6) : hsCell(c))).join('\n')}
    ]
`;

const outputs = [[aikenOut, aiken], [haskellOut, haskell]];
if (process.argv.includes('--check')) {
  let drift = false;
  for (const [path, text] of outputs) {
    let current = '';
    try { current = readFileSync(path, 'utf8'); } catch { /* absent */ }
    if (current !== text) { console.error(`drift: ${path}`); drift = true; }
  }
  if (drift) process.exit(1);
  console.log(`freeze corpus modules up to date (${cells.length} cells: ${accepted} accepted, ${refused} refused, ${skipped.length} unrealizable)`);
} else {
  for (const [path, text] of outputs) writeFileSync(path, text);
  console.log(`wrote ${cells.length} freeze cells (${accepted} accepted, ${refused} refused, ${skipped.length} unrealizable)`);
}
