//// Unit tests for observer claim/envelope decoding and action matching
//// (A-004 family split + R3 four-program: lifecycle Register-only,
//// dedicated advance observer, enforcement Freeze/Convict-only).
//// Honest event-own ObserveAdvance topology lives in
//// validators/checkpoint_observer_tests.ak (cannot import cage_context here).

use cardano/assets.{PolicyId}
use cardano/transaction.{placeholder}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, validate_enforcement,
  validate_lifecycle,
}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

/// Lifecycle rejects ObserveAdvance (four-program: Advance is not lifecycle).
/// Malformed payload also fails; honest-path reject is in the validator suite.
test t115_r1_reject_lifecycle_observe_advance_in_r1() fail {
  let claim = ObserverClaim {
    action: observe_advance,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: 0 }
  validate_lifecycle(hp_policy, 1_000_000_000, envelope, placeholder)
}

test t115_r1_reject_lifecycle_unknown_observer_action() fail {
  let claim = ObserverClaim {
    action: 99,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: 0 }
  validate_lifecycle(hp_policy, 1_000_000_000, envelope, placeholder)
}

test t115_r1_reject_enforcement_observe_advance_in_r1() fail {
  let claim = ObserverClaim {
    action: observe_advance,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: 0 }
  validate_enforcement(envelope, placeholder)
}

test t115_r1_reject_enforcement_unknown_observer_action() fail {
  let claim = ObserverClaim {
    action: 99,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: 0 }
  validate_enforcement(envelope, placeholder)
}
