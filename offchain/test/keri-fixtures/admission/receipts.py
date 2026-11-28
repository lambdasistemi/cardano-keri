"""Shared readers for the receipts of one run. Every reader fails (SystemExit with a message) on a missing,
unexpected, duplicated or contradictory receipt: a coverage exclusion is declared by the producer, never inferred
from an absent line.
"""
import itertools, re

ANSI = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")
HEADER = re.compile(r"^\s*│\s*(PASS|FAIL)\s+\[[^\]]*\]\s+(?:\S+\.)?(\w+)\s*$")
TRACE = re.compile(r"^\s*│\s*\|\s*(.*?)\s*$")
SUMMARY = re.compile(r"┕━+\s*(\d+) tests \| (\d+) passed \| (\d+) failed")


def die(msg):
    raise SystemExit("receipts: " + msg)


def transcript(path):
    """(tests, summary): tests is a list of (status, name, [trace lines]) in order; summary is (n, passed, failed) or None."""
    tests, summary, cur = [], None, None
    for line in open(path, encoding="utf-8"):
        line = ANSI.sub("", line).replace("\r", "").rstrip()
        m = HEADER.match(line)
        if m:
            cur = (m.group(1), m.group(2), [])
            tests.append(cur)
            continue
        m = SUMMARY.search(line)
        if m:
            summary = tuple(int(x) for x in m.groups())
            cur = None
            continue
        m = TRACE.match(line)
        if m and cur is not None:
            cur[2].append(m.group(1))
    return tests, summary


def check_suite(path, tests, summary, expected):
    """The transcript holds exactly the expected tests, once each, and its completion summary agrees."""
    names = [t[1] for t in tests]
    missing = sorted(set(expected) - set(names))
    unexpected = sorted(set(names) - set(expected))
    dups = sorted({n for n in names if names.count(n) > 1})
    if missing:
        die("%s: no result for %s" % (path, ", ".join(missing[:5])))
    if unexpected:
        die("%s: unexpected result %s" % (path, ", ".join(unexpected[:5])))
    if dups:
        die("%s: more than one result for %s" % (path, ", ".join(dups[:5])))
    if summary is None:
        die("%s: no completion summary" % path)
    if summary[0] != len(expected) or summary[1] + summary[2] != summary[0]:
        die("%s: completion summary %s does not match %d expected tests" % (path, summary, len(expected)))
    passed = sum(1 for t in tests if t[0] == "PASS")
    if passed != summary[1]:
        die("%s: summary reports %d passed, the results show %d" % (path, summary[1], passed))


def verdicts(path, prefix, expected_ids, allowed):
    """{case id: verdict} from a suite whose tests print one typed verdict each (and fail on purpose)."""
    tests, summary = transcript(path)
    check_suite(path, tests, summary, [prefix + i for i in expected_ids])
    out = {}
    for status, name, traces in tests:
        if len(traces) != 1:
            die("%s: %s has %d verdict traces, expected exactly one" % (path, name, len(traces)))
        if traces[0] not in allowed:
            die("%s: %s printed an unrecognized verdict %r" % (path, name, traces[0]))
        out[name[len(prefix):]] = traces[0]
    return out


def representable(th):
    if "count" in th:
        return True
    return "weighted" in th and all("key" in w for clause in th["weighted"] for w in clause)


def subset_label(who):
    return "".join(str(i) for i in who) or "none"


def threshold_test_names(cases):
    """The Aiken tests the generator writes for the representable threshold cases."""
    names = []
    for c in cases:
        if not representable(c["threshold"]):
            continue
        names.append("wf_" + c["id"])
        for r in range(2 ** c["n"]):
            names.append("ev_%s_%s" % (c["id"], subset_label([i for i in range(c["n"]) if (r >> i) & 1])))
    return names


def threshold_results(path, cases):
    """{test name: passed} for exactly the expected threshold tests."""
    tests, summary = transcript(path)
    check_suite(path, tests, summary, threshold_test_names(cases))
    return {t[1]: t[0] == "PASS" for t in tests}


def lean_subsets(n):
    return {"".join(str(i) for i in s) for r in range(n + 1) for s in itertools.combinations(range(n), r)}
