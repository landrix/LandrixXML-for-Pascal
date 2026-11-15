#!/usr/bin/env python3
"""Run the W3C XSLT test suite (w3c/xslt30-test, XSLT 1.0 and 2.0 cases) against LandrixXml.

Downloads the suite at a pinned commit into tests/data/xslt30-suite/
(git-ignored, not redistributed), selects the test cases that apply to
the XSLT 2.0 subset and lets the helper tests/LandrixXmlXsltSuite.dpr
run them one by one; this script checks the assertions and compares the
outcome with the committed baseline tests/data/xslt-baseline.txt.

Applicability: the spec of the case (or its test set) names XSLT 1.0+,
2.0+ or 2.0 (XSLT 3.0 cases follow later); no optional feature that is
not provided (streaming, schema awareness, higher-order functions,
XPath 3.1, backwards compatibility, XML 1.1, dynamic evaluation, the
namespace axis, disable-output-escaping, DTD processing, HTML 4, the
xml-stylesheet processing instruction); no other implementation-defined
dependency except the Unicode version and HTML 5 as the default. The
environment may hold the source document ("." from a file or inline, a
document under its own file name) and a stylesheet; the test the
stylesheet, an initial template or mode and parameters (no static ones,
no packages, no initial function).

Assertions: assert (an XPath expression on the result document, also
$result; evaluated by the engine itself, as in QT3), assert-xml (the
serialized result and the expected XML compared as events, see
tools/run-qt3.py), assert-string-value, serialization-matches (a Python
regular expression), assert-serialization (the text, or after
normalizing white space), error (the code, or any), all-of, any-of,
not. The others (messages, result documents, warnings, typed results)
count as assertion-unsupported.

Outcomes: pass; wrong-code (an error was expected, another code came);
fail (with our error code or "value"); unsupported (the processor
rejected the stylesheet or a feature as unsupported: xecUnsupported);
assertion-unsupported; excluded (not applicable, with the reason);
harness-error (crash, timeout, setup).

Usage:
  python tools/run-xslt-tests.py [--exe PATH] [--filter PREFIX] [--jobs N]
                                 [--update-baseline] [--verbose]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlXsltSuite.dpr -NoRun
Exit code: 0 if no baseline case got worse and no harness error occurred.
Results per case: build/xslt-tests/results.txt.
"""

import argparse
import collections
import concurrent.futures
import hashlib
import importlib.util
import io
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMIT = "fddf1cf920087e791f13315d68dfbe874d97dc56"
URL = "https://codeload.github.com/w3c/xslt30-test/tar.gz/" + COMMIT
CATALOG_SHA256 = "21aceb87d73297bc7b29ea0b5727017bb7949c4a1149f5261773af929521d170"
SUITE_DIR = os.path.join(ROOT, "tests", "data", "xslt30-suite")
SUITE = os.path.join(SUITE_DIR, "xslt30-test-" + COMMIT)
BASELINE = os.path.join(ROOT, "tests", "data", "xslt-baseline.txt")
WORK = os.path.join(ROOT, "build", "xslt-tests")
HARNESS_VERSION = "1"
NS = "{http://www.w3.org/2012/10/xslt-test-catalog}"
TIMEOUT = 60

SPECS = {"XSLT10+", "XSLT20+", "XSLT20"}
# features: provided (True) or not (False); a feature not listed is not
# provided
FEATURES = {"serialization": True, "HTML5": True}
# test sets left out as a whole, with the reason: unicode-90 never passes
# the charclass parameter its generated cases need (Saxon fails them too)
# and runs every code point through regular expressions (the catalog marks
# it "very slow")
EXCLUDED_SETS = {"unicode-90": "suite defect (charclass parameter not passed)"}
SUPPORTED_ASSERTIONS = {"assert", "assert-xml", "assert-string-value", "serialization-matches",
                        "assert-serialization", "error", "all-of", "any-of", "not",
                        "assert-result-document"}


def qt3_module():
    spec = importlib.util.spec_from_file_location("qt3", os.path.join(ROOT, "tools", "run-qt3.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


QT3 = qt3_module()


# --- download ----------------------------------------------------------------

def download():
    os.makedirs(SUITE_DIR, exist_ok=True)
    print("downloading", URL)
    data = QT3.read_url(URL, timeout=600)
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


# --- the catalog ---------------------------------------------------------------

class Element(ET.Element):
    """An element that takes attributes of its own (ns, base_dir)."""


def parse_with_namespaces(path):
    """The root element; every element gets .ns, the prefixes in scope."""
    scopes = [{"xml": "http://www.w3.org/XML/1998/namespace"}]
    pending = {}
    root = None
    parser = ET.XMLParser(target=ET.TreeBuilder(element_factory=Element))
    for event, item in ET.iterparse(path, events=("start-ns", "start", "end"), parser=parser):
        if event == "start-ns":
            pending[item[0]] = item[1]
        elif event == "start":
            scope = dict(scopes[-1])
            scope.update(pending)
            pending = {}
            item.ns = scope
            scopes.append(scope)
            if root is None:
                root = item
        else:
            scopes.pop()
    return root


def local(el):
    return el.tag.replace(NS, "")


def clark(qname, ns, default=""):
    """The Clark name of a lexical QName (EQName Q{uri}local too)."""
    qname = qname.strip()
    if qname.startswith("Q{"):
        i = qname.index("}")
        return "{%s}%s" % (qname[2:i], qname[i + 1:]) if qname[2:i] else qname[i + 1:]
    if ":" in qname:
        prefix, name = qname.split(":", 1)
        if prefix not in ns:
            raise ValueError("unbound prefix " + prefix)
        return "{%s}%s" % (ns[prefix], name)
    return "{%s}%s" % (default, qname) if default else qname


class Case:
    def __init__(self, set_name, el, set_dir):
        self.set = set_name
        self.name = el.get("name")
        self.key = set_name + "/" + self.name
        self.el = el
        self.dir = set_dir
        self.outcome = None
        self.detail = ""
        self.reason = ""
        self.stylesheet = None
        self.source = None
        self.inline_source = None
        self.template = ""
        self.mode = ""
        self.params = []
        self.result = el.find(NS + "result")


def dependency_problem(dep):
    kind = local(dep)
    value = dep.get("value", "")
    satisfied = dep.get("satisfied", "true") == "true"
    if kind == "spec":
        if not set(value.split()) & SPECS:
            return "spec " + value
        return None
    if kind == "feature":
        if FEATURES.get(value, False) != satisfied:
            return "feature " + value + ("" if satisfied else " (not)")
        return None
    if kind == "unicode-version":
        return None
    if kind == "default_html_version":
        return None if value.strip() == "5" else "default_html_version " + value
    return kind + " " + value


def environment_problem(env, case):
    """Takes the source and stylesheet of env into case; the reason it is
    not provided, or None."""
    base = env.base_dir
    for ch in env:
        tag = local(ch)
        if tag == "source":
            extra = set(ch.attrib) - {"role", "file", "uri"}
            if extra:
                return "source with " + " ".join(sorted(extra))
            role = ch.get("role")
            if role == ".":
                if ch.get("uri") is not None:
                    return "source with role and uri"
                if ch.get("file"):
                    case.source = os.path.join(base, ch.get("file"))
                else:
                    content = ch.find(NS + "content")
                    if content is None:
                        return "source without content"
                    case.inline_source = content.text or ""
            elif role is None:
                # a document doc() reads by its own (relative) file name
                if ch.get("uri") is None or os.path.normpath(os.path.join(base, ch.get("uri"))) != \
                        os.path.normpath(os.path.join(base, ch.get("file", ""))):
                    return "source under another URI"
            else:
                return "source role " + role
        elif tag == "stylesheet":
            if case.stylesheet is None:
                case.stylesheet = os.path.join(base, ch.get("file"))
        elif tag == "param":
            if ch.get("static") == "yes":
                return "static param"
            try:
                case.params.append((clark(ch.get("name"), ch.ns), ch.get("select"), ch.ns))
            except ValueError as e:
                return str(e)
        else:
            return "environment " + tag
    return None


def assertion_problem(el):
    for e in el.iter():
        tag = local(e)
        if tag != "result" and tag not in SUPPORTED_ASSERTIONS:
            return tag
    return None


def load_cases(filt):
    catalog = ET.parse(os.path.join(SUITE, "catalog.xml")).getroot()
    cases = []
    for ts in catalog.iter(NS + "test-set"):
        name = ts.get("name")
        if filt and not name.startswith(filt):
            continue
        path = os.path.join(SUITE, ts.get("file"))
        set_dir = os.path.dirname(path)
        root = parse_with_namespaces(path)
        envs = {}
        for env in root.findall(NS + "environment"):
            env.base_dir = set_dir
            envs[env.get("name")] = env
        set_deps = root.find(NS + "dependencies")
        for el in root.iter(NS + "test-case"):
            case = Case(name, el, set_dir)
            cases.append(case)
            case.reason = EXCLUDED_SETS.get(name) or plan(case, el, set_deps, envs)
            if case.reason:
                case.outcome = "excluded"
    return cases


def plan(case, el, set_deps, envs):
    """The reason the case is not applicable, or None (case set up)."""
    has_spec = False
    for deps in (set_deps, el.find(NS + "dependencies")):
        if deps is None:
            continue
        for dep in deps:
            if local(dep) == "spec":
                has_spec = True
            problem = dependency_problem(dep)
            if problem:
                return problem
    if not has_spec:
        return "no spec"
    test = el.find(NS + "test")
    if test is None:
        return "no test"
    for ch in test:
        tag = local(ch)
        if tag == "stylesheet":
            if ch.get("role") in (None, "principal"):
                case.stylesheet = os.path.join(case.dir, ch.get("file"))
            elif ch.get("role") != "secondary":
                return "stylesheet role " + ch.get("role")
            if ch.get("xml-version"):
                return "stylesheet xml-version"
        elif tag == "initial-template":
            try:
                case.template = clark(ch.get("name"), ch.ns)
            except ValueError as e:
                return str(e)
        elif tag == "initial-mode":
            if ch.get("select") is not None:
                return "initial-mode select"
            try:
                case.mode = clark(ch.get("name"), ch.ns)
            except ValueError as e:
                return str(e)
        elif tag == "param":
            if ch.get("static") == "yes":
                return "static param"
            try:
                case.params.append((clark(ch.get("name"), ch.ns), ch.get("select"), ch.ns))
            except ValueError as e:
                return str(e)
        elif tag == "output":
            if ch.get("file") or ch.get("result-var"):
                return "output to a file"
        else:
            return "test " + tag
    env = el.find(NS + "environment")
    if env is not None:
        if env.get("ref"):
            if env.get("ref") not in envs:
                return "environment " + env.get("ref") + " not in the test set"
            env = envs[env.get("ref")]
        else:
            env.base_dir = case.dir
        problem = environment_problem(env, case)
        if problem:
            return problem
    if case.stylesheet is None:
        return "no stylesheet"
    if case.result is None:
        return "no result"
    problem = assertion_problem(case.result)
    if problem:
        case.outcome = "assertion-unsupported"
        return None
    return None


# --- running -----------------------------------------------------------------

def walk(el, skip_result_documents=True):
    """el and its descendants, without those of assert-result-document
    (they are about a result document, not the principal result)"""
    yield el
    for e in el:
        if skip_result_documents and local(e) == "assert-result-document":
            continue
        yield from walk(e, skip_result_documents)


def result_documents(el):
    """the assert-result-document elements under el"""
    return [e for e in el.iter() if local(e) == "assert-result-document"]


def needs(el, top=True):
    """(serialize, xml, checks): what the assertions under el need (xml: the
    result as plain XML, for assert-xml)."""
    serialize = False
    xml = False
    checks = []
    for e in walk(el):
        if e is el and not top:
            continue
        tag = local(e)
        if tag == "assert-xml":
            xml = True
        elif tag in ("serialization-matches", "assert-serialization"):
            serialize = True
        elif tag == "assert":
            checks.append(e)
        elif tag == "assert-string-value":
            checks.append(None)
    if top and not checks and not xml:
        # an expected error (also one of serialization) needs a run as well
        serialize = True
    return serialize, xml, checks


def esc(s, spaces=False):
    return QT3.esc(s, spaces)


def run_case(exe, case):
    work = os.path.join(WORK, "cases", case.set)
    os.makedirs(work, exist_ok=True)
    stem = os.path.join(work, case.name)
    serialize, xml, checks = needs(case.result)
    lines = ["stylesheet " + esc(case.stylesheet)]
    if case.inline_source is not None:
        with open(stem + ".source.xml", "w", encoding="utf-8", newline="") as f:
            f.write(case.inline_source)
        lines.append("source " + esc(stem + ".source.xml"))
    elif case.source:
        lines.append("source " + esc(case.source))
    if case.template:
        lines.append("template " + esc(case.template))
    if case.mode:
        lines.append("mode " + esc(case.mode))
    # the base output URI: the principal result's file; the result
    # documents by their URIs resolved against it
    base_output = pathlib.Path(os.path.abspath(stem + ".out")).as_uri()
    docs = []
    for d in result_documents(case.result):
        d_serialize, d_xml, d_checks = needs(d, top=False)
        docs.append((d, urllib.parse.urljoin(base_output, d.get("uri") or ""), d_serialize, d_xml, d_checks))
    namespaces = {}
    for _, _, ns in case.params:
        namespaces.update(ns)
    for e in checks + [c for doc in docs for c in doc[4]]:
        if e is not None:
            namespaces.update(e.ns)
    for prefix, uri in sorted(namespaces.items()):
        if prefix and prefix != "xml":
            lines.append("ns %s %s" % (esc(prefix, True), esc(uri)))
    for name, select, _ in case.params:
        lines.append("param %s %s" % (esc(name, True), esc(select or "()")))
    if serialize:
        lines.append("serialize " + esc(stem + ".out"))
    if xml:
        lines.append("xml " + esc(stem + ".xml"))
    expressions = [e for e in checks if e is not None]
    if checks and not expressions:
        expressions_text = ["true()"]
    else:
        expressions_text = [(e.text or "").strip() for e in expressions]
    for x in expressions_text:
        lines.append("check " + esc(x))
    lines.append("output " + esc(base_output))
    doc_info = []
    for n, (d, uri, d_serialize, d_xml, d_checks) in enumerate(docs, 1):
        lines.append("rdoc " + esc(uri))
        d_stem = "%s.rd%d" % (stem, n)
        if d_serialize:
            lines.append("rserialize " + esc(d_stem + ".out"))
        if d_xml:
            lines.append("rxml " + esc(d_stem + ".xml"))
        d_expressions = [e for e in d_checks if e is not None]
        d_text = [(e.text or "").strip() for e in d_expressions]
        if d_checks and not d_expressions:
            d_text = ["true()"]
        for x in d_text:
            lines.append("rcheck " + esc(x))
        doc_info.append((d, d_stem, d_expressions))
    with open(stem + ".job", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    for path in [stem + ".res", stem + ".out", stem + ".xml"] + \
            [d_stem + ext for _, d_stem, _ in doc_info for ext in (".out", ".xml")]:
        if os.path.exists(path):
            os.remove(path)
    try:
        run = subprocess.run([exe, stem + ".job", stem + ".res"], stdin=subprocess.DEVNULL,
                             capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"harness": "timeout"}
    if not os.path.exists(stem + ".res"):
        return {"harness": "no result file (exit code %d)" % run.returncode}
    r = {"checks": {}, "expressions": expressions, "docs": {}}
    subs = {}
    for n, (d, d_stem, d_expressions) in enumerate(doc_info, 1):
        subs[n] = {"checks": {}, "expressions": d_expressions, "found": False, "stem": d_stem}
        r["docs"][id(d)] = subs[n]
    with open(stem + ".res", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            head, _, rest = line.partition(" ")
            if head.startswith("xml-"):
                # the plain XML serialization of the result failed
                head = head[4:]
            if head in ("error", "unsupported", "exception"):
                # the module named without the suite's path
                rest = QT3.unesc(rest)
                for prefix in ("file:///", "file:/"):
                    rest = rest.replace(prefix + SUITE.replace(os.sep, "/").lstrip("/") + "/", "")
                r.setdefault("error", (head, rest))
            elif head == "serialized":
                with open(stem + ".out", "rb") as g:
                    r["serialized"] = g.read()
            elif head == "xml":
                with open(stem + ".xml", "rb") as g:
                    r["xml"] = g.read()
            elif head == "string":
                r["string"] = QT3.unesc(rest)
            elif head == "check":
                n, _, value = rest.partition(" ")
                r["checks"][int(n)] = value
            elif head in ("rdoc", "rserialized", "rxml", "rstring", "rcheck", "rerror"):
                n, _, value = rest.partition(" ")
                sub = subs.get(int(n))
                if sub is None:
                    continue
                if head == "rdoc":
                    sub["found"] = value == "found"
                elif head == "rerror":
                    sub["error"] = value
                elif head == "rserialized":
                    with open(sub["stem"] + ".out", "rb") as g:
                        sub["serialized"] = g.read()
                elif head == "rxml":
                    with open(sub["stem"] + ".xml", "rb") as g:
                        sub["xml"] = g.read()
                elif head == "rstring":
                    sub["string"] = QT3.unesc(value)
                else:
                    m, _, v = value.partition(" ")
                    sub["checks"][int(m)] = v
    if run.returncode != 0 and "error" not in r:
        r["harness"] = "exit code %d" % run.returncode
    return r


# --- judging -------------------------------------------------------------------

def normalize_space(s):
    return " ".join(s.split())


def regex_flags(flags):
    f = 0
    for ch in flags or "":
        f |= {"s": re.S, "m": re.M, "i": re.I, "x": re.X}.get(ch, 0)
    return f


def expected_text(el, case):
    if el.get("file"):
        with open(os.path.join(case.dir, el.get("file")), "rb") as f:
            return f.read()
    return (el.text or "").encode("utf-8")


def document_events(events):
    """events without white space text outside the element if they are a
    document (one element, no other text at the top): parsed as a document
    (canonical XML) that white space does not exist"""
    if events is None:
        return None
    depth = 0
    elements = 0
    top = []
    for i, e in enumerate(events):
        if e[0] == "start":
            if depth == 0:
                elements += 1
            depth += 1
        elif e[0] == "end":
            depth -= 1
        elif e[0] == "text" and depth == 0:
            if e[1].strip(" \t\r\n"):
                return events
            top.append(i)
    if elements != 1:
        return events
    return [e for i, e in enumerate(events) if i not in top]


def decode_output(data):
    """data as text: ISO-8859-1 if its XML declaration names US-ASCII or
    ISO-8859-1, else strict UTF-8; None if it is not valid in that"""
    m = re.match(rb'<\?xml[^>]*encoding\s*=\s*[\"\']([A-Za-z0-9._-]+)', data)
    if m and m.group(1).decode("ascii").lower() in ("us-ascii", "ascii", "iso-8859-1", "latin1"):
        return data.decode("latin-1")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def check(el, r, case):
    """True or False for the assertion el (r: the run without an error)."""
    tag = local(el)
    if tag == "all-of":
        return all(check(e, r, case) for e in el)
    if tag == "any-of":
        return any(check(e, r, case) for e in el)
    if tag == "not":
        return not all(check(e, r, case) for e in el)
    if tag == "error":
        return False
    if tag == "assert-result-document":
        sub = r.get("docs", {}).get(id(el))
        if sub is None or not sub["found"] or "error" in sub:
            return False
        return all(check(e, sub, case) for e in el)
    if tag == "assert":
        i = r["expressions"].index(el) + 1
        return r["checks"].get(i) == "true"
    if tag == "assert-string-value":
        if "string" not in r:
            return False
        got, want = r["string"], el.text or ""
        if el.get("normalize-space") == "true":
            got, want = normalize_space(got), normalize_space(want)
        return got == want
    if tag == "assert-xml":
        if r.get("xml") is None:
            return False
        ignore = el.get("ignore-prefixes") == "true"
        got = document_events(QT3.xml_events(r["xml"], ignore))
        want = document_events(QT3.xml_events(expected_text(el, case), ignore))
        return got is not None and want is not None and got == want
    serialized = r.get("serialized")
    if serialized is None:
        return False
    text = decode_output(serialized)
    if text is None:
        return False
    if tag == "serialization-matches":
        try:
            return re.search(el.text or "", text, regex_flags(el.get("flags"))) is not None
        except re.error:
            return False
    if tag == "assert-serialization":
        want = decode_output(expected_text(el, case)) if el.get("file") else (el.text or "")
        if want is None:
            return False
        if el.get("normalize-space") == "true":
            return normalize_space(text) == normalize_space(want)
        if el.get("file"):
            # the line ends of the expected file are those of its checkout
            # (the stylesheet's text, parsed, has line feeds only); the
            # output is compared as written, so a carriage return in it
            # still fails
            want = want.replace("\r\n", "\n")
        # only a final line break may differ
        return text.rstrip("\r\n") == want.rstrip("\r\n")
    return False


def expected_codes(el):
    """The error codes that would pass ("*": any)."""
    tag = local(el)
    if tag == "error":
        return {el.get("code", "*")}
    if tag == "any-of":
        codes = set()
        for e in el:
            codes |= expected_codes(e)
        return codes
    return set()


def unparsed_only(case, r):
    """True if the result passes when the assertions that did not parse
    (XPST0003) are taken as true"""
    if not any(v.startswith("error XPST0003") for v in r["checks"].values()):
        return False
    r2 = dict(r)
    r2["checks"] = {n: ("true" if v.startswith("error XPST0003") else v) for n, v in r["checks"].items()}
    return all(check(e, r2, case) for e in case.result)


def judge(case, r):
    if "harness" in r:
        case.outcome, case.detail = "harness-error", r["harness"]
        return
    codes = set()
    for e in case.result:
        codes |= expected_codes(e)
    if "error" in r:
        kind, rest = r["error"]
        if kind == "unsupported":
            case.outcome, case.detail = "unsupported", rest
            return
        code = rest.split(" ", 1)[0] if kind == "error" else "exception"
        if code in codes or ("*" in codes and kind == "error"):
            case.outcome = "pass"
        elif codes and kind == "error":
            case.outcome, case.detail = "wrong-code", "%s, expected %s" % (code, " or ".join(sorted(codes)))
        else:
            case.outcome, case.detail = "fail", rest[:200]
        return
    if all(check(e, r, case) for e in case.result):
        case.outcome = "pass"
    elif unparsed_only(case, r):
        # an assertion in the syntax of XPath 3.0 or later (e.g. the operator
        # "!"), which the checks, run with this library's XPath, cannot
        # parse; only if the result would pass with those taken as true
        case.outcome, case.detail = "assertion-unsupported", "assertion beyond XPath 2.0"
    else:
        case.outcome = "fail"
        case.detail = "value" if not codes or len(case.result) > 1 or local(case.result[0]) != "error" \
            else "no error, expected " + " or ".join(sorted(codes))


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
        f.write("# W3C XSLT test suite baseline: the XSLT 1.0 and 2.0 cases that pass (or give another error code)\n")
        f.write("# suite commit %s, harness %s; written by tools/run-xslt-tests.py --update-baseline\n"
                % (COMMIT, HARNESS_VERSION))
        for c in sorted(cases, key=lambda c: c.key):
            if c.outcome in ("pass", "wrong-code"):
                f.write("%s %s\n" % (c.key, c.outcome))


def fail_class(case):
    if case.outcome != "fail":
        return case.outcome
    head = case.detail.split(" ")[0].rstrip(":")
    if re.match(r"^[A-Z]{4}[0-9]{4}$", head):
        return "fail " + head
    return "fail " + ("value" if case.detail.startswith("value") or case.detail.startswith("no error")
                      else "exception")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    exe_name = "LandrixXmlXsltSuite.exe" if os.name == "nt" else "LandrixXmlXsltSuite"
    ap.add_argument("--exe", default=os.path.join(ROOT, "build", "fpc322-win64", exe_name))
    ap.add_argument("--filter", default="")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    if args.update_baseline and args.filter:
        sys.exit("--update-baseline needs the whole suite (no --filter)")
    args.exe = os.path.abspath(args.exe)
    if not os.path.exists(args.exe):
        sys.exit("helper not found: %s (build tests/LandrixXmlXsltSuite.dpr)" % args.exe)
    if not os.path.exists(os.path.join(SUITE, "catalog.xml")):
        download()
    check_catalog()
    cases = load_cases(args.filter)
    todo = [c for c in cases if c.outcome is None]
    if os.path.exists(os.path.join(WORK, "cases")):
        shutil.rmtree(os.path.join(WORK, "cases"))
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        for case, r in zip(todo, pool.map(lambda c: run_case(args.exe, c), todo)):
            judge(case, r)
    os.makedirs(WORK, exist_ok=True)
    with open(os.path.join(WORK, "results.txt"), "w", encoding="utf-8", newline="\n") as f:
        for c in sorted(cases, key=lambda c: c.key):
            f.write("%s %s %s\n" % (c.key, c.outcome, c.reason or c.detail))
    applicable = [c for c in cases if c.outcome != "excluded"]
    counts = collections.Counter(fail_class(c) for c in applicable)
    reasons = collections.Counter(c.reason.split(" ")[0] + " " + c.reason.split(" ")[1]
                                  if " " in c.reason else c.reason for c in cases if c.outcome == "excluded")
    print("%d cases, %d applicable" % (len(cases), len(applicable)))
    for k, n in counts.most_common():
        print("  %-28s %6d" % (k, n))
    if args.verbose:
        print("excluded:")
        for k, n in reasons.most_common(30):
            print("  %-40s %6d" % (k, n))
    base = read_baseline()
    # a baseline case now excluded (or no longer applicable) counts as worse
    worse = [c for c in cases if base.get(c.key) == "pass" and c.outcome != "pass"
             or base.get(c.key) == "wrong-code" and c.outcome not in ("pass", "wrong-code")]
    better = [c for c in applicable if c.outcome in ("pass", "wrong-code") and base.get(c.key) != c.outcome
              and not (base.get(c.key) == "pass")]
    for c in worse:
        print("WORSE %s: %s (baseline %s) %s" % (c.key, c.outcome, base[c.key], c.detail or c.reason))
    harness = [c for c in applicable if c.outcome == "harness-error"]
    for c in harness[:20]:
        print("HARNESS %s: %s" % (c.key, c.detail))
    print("baseline: %d cases, %d worse, %d better" % (len(base), len(worse), len(better)))
    if args.update_baseline and worse:
        print("baseline not written: cases got worse")
    elif args.update_baseline:
        write_baseline(cases)
        print("baseline written:", BASELINE)
    return 1 if worse or harness else 0


if __name__ == "__main__":
    sys.exit(main())
