#!/usr/bin/env python3
"""Download the Unicode normalization conformance file NormalizationTest.txt
15.0.0 into the git-ignored folder tests/data/unicode-suite/ (verified by
its SHA-256). The test Normalize.UnicodeSuite of tests/LandrixXmlTests.dpr
runs it when the file is there and skips silently otherwise.

  python tools/fetch-unicode-tests.py
"""

import hashlib
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "tests", "data", "unicode-suite", "NormalizationTest.txt")
URL = "https://www.unicode.org/Public/15.0.0/ucd/NormalizationTest.txt"
SHA256 = "fb9ac8cc154a80cad6caac9897af55a4e75176af6f4e2bb6edc2bf8b1d57f326"


def main():
    if os.path.exists(DEST):
        with open(DEST, "rb") as f:
            if hashlib.sha256(f.read()).hexdigest() == SHA256:
                print("present:", DEST)
                return
    print("downloading", URL)
    with urllib.request.urlopen(URL, timeout=120) as response:
        data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SHA256:
        sys.exit("NormalizationTest.txt has SHA-256 %s, expected %s" % (digest, SHA256))
    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    with open(DEST, "wb") as f:
        f.write(data)
    print("written:", DEST)


if __name__ == "__main__":
    main()
