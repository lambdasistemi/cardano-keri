"""Compare indexed model bookings to keripy inception construction and signed Serder reads."""
import ctypes.util
import json
import os
import sys

system_find_library = ctypes.util.find_library


def find_library(name):
    if name in ("sodium", "libsodium"):
        return os.environ["SODIUM_LIB"]
    return system_find_library(name)


ctypes.util.find_library = find_library
import keri
from keri import kering
from keri.core import coring, eventing, serdering, signing

assert keri.__version__ == '1.3.5'
with open(sys.argv[1], encoding="utf-8") as source:
    model = dict(json.load(source))

transferable = signing.Signer(transferable=True)
nontransferable = signing.Signer(transferable=False)
witness = signing.Signer(transferable=False)
next_digest = coring.Diger(ser=transferable.verfer.qb64b).qb64


def check(label, signer, expect, **fields):
    try:
        event = eventing.incept(keys=[signer.verfer.qb64], **fields)
        parsed = serdering.SerderKERI(raw=event.raw)
        assert signer.verfer.verify(signer.sign(ser=parsed.raw).raw, parsed.raw)
    except (kering.ValidationError, ValueError):
        actual = False
    else:
        actual = True
    lean = model.pop(label)
    assert actual == lean == expect, (label, actual, lean, expect)
    print(label, 'admitted' if actual else 'refused')


check('B empty', nontransferable, True)
check('D empty', transferable, True)
check('B next', nontransferable, False, ndigs=[next_digest])
check('D next', transferable, True, ndigs=[next_digest])
check('B witness', nontransferable, False, wits=[witness.verfer.qb64], toad=1)
check('D witness', transferable, True, wits=[witness.verfer.qb64], toad=1)
check('B seal', nontransferable, False, data=[{'d': next_digest}])
check('D seal', transferable, True, data=[{'d': next_digest}])
check('D weighted one', transferable, False, isith=['1'])
check('E digest', transferable, True, code=coring.MtrDex.Blake3_256)
check('D missing next', transferable, False, nsith=1)
check('D oversized next', transferable, False, ndigs=[next_digest], nsith=2)
check('B missing next', nontransferable, False, nsith=1)
check('E zero signing', transferable, False, code=coring.MtrDex.Blake3_256, isith=0)
check('D zero next with digest', transferable, True, ndigs=[next_digest], nsith=0)
assert not model, model
