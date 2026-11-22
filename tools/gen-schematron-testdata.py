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
import sys
import tempfile
import xml.etree.ElementTree as ET
import saxonjar

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
    """White space runs (XML white space only: NBSP is text) to one space, trimmed."""
    return " ".join(x for x in re.split("[ \t\n\r]+", s or "") if x)


def run(java, saxon, xsl, doc):
    with tempfile.TemporaryDirectory() as t:
        out = os.path.join(t, "o.svrl")
        r = subprocess.run([java, "-Duser.timezone=UTC", "-cp", saxon, "net.sf.saxon.Transform", "-s:" + doc,
                            "-xsl:" + xsl, "-o:" + out],
                           capture_output=True)
        if r.returncode != 0:
            err = r.stderr.decode("utf-8", "replace")
            # the first error code, not a warning such as SXWN9026
            codes = [c for c in re.findall(r"\b([A-Z]{4}[0-9]{4})\b", err) if not c.startswith("SXWN")]
            if not codes:
                # no error code: Saxon did not start or failed outside the transformation
                sys.exit("Saxon failed on %s with %s (no output file written):\n%s" % (doc, xsl, err[-2000:]))
            return ["saxon-error " + codes[0]]
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
    saxonjar.check(args.saxon)
    results = []
    for name, syntax, xsl in SETS:
        folder = os.path.join(DATA, syntax)
        lines = []
        docs = sorted(f for f in os.listdir(folder) if f.endswith(".xml"))
        for d in docs:
            lines.append("## " + d)
            lines.extend(run(args.java, args.saxon, os.path.join(args.kosit, xsl), os.path.join(folder, d)))
        results.append((name, lines, len(docs)))
    # write only after every set ran, so a failure leaves all files untouched
    for name, lines, count in results:
        with open(os.path.join(DATA, "expected-%s.txt" % name), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print("%s: %d documents" % (name, count))


if __name__ == "__main__":
    main()
