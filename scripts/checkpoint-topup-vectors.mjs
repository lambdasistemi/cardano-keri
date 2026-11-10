#!/usr/bin/env node
// Generates the top-up and registration cells of the Lean checkpoint corpus,
// for both layers:
//   onchain/validators/checkpoint_register_topup_corpus_tests.ak
//   offchain/test/Cardano/KERI/AID/Checkpoint/TopUpCorpus.hs
// from simulator/checkpoint-simulator-corpus.json (the boundary grid that
// `lean/CheckpointTraceDriver.lean` prints: every state against every action
// under two oracles).
//
//   node scripts/checkpoint-topup-vectors.mjs            # write the modules
//   node scripts/checkpoint-topup-vectors.mjs --check    # exit 1 when a module drifts
//
// A cell is kept when its action is `topUp` (any present or pending state) or
// `register` (from the absent state). Its expected verdict is the Lean's:
// `result: null` is a refusal, anything else is an accepted step. The verdict
// is recomputed here from the model's own guards (`Step.topUp`: the mark is
// clear and the amount is at least P; `Step.register`: the first pool is at
// least P), and an accepted step's state and flow are checked against the
// model's own clause.
//
// Mapping of the Lean values onto the ledger values (restated in each header):
//   present state l             a live version 2 datum: `poisoned`, `frozen`, `toppedUp`
//   l.pool (Lean units)         lovelace: pool x 1,000,000 (P = 2, B = 5, D = 1000)
//   topUp x                     the redeemer's amount: x x 1,000,000 lovelace
//   register pool0              the carrier holds the floor plus pool0 x 1,000,000
//   terminationPending          a termination-pending datum
//   absent, convicted           no checkpoint output exists to spend: not
//                               realizable as a top-up transaction, counted and
//                               skipped; a registration is realizable only from
//                               absent
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const input = resolve(root, 'simulator/checkpoint-simulator-corpus.json');
const aikenOut = resolve(root, 'onchain/validators/checkpoint_register_topup_corpus_tests.ak');
const haskellOut = resolve(root, 'offchain/test/Cardano/KERI/AID/Checkpoint/TopUpCorpus.hs');

const corpus = JSON.parse(readFileSync(input, 'utf8'));
const { params, grid } = corpus;
if (JSON.stringify(Object.keys(params).sort()) !== JSON.stringify(['B', 'D', 'P', 'W'])) throw new Error('corpus params changed');
if (params.P !== 2 || params.B !== 5 || params.D !== 1000) throw new Error(`the fixture amounts assume P=2, B=5, D=1000; the corpus has ${JSON.stringify(params)}`);

const bool = (b) => (b ? 'True' : 'False');
const kindOf = (a, key) => (typeof a === 'object' && a !== null && key in a ? a[key] : null);
const topUps = grid.actions.map((a) => kindOf(a, 'topUp'));
const registers = grid.actions.map((a) => kindOf(a, 'register'));
if (topUps.every((a) => a === null)) throw new Error('the corpus grid has no topUp action');
if (registers.every((a) => a === null)) throw new Error('the corpus grid has no register action');

const sameLive = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const isAbsent = (s) => s === 'absent';
const isConvicted = (s) => s === 'convicted';
const isPending = (s) => typeof s === 'object' && s !== null && 'terminationPending' in s;
const isPresent = (s) => typeof s === 'object' && s !== null && 'present' in s;

// ---------------------------------------------------------------------
// The top-up cells
// ---------------------------------------------------------------------
const topupCells = [];
const topupSkipped = [];
let topupAccepted = 0;
let topupRefused = 0;
for (const cell of grid.cells) {
  const act = topUps[cell.a];
  if (act === null) continue;
  const state = grid.states[cell.s];
  if (isAbsent(state) || isConvicted(state)) {
    topupSkipped.push(`${state} state ${cell.s}, x ${act.x}, env ${cell.e}`);
    continue;
  }
  const pending = isPending(state);
  const live = pending ? null : state.present.l;
  const verdict = cell.result !== null;
  // The model's guards, recomputed from the cell alone.
  const expected = !pending && live.toppedUp === false && params.P <= act.x;
  if (expected !== verdict) throw new Error(`cell ${JSON.stringify(cell)} disagrees with the topUp clause`);
  if (verdict) {
    const { flow, state: after } = cell.result;
    if (!sameLive(after, { present: { l: { ...live, pool: live.pool + act.x, toppedUp: true } } })) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: successor is not the same live state, grown and marked`);
    if (flow.poolIn !== act.x || flow.bIn !== 0 || flow.dregIn !== 0 || flow.hunter !== null || flow.refund !== null || flow.convictor !== null) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: a top-up moves value other than the amount into the pool`);
  }
  topupCells.push({
    name: `cell_topup_${pending ? 'pending' : 'present'}_s${cell.s}_x${act.x}_e${cell.e}`,
    stateIndex: cell.s,
    env: cell.e,
    pending,
    poisoned: pending ? false : live.poisoned,
    frozen: pending ? false : live.frozen,
    marked: pending ? false : live.toppedUp,
    pool: pending ? 0 : live.pool,
    amount: act.x,
    verdict,
  });
  if (verdict) topupAccepted += 1;
  else topupRefused += 1;
}

// Non-vacuity: 24 live states and 1 pending, three amounts, two oracles; the
// accepted cells are exactly the fresh live states with an amount of at least
// P (12 states x 2 amounts x 2 oracles); the oracle never changes a verdict.
if (topupCells.length !== 150) throw new Error(`expected 150 realizable top-up cells, found ${topupCells.length}`);
if (topupSkipped.length !== 12) throw new Error(`expected 12 unrealizable top-up cells, found ${topupSkipped.length}`);
if (topupAccepted !== 48) throw new Error(`expected exactly 48 accepted top-up cells, found ${topupAccepted}`);
if (topupRefused !== 102) throw new Error(`expected 102 refused top-up cells, found ${topupRefused}`);
if (new Set(topupCells.map((c) => c.name)).size !== topupCells.length) throw new Error('top-up cell names are not unique');
for (const c of topupCells) {
  const twin = topupCells.find((d) => d.stateIndex === c.stateIndex && d.amount === c.amount && d.env !== c.env);
  if (!twin || twin.verdict !== c.verdict) throw new Error(`the oracle changes the verdict of ${c.name}`);
}
const markedAccepted = topupCells.filter((c) => c.marked && c.verdict).length;
if (markedAccepted !== 0) throw new Error('a marked state accepted a top-up');
if (topupCells.filter((c) => c.marked).length !== 72) throw new Error('expected 72 cells over the 12 marked states (12 states x 3 amounts x 2 oracles)');

// ---------------------------------------------------------------------
// The registration cells (from the absent state)
// ---------------------------------------------------------------------
const registerCells = [];
const registerSkipped = [];
let registerAccepted = 0;
let registerRefused = 0;
for (const cell of grid.cells) {
  const act = registers[cell.a];
  if (act === null) continue;
  const state = grid.states[cell.s];
  if (!isAbsent(state)) {
    registerSkipped.push(`state ${cell.s}, pool0 ${act.pool0}, env ${cell.e}`);
    continue;
  }
  const verdict = cell.result !== null;
  const expected = params.P <= act.pool0;
  if (expected !== verdict) throw new Error(`cell ${JSON.stringify(cell)} disagrees with the register clause`);
  if (verdict) {
    const { flow, state: after } = cell.result;
    const want = { present: { l: { bornAt: grid.now, epoch: 0, frozen: false, poisoned: false, pool: act.pool0, refundTo: act.refund, sn: 0, toppedUp: false } } };
    if (!sameLive(after, want)) throw new Error(`accepted register cell ${cell.s}/${cell.a}/${cell.e}: the registered state is not the funded zero state with the mark clear`);
    if (flow.poolIn !== act.pool0 || flow.bIn !== params.B || flow.dregIn !== params.D) throw new Error(`accepted register cell ${cell.s}/${cell.a}/${cell.e}: the registration does not bring D, B and the pool`);
  }
  registerCells.push({
    name: `cell_register_pool${act.pool0}_e${cell.e}`,
    env: cell.e,
    pool0: act.pool0,
    verdict,
  });
  if (verdict) registerAccepted += 1;
  else registerRefused += 1;
}
if (registerCells.length !== 6) throw new Error(`expected 6 realizable register cells, found ${registerCells.length}`);
if (registerAccepted !== 4 || registerRefused !== 2) throw new Error(`expected 4 accepted and 2 refused register cells, found ${registerAccepted} and ${registerRefused}`);
if (new Set(registerCells.map((c) => c.name)).size !== registerCells.length) throw new Error('register cell names are not unique');
if (registerSkipped.length !== 3 * 2 * (grid.states.length - 1)) throw new Error(`expected ${3 * 2 * (grid.states.length - 1)} unrealizable register cells, found ${registerSkipped.length}`);

// ---------------------------------------------------------------------
// The Aiken module
// ---------------------------------------------------------------------
const aikenTopup = (c) => {
  const call = c.pending
    ? `corpus_topup_pending(${c.amount})`
    : `corpus_topup(${bool(c.poisoned)}, ${bool(c.frozen)}, ${c.pool}, ${bool(c.marked)}, ${c.amount})`;
  const what = c.pending
    ? 'termination pending'
    : `live, poisoned ${bool(c.poisoned)}, frozen ${bool(c.frozen)}, pool ${c.pool}, topped up ${bool(c.marked)}`;
  return `/// Lean grid state ${c.stateIndex} (${what}) x topUp(x = ${c.amount}) x oracle ${c.env}: ${c.verdict ? 'accepted' : 'refused'}.
test ${c.name}()${c.verdict ? '' : ' fail'} {
  run(${call})
}
`;
};

const aiken = `//// GENERATED by scripts/checkpoint-topup-vectors.mjs from
//// simulator/checkpoint-simulator-corpus.json. DO NOT EDIT.
//// \`just check-checkpoint-topup-vectors\` regenerates and rejects drift.
////
//// The top-up cells of the Lean corpus's boundary grid
//// (parameters \`P = ${params.P}\`, \`B = ${params.B}\`, \`D = ${params.D}\`), one test per cell. A refused cell is a
//// \`fail\` test, an accepted cell passes.
////
//// Top-up: every live state (poisoned and frozen both ways, the pool at one
//// below, exactly and one above the premium, the top-up mark clear and set) and
//// the termination-pending state, against a top-up of 1, 2 and 5 units, under
//// two oracles. A top-up is accepted exactly when the mark is clear and the
//// amount is at least one premium; no oracle changes a verdict.
////
//// The registration cells of the same grid (a first pool of 1, 2 and 7 units)
//// are the registry fold's: the validator's own registration is retired, and the
//// fold's pool rule is the application's (its rows named fold-pool-below-premium).
////
//// Mapping of the Lean values onto the ledger values:
////   live state              a live version 2 datum with that poisoned / frozen / top-up mark
////   pool (Lean units)       lovelace: pool x 1,000,000 (premium 2,000,000, bond 5,000,000)
////   topUp x                 the redeemer's amount: x x 1,000,000 lovelace, and the
////                           successor holds exactly that much more
////   termination pending     a termination-pending datum
////   absent, convicted       no checkpoint output to spend: ${topupSkipped.length} top-up cells, not realizable
////                           as a transaction

use cardano/transaction.{Transaction}
use checkpoint_register
use freeze_fixture.{
  advance_hash, d_reg, enforcement_hash, entitlement_hash, freeze_bond,
  network_id, premium, spent_ref,
}
use registry_fixture.{registry_name, state_policy}
use topup_fixture.{TopUp, corpus_topup, corpus_topup_pending, topup_redeemer}

fn run_spend(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    state_policy(),
    registry_name(),
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

fn run(t: TopUp) -> Bool {
  run_spend(topup_redeemer(t.amount), t.tx)
}

${topupCells.map(aikenTopup).join('\n')}`;

// ---------------------------------------------------------------------
// The Haskell module
// ---------------------------------------------------------------------
const hsTopup = (c) => `    CorpusTopUp
        { tuName = "${c.name}"
        , tuPending = ${bool(c.pending)}
        , tuPoisoned = ${bool(c.poisoned)}
        , tuFrozen = ${bool(c.frozen)}
        , tuToppedUp = ${bool(c.marked)}
        , tuPool = ${c.pool}
        , tuAmount = ${c.amount}
        , tuAccepted = ${bool(c.verdict)}
        }`;
const hsRegister = (c) => `    CorpusRegister
        { rgName = "${c.name}"
        , rgPool0 = ${c.pool0}
        , rgAccepted = ${bool(c.verdict)}
        }`;
const hsList = (xs, render) => xs.map((x, i) => (i === 0 ? '    [ ' + render(x).slice(4) : '    , ' + render(x).slice(4))).join('\n');

const haskell = `{- |
Module      : Cardano.KERI.AID.Checkpoint.TopUpCorpus
Description : The top-up and registration cells of the Lean checkpoint corpus

GENERATED by scripts/checkpoint-topup-vectors.mjs from
simulator/checkpoint-simulator-corpus.json. DO NOT EDIT.
\`just check-checkpoint-topup-vectors\` regenerates and rejects drift.

The same ${topupCells.length} top-up cells and ${registerCells.length} registration cells the Aiken module
@checkpoint_register_topup_corpus_tests@ runs: parameters @P = ${params.P}@, @B = ${params.B}@,
@D = ${params.D}@, every live state (the top-up mark clear and set), the pending
state, a top-up of 1, 2 and 5 units, a first pool of 1, 2 and 7 units, under two
oracles. Amounts and pools are in Lean units; the expected verdict is the Lean's.
-}
module Cardano.KERI.AID.Checkpoint.TopUpCorpus (
    CorpusTopUp (..),
    CorpusRegister (..),
    corpusP,
    corpusTopUps,
    corpusRegisters,
) where

-- | One top-up cell.
data CorpusTopUp = CorpusTopUp
    { tuName :: String
    , tuPending :: Bool
    -- ^ the state is a termination pending
    , tuPoisoned :: Bool
    , tuFrozen :: Bool
    , tuToppedUp :: Bool
    -- ^ the top-up mark of the live state
    , tuPool :: Integer
    -- ^ the Lean pool, in Lean units
    , tuAmount :: Integer
    -- ^ the top-up amount, in Lean units
    , tuAccepted :: Bool
    }
    deriving stock (Show, Eq)

-- | One registration cell, from the absent state.
data CorpusRegister = CorpusRegister
    { rgName :: String
    , rgPool0 :: Integer
    -- ^ the first pool, in Lean units
    , rgAccepted :: Bool
    }
    deriving stock (Show, Eq)

-- | The Lean premium @P@, in Lean units.
corpusP :: Integer
corpusP = ${params.P}

corpusTopUps :: [CorpusTopUp]
corpusTopUps =
${hsList(topupCells, hsTopup)}
    ]

corpusRegisters :: [CorpusRegister]
corpusRegisters =
${hsList(registerCells, hsRegister)}
    ]
`;

const outputs = [[aikenOut, aiken], [haskellOut, haskell]];
const summary = `${topupCells.length} top-up cells (${topupAccepted} accepted, ${topupRefused} refused, ${topupSkipped.length} unrealizable), ${registerCells.length} register cells (${registerAccepted} accepted, ${registerRefused} refused)`;
if (process.argv.includes('--check')) {
  let drift = false;
  for (const [path, text] of outputs) {
    let current = '';
    try { current = readFileSync(path, 'utf8'); } catch { /* absent */ }
    if (current !== text) { console.error(`drift: ${path}`); drift = true; }
  }
  if (drift) process.exit(1);
  console.log(`top-up corpus modules up to date (${summary})`);
} else {
  for (const [path, text] of outputs) writeFileSync(path, text);
  console.log(`wrote ${summary}`);
}
