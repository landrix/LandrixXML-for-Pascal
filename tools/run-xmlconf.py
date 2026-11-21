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

The deviation categories are narrow: a rejected well-formed document with
a DOCTYPE is excused only with the reader's "entity is not expanded"
message, an encoding error only for an encoding outside the supported set,
an accepted not-wf document with an ATTLIST in the body only for expat's
"duplicate attribute" that disappears without namespace processing, and an
accepted not-wf document whose expat error lies before the DOCTYPE never.
Anything else counts as a failure.

Integrity: the archive itself is not pinned by hash (no reference hash of
xmlts20130923.tar.gz was recorded); instead the extracted catalogs are
checked against CATALOG_SHA256, a missing test file is a failure, and the
number of applicable tests must be EXPECTED_TESTS.

Usage:
  python tools/run-xmlconf.py [--exe PATH] [--verbose] [--timeout SECONDS]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlConformance.dpr -NoRun
Exit code: 0 if there are no unexplained failures; a crash, a non-zero exit
code or a hang (--timeout, default 1800 s) of the helper is a failure.
"""

import argparse
import hashlib
import http.client
import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import xml.parsers.expat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITE_DIR = os.path.join(ROOT, "tests", "data", "xmlconf-suite")
SUITE = os.path.join(SUITE_DIR, "xmlconf")
URL = "https://www.w3.org/XML/Test/xmlts20130923.tar.gz"
# SHA-256 over xmlconf.xml and the catalogs it includes (see catalog_digest)
CATALOG_SHA256 = "639df6268c1f43a0c39051c55f17536de5fbf41dcf563cfd2e7fa0aa9ba70cae"
# applicable tests of the pinned catalogs; any other number fails the run
EXPECTED_TESTS = 1965

# Error codes of TLandrixXmlErrorCode
CODES = {0: "None", 1: "General", 2: "InvalidArgument", 3: "InvalidOperation",
         4: "InvalidUnicode", 5: "Encoding", 6: "Syntax", 7: "Namespace",
         8: "InvalidChar", 9: "Limit", 10: "Write",
         11: "Conversion", 12: "UnexpectedElement"}

# the encoding names the reader supports, lower case (LandrixXmlEncoding.pas,
# the label lookup; same set as in fuzz.py)
SUPPORTED_ENCODINGS = {"utf-8", "utf8", "utf-16", "utf-16le", "utf-16be",
                       "iso-8859-1", "iso_8859-1", "iso8859-1", "latin1", "l1", "cp819",
                       "ibm819", "iso-ir-100", "csisolatin1", "windows-1252", "cp1252",
                       "us-ascii", "ascii", "iso-8859-15", "iso_8859-15", "iso8859-15",
                       "latin9", "latin-9", "l9"}
DECL_ENCODING_RE = re.compile(r"""<\?xml\s[^>]*?encoding\s*=\s*["']([^"']*)["']""")
# the documented reason for rejecting a well-formed document with a DOCTYPE
ENTITY_NOT_EXPANDED = "is not expanded: DTD entities are not supported"

ATTR_RE = re.compile(r"""([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')""")
TEST_RE = re.compile(r"<TEST\s+([^>]*)>", re.S)
ENTITY_RE = re.compile(r'<!ENTITY\s+\S+\s+SYSTEM\s+"([^"]+)"\s*>')


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
        tar.extractall(SUITE_DIR, filter="data")


def catalog_digest():
    """SHA-256 over xmlconf.xml and the catalogs it includes, in order."""
    with open(os.path.join(SUITE, "xmlconf.xml"), "rb") as f:
        data = f.read()
    h = hashlib.sha256(data)
    for cat in ENTITY_RE.findall(data.decode("utf-8")):
        with open(os.path.join(SUITE, cat), "rb") as f:
            h.update(f.read())
    return h.hexdigest()


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
    # a missing test file is reported by main(), not dropped
    return True


def run_expat(path):
    """Returns (ok, message, error_after_doctype, position). error_after_doctype
    is True when expat's error lies after the end of the DOCTYPE, i.e. in the
    document body, which the DTD-skipping deviation cannot explain; position
    is (line, column from 0) of the error, None if there is none."""
    p = xml.parsers.expat.ParserCreate(namespace_separator=" ")
    p.SetParamEntityParsing(xml.parsers.expat.XML_PARAM_ENTITY_PARSING_NEVER)
    end = {}

    def end_doctype():
        end["pos"] = (p.CurrentLineNumber, p.CurrentColumnNumber)

    p.EndDoctypeDeclHandler = end_doctype
    try:
        with open(path, "rb") as f:
            p.ParseFile(f)
        return True, "", False, None
    except xml.parsers.expat.ExpatError as e:
        after = "pos" in end and (e.lineno, e.offset) > end["pos"]
        return False, str(e), after, (e.lineno, e.offset)


def literal_duplicate_attribute(path):
    """True if expat reports a duplicate attribute without namespace
    processing too, i.e. the same name twice in one start tag (not two
    prefixes that only meet after normalizing a namespace declaration)."""
    p = xml.parsers.expat.ParserCreate()
    p.SetParamEntityParsing(xml.parsers.expat.XML_PARAM_ENTITY_PARSING_NEVER)
    try:
        with open(path, "rb") as f:
            p.ParseFile(f)
        return False
    except xml.parsers.expat.ExpatError as e:
        return e.code == xml.parsers.expat.errors.codes[
            xml.parsers.expat.errors.XML_ERROR_DUPLICATE_ATTRIBUTE]


def run_landrix(exe, files, timeout):
    """Returns (results, problem); problem is "" or describes a crash, a
    non-zero exit code or a hang of the helper (a tooling failure)."""
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt", encoding="utf-8") as lst:
        lst.write("\n".join(files))
        name = lst.name
    problem = ""
    try:
        try:
            proc = subprocess.run([exe, name], capture_output=True, check=False, timeout=timeout)
            out = proc.stdout
            if proc.returncode != 0:
                problem = "helper exited with %d: %s" % (proc.returncode,
                          proc.stderr.decode("utf-8", "replace").strip()[:500])
        except subprocess.TimeoutExpired as e:
            out = e.stdout or b""
            problem = "helper did not finish within %d seconds" % timeout
    finally:
        os.unlink(name)
    results = {}
    for line in out.decode("utf-8", "replace").splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].isdigit() and int(parts[0]) < len(files):
            results[os.path.normpath(files[int(parts[0])])] = parts[1:]
    return results, problem


def has_doctype(path):
    """(line, column from 0) of "<!DOCTYPE" as expat counts them, or None."""
    with open(path, "rb") as f:
        data = f.read()
    for enc in ("utf-8", "utf-16"):
        try:
            text = data.decode(enc)
            break
        except UnicodeDecodeError:
            text = data.decode("latin-1")
    i = text.find("<!DOCTYPE")
    if i < 0:
        return None
    before = text[:i].replace("\r\n", "\n").replace("\r", "\n")
    return before.count("\n") + 1, len(before) - before.rfind("\n") - 1


def has_attlist(path):
    with open(path, "rb") as f:
        return b"<!ATTLIST" in f.read()


def encoding_unsupported(path):
    """True if the document is in an encoding outside the supported set: a
    declared encoding that is not supported, a byte signature of another
    family (UCS-4, EBCDIC), or UTF-16 without BOM and without a declaration
    naming UTF-16LE or UTF-16BE (documented in the README)."""
    with open(path, "rb") as f:
        data = f.read(1024)
    no_bom_utf16 = False
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        text = data.decode("utf-16", "replace")
    elif data[:2] == b"<\x00":
        text = data.decode("utf-16-le", "replace")
        no_bom_utf16 = True
    elif data[:2] == b"\x00<":
        text = data.decode("utf-16-be", "replace")
        no_bom_utf16 = True
    elif data[:3] == b"\xef\xbb\xbf":
        text = data[3:].decode("latin-1")
    elif data[:1] in (b"<", b" ", b"\t", b"\r", b"\n"):
        text = data.decode("latin-1")
    else:
        return True
    m = DECL_ENCODING_RE.match(text.lstrip("\ufeff"))
    if m is None:
        return no_bom_utf16
    name = m.group(1).lower()
    if no_bom_utf16 and name == "utf-16":
        # without a BOM the declaration must name UTF-16LE or UTF-16BE
        return True
    return name not in SUPPORTED_ENCODINGS


def main():
    ap = argparse.ArgumentParser()
    default = os.path.join(ROOT, "build", "fpc322-win64" if os.name == "nt" else "fpc322-linux",
                           "LandrixXmlConformance" + (".exe" if os.name == "nt" else ""))
    ap.add_argument("--exe", default=default)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--timeout", type=int, default=1800,
                    help="seconds for the helper run over the whole suite")
    args = ap.parse_args()
    if not os.path.exists(os.path.join(SUITE, "xmlconf.xml")):
        download()
    digest = catalog_digest()
    if digest != CATALOG_SHA256:
        sys.exit("unexpected catalogs in %s (SHA-256 %s); delete the folder to download "
                 "the suite again" % (SUITE_DIR, digest))
    tests = [t for t in load_tests() if applicable(t)]
    present = [t for t in tests if os.path.exists(t["FILE"])]
    results, problem = run_landrix(os.path.abspath(args.exe), [t["FILE"] for t in present],
                                   args.timeout)

    cats = {}

    def add(cat, t, detail):
        cats.setdefault(cat, []).append((t, detail))

    for t in tests:
        if not os.path.exists(t["FILE"]):
            add("FAIL test file missing", t, "")
            continue
        r = results.get(t["FILE"], ["MISSING"])
        if r[0] == "RTFAIL":
            rt = " ".join(r[1:])
            if (t["TYPE"] == "not-wf" and rt.startswith("writing failed: ELandrixXmlError")
                    and "in document type content" in rt):
                # a not-wf DOCTYPE the reader let through (DTD not
                # checked): the writer's DOCTYPE check is right to refuse it
                add("info: writer refuses accepted not-wf", t, " ".join(r[1:]))
            else:
                add("FAIL writer round trip", t, " ".join(r[1:]))
            r = ["OK"]
        ours = r[0] == "OK"
        exp_ok, exp_msg, exp_after, exp_pos = run_expat(t["FILE"])
        want = t["TYPE"] != "not-wf"
        doctype = has_doctype(t["FILE"])
        detail = " ".join(r) + ("" if r[0] == "OK" else "")
        if r[0] == "EXC" or r[0] == "MISSING":
            add("FAIL crash/unexpected exception", t, detail)
        elif ours == want:
            add("pass", t, "")
        elif ours and not want:
            if doctype and exp_pos is not None and exp_pos < doctype:
                # e.g. a malformed XML declaration: the DTD cannot explain it
                add("FAIL accepted not-wf (error before the DOCTYPE)", t, "expat: " + exp_msg)
            elif doctype and not exp_after:
                add("deviation: DTD not checked (accepted not-wf)", t, "expat: " + exp_msg)
            elif (doctype and has_attlist(t["FILE"]) and exp_msg.startswith("duplicate attribute")
                    and not literal_duplicate_attribute(t["FILE"])):
                # attributes that only become equal through the normalization
                # of a declared non-CDATA type
                add("deviation: DTD attribute types not applied (accepted not-wf)", t, "expat: " + exp_msg)
            elif doctype:
                add("FAIL accepted not-wf (error after the DOCTYPE)", t, "expat: " + exp_msg)
            else:
                add("FAIL accepted not-wf", t, "expat: " + (exp_msg or "accepts"))
        else:
            code = CODES.get(int(r[1]), r[1]) if len(r) > 1 and r[1].isdigit() else "?"
            if code == "Encoding" and encoding_unsupported(t["FILE"]):
                add("deviation: unsupported encoding", t, detail)
            elif doctype and ENTITY_NOT_EXPANDED in detail and t.get("ENTITIES", "none") != "none":
                add("deviation: external entities not read", t, detail)
            elif doctype and ENTITY_NOT_EXPANDED in detail:
                add("deviation: DTD entities/defaults not processed (rejected wf)", t, detail)
            elif doctype:
                add("FAIL rejected well-formed (with DOCTYPE)", t, detail)
            else:
                add("FAIL rejected well-formed", t, detail)
        if ours != exp_ok and not doctype and r[0] in ("OK", "ERR"):
            add("info: differs from expat (no DOCTYPE)", t, "ours=%s expat=%s %s" % (ours, exp_ok, exp_msg))

    total = len(tests)
    print("W3C XML conformance: %d applicable tests" % total)
    for cat in sorted(cats):
        print("  %-62s %5d" % (cat, len(cats[cat])))
    failures = 0
    if problem:
        print("FAIL " + problem)
        failures += 1
    if total != EXPECTED_TESTS:
        print("FAIL %d applicable tests, expected %d" % (total, EXPECTED_TESTS))
        failures += 1
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
