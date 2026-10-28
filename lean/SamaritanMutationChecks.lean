import CardanoKeri.Samaritan

open CardanoKeri.Samaritan

-- Infer the proposition from the actual Reap.hFund field. This fixture tests
-- the constructor's admitted domain, including amounts outside that domain.
def admitted (Mc Mr tip fee : Nat) : Option Reap :=
  if h : _ then some { Mc, Mr, tip, fReap := fee, hFund := h } else none

def main : IO Unit := do
  let check (name : String) (condition : Bool) : IO Unit :=
    unless condition do throw (IO.userError name)
  check "SM-01:underfunded-constructor-refused" ((admitted 4 4 1 1).isNone)
  let some r := admitted 4 2 1 2 | throw (IO.userError "funded-constructor")
  check "SM-02:request-includes-tip" ((reap r).intoRequest == 3)
  check "SM-03:premium-deducts-tip" ((reap r).premium == 1)
  check "SM-04:fee-is-external" ((reap r).reaperPays == 2)
  check "funded-conservation" ((reap r).intoRequest + (reap r).premium == 4)
  check "underfunded-booker-loses" ((reap r).premium < (reap r).reaperPays)
  IO.println "PASS actual Reap constructor domain, request, premium, external fee and strict-loss witness"
