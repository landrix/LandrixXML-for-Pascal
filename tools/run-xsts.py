#!/usr/bin/env python3
"""Runs the W3C XML Schema Test Suite (XSTS) against the XSD validator.

Usage: python tools/run-xsts.py [--exe PATH] [--filter PREFIX] [--verbose]
                                [--update-baseline] [--jobs N]

The suite (pinned commit of https://github.com/w3c/xsdtests, W3C Document
License) is downloaded on first use into the git-ignored
tests/data/xsts-suite/. Build the helper first:
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlXsts.dpr -NoRun

Applicable: the XSD 1.0 tests (no version attribute, or one naming 1.0, on
the test set, group and test) with status accepted or stable (or none) and
an expected validity for XSD 1.0 that is valid or invalid; groups without
a schema test (the instance names its schema) are excluded. A group with
several schema documents is loaded through a generated schema document
that imports (or includes) all of them; the xml: namespace comes from the
W3C schema xml.xsd (downloaded once, pinned by SHA-256), as from a catalog.

Outcomes per test: pass; fail; unsupported (the loader or the validator
reports a construct this library does not support, also for the instances
of a schema that is not supported); limit (a resource limit, xecLimit,
stopped the check); harness-error (crash, timeout, missing file).
A schema test passes if the schema loads (valid) or the loader rejects it
(invalid: xecSchema, or the document is not well-formed); an instance test
passes if it validates without errors (valid) or has a validation error
other than "unsupported" or is not well-formed (invalid). Messages are not compared (Xerces
stays the oracle for them, see tests/data/xsdvalidator).

Results per test: build/xsts/results.txt. The passing tests are the
baseline tests/data/xsts-baseline.txt; exit code 0 = none of them got
worse. After an improvement: --update-baseline and commit the baseline.
"""

import argparse
import collections
import concurrent.futures
import hashlib
import http.client
import io
import os
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
COMMIT = "7bc3365c652a322f3d762021b3879eb92dae7e30"
URL = "https://codeload.github.com/w3c/xsdtests/tar.gz/" + COMMIT
SUITE_SHA256 = "c64c3b12e9a3dc2d1ad75d4ac1acd7e097cabb82cc017a7cfaee1b09387b98b2"
# the schema of the xml: namespace, which tests import from its W3C location; given to
# the resolver as a catalog entry (the loader never reads the network)
XML_XSD_URL = "https://www.w3.org/2001/xml.xsd"
XML_XSD_SHA256 = "61960fb3131e38022caad5360e2f33a3382578ab3c80cd58bd74320ede61b20c"
XML_NS = "http://www.w3.org/XML/1998/namespace"
SUITE_DIR = os.path.join(ROOT, "tests", "data", "xsts-suite")
SUITE = os.path.join(SUITE_DIR, "xsdtests-" + COMMIT)
XML_XSD = os.path.join(SUITE_DIR, "xml.xsd")
WORK = os.path.join(ROOT, "build", "xsts")
BASELINE = os.path.join(ROOT, "tests", "data", "xsts-baseline.txt")
HARNESS_VERSION = 1

TS = "{http://www.w3.org/XML/2004/xml-schema-test-suite/}"
XLINK = "{http://www.w3.org/1999/xlink}href"
XS = "http://www.w3.org/2001/XMLSchema"
STATUS_OK = {"accepted", "stable", None}
SUPPORTED_VERSIONS = {"1.0"}
# ELandrixXmlError codes (the helper's names) that reject a document: an
# invalid schema or a document that is not well-formed XML
REJECTING = {"schema", "unicode", "encoding", "syntax", "namespace", "char"}
GROUPS_PER_JOB = 400


def read_url(url, timeout=300):
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


def check_suite():
    with open(os.path.join(SUITE, "suite.xml"), "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    if digest != SUITE_SHA256:
        sys.exit("suite.xml has SHA-256 %s, expected %s" % (digest, SUITE_SHA256))
    if not os.path.exists(XML_XSD):
        print("downloading", XML_XSD_URL)
        data = read_url(XML_XSD_URL)
        with open(XML_XSD + ".part", "wb") as f:
            f.write(data)
        os.replace(XML_XSD + ".part", XML_XSD)
    with open(XML_XSD, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    if digest != XML_XSD_SHA256:
        sys.exit("%s has SHA-256 %s, expected %s (delete it to download it again)" % (XML_XSD, digest, XML_XSD_SHA256))


# --- the tests ---------------------------------------------------------------

def version_problem(el):
    """Why the version attribute of el excludes XSD 1.0, or None."""
    v = el.get("version")
    if v is None:
        return None
    if any(t in SUPPORTED_VERSIONS for t in v.split()):
        return None
    return "version " + v


def status_problem(test):
    cur = test.find(TS + "current")
    status = cur.get("status") if cur is not None else None
    if status in STATUS_OK:
        return None
    return "status " + status


def expected_validity(test):
    """(validity, problem): the expected validity for XSD 1.0. The version
    tokens of an expected element must all be supported (on tests and
    groups one is enough, see version_problem)."""
    plain, explicit = [], []
    for e in test.findall(TS + "expected"):
        v = e.get("version")
        if v is None:
            plain.append(e.get("validity"))
        elif all(t in SUPPORTED_VERSIONS for t in v.split()):
            explicit.append(e.get("validity"))
    chosen = explicit or plain
    if not chosen:
        return None, "no expectation for XSD 1.0"
    if len(set(chosen)) > 1:
        return None, "contradicting expectations"
    if chosen[0] not in ("valid", "invalid"):
        return None, "expected " + chosen[0]
    return chosen[0], None


class Test:
    def __init__(self, ident, kind, name, file, expected, excluded):
        self.ident = ident
        self.kind = kind          # "schema" or "instance"
        self.name = name
        self.file = file
        self.expected = expected
        self.excluded = excluded


class Group:
    def __init__(self, set_id, name):
        self.set_id = set_id
        self.name = name
        self.ident = set_id + "/" + name
        self.schema_docs = []
        self.schema_test = None
        self.instances = []

    def tests(self):
        return ([self.schema_test] if self.schema_test else []) + self.instances

    def applicable(self):
        return [t for t in self.tests() if not t.excluded]


def target_namespace(path):
    try:
        for _, el in ET.iterparse(path, events=("start",)):
            return el.get("targetNamespace", "")
    except (ET.ParseError, OSError):
        return None
    return None


def load_tests(filt):
    suite = ET.parse(os.path.join(SUITE, "suite.xml")).getroot()
    groups = []
    for ref in suite.findall(TS + "testSetRef"):
        href = ref.get(XLINK)
        set_id = os.path.splitext(href)[0]
        if filt and not set_id.startswith(filt):
            continue
        path = os.path.join(SUITE, href)
        base = os.path.dirname(path)
        ts = ET.parse(path).getroot()
        set_problem = version_problem(ts)
        for g in ts.findall(TS + "testGroup"):
            group = Group(set_id, g.get("name"))
            groups.append(group)
            group_problem = set_problem or version_problem(g)
            st = g.find(TS + "schemaTest")
            if st is not None:
                group.schema_docs = [os.path.normpath(os.path.join(base, d.get(XLINK)))
                                     for d in st.findall(TS + "schemaDocument")]
                expected, problem = expected_validity(st)
                problem = group_problem or version_problem(st) or status_problem(st) or problem
                group.schema_test = Test(group.ident + "/" + st.get("name"), "schema", st.get("name"),
                                         group.schema_docs[0], expected, problem)
            for it in g.findall(TS + "instanceTest"):
                doc = it.find(TS + "instanceDocument")
                expected, problem = expected_validity(it)
                if st is None:
                    problem = "no schema test (the instance names its schema)"
                problem = group_problem or version_problem(it) or status_problem(it) or problem
                group.instances.append(Test(group.ident + "/" + it.get("name"), "instance", it.get("name"),
                                            os.path.normpath(os.path.join(base, doc.get(XLINK))),
                                            expected, problem))
    return groups


# --- running -----------------------------------------------------------------

def wrapper_schema(g):
    """A schema document that imports (or, without a target namespace,
    includes) every schema document of g, so that they form one schema."""
    folder = os.path.join(WORK, "wrappers")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, g.ident.replace("/", "_") + ".xsd")
    lines = ['<xs:schema xmlns:xs="%s">' % XS]
    for d in g.schema_docs:
        ns = target_namespace(d)
        loc = os.path.relpath(d, folder).replace(os.sep, "/")
        if ns:
            lines.append('  <xs:import namespace="%s" schemaLocation="%s"/>' % (xml_escape(ns), xml_escape(loc)))
        else:
            lines.append('  <xs:include schemaLocation="%s"/>' % xml_escape(loc))
    lines.append("</xs:schema>")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return path


def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace('"', "&quot;")


def job_text(groups):
    out = []
    for g in groups:
        out.append("group\t" + g.ident)
        if len(g.schema_docs) > 1:
            out.append("schema\t" + wrapper_schema(g))
        else:
            out.append("schema\t" + g.schema_docs[0])
        if all(target_namespace(d) != XML_NS for d in g.schema_docs):
            out.append("ns\t%s\t%s" % (XML_NS, XML_XSD))
        out.append("load")
        for t in g.instances:
            if not t.excluded:
                out.append("instance\t%s\t%s" % (t.name, t.file))
        out.append("end")
    text = "\n".join(out) + "\n"
    # the helper reads the job file in the system code page
    if any(ord(c) > 127 for c in text):
        sys.exit("the job file needs ASCII paths: move the repository to an ASCII path")
    return text


def parse_output(text):
    """{group ident: {"schema": (status, fields), "instances": {name: fields}, "done": bool}}"""
    results = {}
    cur = None
    for line in text.split("\n"):
        if not line:
            continue
        f = line.split("\t")
        if f[0] == "group":
            cur = {"schema": None, "instances": {}, "done": False}
            results[f[1]] = cur
        elif cur is None:
            continue
        elif f[0] == "schema":
            cur["schema"] = f[1:]
        elif f[0] == "instance":
            cur["instances"][f[1]] = f[2:]
        elif f[0] == "done":
            cur["done"] = True
    return results


def run_chunk(exe, chunk, index, timeout_per_group):
    """Run the groups of one chunk; resume after a crash or timeout."""
    os.makedirs(os.path.join(WORK, "jobs"), exist_ok=True)
    job = os.path.join(WORK, "jobs", "%04d.job" % index)
    with open(job, "w", encoding="utf-8", newline="\n") as f:
        f.write(job_text(chunk))
    results = {}
    first = 0
    attempt = 0
    while first < len(chunk):
        attempt += 1
        out = os.path.join(WORK, "jobs", "%04d.%d.out" % (index, attempt))
        if os.path.exists(out):
            os.remove(out)
        problem = None
        proc = subprocess.Popen([exe, job, out, str(first)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # the helper writes a line per schema and instance: if its output stops
        # growing for timeout_per_group seconds, a group hangs
        size, since = -1, time.monotonic()
        while proc.poll() is None:
            time.sleep(0.2)
            now_size = os.path.getsize(out) if os.path.exists(out) else 0
            if now_size != size:
                size, since = now_size, time.monotonic()
            elif time.monotonic() - since > timeout_per_group:
                proc.kill()
                proc.wait()
                problem = "timeout"
        text = ""
        if os.path.exists(out):
            with open(out, encoding="utf-8", errors="replace", newline="") as f:
                text = f.read()
        parsed = parse_output(text)
        done = 0
        for k in range(first, len(chunk)):
            r = parsed.get(chunk[k].ident)
            if r is None or not r["done"]:
                break
            results[chunk[k].ident] = r
            done += 1
        first += done
        if first < len(chunk):
            # the group after the last complete one crashed or hung
            results[chunk[first].ident] = {"harness": problem or "crash"}
            first += 1
    return results


# --- judging -----------------------------------------------------------------

def judge_schema(t, schema):
    status = schema[0]
    if status == "ok":
        return ("pass", "") if t.expected == "valid" else ("fail", "accepted an invalid schema")
    if status == "error" and schema[1] == "unsupported":
        return "unsupported", schema[2] if len(schema) > 2 else ""
    detail = " ".join(schema[1:])[:200]
    if status == "error" and schema[1] == "limit":
        return "limit", detail
    if status == "error" and schema[1] in REJECTING and t.expected == "invalid":
        return "pass", ""
    return "fail", ("rejected: " if t.expected == "valid" else "") + status + " " + detail


def judge_instance(t, schema, r):
    if schema[0] != "ok":
        if schema[0] == "error" and schema[1] == "unsupported":
            return "unsupported", "schema: " + (schema[2] if len(schema) > 2 else "")
        return "fail", "schema not loaded: " + " ".join(schema)[:200]
    if r is None:
        return "harness-error", "no result"
    status = r[0]
    if status == "valid":
        return ("pass", "") if t.expected == "valid" else ("fail", "accepted an invalid instance")
    code = r[1] if len(r) > 1 else ""
    detail = " ".join(r)[:200]
    if code == "unsupported":
        return "unsupported", detail
    if status == "error" and code == "limit":
        return "limit", detail
    if t.expected == "invalid" and (status == "invalid" or (status == "error" and code in REJECTING)):
        return "pass", ""
    return "fail", detail


def judge_group(g, r):
    out = {}
    tests = g.applicable()
    missing = [d for d in g.schema_docs if not os.path.exists(d)]
    if missing:
        for t in tests:
            out[t.ident] = ("harness-error", "missing " + missing[0])
        return out
    if "harness" in r:
        for t in tests:
            out[t.ident] = ("harness-error", r["harness"])
        return out
    schema = r["schema"] or ["exception", "?", "no schema result"]
    for t in tests:
        if t.kind == "schema":
            out[t.ident] = judge_schema(t, schema)
        elif not os.path.exists(t.file):
            out[t.ident] = ("harness-error", "missing " + t.file)
        else:
            out[t.ident] = judge_instance(t, schema, r["instances"].get(t.name))
    return out


# --- baseline ----------------------------------------------------------------

def read_baseline():
    """The passing tests of the baseline: a line "set NAME" per test set, then
    per group "GROUP: TEST TEST ..." ("=" for a test named as its group)."""
    passed = set()
    if not os.path.exists(BASELINE):
        return None
    set_id = None
    with open(BASELINE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("set "):
                set_id = line[4:]
                continue
            group, _, tests = line.partition(": ")
            for t in tests.split():
                passed.add("%s/%s/%s" % (set_id, group, group if t == "=" else t))
    return passed


def write_baseline(groups, outcomes):
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
        f.write("# W3C XML Schema Test Suite %s, harness %d: the passing tests\n" % (COMMIT[:7], HARNESS_VERSION))
        f.write("# per test set, one line per group: GROUP: TEST ... (= for a test named as its group)\n")
        last = None
        for g in groups:
            names = [t.name for t in g.tests() if outcomes.get(t.ident, ("", ""))[0] == "pass"]
            if not names:
                continue
            if g.set_id != last:
                f.write("set %s\n" % g.set_id)
                last = g.set_id
            f.write("%s: %s\n" % (g.name, " ".join("=" if n == g.name else n for n in names)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--exe", default=os.path.join(ROOT, "build", "fpc322-win64", "LandrixXmlXsts.exe"))
    ap.add_argument("--filter", help="test set prefix, e.g. msMeta/Element")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--timeout", type=float, default=300.0,
                    help="seconds without output after which a group counts as hung")
    args = ap.parse_args()

    if not os.path.isdir(SUITE):
        download()
    check_suite()
    exe = os.path.abspath(args.exe)
    if not os.path.exists(exe):
        sys.exit("helper not found: " + exe)

    groups = load_tests(args.filter)
    all_tests = [t for g in groups for t in g.tests()]
    runnable = [g for g in groups if g.schema_test is not None and g.applicable()]
    chunks = [runnable[i:i + GROUPS_PER_JOB] for i in range(0, len(runnable), GROUPS_PER_JOB)]
    outcomes = {}
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(run_chunk, exe, c, i, args.timeout) for i, c in enumerate(chunks)]
        for chunk, fut in zip(chunks, futures):
            res = fut.result()
            for g in chunk:
                outcomes.update(judge_group(g, res.get(g.ident, {"harness": "missing"})))

    os.makedirs(WORK, exist_ok=True)
    excluded = collections.Counter()
    with open(os.path.join(WORK, "results.txt"), "w", encoding="utf-8", newline="\n") as f:
        for g in groups:
            for t in g.tests():
                if t.excluded:
                    excluded[t.excluded.split(" ")[0]] += 1
                    f.write("%s\texcluded\t%s\n" % (t.ident, t.excluded))
                else:
                    o, d = outcomes.get(t.ident, ("harness-error", "not run"))
                    f.write("%s\t%s\t%s\n" % (t.ident, o, d))
                    if args.verbose and o != "pass":
                        print("%s: %s %s" % (t.ident, o, d))

    total = collections.Counter(o for o, _ in outcomes.values())
    per_set = collections.OrderedDict()
    for g in groups:
        for t in g.applicable():
            c = per_set.setdefault(g.set_id, collections.Counter())
            c["applicable"] += 1
            c[outcomes.get(t.ident, ("harness-error", ""))[0]] += 1
    print("XSTS %s: %d tests, %d excluded, %d applicable" % (COMMIT[:7], len(all_tests),
                                                           sum(excluded.values()), len(outcomes)))
    for o in ("pass", "fail", "unsupported", "limit", "harness-error"):
        print("  %-14s %6d" % (o, total[o]))
    print("per test set (pass / unsupported / applicable):")
    for set_id, c in per_set.items():
        print("  %-45s %6d / %6d / %6d" % (set_id, c["pass"], c["unsupported"], c["applicable"]))

    if args.update_baseline:
        if args.filter:
            sys.exit("--update-baseline needs the whole suite (no --filter)")
        if total["harness-error"]:
            sys.exit("--update-baseline refused: %d harness errors" % total["harness-error"])
        write_baseline(groups, outcomes)
        print("baseline written:", os.path.relpath(BASELINE, ROOT))
        return 0
    base = read_baseline()
    if base is None:
        print("no baseline yet")
        return 0
    worse = sorted(i for i in base if i in outcomes and outcomes[i][0] != "pass")
    gone = [i for i in base if i not in outcomes]
    if args.filter:
        gone = []
    better = sum(1 for i, (o, _) in outcomes.items() if o == "pass" and i not in base)
    for i in worse:
        print("WORSE %s: %s %s" % ((i,) + outcomes[i]))
    for i in gone:
        print("MISSING " + i)
    print("baseline: %d tests, %d worse, %d better" % (len(base), len(worse) + len(gone), better))
    return 1 if worse or gone else 0


if __name__ == "__main__":
    sys.exit(main())
