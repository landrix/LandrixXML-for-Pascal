#!/usr/bin/env python3
"""Compile the Schematron rule sets of the tests (tests/data/schematron/rules) from
the upstream packages and check them against the XSLT the KoSIT validator runs.

  python tools/gen-schematron-rules.py --packages DIR --kosit DIR

--packages: a folder with the unpacked upstream packages
  en-ubl/  en16931-ubl-1.3.16.zip
  en-cii/  en16931-cii-1.3.16.zip
  xr/      xrechnung-3.0.2-schematron-2.6.0.zip
--kosit: the KoSIT configuration validator-configuration-xrechnung_3.0.2 (its
  XSLT files are the reference for tools/sch-crosscheck.py).

Where the upstream source and the KoSIT XSLT differ, what KoSIT runs wins
(OVERRIDES); the rule file records the original test.
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "schematron", "rules")

EN = "https://github.com/ConnectingEurope/eInvoicing-EN16931/releases/download/validation-1.3.16/"
XR = ("https://projekte.kosit.org/api/v4/projects/356/packages/maven/de/xeinkauf/xrechnung-3.0.2-schematron/"
      "2.6.0/xrechnung-3.0.2-schematron-2.6.0.zip")

SETS = [
    ("en16931-ubl", "en-ubl/schematron/preprocessed/EN16931-UBL-validation-preprocessed.sch",
     EN + "en16931-ubl-1.3.16.zip", "EN16931-UBL-validation.xsl", []),
    ("en16931-cii", "en-cii/schematron/preprocessed/EN16931-CII-validation-preprocessed.sch",
     EN + "en16931-cii-1.3.16.zip", "EN16931-CII-validation.xsl",
     # the CII syntax binding defines CII-SR-282 twice; KoSIT's XSLT has the second definition
     ["CII-SR-282=not(ram:BuyerTaxRepresentativeTradeParty)"]),
    ("xrechnung-ubl", "xr/schematron/ubl/XRechnung-UBL-validation.sch", XR,
     "resources/xrechnung/3.0.2/xsl/XRechnung-UBL-validation.xsl", []),
    ("xrechnung-cii", "xr/schematron/cii/XRechnung-CII-validation.sch", XR,
     "resources/xrechnung/3.0.2/xsl/XRechnung-CII-validation.xsl", []),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--packages", required=True)
    ap.add_argument("--kosit", required=True)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    tools = os.path.dirname(os.path.abspath(__file__))
    failed = False
    for name, src, url, xsl, overrides in SETS:
        out = os.path.join(OUT, name + ".xml")
        cmd = [sys.executable, os.path.join(tools, "sch-compile.py"), os.path.join(args.packages, src), out,
               "--url", url]
        if overrides:
            cmd += ["--override"] + overrides
        subprocess.run(cmd, check=True)
        r = subprocess.run([sys.executable, os.path.join(tools, "sch-crosscheck.py"), out,
                            os.path.join(args.kosit, xsl)])
        failed = failed or r.returncode != 0
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
