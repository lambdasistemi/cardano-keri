#!/usr/bin/env node
// Generates the deposit cells of the Lean checkpoint corpus, for both layers:
//   onchain/validators/checkpoint_register_deposit_corpus_tests.ak
//   offchain/test/Cardano/KERI/AID/Checkpoint/DepositCorpus.hs
// from simulator/checkpoint-simulator-corpus.json (the boundary grid that
// `lean/CheckpointTraceDriver.lean` prints: every state against every action
// under two oracles) and its trace `freeze-then-unfreeze`.
//
//   node scripts/checkpoint-deposit-corpus.mjs            # write the modules
//   node scripts/checkpoint-deposit-corpus.mjs --check    # exit 1 when a module drifts
//
// A cell is kept when its action is a rotation with the deposit option. Its
// expected verdict is the Lean's: `result: null` is a refusal, anything else is
// an accepted step, and an accepted step's state and flow are checked here
// against the model's own clause (`rotateDepositPaid`, `rotateDepositUnpaid`):
// the successor is the rotated state unfrozen and unpoisoned, the deposit moves
// `B - bHeld` into the output, and the premium goes to the payee exactly when
// the pool covers it.
//
// Mapping of the Lean values onto the ledger values (restated in each header):
//   present state l             a live version 2 datum: `poisoned`, `frozen`
//   l.pool (Lean units)         lovelace: pool x 1,000,000 (P = 2, B = 5, D = 1000)
//   sn' against l.sn            earlier / equal / later; the later case is the
//                               genuine witnessed rotation, the other two
//                               re-label the spent checkpoint so that rotation
//                               is not later than it
//   env.rotationTo (epoch, sn, sn')  the rotation is evidenced; when absent the
//                               evidence carries no signature and no receipt
//   env.depositAuthorized (epoch + 1) the new keys signed the intent the validator
//                               requires; when absent they signed another rotation's
//   terminationPending          a termination-pending datum
//   absent, convicted           no checkpoint output exists to spend: not
//                               realizable as a transaction, counted and skipped
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const input = resolve(root, 'simulator/checkpoint-simulator-corpus.json');
const aikenOut = resolve(root, 'onchain/validators/checkpoint_register_deposit_corpus_tests.ak');
const haskellOut = resolve(root, 'offchain/test/Cardano/KERI/AID/Checkpoint/DepositCorpus.hs');

const corpus = JSON.parse(readFileSync(input, 'utf8'));
const { params, grid } = corpus;
if (JSON.stringify(Object.keys(params).sort()) !== JSON.stringify(['B', 'D', 'P', 'W'])) throw new Error('corpus params changed');
if (params.P !== 2 || params.B !== 5 || params.D !== 1000) throw new Error(`the fixture amounts assume P=2, B=5, D=1000; the corpus has ${JSON.stringify(params)}`);

const bool = (b) => (b ? 'True' : 'False');

const depositAction = (a) => (typeof a === 'object' && a !== null && 'rotate' in a && a.rotate.op === 'deposit' ? a.rotate : null);
const actionsByIndex = grid.actions.map(depositAction);
if (actionsByIndex.every((a) => a === null)) throw new Error('the corpus grid has no deposit rotation');

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// The top-up mark does not decide a deposit rotation: the Lean gives a topped-up
// state the verdict of the same state not topped up, and an accepted deposit
// rotation clears the mark to the same successor. Both are asserted below for
// every topped-up cell, which is then emitted like any other.
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
    if ((cell.result === null) !== (other.result === null)) throw new Error(`topped-up cell ${cell.s}/${cell.a}/${cell.e}: the top-up mark changes the deposit verdict`);
    if (cell.result !== null && (!same(cell.result, other.result))) throw new Error(`topped-up cell ${cell.s}/${cell.a}/${cell.e}: a deposit rotation does not clear the top-up mark to the same successor`);
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
  const authorized = env.depositAuthorized.some(([e]) => e === hash.epoch + 1);
  const verdict = cell.result !== null;
  // The model's guards, recomputed from the cell alone: the corpus must say
  // what the Lean's deposit clauses say.
  const expected = !isPending && evidenced && live.sn < snPrime && authorized;
  if (expected !== verdict) throw new Error(`cell ${JSON.stringify(cell)} disagrees with the deposit clause`);
  if (verdict) {
    const { flow, state: after } = cell.result;
    const covers = params.P <= live.pool;
    const successor = { ...live, sn: snPrime, epoch: live.epoch + 1, poisoned: false, frozen: false, toppedUp: false, pool: covers ? live.pool - params.P : live.pool };
    if (!same(after, { present: { l: successor } })) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: the successor is not the rotated state, unfrozen and unpoisoned, with the premium taken from the pool exactly when it covers it`);
    const bIn = live.frozen ? params.B : 0;
    if (flow.bIn !== bIn) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: the deposit is B - bHeld = ${bIn}, the corpus moves ${flow.bIn}`);
    const hunter = covers ? { addr: act.payee, b: 0, dreg: 0, pool: params.P } : null;
    if (!same(flow.hunter, hunter)) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: the payee must receive exactly the premium when the pool covers it and nothing otherwise`);
    if (flow.poolIn !== 0 || flow.dregIn !== 0 || flow.refund !== null || flow.convictor !== null) throw new Error(`accepted cell ${cell.s}/${cell.a}/${cell.e}: a deposit rotation moves value other than the bond and the premium`);
  }
  const relation = snPrime < hash.sn ? -1 : snPrime === hash.sn ? 0 : 1;
  cells.push({
    name: `cell_${isPending ? 'pending' : 'present'}_s${cell.s}_sn${snPrime}_e${cell.e}`,
    stateIndex: cell.s,
    pending: isPending,
    poisoned: isPending ? false : live.poisoned,
    frozen: isPending ? false : live.frozen,
    toppedUp: isPending ? false : live.toppedUp,
    pool: isPending ? 0 : live.pool,
    snPrime,
    relation,
    evidenced,
    authorized,
    verdict,
  });
  if (verdict) accepted += 1;
  else refused += 1;
}

// Non-vacuity: 24 live states (12 with the top-up mark set) and 1 pending,
// three requested sequence numbers, two oracles; both verdicts occur, and the
// accepted cells are exactly the live states (poison, frozen, the mark and every
// pool) with the later sequence number under the oracle that evidences the
// rotation and authorizes the deposit.
if (cells.length !== 150) throw new Error(`expected 150 realizable deposit cells, found ${cells.length}`);
if (markedEmitted !== 72) throw new Error(`expected 72 topped-up deposit cells, found ${markedEmitted}`);
if (skipped.length !== 12) throw new Error(`expected 12 unrealizable deposit cells, found ${skipped.length}`);
if (accepted !== 24) throw new Error(`expected exactly 24 accepted deposit cells (every live state, one sequence number, one oracle), found ${accepted}`);
if (refused !== 126) throw new Error(`expected 126 refused deposit cells, found ${refused}`);
const names = new Set(cells.map((c) => c.name));
if (names.size !== cells.length) throw new Error('cell names are not unique');

// The trace the corpus records for the journey: the deposit step of
// `freeze-then-unfreeze`, a frozen checkpoint with pool 1 (below the premium).
const trace = corpus.traces.find((t) => t.name === 'freeze-then-unfreeze');
if (!trace) throw new Error('the corpus has no trace freeze-then-unfreeze');
const stepAt = trace.steps.findIndex((s) => typeof s.action === 'object' && 'rotate' in s.action && s.action.rotate.op === 'deposit' && s.result !== null);
const step = trace.steps[stepAt];
if (!step) throw new Error('freeze-then-unfreeze has no accepted deposit step');
const before = step.input.present.l;
if (!(before.frozen === true && before.pool === 1)) throw new Error('the deposit step of the trace is no longer a frozen checkpoint with pool 1');
if (step.result.flow.bIn !== params.B || step.result.flow.hunter !== null) throw new Error('the deposit step of the trace moves other than the bond');
if (!same(step.result.state, { present: { l: { ...before, sn: step.action.rotate["sn'"], epoch: before.epoch + 1, frozen: false } } })) throw new Error('the deposit step of the trace does not unfreeze the rotated state keeping the pool');

// ---------------------------------------------------------------------
// The Aiken module
// ---------------------------------------------------------------------
const aikenCell = (c) => {
  const call = c.pending
    ? `corpus_deposit_pending(${bool(c.evidenced)}, ${bool(c.authorized)})`
    : `corpus_deposit(${bool(c.poisoned)}, ${bool(c.frozen)}, ${bool(c.toppedUp)}, ${c.pool}, ${c.relation}, ${bool(c.evidenced)}, ${bool(c.authorized)})`;
  const what = c.pending ? `termination pending` : `live, poisoned ${bool(c.poisoned)}, frozen ${bool(c.frozen)}, topped up ${bool(c.toppedUp)}, pool ${c.pool}`;
  return `/// Lean grid state ${c.stateIndex} (${what}) x deposit rotation(sn' = ${c.snPrime}) x ${c.evidenced ? 'the rotation evidenced' : 'no rotation evidenced'}, ${c.authorized ? 'the deposit authorized' : 'no deposit authorized'}: ${c.verdict ? 'accepted' : 'refused'}.
test ${c.name}()${c.verdict ? '' : ' fail'} {
  run(${call})
}
`;
};

const aiken = `//// GENERATED by scripts/checkpoint-deposit-corpus.mjs from
//// simulator/checkpoint-simulator-corpus.json. DO NOT EDIT.
//// \`just check-checkpoint-deposit-corpus\` regenerates and rejects drift.
////
//// The deposit-rotation cells of the Lean corpus's boundary grid (parameters
//// \`P = ${params.P}\`, \`B = ${params.B}\`, \`D = ${params.D}\`), one test per cell: every live state
//// (poisoned, frozen and the top-up mark each clear and set, the pool at one below, exactly and one above
//// the premium), the termination-pending state, a requested sequence number
//// earlier than, equal to and later than the state's, under an oracle that
//// evidences the rotation and authorizes the deposit and one that does neither.
//// A refused cell is a \`fail\` test, an accepted cell passes. The last test is
//// the deposit step of the corpus trace freeze-then-unfreeze.
////
//// Mapping of the Lean values onto the ledger values:
////   live state              a live version 2 datum with that poisoned / frozen / top-up mark
////   pool (Lean units)       lovelace: pool x 1,000,000 (premium 2,000,000, bond 5,000,000)
////   sn' against the state's sn
////                           earlier / equal / later: the later case is the genuine
////                           witnessed rotation; the other two re-label the spent
////                           checkpoint so that rotation is not later than it
////   rotationTo evidenced    the rotation evidence; when it is not, the evidence
////                           carries no signature and no receipt
////   depositAuthorized       the new keys sign the intent the validator requires;
////                           when it is not, they sign another sequence number's
////   termination pending     a termination-pending datum
////   absent, convicted       no checkpoint output to spend: ${skipped.length} cells, not realizable
////                           as a transaction

use checkpoint_observer
use checkpoint_register
use deposit_fixture.{Case, corpus_deposit, corpus_deposit_pending}
use freeze_fixture.{
  advance_hash, d_reg, enforcement_hash, entitlement_hash, freeze_bond, premium,
}
use registry_fixture.{registry_name, state_policy}

fn run_spend(c: Case) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    state_policy(),
    registry_name(),
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    c.network,
    d_reg,
    freeze_bond,
    premium,
    None,
    c.redeemer,
    c.own_ref,
    c.tx,
  )
}

fn run(c: Case) -> Bool {
  run_spend(c) && checkpoint_observer.observer_advance.withdraw(
    0,
    c.observed,
    0,
    c.tx,
  )
}

${cells.map(aikenCell).join('\n')}
/// The deposit step of the corpus trace freeze-then-unfreeze (step ${stepAt}): a
/// frozen checkpoint with pool 1 takes the deposit rotation; the bond comes back
/// and nobody is paid.
test trace_freeze_then_unfreeze_deposit() {
  run(corpus_deposit(False, True, False, 1, 1, True, True))
}
`;

// ---------------------------------------------------------------------
// The Haskell module
// ---------------------------------------------------------------------
const hsCell = (c) => `    , DepositCell
        { dcName = "${c.name}"
        , dcPending = ${bool(c.pending)}
        , dcPoisoned = ${bool(c.poisoned)}
        , dcFrozen = ${bool(c.frozen)}
        , dcToppedUp = ${bool(c.toppedUp)}
        , dcPool = ${c.pool}
        , dcSnRelation = ${c.relation}
        , dcRotationEvidenced = ${bool(c.evidenced)}
        , dcDepositAuthorized = ${bool(c.authorized)}
        , dcAccepted = ${bool(c.verdict)}
        }`;

const haskell = `{- |
Module      : Cardano.KERI.AID.Checkpoint.DepositCorpus
Description : The deposit-rotation cells of the Lean checkpoint corpus

GENERATED by scripts/checkpoint-deposit-corpus.mjs from
simulator/checkpoint-simulator-corpus.json. DO NOT EDIT.
\`just check-checkpoint-deposit-corpus\` regenerates and rejects drift.

The same ${cells.length} cells the Aiken module
@checkpoint_register_deposit_corpus_tests@ runs: parameters @P = ${params.P}@,
@B = ${params.B}@, @D = ${params.D}@, every live state, the pending state, a requested
sequence number earlier than, equal to and later than the state's, under an
oracle that evidences the rotation and authorizes the deposit and one that does
neither. Pools are in Lean units; the expected verdict is the Lean's.
-}
module Cardano.KERI.AID.Checkpoint.DepositCorpus (
    DepositCell (..),
    depositCells,
) where

-- | One deposit-rotation cell.
data DepositCell = DepositCell
    { dcName :: String
    , dcPending :: Bool
    -- ^ the state is a termination pending
    , dcPoisoned :: Bool
    , dcFrozen :: Bool
    , dcToppedUp :: Bool
    -- ^ the top-up mark of the live state; a rotation clears it
    , dcPool :: Integer
    -- ^ the Lean pool, in Lean units
    , dcSnRelation :: Int
    -- ^ the requested sequence number against the state's: -1, 0 or 1
    , dcRotationEvidenced :: Bool
    , dcDepositAuthorized :: Bool
    , dcAccepted :: Bool
    }
    deriving stock (Show, Eq)

depositCells :: [DepositCell]
depositCells =
${cells.map((c, i) => (i === 0 ? '    [ ' + hsCell(c).slice(6) : hsCell(c))).join('\n')}
    ]
`;

// The Aiken module is compared after \`aiken fmt\`: the drift check ignores layout.
// Layout only: whitespace between two word characters separates tokens (`Weight 1 2`
// is not `Weight 12`) and is kept as one mark; every other whitespace is dropped.
const normalize = (text) =>
  text
    .replace(/(?<=\w)\s+(?=\w)/g, '\u0001')
    .replace(/\s+/g, '')
    .replace(/,(?=[\])}])/g, '');

const outputs = [
  [aikenOut, aiken, true],
  [haskellOut, haskell, true],
];
if (process.argv.includes('--check')) {
  let drift = false;
  for (const [path, text, layoutFree] of outputs) {
    let current = '';
    try {
      current = readFileSync(path, 'utf8');
    } catch {
      /* absent */
    }
    const equal = layoutFree ? normalize(current) === normalize(text) : current === text;
    if (!equal) {
      console.error(`drift: ${path}`);
      drift = true;
    }
  }
  if (drift) process.exit(1);
  console.log(`deposit corpus modules up to date (${cells.length} cells: ${accepted} accepted, ${refused} refused, ${skipped.length} unrealizable)`);
} else {
  for (const [path, text] of outputs) writeFileSync(path, text);
  console.log(`wrote ${cells.length} deposit cells (${accepted} accepted, ${refused} refused, ${skipped.length} unrealizable)`);
}
