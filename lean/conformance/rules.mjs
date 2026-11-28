// Reviewed rule-to-source bindings. Each anchor must identify exactly one code line.
// A forked implementation may override a row's "main" or "january" assessment.
const model = name => 'lean/CardanoKeri/' + name + '.lean';
const ck = name => 'onchain/lib/cardano_keri/checkpoint/' + name + '.ak';
const app = name => 'onchain/lib/cardano_keri/application/' + name + '.ak';
const at = (path, text) => ({path, text});
const book = at(model('Application'), 'def bookRegistration ');
const dup = decl => at(model('Duplicity'), 'def ' + decl + ' ');
const prefix = decl => [
  at(model('ApplicationInceptionPrefix'), decl),
  at(model('InceptionPrefixOpening'), decl),
  {...book, note: 'economic inception premise only'},
];
const inception = [
  at(model('ApplicationInceptionPrefix'), 'def inceptionWrites '),
  at(model('CheckpointEventHistory'), 'def inceptionWrites '),
  {...book, note: 'economic inception premise only'},
];
const witness = [dup('receiptsValid')];
const next = [at(model('Duplicity'), 'def Threshold.fitsNextKeys '),
  {...dup('rotationValid'), note: 'no declared-next-rule guard'}];
const reg = text => at(ck('registration'), text);
const adv = text => at(ck('message'), text);
const threshold = text => at(ck('threshold'), text);
const datum = text => at(ck('datum'), text);
const convict = text => at(ck('enforcement'), text);
const issue = text => at(app('attestation'), text);
const booking = text => at(app('registration'), text);

export const entryPoints = [
  at('onchain/validators/keri_application.ak', 'application_mint('),
  issue('fn inception_proof('), issue('expect registration_predicate(ctx, d, lovelace, evidence)'),
  at(ck('observer'), 'advance_predicate(spent, new, evidence) == AdvancePredicateValid'),
  at(ck('enforcement_observer'), 'expect convict_predicate(tip, decoded) == ConvictValid'),
];

function row(coverage, rule, models, status, sites, tickets = []) {
  return {coverage, rule, models, status, sites, tickets};
}
export const rules = [
  row('enforced', 'Booking reads the registry configuration and checks the request shape, checkpoint address, deposit and clock.',
    [book], 'Enforced at the application mint', [booking('configuration_of(application_policy'), booking('registration_shape(application_policy, output, data)'), booking('booking_clock(data,')]),
  row('enforced', 'Booking commits the initial state for the request key and mints exactly one registration approval.',
    [at(model('Application'), 'def initialStateDatum ')], 'Enforced at booking',
    [booking('registration_approval(data),'), at(app('inception'), 'facts.aid == key,')]),
  row('enforced', 'The indexed booking evidence belongs to the request and initial datum being approved.',
    [at(model('InceptionPrefix'), 'def issue '), at(model('Application'), 'def bookingOpening '), {...book,note:'key-level premise'}],
    'Enforced for the indexed attestation', [booking('attested('), issue('expect Some(output) = list.at(tx.outputs, entry.request_index)'), issue('list.all(names, fn(name)')], [576]),
  row('missing', 'Register only an ordinary inception with structurally decoded type, sequence, identifier and signed fields.',
    inception, 'not enforced structurally; the existing predicate compares slices', [reg('if !slice_matches(e.event_bytes, e.off_t'), reg('RegistrationInvalid(E3SequenceMismatch)')], [291,320]),
  row('missing', 'An ordinary inception has no prior digest, witness cuts or witness additions.',
    inception, 'not enforced structurally by the retained registration reader', [reg('pub fn event_binding(')], [291,590]),
  row('enforced', 'The initial controller keys are nonempty and distinct; the initial witnesses are distinct.',
    inception, 'Enforced on the decoded key material', [threshold('if list.is_empty(keys)'),threshold('} else if list.length(list.unique(keys))'),datum('} else if list.length(list.unique(witnesses))')]),
  row('missing', 'Derive a basic prefix from the sole signing key; require numeric signing threshold one.',
    prefix('def OpeningReads.binding '), 'not enforced; the booking issuer requires a digest identifier',
    [issue('expect Some(digest) = aid_digest(aid)'), reg('RegistrationInvalid(E2AidMismatch)')], [590]),
  row('missing', 'A non-transferable basic inception has no next keys, initial witnesses or signed seals.',
    prefix('def OpeningReads.binding '), 'not enforced; basic-prefix registration is unavailable', [issue('expect Some(digest) = aid_digest(aid)')], [590]),
  row('partial', 'For a self-addressing prefix, derive the identifier from the same original signed body.',
    prefix('def OpeningReads.binding '), 'Partial: E-code digest verification and token binding; structural decoding and other admitted digest codes remain open',
    [at('onchain/validators/hash_proof.ak','expect blake3.verify('), issue('let proof_name = proof_token_name(')], [291,590]),
  row('partial', 'Match current and next keys and thresholds, witness list and receipt threshold to the initial datum.',
    [at(model('InceptionPrefix'),'def verify '),at(model('ApplicationInceptionPrefix'),'def verify '),{...book,note:'initial state facts only'}],
    'Partial: the predicate compares all six projections; structural field identity remains open',
    [reg('RegistrationInvalid(E4CurKeysMismatch)'),reg('RegistrationInvalid(E9ToadMismatch)')], [291,590]),
  row('enforced', 'Verify the current controller quorum on the signed inception and the distinct witness receipts for that body.',
    inception, 'Enforced on the supplied event bytes in the registration predicate',
    [reg('let signed = verified_positions('),reg('let witnessed = verified_positions('),reg('let receipts_satisfied = if d.toad == 0')]),
  row('enforced', 'A zero signing threshold never authorizes a registration or advance, including with all signatures.',
    [dup('Threshold.satisfied')], 'Enforced by datum validation before acceptance; the bare quorum evaluator alone accepts zero',
    [datum('when threshold.well_formed(cur_keys'),threshold('if 1 <= m && m <= list.length(keys)'),threshold('Unweighted(m) -> list.length(valid) >= m')], [596]),
  row('enforced', 'Bound the declared next threshold by the available commitments and each individual weight by one.',
    next, 'Enforced for the flat F18 numeric/weighted domain; width and overweight refusal apply at registration and advance',
    [datum('when threshold.well_formed(next_keys'),threshold('if 1 <= m && m <= list.length(keys)'),threshold('} else if num > den {')], [595]),
  row('missing', 'A future numeric zero permits an empty next list, including ordinary abandonment; zero can also accompany a digest at inception.',
    [dup('rotationValid'),...inception], 'not enforced as an admission rule; the next-key codec refuses these valid declarations',
    [datum('when threshold.well_formed(next_keys'),threshold('if list.is_empty(keys)'),threshold('if 1 <= m && m <= list.length(keys)')], [590,591]),
  row('partial', 'Each declared weighted next clause must reach one, including the members of a nested group.',
    next, 'Partial: F18 sums flat clauses. Its weight type has no nested group', [threshold('Valid -> check_clause_sums(clauses)'),threshold('pub type Weight {')], [573,595]),
  row('enforced', 'A rotation proves its own signing quorum and the predecessor’s next quorum over revealed keys.',
    [dup('signingValid')], 'Enforced on the ordinary advance path', [adv('AdvanceInvalid(Eq6CurrentQuorumUnsatisfied)'),adv('spent.next_threshold,')]),
  row('partial', 'Advance reads a structurally decoded ordinary rotation, bound to the same AID and later native sequence.',
    [dup('rotationValid')], 'Partial: sequence and AID checks exist; structural event type remains open',
    [at(ck('advance'),'if !slice_matches(e.event_bytes, e.off_t'),adv('} else if !(new.seq == spent.seq + 1')], [291,320]),
  row('enforced', 'Each cut removes a previous witness; additions are new and disjoint from cuts.',
    witness, 'Enforced at advance for membership, duplicate entries and overlap', [adv('AdvanceInvalid(EqW1CutInvalid)'),adv('AdvanceInvalid(EqW2AddInvalid)')], [598]),
  // This checkout's successor check is the stronger `key_state_after_rotation_well_formed`: it applies the same receipt threshold
  // rule (`toad_ok`, zero exactly when no witness remains) and admits the abandonment state, so the coverage is unchanged. The
  // January column keeps the published pin's `key_state_well_formed`.
  {...row('enforced', 'Derive the incoming witnesses and require a positive receipt threshold when the resulting set is nonempty.',
    witness, 'Enforced at advance; an empty result permits zero', [adv('when key_state_well_formed(new)'),datum('1 <= toad && toad <= wit_count'),at(ck('advance'),'if e.wit_receipts != []')], [598]),
    main: {sites: [adv('when key_state_after_rotation_well_formed(new) is {'),datum('1 <= toad && toad <= wit_count'),at(ck('advance'),'if e.wit_receipts != []')]}},
  row('missing', 'Weighted threshold arithmetic accepts satisfiable unreduced weights and denominators above 2^32.',
    [dup('Weight.wellFormed')], 'not enforced as the same domain; F18 refuses both representations', [threshold('} else if math.gcd(num, den) != 1'),threshold('} else if den > max_weight_denom')], [597]),
  row('missing', 'Each rival rotation independently meets its next-rule width, weight and signing requirements against the common predecessor.',
    [dup('duplicity')], 'not enforced; the conviction predicate uses the installed tip quorum', [convict('} else if evidence.revealed_keys != tip.cur_keys'),convict('verified_positions(tip.cur_keys, evidence.event_bytes, evidence.ctrl_sigs)')], [573,595,596]),
  row('missing', 'Conviction derives the rival’s own witnesses, validates its cuts/additions, and tests its own receipt quorum.',
    [dup('duplicity')], 'not enforced; the conviction receipt check uses the tip witnesses and threshold',
    [convict('} else if count_receipts('),convict(') < tip.toad {')], [573,598]),
  row('missing', 'A valid same-position sibling can convict after abandonment; abandonment alone supplies no conflicting event.',
    [dup('duplicity')], 'not enforced over the model’s full sibling domain; the ordinary abandoning advance is also unavailable',
    [convict('} else if forward_agrees(tip, evidence)'),datum('when threshold.well_formed(next_keys')], [573,591]),
  row('missing', 'Compare distinct authenticated signed event identities for conviction.',
    [dup('duplicity')], 'not enforced; the predicate compares selected forward fields',
    [convict('fn forward_agrees(')], [573]),
];
