#!/usr/bin/env python3
"""Run the W3C XML conformance test suite against LandrixXml.

Downloads the suite (xmlts20130923) into tests/data/xmlconf-suite/ if it is
missing (git-ignored, not redistributed), selects the XML 1.0 + Namespaces
1.0 tests, reads every document with the LandrixXmlConformance helper and
compares the result with
  - the expected outcome from the catalog (not-wf must be rejected,
    valid/invalid must be accepted), and
  - Python's expat with namespace processing as an independent oracle.

Known, deliberate deviations (documented in the README) are reported in
their own categories instead of as failures:
  - the internal DTD subset is skipped, not checked (malformed declarations
    are accepted), and DTD entities are not expanded (references to them
    are rejected);
  - encodings other than UTF-8/UTF-16/ISO-8859-1/Windows-1252/
    ISO-8859-15/US-ASCII are rejected;
  - external entities and external DTDs are never read.

Every accepted document is also copied through TLandrixXmlWriter and read
again; a different token stream is reported as "FAIL writer round trip".

Usage:
  python tools/run-xmlconf.py [--exe PATH] [--verbose]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlConformance.dpr -NoRun
Exit code: 0 if there are no unexplained failures.
"""

import argparse
import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import xml.parsers.expat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITE_DIR = os.path.join(ROOT, "tests", "data", "xmlconf-suite")
SUITE = os.path.join(SUITE_DIR, "xmlconf")
URL = "https://www.w3.org/XML/Test/xmlts20130923.tar.gz"

# Error codes of TLandrixXmlErrorCode
CODES = {0: "None", 1: "General", 2: "InvalidArgument", 3: "InvalidOperation",
         4: "InvalidUnicode", 5: "Encoding", 6: "Syntax", 7: "Namespace",
         8: "InvalidChar", 9: "Limit", 10: "Write",
         11: "Conversion"}

ATTR_RE = re.compile(r"""([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')""")
TEST_RE = re.compile(r"<TEST\s+([^>]*)>", re.S)
ENTITY_RE = re.compile(r'<!ENTITY\s+\S+\s+SYSTEM\s+"([^"]+)"\s*>')


def download():
    os.makedirs(SUITE_DIR, exist_ok=True)
    print("downloading", URL)
    with urllib.request.urlopen(URL) as resp:
        data = resp.read()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        tar.extractall(SUITE_DIR, filter="data")


def load_tests():
    with open(os.path.join(SUITE, "xmlconf.xml"), encoding="utf-8") as f:
        catalogs = ENTITY_RE.findall(f.read())
    tests = []
    for cat in catalogs:
        path = os.path.join(SUITE, cat)
        base = os.path.dirname(path)
        with open(path, "rb") as f:
            text = f.read().decode("utf-8", "replace")
        for m in TEST_RE.finditer(text):
            attrs = {}
            for a in ATTR_RE.finditer(m.group(1)):
                attrs[a.group(1)] = a.group(2) if a.group(2) is not None else a.group(3)
            attrs["FILE"] = os.path.normpath(os.path.join(base, attrs["URI"]))
            attrs["CATALOG"] = cat
            tests.append(attrs)
    return tests


def applicable(t):
    rec = t.get("RECOMMENDATION", "XML1.0")
    if rec not in ("XML1.0", "NS1.0", "XML1.0-errata2e", "XML1.0-errata3e",
                   "XML1.0-errata4e", "NS1.0-errata1e"):
        return False
    if t.get("VERSION", "1.0") not in ("1.0",):
        return False
    edition = t.get("EDITION")
    if edition and "5" not in edition.split():
        return False
    if t.get("NAMESPACE") == "no":
        return False
    if t["TYPE"] == "error":
        return False
    return os.path.exists(t["FILE"])


def run_expat(path):
    """Returns (ok, message, error_after_doctype). error_after_doctype is
    True when expat's error lies after the end of the DOCTYPE, i.e. in the
    document body, which the DTD-skipping deviation cannot explain."""
    p = xml.parsers.expat.ParserCreate(namespace_separator=" ")
    p.SetParamEntityParsing(xml.parsers.expat.XML_PARAM_ENTITY_PARSING_NEVER)
    end = {}

    def end_doctype():
        end["pos"] = (p.CurrentLineNumber, p.CurrentColumnNumber)

    p.EndDoctypeDeclHandler = end_doctype
    try:
        with open(path, "rb") as f:
            p.ParseFile(f)
        return True, "", False
    except xml.parsers.expat.ExpatError as e:
        after = "pos" in end and (e.lineno, e.offset) > end["pos"]
        return False, str(e), after


def run_landrix(exe, files):
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt", encoding="utf-8") as lst:
        lst.write("\n".join(files))
        name = lst.name
    try:
        out = subprocess.run([exe, name], capture_output=True, check=False).stdout
    finally:
        os.unlink(name)
    results = {}
    for line in out.decode("utf-8", "replace").splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            results[os.path.normpath(parts[0])] = parts[1:]
    return results


def has_doctype(path):
    with open(path, "rb") as f:
        data = f.read()
    for enc in ("utf-8", "utf-16"):
        try:
            text = data.decode(enc)
            break
        except UnicodeDecodeError:
            text = data.decode("latin-1")
    return "<!DOCTYPE" in text


def has_attlist(path):
    with open(path, "rb") as f:
        return b"<!ATTLIST" in f.read()


def main():
    ap = argparse.ArgumentParser()
    default = os.path.join(ROOT, "build", "fpc322-win64" if os.name == "nt" else "fpc322-linux",
                           "LandrixXmlConformance" + (".exe" if os.name == "nt" else ""))
    ap.add_argument("--exe", default=default)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    if not os.path.exists(os.path.join(SUITE, "xmlconf.xml")):
        download()
    tests = [t for t in load_tests() if applicable(t)]
    results = run_landrix(os.path.abspath(args.exe), [t["FILE"] for t in tests])

    cats = {}

    def add(cat, t, detail):
        cats.setdefault(cat, []).append((t, detail))

    for t in tests:
        r = results.get(t["FILE"], ["MISSING"])
        if r[0] == "RTFAIL":
            add("FAIL writer round trip", t, " ".join(r[1:]))
            r = ["OK"]
        ours = r[0] == "OK"
        exp_ok, exp_msg, exp_after = run_expat(t["FILE"])
        want = t["TYPE"] != "not-wf"
        doctype = has_doctype(t["FILE"])
        detail = " ".join(r) + ("" if r[0] == "OK" else "")
        if r[0] == "EXC" or r[0] == "MISSING":
            add("FAIL crash/unexpected exception", t, detail)
        elif ours == want:
            add("pass", t, "")
        elif ours and not want:
            if doctype and not exp_after:
                add("deviation: DTD not checked (accepted not-wf)", t, "expat: " + exp_msg)
            elif doctype and has_attlist(t["FILE"]):
                add("deviation: DTD attribute types not applied (accepted not-wf)", t, "expat: " + exp_msg)
            elif doctype:
                add("FAIL accepted not-wf (error after the DOCTYPE)", t, "expat: " + exp_msg)
            else:
                add("FAIL accepted not-wf", t, "expat: " + (exp_msg or "accepts"))
        else:
            code = CODES.get(int(r[1]), r[1]) if len(r) > 1 and r[1].isdigit() else "?"
            if code == "Encoding":
                add("deviation: unsupported encoding", t, detail)
            elif doctype and t.get("ENTITIES", "none") != "none":
                add("deviation: external entities not read", t, detail)
            elif doctype:
                add("deviation: DTD entities/defaults not processed (rejected wf)", t, detail)
            else:
                add("FAIL rejected well-formed", t, detail)
        if ours != exp_ok and not doctype and r[0] in ("OK", "ERR"):
            add("info: differs from expat (no DOCTYPE)", t, "ours=%s expat=%s %s" % (ours, exp_ok, exp_msg))

    total = len(tests)
    print("W3C XML conformance: %d applicable tests" % total)
    for cat in sorted(cats):
        print("  %-62s %5d" % (cat, len(cats[cat])))
    failures = 0
    for cat in sorted(cats):
        if cat.startswith("FAIL") or (args.verbose and cat != "pass"):
            print()
            print("== %s ==" % cat)
            for t, detail in cats[cat]:
                print("  %s %s [%s] %s" % (t["ID"], os.path.relpath(t["FILE"], SUITE), t["TYPE"], detail))
            if cat.startswith("FAIL"):
                failures += len(cats[cat])
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
