import Singular

namespace CardanoKeri

/-- Dependency binding only. Given any upstream registry state, when the
canonical updateActive request is stepped, then the excluded edge is refused
before approval lookup. This does not relate the KERI and Singular machines. -/
theorem singular_step_binding (s : Singular.RegistryState) :
    Singular.step s (Singular.canonicalRequest .updateActive) =
      .error "edge-inadmissible" := rfl

end CardanoKeri
