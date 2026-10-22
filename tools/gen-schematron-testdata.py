#!/usr/bin/env python3
"""Generate the expected results of the Schematron tests.

For every rule set in tests/data/schematron/rules and the documents of its syntax
(ubl/ or cii/), this script runs the XSLT the KoSIT validator uses (compiled by
SchXslt) with Saxon HE and writes expected-<rule set>.txt:

  ## DOCUMENT
  fired CONTEXT                          per svrl:fired-rule, in order
  KIND ID FLAG LOCATION | MESSAGE        per svrl:failed-assert / successful-report
  saxon-error CODE                       Saxon stopped with a dynamic error

KIND is failed-assert or successful-report; MESSAGE is the svrl:text with white
space normalized.

  python tools/gen-schematron-testdata.py --java PATH/java.exe --saxon validator-1.6.3-standalone.jar
      --kosit validator-configuration-xrechnung_3.0.2

The files are committed; rerun this script when the rules or documents change.
"""

import argparse
import os
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data", "schematron")
SVRL = "{http://purl.oclc.org/dsdl/svrl}"

SETS = [
    ("en16931-ubl", "ubl", "EN16931-UBL-validation.xsl"),
    ("en16931-cii", "cii", "EN16931-CII-validation.xsl"),
    ("xrechnung-ubl", "ubl", "resources/xrechnung/3.0.2/xsl/XRechnung-UBL-validation.xsl"),
    ("xrechnung-cii", "cii", "resources/xrechnung/3.0.2/xsl/XRechnung-CII-validation.xsl"),
]


def norm(s):
    return " ".join((s or "").split())


def run(java, saxon, xsl, doc):
    with tempfile.TemporaryDirectory() as t:
        out = os.path.join(t, "o.svrl")
        r = subprocess.run([java, "-cp", saxon, "net.sf.saxon.Transform", "-s:" + doc, "-xsl:" + xsl, "-o:" + out],
                           capture_output=True)
        if r.returncode != 0:
            m = re.search(r"\b([A-Z]{4}[0-9]{4})\b", r.stderr.decode("utf-8", "replace"))
            return ["saxon-error " + (m.group(1) if m else "unknown")]
        root = ET.parse(out).getroot()
    lines = []
    for el in root:
        if el.tag == SVRL + "fired-rule":
            lines.append("fired " + norm(el.get("context")))
    for el in root:
        if el.tag in (SVRL + "failed-assert", SVRL + "successful-report"):
            kind = "failed-assert" if el.tag == SVRL + "failed-assert" else "successful-report"
            text = el.find(SVRL + "text")
            lines.append("%s %s %s %s | %s" % (kind, el.get("id") or "", el.get("flag") or "", el.get("location"),
                                               norm("".join(text.itertext()) if text is not None else "")))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--saxon", required=True)
    ap.add_argument("--kosit", required=True)
    args = ap.parse_args()
    for name, syntax, xsl in SETS:
        folder = os.path.join(DATA, syntax)
        lines = []
        docs = sorted(f for f in os.listdir(folder) if f.endswith(".xml"))
        for d in docs:
            lines.append("## " + d)
            lines.extend(run(args.java, args.saxon, os.path.join(args.kosit, xsl), os.path.join(folder, d)))
        with open(os.path.join(DATA, "expected-%s.txt" % name), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print("%s: %d documents" % (name, len(docs)))


if __name__ == "__main__":
    main()
