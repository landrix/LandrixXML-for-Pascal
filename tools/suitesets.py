"""Per test set report of a suite run, shared by run-qt3.py and
run-xslt-tests.py: for each test set the applicable cases, how many pass,
the pass rate and the difference to the passing cases of the baseline.

Every set the run loaded goes into a tab separated file next to the
results (also one whose cases are all excluded); on the console a set in
which a passing case of the baseline no longer passes is always named
("SET DOWN", even when the set or the whole run has more passing cases),
and with --sets the sets with the most cases that do not pass are
listed, the order in which to look at them. A rate that drops because
new cases became applicable (a new suite pin) is not reported: such a
pin comes with a new baseline.
"""
import argparse
import collections


def set_of(key):
    """The test set of a case key "set/case"."""
    return key.split("/", 1)[0]


def count(text):
    """argparse type of --sets: a count of 0 or more."""
    n = int(text)
    if n < 0:
        raise argparse.ArgumentTypeError("not a count: %s" % text)
    return n


def report(rows, base, path, top, skip=()):
    """rows: (key, outcome) of every case the run loaded ("excluded" ones
    too); base: key -> outcome of the baseline (only "pass" counts); path:
    the file for every set; top: how many sets to list (0: none); skip:
    keys left out of the comparison with the baseline (platform-dependent
    cases). Returns the sets in which a passing case of the baseline no
    longer passes."""
    stats = collections.defaultdict(collections.Counter)
    outcome_of = {}
    for key, outcome in rows:
        s = stats[set_of(key)]
        outcome_of[key] = outcome
        if outcome == "excluded":
            continue
        s["applicable"] += 1
        s[outcome] += 1
    for key, outcome in base.items():
        if outcome == "pass" and key not in skip:
            s = stats[set_of(key)]
            s["base"] += 1
            if outcome_of.get(key) == "pass":
                s["kept"] += 1
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("set\tapplicable\tpass\trate\twrong-code\tother\tbaseline-pass\tdelta\n")
        for name in sorted(stats):
            s = stats[name]
            other = s["applicable"] - s["pass"] - s["wrong-code"]
            f.write("%s\t%d\t%d\t%s\t%d\t%d\t%d\t%+d\n" % (
                name, s["applicable"], s["pass"], rate(s), s["wrong-code"], other, s["base"],
                s["pass"] - s["base"]))
    down = sorted(name for name, s in stats.items() if s["kept"] < s["base"])
    for name in down:
        s = stats[name]
        print("SET DOWN %s: %d of the %d passing cases of the baseline no longer pass" % (
            name, s["base"] - s["kept"], s["base"]))
    if top:
        ranked = sorted((name for name in stats if stats[name]["applicable"]),
                        key=lambda n: (-(stats[n]["applicable"] - stats[n]["pass"]), n))
        print("test sets by cases that do not pass (pass / applicable, rate, change to baseline):")
        for name in ranked[:top]:
            s = stats[name]
            if s["applicable"] == s["pass"]:
                break
            print("  %-32s %6d / %6d  %6s  %+d" % (name, s["pass"], s["applicable"], rate(s),
                                                  s["pass"] - s["base"]))
        print("every set: %s" % path)
    return down


def rate(s):
    if not s["applicable"]:
        return "-"
    return "%.1f%%" % (100.0 * s["pass"] / s["applicable"])
