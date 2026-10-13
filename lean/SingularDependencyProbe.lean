import CardanoKeri
import CardanoKeri.Statements

-- A finite execution of the actual upstream function; not a KERI lifecycle.
private def state : Singular.RegistryState :=
  { config := { root := Singular.rootOf [], maxFee := 0,
                processTime := 0, retractTime := 0, applicationPolicy := 1,
                activePolicy := 2, absentPolicy := 3, terminalPolicy := 4 },
    trie := [], custody := [], held := [] }

#guard match Singular.step state (Singular.canonicalRequest .updateActive) with
  | .error reason => reason == "edge-inadmissible"
  | .ok _ => false

-- A different admitted edge reaches the next guard, discriminating the action.
#guard match Singular.step state (Singular.canonicalRequest .insertActive) with
  | .error reason => reason == "no-approval"
  | .ok _ => false

#print axioms CardanoKeri.singular_step_binding
