#!/usr/bin/env python3
"""Check tests/data/xsdschema/rules.txt against the XML Schema validator of
the Java runtime (Xerces, as used by the KoSIT validator): every schema
must be rejected with the listed constraint code (the sixth field where
Xerces reports another code than LandrixXml), every 'valid' one must
load. The file is written by hand; run this after adding cases and with
every new JDK (tools/check-xerces-drift.py does).
  javac --release 17 -d OUT tools/XsdOracle.java
  python tools/check-xsdrules.py --java PATH/java.exe --classes OUT
Exit code 0 if every case agrees with the JDK.
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RULES = os.path.join(ROOT, "tests", "data", "xsdschema", "rules.txt")


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            i += 1
            out.append({"n": "\n", "r": "\r", "t": "\t"}.get(s[i], s[i]))
        else:
            out.append(s[i])
        i += 1
    return "".join(out)


def read_rules(path):
    rows = []
    with open(path, encoding="ascii") as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) not in (5, 6):
                sys.exit("%s:%d: expected 5 or 6 fields" % (path, number))
            code, _, name, root, body = fields[:5]
            known = len(fields) == 6
            if known:
                code = fields[5]
            rows.append((number, code, name, unescape(root), unescape(body), known))
    return rows


def verdict(java, classes, tmp, number, root, body):
    """The constraint code Xerces reports for the schema, 'valid', or
    'oracle-failed' if the Java process failed otherwise."""
    xsd = os.path.join(tmp, "rule%d.xsd" % number)
    xml = os.path.join(tmp, "rule%d.xml" % number)
    with open(xsd, "w", encoding="utf-8", newline="\n") as f:
        f.write('<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"' + root + '>' + body + '</xs:schema>')
    with open(xml, "w", encoding="utf-8", newline="\n") as f:
        f.write("<r/>\n")
    p = subprocess.run([java, "-cp", classes, "XsdOracle", xsd, xml], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if p.returncode == 0:
        return "valid", ""
    if p.returncode != 2:
        return "oracle-failed", "exit code %d: %s" % (p.returncode, p.stderr.strip()[:300])
    m = re.search(r"schema error: ([A-Za-z0-9.\-]+):", p.stderr)
    return (m.group(1) if m else "other"), p.stderr.strip()[:300]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--classes", required=True, help="folder with the compiled XsdOracle class")
    ap.add_argument("--rules", default=RULES)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()
    rows = read_rules(args.rules)
    bad = 0
    known = sum(1 for row in rows if row[5])
    with tempfile.TemporaryDirectory() as tmp, concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(verdict, args.java, args.classes, tmp, number, root, body)
                   for number, code, name, root, body, _ in rows]
        for (number, code, name, root, body, _), future in zip(rows, futures):
            got, message = future.result()
            if got != code:
                bad += 1
                print("line %d (%s): expected %s, the JDK says %s %s" % (number, name, code, got, message))
    print("%d rules, %d agree, %d differ (%d with a known other code in LandrixXml)" %
          (len(rows), len(rows) - bad, bad, known))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
