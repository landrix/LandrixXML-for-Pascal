#!/usr/bin/env python3
"""Cross-check the local golden files (tests/data/local/) with expat.

Every file below tests/data/local/{xrechnung,zugferd,gaeb} is read with the
LandrixXmlConformance helper (reader, writer round trip and DOM round trip)
and with Python's expat. The script prints one line per file with the
classification (accepted / rejected with code and position) and reports
  - disagreements between LandrixXml and expat (each one must be explained:
    a library bug or a documented, intended difference),
  - round-trip failures (writer or DOM),
  - rejected XRechnung/ZUGFeRD files (these are expected to be well-formed),
  - GAEB files whose classification differs from an optional list of
    expected rejections in tests/data/local/expected-rejections.txt
    (one path relative to tests/data/local per line).
File contents are never printed. The folder is git-ignored; when it is
missing the script reports that and exits with 0.

Usage:
  python tools/check-local.py [--exe PATH]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlConformance.dpr -NoRun
Exit code: 0 if there is nothing unexplained.
"""

import argparse
import os
import subprocess
import sys
import tempfile
import xml.parsers.expat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL = os.path.join(ROOT, "tests", "data", "local")
FOLDERS = ("xrechnung", "zugferd", "gaeb")
CODES = {0: "None", 1: "General", 2: "InvalidArgument", 3: "InvalidOperation",
         4: "InvalidUnicode", 5: "Encoding", 6: "Syntax", 7: "Namespace",
         8: "InvalidChar", 9: "Limit", 10: "Write", 11: "Conversion", 12: "UnexpectedElement"}


def expat_ok(path):
    p = xml.parsers.expat.ParserCreate(namespace_separator=" ")
    p.SetParamEntityParsing(xml.parsers.expat.XML_PARAM_ENTITY_PARSING_NEVER)
    try:
        with open(path, "rb") as f:
            p.ParseFile(f)
        return True, ""
    except xml.parsers.expat.ExpatError as e:
        return False, "line %d, column %d: %s" % (e.lineno, e.offset + 1, xml.parsers.expat.ErrorString(e.code))
    except (UnicodeDecodeError, LookupError, ValueError) as e:
        return False, type(e).__name__


def run_helper(exe, files):
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt", encoding="utf-8") as lst:
        lst.write("\n".join(files))
        name = lst.name
    try:
        proc = subprocess.run([exe, name], capture_output=True, check=False)
        out = proc.stdout
        if proc.returncode != 0:
            # a crash of the helper is a tooling problem, not a per-file result
            print("helper exited with %d: %s" % (proc.returncode,
                  proc.stderr.decode("utf-8", "replace").strip()[:500]))
    finally:
        os.unlink(name)
    results = {}
    for line in out.decode("utf-8", "replace").splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].isdigit() and int(parts[0]) < len(files):
            results[os.path.normpath(files[int(parts[0])])] = parts[1:]
    return results


def main():
    ap = argparse.ArgumentParser()
    default = os.path.join(ROOT, "build", "fpc322-win64" if os.name == "nt" else "fpc322-linux",
                           "LandrixXmlConformance" + (".exe" if os.name == "nt" else ""))
    ap.add_argument("--exe", default=default)
    args = ap.parse_args()
    if not os.path.isdir(LOCAL):
        print("tests/data/local is missing - nothing to check")
        return 0
    files = []
    for folder in FOLDERS:
        base = os.path.join(LOCAL, folder)
        for dirpath, _, names in os.walk(base):
            for n in sorted(names):
                files.append(os.path.normpath(os.path.join(dirpath, n)))
    expected = set()
    exp_file = os.path.join(LOCAL, "expected-rejections.txt")
    if os.path.exists(exp_file):
        with open(exp_file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    expected.add(os.path.normpath(os.path.join(LOCAL, line)))
    results = run_helper(os.path.abspath(args.exe), files)
    problems = 0
    counts = {}
    for path in files:
        rel = os.path.relpath(path, LOCAL)
        folder = rel.split(os.sep)[0]
        r = results.get(path, ["MISSING"])
        ok_expat, expat_msg = expat_ok(path)
        if r[0] == "OK":
            state = "accepted"
        elif r[0] == "ERR":
            code = CODES.get(int(r[1]), r[1]) if r[1].isdigit() else r[1]
            state = "rejected %s line %s column %s" % (code, r[2], r[3])
        else:
            state = r[0]
        counts[(folder, state.split()[0])] = counts.get((folder, state.split()[0]), 0) + 1
        notes = []
        if r[0] in ("EXC", "MISSING"):
            notes.append("PROBLEM: no clean ELandrixXmlError")
        if r[0] == "RTFAIL":
            notes.append("PROBLEM: round trip: " + " ".join(r[1:]))
        ours = r[0] in ("OK", "RTFAIL")
        if ours != ok_expat:
            notes.append("PROBLEM: expat %s (%s)" % ("accepts" if ok_expat else "rejects", expat_msg))
        if not ours and folder in ("xrechnung", "zugferd"):
            notes.append("PROBLEM: e-invoice files must be well-formed")
        if folder == "gaeb" and expected:
            if (path in expected) == ours:
                notes.append("PROBLEM: differs from expected-rejections.txt")
        problems += sum(1 for n in notes if n.startswith("PROBLEM"))
        print("%-60s %s%s" % (rel, state, ("  " + "; ".join(notes)) if notes else ""))
    print()
    for key in sorted(counts):
        print("%-10s %-9s %4d" % (key[0], key[1], counts[key]))
    print("problems: %d" % problems)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
