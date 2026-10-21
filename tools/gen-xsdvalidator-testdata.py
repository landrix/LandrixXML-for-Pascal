#!/usr/bin/env python3
"""Generate the expected results of the XSD validator tests.

Every folder in tests/data/xsdvalidator and in its subfolder edge (small
cases of single rules) holds a schema (main.xsd, with the documents it
includes or imports) and hand-written documents (*.xml).
This script adds mutated variants of valid.xml (an element deleted,
duplicated, renamed or moved, a value or an attribute changed), validates
all documents with the XML Schema validator of the Java runtime
(tools/XsdOracle.java) and writes expected.txt into each folder:

  javac --release 17 -d OUT tools/XsdOracle.java
  python tools/gen-xsdvalidator-testdata.py --java PATH/java.exe --classes OUT

expected.txt lists the documents in this form:
  file NAME            a document of the folder, or
  text ESCAPED         a generated document (backslash escapes \\\\ \\n \\r \\t)
followed by its errors, one per line:
  error LINE COLUMN CODE MESSAGE
  jdk-exception        the JDK's validator threw (an exceeded counted
                       maxOccurs); the library reports cvc-complex-type.2.4.d
and an empty line. Messages render characters outside printable ASCII as
U+XXXX, as the library does.

The files are committed; rerun this script when a folder changes.
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile
import xml.dom.minidom

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data", "xsdvalidator")
BS = chr(92)


def escape_message(s):
    return "".join(c if 32 <= ord(c) < 127 else "U+%04X" % ord(c) for c in s)


def escape_text(s):
    return (s.replace(BS, BS + BS).replace("\n", BS + "n").replace("\r", BS + "r")
            .replace("\t", BS + "t"))


def elements(node):
    out = []
    stack = [node]
    while stack:
        n = stack.pop()
        if n.nodeType == n.ELEMENT_NODE:
            out.append(n)
        stack.extend(reversed(n.childNodes))
    return out


def mutate(rng, text):
    doc = xml.dom.minidom.parseString(text.encode("utf-8"))
    els = elements(doc.documentElement)[1:]
    if not els:
        return None
    e = rng.choice(els)
    op = rng.randint(0, 7)
    parent = e.parentNode
    if op == 0:
        parent.removeChild(e)
    elif op == 1:
        parent.insertBefore(e.cloneNode(True), e)
    elif op == 2:
        sibs = [s for s in parent.childNodes if s.nodeType == s.ELEMENT_NODE and s is not e]
        if not sibs:
            return None
        other = rng.choice(sibs)
        e.tagName = other.tagName
        e.nodeName = other.tagName
    elif op == 3:
        sibs = [s for s in parent.childNodes if s.nodeType == s.ELEMENT_NODE and s is not e]
        parent.removeChild(e)
        parent.insertBefore(e, rng.choice(sibs) if sibs else None)
    elif op == 4:
        texts = [c for c in e.childNodes if c.nodeType == c.TEXT_NODE]
        value = rng.choice(["", "x", "-1", "999999999", "1.005", "2026-13-01", "  a  b  ", "true"])
        if texts:
            texts[0].data = value
        else:
            e.appendChild(doc.createTextNode(value))
    elif op == 5:
        names = [a for a in e.attributes.keys() if not a.startswith("xmlns")]
        if not names:
            return None
        e.removeAttribute(rng.choice(names))
    elif op == 6:
        e.setAttribute("unknown", "1")
    else:
        names = [a for a in e.attributes.keys() if not a.startswith("xmlns")]
        if not names:
            return None
        e.setAttribute(rng.choice(names), rng.choice(["", "x", "0", "-5", "2001-02-30"]))
    out = doc.documentElement.toxml()
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + out + "\n"


def run_oracle(java, classes, schema, files):
    out = subprocess.run([java, "-cp", classes, "XsdOracle", schema] + files,
                         capture_output=True, encoding="utf-8")
    if out.returncode != 0:
        sys.exit("oracle failed for %s:\n%s" % (schema, out.stderr[-2000:]))
    results = {f: [] for f in files}
    for line in out.stdout.splitlines():
        name, line_no, col, code, message = line.split("\t", 4)
        if code == "jdk-exception":
            results[name] = None
        elif results[name] is not None:
            results[name].append("error %s %s %s %s" % (line_no, col, code, escape_message(message)))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--classes", required=True)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--mutations", type=int, default=40)
    args = ap.parse_args()
    cases = [c for c in sorted(os.listdir(DATA)) if c != "edge"]
    cases += ["edge/" + c for c in sorted(os.listdir(os.path.join(DATA, "edge")))]
    for case in cases:
        folder = os.path.join(DATA, case)
        schema = os.path.join(folder, "main.xsd")
        if not os.path.isfile(schema):
            continue
        rng = random.Random("%s-%d" % (case, args.seed))
        names = sorted(f for f in os.listdir(folder) if f.endswith(".xml"))
        entries = [("file", n, os.path.join(folder, n)) for n in names]
        valid = [n for n in names if n.startswith("valid")]
        generated = []
        with tempfile.TemporaryDirectory() as tmp:
            if valid:
                base = open(os.path.join(folder, valid[0]), encoding="utf-8").read()
                seen = set()
                tries = 0
                while len(generated) < args.mutations and tries < 20 * args.mutations:
                    tries += 1
                    text = mutate(rng, base)
                    if text is None or text in seen:
                        continue
                    seen.add(text)
                    path = os.path.join(tmp, "g%d.xml" % len(generated))
                    with open(path, "w", encoding="utf-8", newline="") as f:
                        f.write(text)
                    generated.append(("text", text, path))
            all_entries = entries + generated
            results = run_oracle(args.java, args.classes, schema, [e[2] for e in all_entries])
            lines = []
            for kind, value, path in all_entries:
                lines.append("file " + value if kind == "file" else "text " + escape_text(value))
                res = results[path]
                lines.extend(["jdk-exception"] if res is None else res)
                lines.append("")
        with open(os.path.join(folder, "expected.txt"), "w", encoding="ascii", newline="\n") as f:
            f.write("\n".join(lines))
        print("%s: %d documents" % (case, len(all_entries)))


if __name__ == "__main__":
    main()
