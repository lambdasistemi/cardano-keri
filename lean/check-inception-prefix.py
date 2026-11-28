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
from keri.db import basing

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
# Each digest names a different next key; only the current key signs the inception.
next_digests = [
    coring.Diger(ser=signing.Signer().verfer.qb64b).qb64 for _ in range(3)
]
future_cases = [
    ('D next below one', 2, ['1/3', '1/3'], False),
    ('D next unreduced', 2, ['2/4', '2/4'], True),
    ('D next partial coverage', 3, [['1'], ['1']], True),
    ('D weighted next without commitments', 0, ['1'], False),
    ('D next exact one', 2, ['1/2', '1/2'], True),
    ('D next second clause below one', 2, [['1'], ['1/3']], False),
    ('D next inner below one', 3, ['1', {'1/2': ['1/3', '1/3']}], False),
    ('D next nested exact one', 3, ['1/2', {'1/2': ['1/2', '1/2']}], True),
    ('D next no clauses', 0, [], False),
]
mismatches = []
for label, count, declaration, expected in future_cases:
    try:
        written = eventing.incept(keys=[transferable.verfer.qb64],
                                  ndigs=next_digests[:count], nsith=declaration)
    except ValueError as err:
        actual, detail = False, str(err)
    else:
        parsed = serdering.SerderKERI(raw=written.raw)
        signature = transferable.sign(ser=parsed.raw, index=0)
        with basing.openDB() as db:
            state = eventing.Kever(serder=parsed, sigers=[signature], db=db)
            assert state.serder.said == written.said
        actual, detail = True, f"signed nt={parsed.sad['nt']!r}"
        if label == 'D next unreduced':
            assert parsed.sad['nt'] == ['1/2', '1/2']
            # The writer normalizes its input. Also verify an inception whose
            # original signed JSON actually contains the unreduced spelling.
            source = serdering.SerderKERI(sad=dict(parsed.sad, nt=declaration), makify=True)
            wire = serdering.SerderKERI(raw=source.raw)
            with basing.openDB() as db:
                signed = transferable.sign(ser=wire.raw, index=0)
                received = eventing.Kever(serder=wire, sigers=[signed], db=db)
                assert wire.sad['nt'] == declaration
                assert received.ntholder.sith == ['1/2', '1/2']
            detail += f", signed literal {wire.sad['nt']!r} also admitted"
    lean = model.pop(label)
    print(f"{label}: keripy={actual} Lean={lean} ({detail})")
    if (actual, lean) != (expected, expected):
        mismatches.append((label, actual, lean, expected))
assert not model, model
assert not mismatches, mismatches
