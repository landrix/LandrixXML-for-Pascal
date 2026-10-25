#!/usr/bin/env python3
"""Run the W3C XPath/XQuery test suite QT3 (XPath 2.0 cases) against LandrixXml.

Downloads the suite at a pinned commit into tests/data/qt3-suite/
(git-ignored, not redistributed), selects the test cases that apply to
XPath 2.0 and lets the helper tests/LandrixXmlQt3.dpr evaluate them; this
script checks the assertions and compares the outcome with the committed
baseline tests/data/qt3-baseline.txt.

Applicability: the dependencies of the test set and of the test case
must all hold (the tokens of one spec value are alternatives): spec
XP20 or XP20+, no optional feature, XML 1.0 (fifth edition), XSD 1.0.
Environments with schemas, typed sources, collections, collations, a
static base URI, decimal formats or resources are not provided.

Assertions: values are checked here from the typed lines the helper
writes (type and string value per item), so that the engine does not
judge itself: assert-true/false (a single xs:boolean), assert-empty,
assert-count, assert-string-value, assert-type (from the item types),
error codes, and assert-eq/assert-deep-eq/assert-permutation against
the expected expression evaluated on its own. Only assert (an XPath
expression over $result) is evaluated by the engine. assert-xml and the
serialization assertions are not supported yet.

Outcomes: pass; wrong-code (an error was expected, another code came);
fail (with the error our engine raised, or "value"); assertion-error
(the engine could not evaluate an assert expression);
assertion-unsupported; excluded (not applicable, with the reason);
harness-error (crash, timeout, setup).

Usage:
  python tools/run-qt3.py [--exe PATH] [--filter PREFIX] [--jobs N]
                          [--profile xpath20|saxon] [--update-baseline]
                          [--verbose] [--self-test]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlQt3.dpr -NoRun
Exit code: 0 if no baseline case got worse and no harness error occurred.
Results per case: build/qt3/results-PROFILE.txt. --self-test checks the assertion
checks on made-up results.
"""

import argparse
import collections
import concurrent.futures
import decimal
import hashlib
import http.client
import io
import os
import re
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMIT = "201a6e466940cdfc727f4babfedcde5332b9f578"
URL = "https://codeload.github.com/w3c/qt3tests/tar.gz/" + COMMIT
CATALOG_SHA256 = "d65d6fb5e77776a537db32ca59554cbf00388a38f2c532866691de9e668e88ea"
SUITE_DIR = os.path.join(ROOT, "tests", "data", "qt3-suite")
SUITE = os.path.join(SUITE_DIR, "qt3tests-" + COMMIT)
BASELINES = {"xpath20": os.path.join(ROOT, "tests", "data", "qt3-baseline.txt"),
             "saxon": os.path.join(ROOT, "tests", "data", "qt3-baseline-saxon.txt")}
BASELINE = BASELINES["xpath20"]
WORK = os.path.join(ROOT, "build", "qt3")
HARNESS_VERSION = "1"
PROFILE = "xpath20"
NS = "{http://www.w3.org/2010/09/qt-fots-catalog}"

# Cases whose outcome depends on the platform: neither in the baseline nor
# a regression, reported on their own.
PLATFORM_DEPENDENT = {
    "fn-count/cbcl-count-001": "10^7 items do not fit into a 32-bit process",
}

SPECS = {"XP20", "XP20+"}
XML_VERSIONS = {"1.0", "1.0:5+"}
XSD_VERSIONS = {"1.0"}


def read_url(url, timeout=120):
    """The body of url; a failed request is retried, as runners lose DNS now and then.
    An HTTP client error other than 408 and 429 fails at once."""
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as resp:
                return resp.read()
        except (OSError, http.client.HTTPException) as e:
            permanent = (isinstance(e, urllib.error.HTTPError) and 400 <= e.code < 500
                         and e.code not in (408, 429))
            if permanent or attempt == 3:
                raise
            print("download failed (%s), retrying" % e)
            time.sleep(10 * (attempt + 1))


def download():
    os.makedirs(SUITE_DIR, exist_ok=True)
    print("downloading", URL)
    data = read_url(URL)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar.getmembers():
            name = os.path.normpath(member.name)
            if name.startswith("..") or os.path.isabs(name) or not (member.isfile() or member.isdir()):
                sys.exit("unexpected archive member: " + member.name)
        tar.extractall(SUITE_DIR)


def check_catalog():
    with open(os.path.join(SUITE, "catalog.xml"), "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    if digest != CATALOG_SHA256:
        sys.exit("catalog.xml has SHA-256 %s, expected %s" % (digest, CATALOG_SHA256))


# --- applicability ---------------------------------------------------------

def dependency_problem(dep):
    kind, value = dep.get("type"), dep.get("value", "")
    satisfied = dep.get("satisfied", "true") == "true"
    tokens = set(value.split())
    if kind == "spec":
        have = bool(tokens & SPECS)
    elif kind == "feature":
        have = False
    elif kind == "xml-version":
        have = bool(tokens & XML_VERSIONS)
    elif kind == "xsd-version":
        have = bool(tokens & XSD_VERSIONS)
    else:
        have = None
    if have is None:
        return "dependency %s %s" % (kind, value)
    if have != satisfied:
        return "%s %s%s" % (kind, value, "" if satisfied else " (not)")
    return None


# --- environments ----------------------------------------------------------

class Environment:
    def __init__(self, el, base):
        self.problem = None
        self.source = None
        self.vars = []
        self.docs = []
        self.ns = []
        self.params = []
        for ch in el:
            tag = ch.tag.replace(NS, "")
            if tag == "source":
                if ch.get("validation") not in (None, "skip"):
                    self.problem = "typed source"
                    continue
                path = os.path.join(base, ch.get("file", ""))
                role = ch.get("role")
                if role and ch.get("uri"):
                    # doc(uri) must return the same document: not provided yet
                    self.problem = "source with role and uri"
                elif role == ".":
                    self.source = path
                elif role and role.startswith("$"):
                    self.vars.append((role[1:], path))
                elif ch.get("uri"):
                    self.docs.append((ch.get("uri"), path))
                else:
                    self.problem = "source without role"
            elif tag == "param":
                if ch.get("select") is None or ch.get("source"):
                    self.problem = "param without select"
                else:
                    self.params.append((ch.get("name"), ch.get("select")))
            elif tag == "namespace":
                self.ns.append((ch.get("prefix"), ch.get("uri")))
            elif tag == "description" or tag == "created" or tag == "modified":
                pass
            else:
                self.problem = "environment " + tag


# --- the cases ---------------------------------------------------------------

class Case:
    def __init__(self, test_set, name, category):
        self.test_set = test_set
        self.name = name
        self.category = category
        self.excluded = None
        self.env = None
        self.expr = None
        self.result = None
        self.checks = []
        self.values = []
        # assertion element (id) -> number of its check or value
        self.idx = {}
        self.outcome = None
        self.detail = ""

    @property
    def key(self):
        return self.test_set + "/" + self.name


def plan_assertion(case, el):
    """Number the checks and values the assertion tree needs (case.idx)."""
    tag = el.tag.replace(NS, "")
    if tag in ("any-of", "all-of", "not"):
        for ch in el:
            plan_assertion(case, ch)
    elif tag == "assert":
        case.checks.append(el.text or "")
        case.idx[id(el)] = len(case.checks)
    elif tag in ("assert-eq", "assert-deep-eq", "assert-permutation"):
        case.values.append(el.text or "")
        case.idx[id(el)] = len(case.values)


def load_cases(filt):
    catalog = ET.parse(os.path.join(SUITE, "catalog.xml")).getroot()
    global_envs = {}
    for e in catalog.findall(NS + "environment"):
        global_envs[e.get("name")] = Environment(e, SUITE)
    cases = []
    for ts in catalog.findall(NS + "test-set"):
        name, file = ts.get("name"), ts.get("file")
        if filt and not name.startswith(filt):
            continue
        path = os.path.join(SUITE, file)
        base = os.path.dirname(path)
        root = ET.parse(path).getroot()
        set_envs = {}
        for e in root.findall(NS + "environment"):
            if e.get("name"):
                set_envs[e.get("name")] = Environment(e, base)
        set_deps = root.findall(NS + "dependency")
        for tc in root.findall(NS + "test-case"):
            case = Case(name, tc.get("name"), file.split("/")[0])
            cases.append(case)
            for dep in set_deps + tc.findall(NS + "dependency"):
                problem = dependency_problem(dep)
                if problem:
                    case.excluded = problem
                    break
            if case.excluded:
                continue
            env = tc.find(NS + "environment")
            if env is not None:
                ref = env.get("ref")
                if ref:
                    case.env = set_envs.get(ref) or global_envs.get(ref)
                    if case.env is None:
                        case.excluded = "unknown environment " + ref
                        continue
                else:
                    case.env = Environment(env, base)
                if case.env.problem:
                    case.excluded = case.env.problem
                    continue
            test = tc.find(NS + "test")
            if test is None or test.get("file"):
                case.excluded = "test in a file"
                continue
            case.expr = test.text or ""
            case.result = list(tc.find(NS + "result"))[0]
            plan_assertion(case, case.result)
    return cases


# --- helper protocol ---------------------------------------------------------

def esc(s, spaces=False):
    out = []
    for ch in s:
        if ord(ch) < 32 or ch == chr(92) or (spaces and ch == " "):
            out.append(chr(92) + "x%02X" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


ESC_RE = re.compile(re.escape(chr(92)) + "x([0-9A-Fa-f]{2})")


def unesc(s):
    return ESC_RE.sub(lambda m: chr(int(m.group(1), 16)), s)


def job_text(cases, profile):
    lines = []
    for c in cases:
        lines.append("case " + esc(c.name, True))
        if profile == "saxon":
            lines.append("profile saxon")
        env = c.env
        if env:
            if env.source:
                lines.append("source " + esc(env.source))
            for n, p in env.vars:
                lines.append("var %s %s" % (esc(n, True), esc(p)))
            for u, p in env.docs:
                lines.append("doc %s %s" % (esc(u, True), esc(p)))
            for prefix, uri in env.ns:
                lines.append("ns %s %s" % (esc(prefix, True), esc(uri)))
            for n, s in env.params:
                lines.append("param %s %s" % (esc(n, True), esc(s)))
        lines.append("expr " + esc(c.expr))
        for x in c.checks:
            lines.append("check " + esc(x))
        for x in c.values:
            lines.append("value " + esc(x))
        lines.append("run")
    return "\n".join(lines) + "\n"


def parse_output(text):
    """{case name: {tag: value}}; a value is ("error", code, msg) or a list
    of items (type, name, string); "done" marks a complete case."""
    out = collections.OrderedDict()
    cur = None
    for line in text.split("\n"):
        if not line:
            continue
        head, _, rest = line.partition(" ")
        if head == "case":
            cur = {"done": False}
            out[unesc(rest)] = cur
        elif cur is None:
            continue
        elif head == "done":
            cur["done"] = True
        elif head == "setup":
            cur["setup"] = unesc(rest.partition(" ")[2])
        else:
            kind, _, rest = rest.partition(" ")
            if kind == "count":
                cur[head] = []
            elif kind in ("error", "exception"):
                code, _, msg = rest.partition(" ")
                cur[head] = (kind, code, unesc(msg))
            elif kind == "node":
                nk, _, rest = rest.partition(" ")
                name, _, value = rest.partition(" ")
                cur.setdefault(head, []).append(("node:" + nk, unesc(name), unesc(value)))
            else:
                cur.setdefault(head, []).append((kind, None, unesc(rest)))
    return out


def run_set(exe, cases, timeout_per_case, profile):
    """Run the cases of one test set; resume after a crash or timeout."""
    os.makedirs(os.path.join(WORK, "jobs"), exist_ok=True)
    name = cases[0].test_set
    job = os.path.join(WORK, "jobs", "%s.%s.job" % (name, profile))
    with open(job, "w", encoding="utf-8", newline="\n") as f:
        f.write(job_text(cases, profile))
    results = {}
    first = 0
    attempt = 0
    while first < len(cases):
        attempt += 1
        out = os.path.join(WORK, "jobs", "%s.%s.%d.out" % (name, profile, attempt))
        # never read the output of an earlier run
        if os.path.exists(out):
            os.remove(out)
        problem = None
        try:
            subprocess.run([exe, job, out, str(first)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=10 + timeout_per_case * (len(cases) - first))
        except subprocess.TimeoutExpired:
            problem = "timeout"
        text = ""
        if os.path.exists(out):
            with open(out, encoding="utf-8", errors="replace", newline="") as f:
                text = f.read()
        parsed = parse_output(text)
        done = 0
        for k in range(first, len(cases)):
            r = parsed.get(cases[k].name)
            if r is None or not r["done"]:
                break
            results[cases[k].name] = r
            done += 1
        first += done
        if first < len(cases):
            # the case after the last complete one crashed or hung
            results[cases[first].name] = {"harness": problem or "crash"}
            first += 1
    return results


# --- values ------------------------------------------------------------------

# the types derived from xs:integer and the type each one restricts
INTEGER_BASES = {
    "xs:nonPositiveInteger": "xs:integer", "xs:negativeInteger": "xs:nonPositiveInteger",
    "xs:long": "xs:integer", "xs:int": "xs:long", "xs:short": "xs:int", "xs:byte": "xs:short",
    "xs:nonNegativeInteger": "xs:integer", "xs:unsignedLong": "xs:nonNegativeInteger",
    "xs:unsignedInt": "xs:unsignedLong", "xs:unsignedShort": "xs:unsignedInt",
    "xs:unsignedByte": "xs:unsignedShort", "xs:positiveInteger": "xs:nonNegativeInteger",
}
NUMERIC = {"xs:integer", "xs:decimal", "xs:double"} | set(INTEGER_BASES)
# the types derived from xs:string and the type each one restricts
STRING_BASES = {
    "xs:normalizedString": "xs:string", "xs:token": "xs:normalizedString",
    "xs:language": "xs:token", "xs:NMTOKEN": "xs:token", "xs:Name": "xs:token",
    "xs:NCName": "xs:Name", "xs:ID": "xs:NCName", "xs:IDREF": "xs:NCName", "xs:ENTITY": "xs:NCName",
}
STRINGS = {"xs:string", "xs:anyURI", "xs:untypedAtomic"} | set(STRING_BASES)


def number(t, v):
    if t == "xs:double":
        try:
            return float(v.replace("INF", "inf"))
        except ValueError:
            return float("nan")
    return decimal.Decimal(v)


def same_number(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return float(a) == float(b)
    return a == b


TEMPORAL_RE = re.compile(r"^(-?\d{4,})-(\d\d)-(\d\d)(?:T(\d\d):(\d\d):(\d\d)(\.\d+)?)?(Z|[+-]\d\d:\d\d)?$")
TIME_RE = re.compile(r"^(\d\d):(\d\d):(\d\d)(\.\d+)?(Z|[+-]\d\d:\d\d)?$")


def days_from_civil(y, m, d):
    """Days since 1970-01-01 in the proleptic Gregorian calendar; y is the
    astronomical year (0 = 1 BCE). Python's // rounds down for negative
    numbers, so no correction is needed."""
    y -= m <= 2
    era = y // 400
    yoe = y - era * 400
    doy = (153 * (m + (-3 if m > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def temporal_key(t, v):
    """A date, dateTime or time as (has time zone, seconds, fraction):
    equal values give equal keys (time zones applied; 24:00:00 is the
    next day of a date, midnight of a time); None if it cannot be read."""
    if t == "xs:time":
        m = TIME_RE.match(v)
        if not m:
            return None
        year, month, day = 1972, 12, 31
        hh, mi, ss, frac, zone = m.groups()
        if hh == "24":
            # xs:time 24:00:00 is 00:00:00
            hh = "00"
    else:
        m = TEMPORAL_RE.match(v)
        if not m:
            return None
        year, month, day, hh, mi, ss, frac, zone = m.groups()
        year, month, day = int(year), int(month), int(day)
        if t == "xs:date":
            hh = mi = ss = "00"
    if year > 0:
        days = days_from_civil(year, month, day)
    else:
        # XSD 1.0 as Xerces and the engine count: no year 0, the year -N as
        # long as the year N, the years before 1 backwards from 0001-01-01
        n = -year
        first = days_from_civil(1, 1, 1)
        days = 2 * first - days_from_civil(n + 1, 1, 1) + days_from_civil(n, month, day) - days_from_civil(n, 1, 1)
    seconds = days * 86400 + int(hh) * 3600 + int(mi) * 60 + int(ss)
    if zone and zone != "Z":
        sign = -1 if zone[0] == "+" else 1
        seconds += sign * (int(zone[1:3]) * 3600 + int(zone[4:6]) * 60)
    return (zone is not None, seconds, decimal.Decimal(frac or ".0"))


DURATIONS = {"xs:duration", "xs:yearMonthDuration", "xs:dayTimeDuration"}
DURATION_RE = re.compile(r"^(-)?P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$")


def duration_key(v):
    """A duration as (months, seconds); None if it cannot be read."""
    m = DURATION_RE.match(v)
    if not m or v.endswith("P") or v.endswith("T"):
        return None
    sign, y, mo, d, h, mi, sec = m.groups()
    months = int(y or 0) * 12 + int(mo or 0)
    seconds = (int(d or 0) * 86400 + int(h or 0) * 3600 + int(mi or 0) * 60) + decimal.Decimal(sec or 0)
    if sign:
        months, seconds = -months, -seconds
    return (months, seconds)


def atomic_equal(x, y, deep=False):
    """eq of two items from the serialization (nodes atomized to
    xs:untypedAtomic, which compares as a string); None if not decidable
    here (nodes in deep-equal)."""
    (tx, _, vx), (ty, _, vy) = x, y
    if tx.startswith("node:") or ty.startswith("node:"):
        if deep:
            return None
        tx = "xs:untypedAtomic" if tx.startswith("node:") else tx
        ty = "xs:untypedAtomic" if ty.startswith("node:") else ty
    if tx in NUMERIC and ty in NUMERIC:
        try:
            a, b = number(tx, vx), number(ty, vy)
        except decimal.InvalidOperation:
            return False
        if deep and isinstance(a, float) and isinstance(b, float) and a != a and b != b:
            return True
        return same_number(a, b)
    if tx in STRINGS and ty in STRINGS:
        return vx == vy
    if tx in DURATIONS and ty in DURATIONS:
        kx, ky = duration_key(vx), duration_key(vy)
        if kx is None or ky is None:
            return vx == vy
        return kx == ky
    if tx == ty and tx in ("xs:date", "xs:dateTime", "xs:time"):
        kx, ky = temporal_key(tx, vx), temporal_key(ty, vy)
        if kx is None or ky is None:
            return vx == vy
        # a value without time zone is in the implicit time zone, which is
        # UTC in the helper (the engine's default)
        return kx[1:] == ky[1:]
    if tx == ty:
        return vx == vy
    return False


def permutation_equal(a, b):
    """The same items in any order (deep-equal per item, with counts);
    None if not decidable here."""
    if len(a) != len(b):
        return False
    edges = []
    for x in a:
        row = []
        for k, y in enumerate(b):
            same = atomic_equal(x, y, True)
            if same is None:
                return None
            if same:
                row.append(k)
        edges.append(row)
    # a perfect matching (augmenting paths, found breadth first without
    # recursion): equality with numeric promotion is not transitive, so a
    # greedy match is not enough
    owner = [-1] * len(b)
    match = [-1] * len(a)
    for i in range(len(a)):
        reached = {}
        queue = collections.deque([i])
        found = -1
        while queue and found < 0:
            u = queue.popleft()
            for k in edges[u]:
                if k in reached:
                    continue
                reached[k] = u
                if owner[k] < 0:
                    found = k
                    break
                queue.append(owner[k])
        if found < 0:
            return False
        k = found
        while k >= 0:
            u = reached[k]
            before = match[u]
            owner[k], match[u] = u, k
            k = before
    return True


XML_SPACE_RE = re.compile("[ \t\r\n]+")


def normalize_space(s):
    """fn:normalize-space: XML white space only (not U+00A0)."""
    return XML_SPACE_RE.sub(" ", s).strip(" ")


ATOMIC_PARENTS = {
    "xs:integer": {"xs:integer", "xs:decimal", "xs:anyAtomicType"},
    "xs:decimal": {"xs:decimal", "xs:anyAtomicType"},
    "xs:double": {"xs:double", "xs:anyAtomicType"},
    "xs:string": {"xs:string", "xs:anyAtomicType"},
    "xs:anyURI": {"xs:anyURI", "xs:anyAtomicType"},
    "xs:untypedAtomic": {"xs:untypedAtomic", "xs:anyAtomicType"},
    "xs:boolean": {"xs:boolean", "xs:anyAtomicType"},
    "xs:date": {"xs:date", "xs:anyAtomicType"},
    "xs:dateTime": {"xs:dateTime", "xs:anyAtomicType"},
    "xs:time": {"xs:time", "xs:anyAtomicType"},
    "xs:duration": {"xs:duration", "xs:anyAtomicType"},
    "xs:yearMonthDuration": {"xs:yearMonthDuration", "xs:duration", "xs:anyAtomicType"},
    "xs:dayTimeDuration": {"xs:dayTimeDuration", "xs:duration", "xs:anyAtomicType"},
}
for _derived in STRING_BASES:
    _chain, _t = {_derived}, _derived
    while _t in STRING_BASES:
        _t = STRING_BASES[_t]
        _chain.add(_t)
    ATOMIC_PARENTS[_derived] = _chain | ATOMIC_PARENTS["xs:string"]
for _derived in INTEGER_BASES:
    _chain, _t = {_derived}, _derived
    while _t in INTEGER_BASES:
        _t = INTEGER_BASES[_t]
        _chain.add(_t)
    ATOMIC_PARENTS[_derived] = _chain | ATOMIC_PARENTS["xs:integer"]
NODE_TESTS = {"element": "element", "attribute": "attribute", "text": "text", "comment": "comment",
              "processing-instruction": "processing-instruction", "document-node": "document-node"}


def type_matches(items, t):
    """assert-type from the item types; None if the type cannot be read."""
    t = " ".join(t.split())
    if t == "empty-sequence()":
        return len(items) == 0
    occ = ""
    if t and t[-1] in "?*+":
        occ, t = t[-1], t[:-1].strip()
    n = len(items)
    if (occ == "" and n != 1) or (occ == "?" and n > 1) or (occ == "+" and n < 1):
        return False
    for typ, name, _ in items:
        if t == "item()":
            continue
        if t == "node()":
            if not typ.startswith("node:"):
                return False
            continue
        m = re.match(r"^([a-z-]+)\((.*)\)$", t)
        if m:
            kind = NODE_TESTS.get(m.group(1))
            if kind is None:
                return None
            if typ != "node:" + kind:
                return False
            arg = m.group(2).strip()
            if arg and arg != "*" and kind in ("element", "attribute"):
                if "," in arg or ":" in arg:
                    return None
                # no default element namespace in the static context
                if name != "Q{}" + arg:
                    return False
            elif arg and arg != "*":
                return None
            continue
        if not t.startswith("xs:"):
            return None
        if typ.startswith("node:") or t not in ATOMIC_PARENTS.get(typ, ()):
            return False
    return True


# --- assertions --------------------------------------------------------------

def effective_boolean(items):
    """fn:boolean of the serialized items; None for FORG0006."""
    if not items:
        return False
    t, _, v = items[0]
    if t.startswith("node:"):
        return True
    if len(items) > 1:
        return None
    if t == "xs:boolean":
        return v == "true"
    if t in STRINGS:
        return v != ""
    if t in NUMERIC:
        x = number(t, v)
        return x == x and x != 0
    return None


RANK = {"pass": 0, "wrong-code": 1, "assertion-unsupported": 2, "assertion-error": 3, "fail": 4}


def check(el, r, idx):
    """(outcome, detail) of the assertion el against the case result r."""
    tag = el.tag.replace(NS, "")
    got = r.get("R")
    if tag in ("any-of", "all-of"):
        subs = [check(ch, r, idx) for ch in el]
        if tag == "any-of":
            return min(subs, key=lambda s: RANK[s[0]])
        return max(subs, key=lambda s: RANK[s[0]])
    if tag == "not":
        o, d = check(list(el)[0], r, idx)
        if o == "pass":
            return "fail", "not: " + d
        if o == "fail":
            return "pass", ""
        return o, d
    if tag == "error":
        code = el.get("code", "*")
        if isinstance(got, tuple) and got[0] == "error":
            if code == "*" or got[1] == code or got[1].endswith(":" + code):
                return "pass", ""
            return "wrong-code", "expected %s, got %s" % (code, got[1])
        if isinstance(got, tuple):
            # another exception is a defect, never the expected error
            return "fail", "exception %s: %s" % (got[1], got[2][:200])
        return "fail", "expected error %s, got %s" % (code, show(got))
    if isinstance(got, tuple):
        return "fail", "%s%s: %s" % ("exception " if got[0] == "exception" else "", got[1], got[2][:200])
    items = got
    if tag in ("assert-true", "assert-false"):
        want = "true" if tag == "assert-true" else "false"
        if len(items) == 1 and items[0][0] == "xs:boolean" and items[0][2] == want:
            return "pass", ""
        return "fail", "expected %s, got %s" % (want, show(items))
    if tag == "assert-empty":
        return ("pass", "") if not items else ("fail", "expected empty, got " + show(items))
    if tag == "assert-count":
        want = int((el.text or "").strip())
        return ("pass", "") if len(items) == want else ("fail", "expected %d items, got %d" % (want, len(items)))
    if tag == "assert-string-value":
        got_s = " ".join(v for _, _, v in items)
        want = el.text or ""
        if el.get("normalize-space") == "true":
            got_s, want = normalize_space(got_s), normalize_space(want)
        return ("pass", "") if got_s == want else ("fail", "expected %r, got %r" % (want[:100], got_s[:100]))
    if tag == "assert-type":
        ok = type_matches(items, el.text or "")
        if ok is None:
            return "assertion-unsupported", "assert-type " + (el.text or "")
        return ("pass", "") if ok else ("fail", "expected type %s, got %s" % (el.text, show(items)))
    if tag == "assert":
        c = r.get("C%d" % idx[id(el)])
        if isinstance(c, tuple):
            return "assertion-error", "assert %s: %s" % (c[1], c[2][:200])
        ebv = effective_boolean(c or [])
        if ebv is None:
            return "assertion-error", "assert: no effective boolean value of " + show(c)
        if ebv:
            return "pass", ""
        return "fail", "assert %s on %s" % ((el.text or "").strip()[:100], show(items))
    if tag in ("assert-eq", "assert-deep-eq", "assert-permutation"):
        v = r.get("V%d" % idx[id(el)])
        if isinstance(v, tuple) or v is None:
            return "assertion-error", "expected value %s: %s" % (el.text, v[1] if v else "missing")
        if tag == "assert-eq":
            if len(items) != 1 or len(v) != 1:
                return "fail", "expected %s, got %s" % (show(v), show(items))
            ok = atomic_equal(items[0], v[0])
        elif tag == "assert-deep-eq":
            if len(items) != len(v):
                return "fail", "expected %s, got %s" % (show(v), show(items))
            oks = [atomic_equal(a, b, True) for a, b in zip(items, v)]
            ok = None if None in oks else all(oks)
        else:
            ok = permutation_equal(items, v)
        if ok is None:
            return "assertion-unsupported", tag + ": nodes"
        return ("pass", "") if ok else ("fail", "expected %s, got %s" % (show(v), show(items)))
    return "assertion-unsupported", tag


def show(items):
    if items is None:
        return "nothing"
    if isinstance(items, tuple):
        return "error " + items[1]
    parts = ["%s %s" % (t, v[:40]) for t, _, v in items[:3]]
    if len(items) > 3:
        parts.append("... (%d items)" % len(items))
    return "(" + ", ".join(parts) + ")"


def judge(case, r):
    if "harness" in r:
        return "harness-error", r["harness"]
    if "setup" in r:
        return "harness-error", "setup: " + r["setup"][:200]
    got = r.get("R")
    if isinstance(got, tuple) and got[0] == "exception":
        # a defect whatever the assertion says (also inside not or any-of)
        return "fail", "exception %s: %s" % (got[1], got[2][:200])
    return check(case.result, r, case.idx)


def fail_class(case):
    """XPST0003 (parser), XPST0017 (function), another error, or value."""
    if case.outcome != "fail":
        return case.outcome
    if case.detail.startswith("exception "):
        return "fail exception"
    head = case.detail.split(":")[0]
    if re.match(r"^[A-Z]{4}[0-9]{4}$", head):
        return "fail " + head
    return "fail value"


# --- baseline ----------------------------------------------------------------

def read_baseline():
    base = {}
    if os.path.exists(BASELINE):
        with open(BASELINE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    k, _, o = line.partition(" ")
                    base[k] = o
    return base


def write_baseline(cases):
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
        f.write("# QT3 baseline: the XPath 2.0 cases that pass (or give another error code)\n")
        f.write("# profile %s, suite commit %s, harness %s; written by tools/run-qt3.py --update-baseline\n"
                % (PROFILE, COMMIT, HARNESS_VERSION))
        for c in sorted(cases, key=lambda c: c.key):
            if c.outcome in ("pass", "wrong-code") and c.key not in PLATFORM_DEPENDENT:
                f.write("%s %s\n" % (c.key, c.outcome))


def self_test():
    """The assertion checks on made-up results: each must give its outcome."""
    def el(xml):
        return ET.fromstring('<r xmlns="http://www.w3.org/2010/09/qt-fots-catalog">%s</r>' % xml)[0]

    def items(*pairs):
        return [(t, None, v) if not t.startswith("node:") else (t, "Q{}a", v) for t, v in pairs]
    b_true, i1 = ("xs:boolean", "true"), ("xs:integer", "1")
    cases = [
        ("<assert-true/>", {"R": items(b_true)}, "pass"),
        ("<assert-true/>", {"R": items(i1)}, "fail"),
        ("<assert-true/>", {"R": items(b_true, b_true)}, "fail"),
        ("<assert-false/>", {"R": items(b_true)}, "fail"),
        ("<assert-empty/>", {"R": []}, "pass"),
        ("<assert-empty/>", {"R": items(i1)}, "fail"),
        ("<assert-count>2</assert-count>", {"R": items(i1, i1)}, "pass"),
        ("<assert-count>2</assert-count>", {"R": items(i1)}, "fail"),
        ("<assert-string-value>1 a</assert-string-value>", {"R": items(i1, ("node:element", "a"))}, "pass"),
        ("<assert-string-value normalize-space='true'> x  y</assert-string-value>",
         {"R": items(("xs:string", "x y "))}, "pass"),
        ("<assert-string-value>x</assert-string-value>", {"R": items(("xs:string", "x "))}, "fail"),
        ("<error code='FOAR0001'/>", {"R": ("error", "FOAR0001", "")}, "pass"),
        ("<error code='FOAR0001'/>", {"R": ("error", "XPST0017", "")}, "wrong-code"),
        ("<error code='*'/>", {"R": ("error", "XPTY0004", "")}, "pass"),
        ("<error code='FOAR0001'/>", {"R": items(i1)}, "fail"),
        ("<assert-true/>", {"R": ("error", "XPST0017", "")}, "fail"),
        ("<assert-eq>1.0</assert-eq>", {"R": items(i1), "V1": items(("xs:decimal", "1"))}, "pass"),
        ("<assert-eq>1</assert-eq>", {"R": items(("xs:double", "1")), "V1": items(i1)}, "pass"),
        ("<assert-eq>'1'</assert-eq>", {"R": items(i1), "V1": items(("xs:string", "1"))}, "fail"),
        ("<assert-eq>2</assert-eq>", {"R": items(i1), "V1": items(("xs:integer", "2"))}, "fail"),
        ("<assert-eq>'a'</assert-eq>", {"R": items(("node:element", "a")), "V1": items(("xs:string", "a"))}, "pass"),
        ("<assert-deep-eq>1, 2</assert-deep-eq>", {"R": items(i1, ("xs:integer", "2")),
                                                   "V1": items(i1, ("xs:integer", "2"))}, "pass"),
        ("<assert-deep-eq>2, 1</assert-deep-eq>", {"R": items(i1, ("xs:integer", "2")),
                                                   "V1": items(("xs:integer", "2"), i1)}, "fail"),
        ("<assert-permutation>2, 1</assert-permutation>", {"R": items(i1, ("xs:integer", "2")),
                                                           "V1": items(("xs:integer", "2"), i1)}, "pass"),
        ("<assert-type>xs:decimal</assert-type>", {"R": items(i1)}, "pass"),
        ("<assert-type>xs:integer</assert-type>", {"R": items(("xs:byte", "1"))}, "pass"),
        ("<assert-type>xs:long</assert-type>", {"R": items(i1)}, "fail"),
        ("<assert-type>xs:token</assert-type>", {"R": items(("xs:ID", "a"))}, "pass"),
        ("<assert-eq>'a'</assert-eq>", {"R": items(("xs:NCName", "a")), "V1": items(("xs:string", "a"))}, "pass"),
        ("<assert-eq>1</assert-eq>", {"R": items(("xs:unsignedLong", "1")), "V1": items(i1)}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:duration", "P1Y")),
                                     "V1": items(("xs:yearMonthDuration", "P12M"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dayTimeDuration", "PT0S")),
                                     "V1": items(("xs:yearMonthDuration", "P0M"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dayTimeDuration", "P1D")),
                                     "V1": items(("xs:yearMonthDuration", "P1M"))}, "fail"),
        ("<assert-type>xs:duration</assert-type>", {"R": items(("xs:dayTimeDuration", "P1D"))}, "pass"),
        ("<assert-type>xs:string</assert-type>", {"R": items(i1)}, "fail"),
        ("<assert-type>xs:int</assert-type>", {"R": items(i1)}, "fail"),
        ("<assert-type>xs:integer*</assert-type>", {"R": items(i1, i1)}, "pass"),
        ("<assert-type>xs:integer</assert-type>", {"R": items(i1, i1)}, "fail"),
        ("<assert-type>element(a)</assert-type>", {"R": items(("node:element", "x"))}, "pass"),
        ("<assert-type>attribute()</assert-type>", {"R": items(("node:element", "x"))}, "fail"),
        ("<assert>$result</assert>", {"R": [], "C1": items(("node:element", ""))}, "pass"),
        ("<assert>$result</assert>", {"R": [], "C1": []}, "fail"),
        ("<assert>$result</assert>", {"R": [], "C1": ("error", "XPST0003", "")}, "assertion-error"),
        ("<any-of><assert-true/><error code='FOAR0001'/></any-of>", {"R": ("error", "FOAR0001", "")}, "pass"),
        ("<all-of><assert-count>1</assert-count><assert-true/></all-of>", {"R": items(i1)}, "fail"),
        ("<not><assert-true/></not>", {"R": items(("xs:boolean", "false"))}, "pass"),
        ("<error code='*'/>", {"R": ("exception", "EAccessViolation", "")}, "fail"),
        ("<assert-deep-eq>1</assert-deep-eq>", {"R": items(("xs:untypedAtomic", "1")), "V1": items(i1)}, "fail"),
        ("<assert-eq>1</assert-eq>", {"R": items(("node:element", "1")), "V1": items(i1)}, "fail"),
        ("<assert-type>element(a)</assert-type>", {"R": [("node:element", "Q{urn:x}a", "")]}, "fail"),
        ("<assert-string-value normalize-space='true'>a b</assert-string-value>",
         {"R": items(("xs:string", "a" + chr(160) + "b"))}, "fail"),
        ("<assert-permutation>1, 0</assert-permutation>", {"R": items(("xs:double", "0"), i1),
                                                           "V1": items(i1, ("xs:integer", "0"))}, "pass"),
        ("<assert-permutation>1, 1</assert-permutation>", {"R": items(i1, ("xs:integer", "2")),
                                                           "V1": items(i1, i1)}, "fail"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "2000-01-01T01:00:00+01:00")),
                                      "V1": items(("xs:dateTime", "2000-01-01T00:00:00Z"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "2000-01-01T01:00:00Z")),
                                      "V1": items(("xs:dateTime", "2000-01-01T00:00:00Z"))}, "fail"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:time", "24:00:00")),
                                      "V1": items(("xs:time", "00:00:00"))}, "pass"),
        ("<assert-permutation>x</assert-permutation>",
         {"R": items(("xs:double", "9007199254740992"), ("xs:integer", "9007199254740992")),
          "V1": items(("xs:integer", "9007199254740992"), ("xs:integer", "9007199254740993"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "0001-01-01T00:00:00+01:00")),
                                      "V1": items(("xs:dateTime", "0001-01-01T00:00:00+01:00"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "9999-01-01T01:00:00+01:00")),
                                      "V1": items(("xs:dateTime", "9999-01-01T00:00:00Z"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "-0044-03-15T12:00:00Z")),
                                      "V1": items(("xs:dateTime", "-0044-03-15T13:00:00+01:00"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "2000-01-01T00:00:00")),
                                      "V1": items(("xs:dateTime", "2000-01-01T00:00:00Z"))}, "pass"),
        ("<assert-eq>x</assert-eq>", {"R": items(("xs:dateTime", "-0001-12-31T23:00:00Z")),
                                      "V1": items(("xs:dateTime", "0001-01-01T00:00:00+01:00"))}, "pass"),
        ("<assert-permutation>x</assert-permutation>", {"R": items(*([i1] * 1000)), "V1": items(*([i1] * 1000))},
         "pass"),
        ("<assert-permutation>x</assert-permutation>", {"R": items(*([i1] * 999 + [("xs:integer", "2")])),
                                                        "V1": items(*([i1] * 1000))}, "fail"),
        ("<assert-xml>&lt;a/&gt;</assert-xml>", {"R": items(("node:element", ""))}, "assertion-unsupported"),
    ]
    bad = 0
    for xml, r, want in cases:
        e = el(xml)
        idx = {}
        for k, sub in enumerate([x for x in e.iter() if x.tag.replace(NS, "") in
                                 ("assert", "assert-eq", "assert-deep-eq", "assert-permutation")]):
            idx[id(sub)] = 1
        got = check(e, r, idx)[0]
        if got != want:
            bad += 1
            print("self-test: %s on %r gives %s, expected %s" % (xml, r, got, want))
    # judge: an exception is a failure whatever the assertion (also under not)
    fake = Case("t", "t", "t")
    fake.result = el("<not><assert-true/></not>")
    if judge(fake, {"R": ("exception", "EAccessViolation", "")})[0] != "fail":
        bad += 1
        print("self-test: an exception under not does not fail")
    print("self-test: %d checks, %d wrong" % (len(cases) + 1, bad))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    if os.name == "nt":
        default_exe = os.path.join(ROOT, "build", "fpc322-win64", "LandrixXmlQt3.exe")
    else:
        default_exe = os.path.join(ROOT, "build", "fpc322-linux", "LandrixXmlQt3")
    ap.add_argument("--exe", default=default_exe)
    ap.add_argument("--filter", default="")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--timeout", type=float, default=5.0, help="seconds per case")
    ap.add_argument("--profile", choices=sorted(BASELINES), default="xpath20",
                    help="the language profile; the Saxon profile has its own baseline")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--self-test", action="store_true", help="only check the assertion checks")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    global BASELINE, PROFILE
    PROFILE = args.profile
    BASELINE = BASELINES[PROFILE]
    if not os.path.exists(os.path.join(SUITE, "catalog.xml")):
        download()
    check_catalog()
    exe = os.path.abspath(args.exe)
    if not os.path.exists(exe):
        sys.exit("helper not found: " + exe)

    cases = load_cases(args.filter)
    by_set = collections.OrderedDict()
    for c in cases:
        if c.excluded:
            c.outcome, c.detail = "excluded", c.excluded
        else:
            by_set.setdefault(c.test_set, []).append(c)
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = {pool.submit(run_set, exe, cs, args.timeout, PROFILE): cs for cs in by_set.values()}
        for fut in concurrent.futures.as_completed(futures):
            cs = futures[fut]
            results = fut.result()
            for c in cs:
                try:
                    c.outcome, c.detail = judge(c, results.get(c.name, {"harness": "missing"}))
                except Exception as e:
                    c.outcome, c.detail = "harness-error", "checker: %s: %s" % (type(e).__name__, e)

    os.makedirs(WORK, exist_ok=True)
    with open(os.path.join(WORK, "results-%s.txt" % PROFILE), "w", encoding="utf-8", newline="\n") as f:
        for c in sorted(cases, key=lambda c: c.key):
            f.write("%s\t%s\t%s\n" % (c.key, c.outcome, c.detail.replace("\n", " ").replace("\t", " ")))

    applicable = [c for c in cases if c.outcome != "excluded"]
    totals = collections.Counter(c.outcome for c in applicable)
    print("QT3 %s, profile %s: %d cases, %d excluded, %d applicable" % (COMMIT[:7], PROFILE, len(cases), len(cases) - len(applicable),
                                                         len(applicable)))
    for o in ("pass", "wrong-code", "fail", "assertion-error", "assertion-unsupported", "harness-error"):
        print("  %-22s %6d" % (o, totals[o]))
    print("per category (pass / applicable):")
    cats = collections.defaultdict(collections.Counter)
    for c in applicable:
        cats[c.category][c.outcome] += 1
    for cat in sorted(cats):
        n = sum(cats[cat].values())
        print("  %-6s %6d / %6d  %5.1f %%" % (cat, cats[cat]["pass"], n, 100.0 * cats[cat]["pass"] / n))
    fails = collections.Counter(fail_class(c) for c in applicable if c.outcome == "fail")
    print("failures by kind:")
    for k, n in fails.most_common(12):
        print("  %-22s %6d" % (k, n))
    missing = collections.Counter()
    for c in applicable:
        if c.outcome == "fail" and c.detail.startswith("XPST0017"):
            m = re.search(r"([A-Za-z][\w.-]*:)?[A-Za-z][\w.-]*#\d+|function [^ ]+|unknown function [^ ]+", c.detail)
            missing[m.group(0) if m else c.detail[:60]] += 1
    if missing:
        print("most frequent XPST0017:")
        for k, n in missing.most_common(15):
            print("  %-40s %5d" % (k, n))
    if args.verbose:
        for c in applicable:
            if c.outcome != "pass":
                print("%s %s: %s" % (c.outcome, c.key, c.detail))

    status = 0
    harness = [c for c in applicable if c.outcome == "harness-error"]
    if harness:
        print("%d harness errors (see build/qt3/results-%s.txt)" % (len(harness), PROFILE))
        status = 1
    if args.update_baseline:
        write_baseline(cases)
        print("baseline written:", os.path.relpath(BASELINE, ROOT))
        return status
    base = read_baseline()
    if args.filter:
        base = {k: o for k, o in base.items() if k.startswith(args.filter)}
    for k, why in sorted(PLATFORM_DEPENDENT.items()):
        if k in {c.key for c in applicable}:
            print("platform-dependent %s: %s (%s)" % (k, [c.outcome for c in applicable if c.key == k][0], why))
    now = {c.key: c for c in cases}
    worse = []
    for k, o in sorted(base.items()):
        if k in PLATFORM_DEPENDENT:
            continue
        c = now.get(k)
        if c is None or RANK.get(c.outcome, 9) > RANK[o]:
            worse.append("%s: %s -> %s %s" % (k, o, c.outcome if c else "missing", c.detail if c else ""))
    better = [c for c in applicable if c.outcome in ("pass", "wrong-code") and c.key not in PLATFORM_DEPENDENT and
              (c.key not in base or RANK[c.outcome] < RANK[base[c.key]])]
    print("baseline: %d cases, %d worse, %d better" % (len(base), len(worse), len(better)))
    for w in worse[:50]:
        print("  WORSE " + w)
    if worse:
        status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
