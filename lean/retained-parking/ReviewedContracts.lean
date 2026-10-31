import CardanoKeri

/-! Exact expected types at the no-owner-exit revision. Unused proof binder
names have an underscore prefix. This file holds the contracts revised by the
retained-output revision or by the no-owner-exit revision; the dispositions
of removed and changed contracts are in `lean/NO-OWNER-EXIT-DISPOSITIONS.md`. -/
set_option pp.universes true
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.reap_conserves : ∀ (r : Reap), (reap r).intoRequest + (reap r).premium = r.Mc)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.termination_fold_accounting : ∀ (r : Reap) (world after : Singular.World) (_reachable : Singular.WorldReachable world) (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (b : Singular.TerminationBooking) (_matched : MatchesBooking r b) (_members : Singular.foldMembers world tx = [.termination b]) (_accepted : fold world unspent tx = .ok after), tx.transaction.donation = r.Mr ∧ Singular.foldCarrierLovelace tx.outputs = 0 ∧ Singular.foldOrdinaryLovelace tx.outputs + tx.transaction.fee = Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) + r.tip ∧ tx.transaction.fee ≤ Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) ∧ after.treasury = world.treasury + r.Mr ∧ Singular.balanced unspent.ledger tx.transaction = true ∧ Singular.requestTagsBurned unspent tx = true)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.booking_premium_exact : ∀ (r : Reap), (reap r).premium + r.Mr + r.tip = r.Mc)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.booker_nonloss_iff : ∀ (r : Reap), (reap r).reaperPays ≤ (reap r).premium ↔ r.Mr + r.tip + r.fReap ≤ r.Mc)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.booker_loses_when_underfunded : ∀ (r : Reap) (_h : r.Mc < r.Mr + r.tip + r.fReap), (reap r).premium < (reap r).reaperPays)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.self_fold_addressed_accounting : ∀ (r : Reap) (world after : Singular.World) (_reachable : Singular.WorldReachable world) (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (b : Singular.TerminationBooking) (booker : Nat) (_matched : MatchesBooking r b) (_members : Singular.foldMembers world tx = [.termination b]) (_accepted : fold world unspent tx = .ok after) (_inputsAt : AllOrdinaryAt booker (Singular.economicSpent unspent tx)) (_outputsAt : AllOrdinaryAt booker tx.outputs), ordinaryAt booker tx.outputs + tx.transaction.fee = ordinaryAt booker (Singular.economicSpent unspent tx) + r.tip)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.self_fold_nonloss_iff : ∀ (r : Reap) (world after : Singular.World) (_reachable : Singular.WorldReachable world) (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (b : Singular.TerminationBooking) (booker : Nat) (_matched : MatchesBooking r b) (_members : Singular.foldMembers world tx = [.termination b]) (_accepted : fold world unspent tx = .ok after) (_inputsAt : AllOrdinaryAt booker (Singular.economicSpent unspent tx)) (_outputsAt : AllOrdinaryAt booker tx.outputs), r.fReap + ordinaryAt booker (Singular.economicSpent unspent tx) ≤ (reap r).premium + ordinaryAt booker tx.outputs ↔ r.Mr + r.fReap + tx.transaction.fee ≤ r.Mc)
end CardanoKeri.Samaritan
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.imported_fold_accounting : ∀ (world after : Singular.World) (_reachable : Singular.WorldReachable world) (unspent : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (_accepted : fold world unspent tx = .ok after), Singular.balanced unspent.ledger tx.transaction = true ∧ Singular.foldStateLovelace (Singular.economicSpent unspent tx) = Singular.foldStateLovelace tx.outputs ∧ tx.transaction.donation = (Singular.foldObligations (Singular.foldMembers world tx)).donation ∧ Singular.foldCarrierLovelace tx.outputs = (Singular.foldObligations (Singular.foldMembers world tx)).carriers ∧ Singular.foldOrdinaryLovelace tx.outputs + tx.transaction.fee = Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) + (Singular.foldObligations (Singular.foldMembers world tx)).tips ∧ tx.transaction.fee ≤ Singular.foldOrdinaryLovelace (Singular.economicSpent unspent tx) ∧ after.treasury = world.treasury + tx.transaction.donation ∧ Singular.requestTagsBurned unspent tx = true)
end CardanoKeri.Samaritan
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.total_projection : ∀ (s : Sys), s.toWorld.registry = { config := s.config, trie := s.trie, held := s.carriers.map (·.original) } ∧ s.toWorld.pending = s.registrations ∧ s.toWorld.terminations = s.terminations.map (·.booking) ∧ s.toWorld.treasury = s.treasury)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.reachable_wellFormed : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_h : Reach p env cfg s), WellFormed p s)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.active_custody_iff : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_h : Reach p env cfg s) (aid : Nat), Singular.trieGet s.trie aid = .known .active ↔ ((s.carriers.filter (fun c => c.aid == aid)).length = 1 ∧ (s.terminations.filter (fun e => e.payload.aid == aid)).length = 0) ∨ ((s.carriers.filter (fun c => c.aid == aid)).length = 0 ∧ (s.terminations.filter (fun e => e.payload.aid == aid)).length = 1))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.convictCkpt_iff : ∀ (env : Env) (s s' : Sys) (aid : Nat) (f : Flow), convictCkpt env s aid = .ok (f, s') ↔ ∃ c, carrierAt s aid = some c ∧ c.st = .live ∧ env.duplicity aid c.k = true ∧ f = {} ∧ s' = { s with carriers := s.carriers.map (fun old => if old.aid == aid then { old with st := .terminationPending } else old) })
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.local_conviction_retains : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} {aid : Nat} {f : Flow} {c : Carrier} (_hr : Reach p env cfg s) (_hc : carrierAt s aid = some c) (_hs : convictCkpt env s aid = .ok (f, s')), carrierAt s' aid = some { c with st := .terminationPending } ∧ minAdaAt s' aid = p.Mc ∧ s'.toWorld = s.toWorld ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken ∧ s'.gen = s.gen ∧ s'.terminations = s.terminations ∧ s'.registrations = s.registrations ∧ (∀ other, other ≠ aid → carrierAt s' other = carrierAt s other) ∧ f = {})
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.bookTermination_iff : ∀ (p : Params) (s s' : Sys) (aid booker fee : Nat) (b : Singular.TerminationBooking) (f : Flow), bookTermination p s aid booker fee b = .ok (f, s') ↔ ∃ c world, carrierAt s aid = some c ∧ c.st = .terminationPending ∧ b.request.key = aid ∧ b.request.destination = c.original.output ∧ b.custodyInputs = [c.original] ∧ c.minAda = p.Mc ∧ b.request.carrierAda = p.Mr ∧ b.request.declaredTip = p.tip ∧ b.request.contents.lovelace = p.Mr + p.tip ∧ Singular.bookTermination s.toWorld b = .ok world ∧ s' = { s with carriers := s.carriers.filter (fun old => old.aid != aid), terminations := { booking := b, payload := { aid := aid, token := c.token, keyState := c.k, original := c.original, booker := booker, bookingFee := fee } } :: s.terminations } ∧ s'.toWorld = world ∧ f = { premium := some (booker, p.Mc - p.Mr - p.tip), bookingFee := fee, intoRequest := p.Mr + p.tip })
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.pending_has_keri_authorization : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_hr : Reach p env cfg s) (e : TerminationEntry) (_he : e ∈ s.terminations), ∃ before after : Sys, ∃ c : Carrier, Reach p env cfg before ∧ carrierAt before e.payload.aid = some c ∧ c.token = e.payload.token ∧ c.k = e.payload.keyState ∧ c.original = e.payload.original ∧ c.st = .live ∧ env.duplicity e.payload.aid c.k = true ∧ convictCkpt env before e.payload.aid = .ok ({}, after))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.booking_keeps_prior_pending : ∀ (p : Params) {s s' : Sys} {aid booker fee : Nat} {b : Singular.TerminationBooking} {f : Flow} (_hs : bookTermination p s aid booker fee b = .ok (f, s')) {ref : Singular.OutRef} {e : TerminationEntry} (_hp : pendingAt s ref = some e), ref ≠ b.request.reference ∧ pendingAt s' ref = some e ∧ s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧ s'.registrations = s.registrations ∧ s'.treasury = s.treasury ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.booking_keeps_active_supply : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} {aid booker fee : Nat} {b : Singular.TerminationBooking} {f : Flow} (_hr : Reach p env cfg s) (_hs : bookTermination p s aid booker fee b = .ok (f, s')), Singular.trieGet s'.trie aid = .known .active ∧ Singular.worldSingularSupply s'.toWorld aid = 1 ∧ carrierAt s' aid = none ∧ ∃ e, pendingAt s' b.request.reference = some e ∧ e.booking = b ∧ e.payload.aid = aid ∧ bindingAt s' aid = some e.payload.token)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_sound : ∀ (p : Params) (env : Env) {s s' : Sys} {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow} (_hs : fold p env s gen plugin u tx = .ok (f, s')), gen = s.gen ∧ plugin = s.config.applicationPolicy ∧ registrationsAuthorized env (Singular.foldMembers s.toWorld tx) = true ∧ Singular.foldAccepted s.toWorld u tx = .ok s'.toWorld ∧ s'.gen = s.gen + 1 ∧ s'.registrations = s.registrations.filter (fun b => !Singular.inputsContainReference tx.transaction.inputs b.request.reference) ∧ s'.terminations = s.terminations.filter (fun e => !Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_complete : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_hr : Reach p env cfg s) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (world : Singular.World) (_auth : registrationsAuthorized env (Singular.foldMembers s.toWorld tx) = true) (_accepted : Singular.foldAccepted s.toWorld u tx = .ok world), ∃ f s', fold p env s s.gen s.config.applicationPolicy u tx = .ok (f, s') ∧ s'.toWorld = world)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_keeps_unselected : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} (_hr : Reach p env cfg s) {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow} (_hs : fold p env s gen plugin u tx = .ok (f, s')) {ref : Singular.OutRef} {e : TerminationEntry} (_hp : pendingAt s ref = some e) (_hn : Singular.inputsContainReference tx.transaction.inputs ref = false), pendingAt s' ref = some e ∧ Singular.trieGet s'.trie e.payload.aid = .known .active ∧ bindingAt s' e.payload.aid = some e.payload.token ∧ Singular.worldSingularSupply s'.toWorld e.payload.aid = 1)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_consumes_exact : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} (_hr : Reach p env cfg s) {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow} (_hs : fold p env s gen plugin u tx = .ok (f, s')) {ref : Singular.OutRef} {e : TerminationEntry} (_hp : pendingAt s ref = some e) (_hc : Singular.inputsContainReference tx.transaction.inputs ref = true), pendingAt s' ref = none ∧ carrierAt s' e.payload.aid = none ∧ Singular.trieGet s'.trie e.payload.aid = .known .terminal ∧ Singular.worldSingularSupply s'.toWorld e.payload.aid = 0 ∧ bindingAt s' e.payload.aid = some e.payload.token ∧ ((tx.singularMint.filter (fun pair => decide (pair.1 = s.config.singularTag e.payload.aid))).map Prod.snd).sum = -1 ∧ (tx.outputs.flatMap (·.singularTags)).count (s.config.singularTag e.payload.aid) = 0)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.registration_posted_value : ∀ (p : Params) {s s' : Sys} {b : Singular.RegistrationBooking} {f : Flow} (_hs : bookRegistration p s b = .ok (f, s')), p.Mc + p.D ≤ b.request.carrierAda ∧ b.request.declaredTip = p.tip ∧ b.request.contents.lovelace = b.request.registrationCost + p.tip + b.request.carrierAda ∧ f = { deposited := b.request.contents.lovelace })
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.registration_delivery : ∀ (p : Params) (env : Env) {s s' : Sys} {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow} (_hs : fold p env s gen plugin u tx = .ok (f, s')) (b : Singular.RegistrationBooking) (_selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx), ∃ output : Singular.EconomicOutput, tx.outputs.filter (fun o => o.singularTags.contains (s.config.singularTag b.request.key)) = [output] ∧ output.output.address = some b.request.destination ∧ output.output.datumValue = b.request.datum ∧ output.output.datum = Singular.datumFormOf b.request.datum ∧ output.output.lovelace = b.request.carrierAda ∧ output.singularTags = [s.config.singularTag b.request.key] ∧ output.output.stateTokens = 0 ∧ output.request = none ∧ output.contents.trieReadyTags = [] ∧ output.contents.applicationTags = [] ∧ Singular.foldBareValue output = true)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.leaf_change_requires_fold : ∀ (p : Params) (env : Env) {s s' : Sys} {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')) (aid : Nat) (_changed : Singular.trieGet s'.trie aid ≠ Singular.trieGet s.trie aid), ∃ gen plugin u tx, action = .fold gen plugin u tx)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.retired_preserved : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} (_hr : Reach p env cfg s) {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')) (aid : Nat) (_retired : Singular.trieGet s.trie aid = .known .terminal), Singular.trieGet s'.trie aid = .known .terminal ∧ carrierAt s' aid = none ∧ (s'.terminations.filter (fun e => e.payload.aid == aid)) = [])
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.completion_receipt_effects : ∀ (p : Params) (env : Env) (cfg : Singular.Config) (r : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat) (_hc : Completes r ref aid token), Singular.foldAccepted r.before.toWorld r.unspent r.transaction = .ok r.after.toWorld ∧ pendingAt r.after ref = none ∧ carrierAt r.after aid = none ∧ Singular.trieGet r.after.trie aid = .known .terminal ∧ Singular.worldSingularSupply r.after.toWorld aid = 0 ∧ bindingAt r.after aid = some token)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.completion_not_unselected : ∀ (p : Params) (env : Env) (cfg : Singular.Config) (r : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat) (_hu : Singular.inputsContainReference r.transaction.transaction.inputs ref = false), ¬ Completes r ref aid token)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_iff : ∀ (p : Params) (env : Env) (s s' : Sys) (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (f : Flow), fold p env s gen plugin u tx = .ok (f, s') ↔ gen = s.gen ∧ plugin = s.config.applicationPolicy ∧ registrationsAuthorized env (Singular.foldMembers s.toWorld tx) = true ∧ ∃ world, Singular.foldAccepted s.toWorld u tx = .ok world ∧ foldResult p s tx world = .ok (f, s'))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_stale_refused : ∀ (p : Params) (env : Env) (s : Sys) (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (_hg : gen ≠ s.gen), (fold p env s gen plugin u tx).toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_plugin_swap_refused : ∀ (p : Params) (env : Env) (s : Sys) (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (_hp : plugin ≠ s.config.applicationPolicy), (fold p env s gen plugin u tx).toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_empty_refused : ∀ (p : Params) (env : Env) (s : Sys) (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (_he : Singular.foldMembers s.toWorld tx = []), (fold p env s gen plugin u tx).toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.generation_cannot_be_reused : ∀ (p : Params) (env : Env) {s s' : Sys} {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow} (_hs : fold p env s gen plugin u tx = .ok (f, s')) (plugin' : Nat) (u' : Singular.EconomicUtxo) (tx' : Singular.EconomicTransaction), (fold p env s' gen plugin' u' tx').toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.config_and_generation_frame : ∀ (p : Params) (env : Env) {s s' : Sys} {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')), s'.config = { s.config with root := s'.config.root } ∧ (s'.gen = s.gen ∨ s'.gen = s.gen + 1) ∧ ((∀ gen plugin u tx, action ≠ .fold gen plugin u tx) → s'.gen = s.gen ∧ s'.config = s.config ∧ s'.trie = s.trie))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.registered_key_permanent : ∀ (p : Params) (env : Env) {s s' : Sys} {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')) (aid : Nat) (_hk : Singular.trieGet s.trie aid = .known .active ∨ Singular.trieGet s.trie aid = .known .terminal), Singular.trieGet s'.trie aid = .known .active ∨ Singular.trieGet s'.trie aid = .known .terminal)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.terminal_leaf_permanent : ∀ (p : Params) (env : Env) {s s' : Sys} {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')) (aid : Nat) (_hk : Singular.trieGet s.trie aid = .known .terminal), Singular.trieGet s'.trie aid = .known .terminal)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.generic_retraction_sound : ∀ (s s' : Sys) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (f : Flow) (_hs : genericRetraction s u tx = .ok (f, s')), Singular.retractionAccepted s.toWorld u tx = .ok s'.toWorld ∧ s'.carriers = s.carriers ∧ s'.terminations = s.terminations ∧ s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧ s'.treasury = s.treasury ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken ∧ f = {})
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.generic_rejection_sound : ∀ (s s' : Sys) (u : Singular.EconomicUtxo) (tx : Singular.Rejection) (f : Flow) (_hs : genericRejection s u tx = .ok (f, s')), Singular.rejectionAccepted s.toWorld u tx = .ok s'.toWorld ∧ s'.carriers = s.carriers ∧ s'.terminations = s.terminations ∧ s'.config = s.config ∧ s'.trie = s.trie ∧ s'.gen = s.gen ∧ s'.treasury = s.treasury ∧ s'.bindings = s.bindings ∧ s'.nextToken = s.nextToken ∧ f = {})
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.current_sys_fold_accounting : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} (_hr : Reach p env cfg s) {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow} (_hs : fold p env s gen plugin u tx = .ok (f, s')), Singular.balanced u.ledger tx.transaction = true ∧ Singular.foldStateLovelace (Singular.economicSpent u tx) = Singular.foldStateLovelace tx.outputs ∧ tx.transaction.donation = (Singular.foldObligations (Singular.foldMembers s.toWorld tx)).donation ∧ Singular.foldCarrierLovelace tx.outputs = (Singular.foldObligations (Singular.foldMembers s.toWorld tx)).carriers ∧ Singular.foldOrdinaryLovelace tx.outputs + tx.transaction.fee = Singular.foldOrdinaryLovelace (Singular.economicSpent u tx) + (Singular.foldObligations (Singular.foldMembers s.toWorld tx)).tips ∧ tx.transaction.fee ≤ Singular.foldOrdinaryLovelace (Singular.economicSpent u tx) ∧ s'.treasury = s.treasury + tx.transaction.donation ∧ Singular.requestTagsBurned u tx = true)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.wellFormed_initial : ∀ (p : Params) (cfg : Singular.Config), WellFormed p (Sys.init cfg))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.wellFormed_step : ∀ (p : Params) (env : Env) {s s' : Sys} (_hw : WellFormed p s) {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')), WellFormed p s')
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.reachable_binding_domain : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_hr : Reach p env cfg s) (aid : Nat), (∃ token, bindingAt s aid = some token) ↔ (Singular.trieGet s.trie aid = .known .active ∨ Singular.trieGet s.trie aid = .known .terminal))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.pending_lookup_mem : ∀ (s : Sys) (ref : Singular.OutRef) (e : TerminationEntry) (_hp : pendingAt s ref = some e), e ∈ s.terminations ∧ e.booking.request.reference = ref)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.pending_preserved_unless_consumed : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s s' : Sys} (_hr : Reach p env cfg s) {action : Action} {f : Flow} (_hs : stepFn p env action s = .ok (f, s')) (ref : Singular.OutRef) (e : TerminationEntry) (_hp : pendingAt s ref = some e) (_hn : ¬ ConsumesPending ref action), pendingAt s' ref = some e ∧ bindingAt s' e.payload.aid = some e.payload.token ∧ Singular.trieGet s'.trie e.payload.aid = .known .active ∧ Singular.worldSingularSupply s'.toWorld e.payload.aid = 1)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fold_signers_irrelevant : ∀ (p : Params) (env : Env) (s : Sys) (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (signers : List Nat), fold p env s gen plugin u { tx with transaction := { tx.transaction with signers := signers } } = fold p env s gen plugin u tx)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.registered_registration_refused : ∀ (p : Params) (env : Env) (s : Sys) (gen plugin : Nat) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (b : Singular.RegistrationBooking) (_selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx) (_known : Singular.trieGet s.trie b.request.key = .known .active ∨ Singular.trieGet s.trie b.request.key = .known .terminal), (fold p env s gen plugin u tx).toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.termination_retraction_refused : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_hr : Reach p env cfg s) (ref : Singular.OutRef) (e : TerminationEntry) (_hp : pendingAt s ref = some e) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (_spent : Singular.inputsContainReference tx.transaction.inputs ref = true), (genericRetraction s u tx).toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.termination_rejection_refused : ∀ (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys} (_hr : Reach p env cfg s) (ref : Singular.OutRef) (e : TerminationEntry) (_hp : pendingAt s ref = some e) (u : Singular.EconomicUtxo) (tx : Singular.Rejection) (reason : Singular.RejectReason) (_member : (ref, reason) ∈ tx.members), (genericRejection s u tx).toOption = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.retraction_refund_and_guards : ∀ (s s' : Sys) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (f : Flow) (_hs : genericRetraction s u tx = .ok (f, s')), ∃ request : Singular.RegistrationRequest, ∃ interval : Singular.Interval, Singular.retractionRequest s.toWorld tx = .ok request ∧ tx.transaction.signers.contains request.refundAddress = true ∧ tx.transaction.validity = some interval ∧ interval.valid ∧ request.submittedAt + s.config.processTime ≤ interval.lower ∧ interval.upper ≤ request.submittedAt + s.config.processTime + s.config.retractTime ∧ request.contents.lovelace ≤ Singular.refundPaid tx request.refundAddress ∧ tx.transaction.donation = 0 ∧ Singular.requestTagsBurned u tx = true ∧ tx.transaction.fee ≤ Singular.retractionFundingLovelace u tx request ∧ Singular.balanced u.ledger tx.transaction = true)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.rejection_refund_destinations : ∀ (s s' : Sys) (u : Singular.EconomicUtxo) (tx : Singular.Rejection) (f : Flow) (_hs : genericRejection s u tx = .ok (f, s')), ∀ address, Singular.refundOwed (Singular.rejectedRequests s.toWorld tx.members) false address ≤ Singular.refundPaid tx.transaction address)
end CardanoKeri.Registry
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.pending_has_no_local_exit : ∀ (p : Params) (env : Env) (h : Hash) (a : Action) (now : Slot), stepFn p env a now (.terminationPending h) = none)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.pending_consumer_refused : ∀ (p : Params) (now : Slot) (h : Hash), ¬ consumableState p now (.terminationPending h) ∧ consumableStateB p now (.terminationPending h) = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.pending_custody_observations : ∀ (p : Params) (h : Hash), (State.terminationPending h).hasOutput = true ∧ (State.terminationPending h).representativeHeld = 1 ∧ (State.terminationPending h).leaf = .active ∧ (State.terminationPending h).sn? = some h.sn ∧ (State.terminationPending h).dregHeld p = 0 ∧ (State.terminationPending h).bHeld p = 0 ∧ (State.terminationPending h).poolHeld = 0)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_sysstep_partition : ∀ (p : Params) (env : Env) {s s' : Sys} (_h : SysStep p env s s'), RegistrationEvent p env s s' ∨ LocalEvent p env s s' ∨ BookingEvent s s' ∨ CompletionEvent s s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.local_event_preserves_associations : ∀ (p : Params) (env : Env) {s s' : Sys} (_h : LocalEvent p env s s'), s'.origins = s.origins ∧ s'.pending = s.pending)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.booking_event_preserves_checkpoint : ∀ (s s' : Sys) (_h : BookingEvent s s'), s'.states = s.states ∧ s'.leaves = s.leaves ∧ s'.origins = s.origins)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.indexed_receipt_preserves_origin_config : ∀ (association : PendingAssociation) (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters association.origin.environment association.origin.configuration), receipt.before.config = { association.origin.configuration with root := receipt.before.config.root })
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.receipt_missing_own_request_refused : ∀ (s : Sys) (aid : AID) (association : PendingAssociation) (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters association.origin.environment association.origin.configuration) (_missing : CardanoKeri.Registry.pendingAt receipt.before association.reference = none), ¬ ReceiptMatches s aid association receipt)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.completion_uses_recorded_pending_key : ∀ (s s' : Sys) (_h : CompletionEvent s s'), ∃ aid association, s.pending aid = some association ∧ s.origins aid = some association.origin ∧ s.states aid = .terminationPending association.keyState ∧ s'.states aid = .convicted ∧ s'.pending aid = none ∧ s'.origins = s.origins)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.sysstep_preserves_existing_origin : ∀ (p : Params) (env : Env) {s s' : Sys} (_hs : SysStep p env s s') (aid : AID) (origin : Origin) (_ho : s.origins aid = some origin), s'.origins aid = some origin)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Registry.Examples
#check (@CardanoKeri.Registry.Examples.W5_connected_termination : ∃ registered pending booked retired, ∃ (b : Singular.TerminationBooking) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (f : Flow), RegistrationJourney registered ∧ convictCkpt env registered 11 = .ok ({}, pending) ∧ carrierAt pending 11 = some { liveCarrier with st := .terminationPending } ∧ Singular.trieGet pending.trie 11 = .known .active ∧ b.request.reference = ⟨200, 0⟩ ∧ bookTermination p pending 11 7 1 b = .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, booked) ∧ Singular.worldSingularSupply booked.toWorld 11 = 1 ∧ fold p env booked booked.gen cfg.applicationPolicy u tx = .ok (f, retired) ∧ Singular.trieGet retired.trie 11 = .known .terminal ∧ Singular.worldSingularSupply retired.toWorld 11 = 0 ∧ tx.transaction.donation = 2 ∧ Singular.foldCarrierLovelace tx.outputs = 0 ∧ pendingAt retired ⟨200, 0⟩ = none)
end CardanoKeri.Registry.Examples
namespace CardanoKeri.Registry.Examples
#check (@CardanoKeri.Registry.Examples.phantom_binding_not_wellFormed : ¬ WellFormed p { Sys.init cfg with bindings := [(11, 0)], nextToken := 1 })
end CardanoKeri.Registry.Examples
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_edges_leave_the_leaf : ∀ (p : Params) (env : Env) {s : Sys} {aid : AID} {a : Action} {now : Slot} {f : Flow} {st' : State} (_hs : SysReach p env s) (_hstep : Step p env a now (s.states aid) f st'), (s.set aid st').leaves = s.leaves ↔ a.touchesLeaf = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_leaf_states : ∀ (p : Params) (env : Env) {s : Sys} (_h : SysReach p env s) (aid : AID), (s.leaves aid = .active ↔ (∃ l, s.states aid = .present l) ∨ (∃ pending, s.states aid = .terminationPending pending)) ∧ (s.leaves aid = .retired → s.states aid = .convicted))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_utxo_iff_active : ∀ (p : Params) (env : Env) {s : Sys} (_h : SysReach p env s) (aid : AID), (s.states aid).hasOutput = true ↔ s.leaves aid = .active)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_mint_once : ∀ (p : Params) (env : Env) {s : Sys} (_h : SysReach p env s) (aid : AID), ∀ refund pool0 now f st', Step p env (.register refund pool0) now (s.states aid) f st' → s.leaves aid = .absent)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_component_conservation : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s'), s.dregHeld p + f.dregIn = s'.dregHeld p + Payment?.dreg f.refund + Payment?.dreg f.hunter + Payment?.dreg f.convictor ∧ s.bHeld p + f.bIn = s'.bHeld p + Payment?.b f.refund + Payment?.b f.hunter + Payment?.b f.convictor ∧ s.poolHeld + f.poolIn = s'.poolHeld + Payment?.pool f.refund + Payment?.pool f.hunter + Payment?.pool f.convictor)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.consumableStateB_iff : ∀ (p : Params) (now : Slot) (s : State), consumableStateB p now s = true ↔ consumableState p now s)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T7_step_iff_stepFn : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}, Step p env a t s f s' ↔ stepFn p env a t s = some (f, s'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T7_trace_iff_replay : ∀ (p : Params) (env : Env) {t : Slot} {s s' : State} {es : List (Slot × Action)}, Trace p env t s es s' ↔ replay p env t s es = some s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.local_progress_unless_pending_or_retired : ∀ (p : Params) (env : Env) (t : Slot) (s : State) (_hnot : s ≠ .convicted) (_hnotPending : ∀ h, s ≠ .terminationPending h), ∃ a f s', Step p env a t s f s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T12_convicted_terminal : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State} (_h : Step p env a t .convicted f s'), False)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T12_convict_exact : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} {pendingKey : Hash} (_h : Step p env a t (.present l) f (.terminationPending pendingKey)), pendingKey = l.hash ∧ (∃ payee, a = .convict payee ∧ f = { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool }, convictor := some { addr := payee, dreg := p.D } }) ∧ env.duplicityAt l.epoch l.sn = true)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.convict_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (payee : Addr), Step p env (.convict payee) now (.present l) { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool }, convictor := some { addr := payee, dreg := p.D } } (.terminationPending l.hash) ↔ env.duplicityAt l.epoch l.sn = true)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.convict_requires_concrete_pair : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} (_h : Step p env a t (.present l) f (.terminationPending l.hash)), ∃ context rival, env.convictionContext l.epoch l.sn = some context ∧ env.convictionRival l.epoch l.sn = some rival ∧ context.epoch = l.epoch ∧ context.accepted.event.sn = l.sn ∧ Duplicity.rotationValid context.prior context.accepted = true ∧ Duplicity.rotationValid context.prior rival = true ∧ context.accepted.event.sn = rival.event.sn ∧ context.accepted.event ≠ rival.event)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.old_pair_cannot_convict_new_target : ∀ (epoch sn next : Nat) (context : Duplicity.Context) (rival : Duplicity.SignedEvent) (_old : Duplicity.duplicityAt epoch sn context rival = true) (_later : sn < next), Duplicity.duplicityAt epoch next context rival = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Env.duplicityAt_iff : ∀ (env : Env) (epoch : Epoch) (sn : Seq), env.duplicityAt epoch sn = true ↔ ∃ context rival, env.convictionContext epoch sn = some context ∧ env.convictionRival epoch sn = some rival ∧ CardanoKeri.Duplicity.duplicityAt epoch sn context rival = true)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Env.inception_duplicity_refused : ∀ (env : Env) (epoch : Epoch), env.duplicityAt epoch 0 = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_convict_enabled : ∀ (p : Params) (env : Env) (t : Slot) (l : Live) (payee : Addr) (_hdup : env.duplicityAt l.epoch l.sn = true), ∃ f, Step p env (.convict payee) t (.present l) f (.terminationPending l.hash))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_dreg_never_a_fee : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s'), Payment?.dreg f.hunter = 0 ∧ (Payment?.dreg f.refund ≠ 0 → Payment?.dreg f.refund = p.D ∧ s.dregHeld p = p.D ∧ s'.dregHeld p = 0) ∧ (Payment?.dreg f.convictor ≠ 0 → Payment?.dreg f.convictor = p.D ∧ s.dregHeld p = p.D ∧ ∃ l, s = .present l ∧ s' = .terminationPending l.hash))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_leaf_never_absent_again : ∀ (p : Params) (env : Env) {s s' : Sys} (_hs : SysReach p env s) (_h : SysStep p env s s') (aid : AID), (s.leaves aid ≠ .absent → s'.leaves aid ≠ .absent) ∧ (s.leaves aid = .retired → s'.leaves aid = .retired))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_dreg_enters_only_at_birth : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s') (_hin : f.dregIn ≠ 0), (∃ refund pool0, a = .register refund pool0 ∧ s = .absent) ∧ f.dregIn = p.D ∧ f.bIn = p.B ∧ ∃ l', s' = .present l' ∧ l'.frozen = false ∧ l'.bornAt = t)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_intent_requires_new_keys : ∀ (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}, (∀ {sn' payee r'}, Step p env (.rotate sn' .deposit payee r') t (.present l) f s' → env.intentAuthorized (l.epoch + 1) .deposit r' = true) ∧ (∀ {sn' payee r}, Step p env (.rotate sn' .keep payee (some r)) t (.present l) f s' → env.intentAuthorized (l.epoch + 1) .keep (some r) = true))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T10_bonds_are_observable : ∀ (p : Params) (l : Live) (h : Hash), (State.present l).dregHeld p ≠ (State.terminationPending h).dregHeld p ∧ (State.present l).dregHeld p ≠ State.convicted.dregHeld p ∧ (l.frozen = true → (State.present l).bHeld p ≠ p.B))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.live_cannot_book : ∀ (p : Params) (s : Sys) (aid booker fee : Nat) (b : Singular.TerminationBooking) (c : Carrier) (_hc : carrierAt s aid = some c) (_hp : c.st = .live), bookTermination p s aid booker fee b = .error "keri-conviction-required")
end CardanoKeri.Registry
namespace CardanoKeri.Registry.Examples
#check (@CardanoKeri.Registry.Examples.W6_live_booking_refused : Reach p env cfg registered ∧ carrierAt registered 11 = some liveCarrier ∧ liveCarrier.st = .live ∧ bookTermination p registered 11 7 1 termination = .error "keri-conviction-required" ∧ minAdaAt registered 11 = 4 ∧ Singular.trieGet registered.trie 11 = .known .active)
end CardanoKeri.Registry.Examples
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T4_current_key_thief_cannot_rotate_or_freeze : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} {s' : State} (_hthief : ∀ sn', env.rotationTo l.epoch l.sn sn' = false) (_h : Step p env a t (.present l) f s'), a.actor ≠ .nextKeys ∧ (∀ sn' payee, a ≠ .freeze sn' payee))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_freeze_and_convict_actors_are_proof : ∀ (sn' : Seq) (payee : Addr), (Action.freeze sn' payee).actor = .proof ∧ (Action.convict payee).actor = .proof)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.convicted_holds_no_bonds_or_pool : ∀ (p : Params), State.convicted.dregHeld p = 0 ∧ State.convicted.bHeld p = 0 ∧ State.convicted.poolHeld = 0)
end CardanoKeri.Checkpoint
