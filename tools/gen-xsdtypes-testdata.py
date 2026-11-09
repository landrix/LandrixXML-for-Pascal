#!/usr/bin/env python3
"""Generate the XML Schema simple type test data in tests/data/xsdtypes/.

The expected results come from the XML Schema validator of the Java
runtime (Xerces, as used by the KoSIT validator) through tools/XsdOracle.java:

  javac --release 17 -d OUT tools/XsdOracle.java
  python tools/gen-xsdtypes-testdata.py --java PATH/java.exe --classes OUT

Every type below gets an element in a generated schema; every value becomes
one element of a generated instance, one per line, so that each Xerces
error can be attributed to its value. Only the first datatype error of a
value is kept (the follow-up errors cvc-type.3.1.3 and cvc-complex-type.2.2
belong to element validation, cvc-id.* to the document-wide ID checks).

types.txt   id TAB base TAB facet=value TAB ...   (base: a built-in local
            name or the id of an earlier type; facet names as in XML Schema;
            "union" as base with member ids or built-in names as fields)
cases.txt   id TAB value TAB code   (code empty for a valid value); a value
            that is not printable ASCII is written as "hex:" + UTF-8 bytes

The files are committed; rerun this script only when the set changes.
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "xsdtypes")
BS = chr(92)

# id, base, [(facet, value), ...]
TYPES = [
    ("b-string", "string", []), ("b-normalizedString", "normalizedString", []), ("b-token", "token", []),
    ("b-language", "language", []), ("b-Name", "Name", []), ("b-NCName", "NCName", []), ("b-ID", "ID", []),
    ("b-IDREF", "IDREF", []), ("b-NMTOKEN", "NMTOKEN", []), ("b-boolean", "boolean", []),
    ("b-decimal", "decimal", []), ("b-integer", "integer", []), ("b-nonPositiveInteger", "nonPositiveInteger", []),
    ("b-negativeInteger", "negativeInteger", []), ("b-long", "long", []), ("b-int", "int", []),
    ("b-short", "short", []), ("b-byte", "byte", []), ("b-nonNegativeInteger", "nonNegativeInteger", []),
    ("b-unsignedLong", "unsignedLong", []), ("b-unsignedInt", "unsignedInt", []),
    ("b-unsignedShort", "unsignedShort", []), ("b-unsignedByte", "unsignedByte", []),
    ("b-positiveInteger", "positiveInteger", []), ("b-float", "float", []), ("b-double", "double", []),
    ("b-dateTime", "dateTime", []), ("b-time", "time", []), ("b-date", "date", []),
    ("b-gYearMonth", "gYearMonth", []), ("b-gYear", "gYear", []), ("b-gMonthDay", "gMonthDay", []),
    ("b-gDay", "gDay", []), ("b-gMonth", "gMonth", []), ("b-hexBinary", "hexBinary", []),
    ("b-base64Binary", "base64Binary", []), ("b-anyURI", "anyURI", []),
    # facets as used by GAEB, CII and UBL
    ("ns40", "normalizedString", [("maxLength", "40")]),
    ("tok35", "token", [("minLength", "1"), ("maxLength", "35")]),
    ("len3", "string", [("length", "3")]),
    ("enumNs", "normalizedString", [("enumeration", "Yes"), ("enumeration", "No"), ("enumeration", "a  b")]),
    ("enumTok", "token", [("enumeration", "Yes"), ("enumeration", "a  b")]),
    ("pat", "normalizedString", [("pattern", "[0-9]{0,17}")]),
    ("pat2", "pat", [("pattern", "[1-9][0-9]*"), ("pattern", "0")]),
    ("patEnum", "token", [("pattern", "[a-z]+"), ("enumeration", "abc"), ("enumeration", "x1")]),
    ("patLen", "patEnum", [("maxLength", "2")]),
    ("blank", "string", [("pattern", " {2,2} {9,9}.{69,69}")]),
    ("dec9_6", "decimal", [("totalDigits", "9"), ("fractionDigits", "6")]),
    ("dec4_2", "decimal", [("totalDigits", "4"), ("fractionDigits", "2"), ("maxInclusive", "50")]),
    ("posMax", "positiveInteger", [("maxInclusive", "999")]),
    ("intRange", "integer", [("minInclusive", "-5"), ("maxInclusive", "5")]),
    ("decExcl", "decimal", [("minExclusive", "0"), ("maxExclusive", "1.5")]),
    ("floatPos", "float", [("minExclusive", "0")]),
    ("dblRange", "double", [("minInclusive", "-1e3"), ("maxInclusive", "INF")]),
    ("gymEnum", "gYearMonth", [("enumeration", "2013-10"), ("enumeration", "2021-05")]),
    ("dateRange", "date", [("minInclusive", "2000-01-01"), ("maxExclusive", "2100-01-01")]),
    ("iban", "normalizedString", [("pattern", "[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}")]),
    ("b64len", "base64Binary", [("maxLength", "3")]),
    ("hexlen", "hexBinary", [("length", "2")]),
    ("uriMax", "anyURI", [("maxLength", "10")]),
    ("collapseStr", "string", [("whiteSpace", "collapse"), ("maxLength", "3")]),
    ("replaceStr", "string", [("whiteSpace", "replace"), ("enumeration", " a ")]),
    ("enumDec", "decimal", [("enumeration", "1.50"), ("enumeration", "-0")]),
    ("patBool", "boolean", [("pattern", "true|false")]),
    ("enumDbl", "double", [("enumeration", "1e2"), ("enumeration", "NaN")]),
    # facets on several derivation levels: Xerces checks them in one order
    ("enum123", "decimal", [("enumeration", "1"), ("enumeration", "2"), ("enumeration", "3")]),
    ("enum123max2", "enum123", [("maxInclusive", "2")]),
    ("max5", "string", [("maxLength", "5")]),
    ("max5len3", "max5", [("length", "3")]),
    ("frac1", "decimal", [("fractionDigits", "1")]),
    ("frac1tot3", "frac1", [("totalDigits", "3")]),
    ("timeMax", "time", [("maxInclusive", "16:00:30")]),
    ("timeMinZ", "time", [("minInclusive", "02:00:00Z")]),
    ("dateEnumNeg", "date", [("enumeration", "-0001-03-01"), ("enumeration", "-0004-02-29")]),
    ("b64enum", "base64Binary", [("enumeration", "QUJD")]),
    ("floatMin1", "float", [("minExclusive", "1")]),
    ("uriEnum", "anyURI", [("enumeration", "a b"), ("enumeration", "c  d")]),
    ("uriPatEnum", "anyURI", [("pattern", ".*"), ("enumeration", "a b")]),
    ("uriLen4", "anyURI", [("length", "4")]),
    ("u-enum-any", "union", ["enumNs", "string"]),
    ("u-int-tok", "union", ["b-int", "enumTok"]),
    # facets on unions: patterns on the collapsed value, enumeration by the
    # value of the member type that accepts it
    ("u-pat", "u-int-tok", [("pattern", "[0-9]+|Yes")]),
    ("u-enum", "u-int-tok", [("enumeration", "007"), ("enumeration", "Yes"), ("enumeration", "a  b")]),
    ("u-pat-enum", "u-pat", [("enumeration", "1"), ("enumeration", "Yes")]),
    ("u-pat-ws", "u-enum-any", [("pattern", "a b|Yes")]),
    ("u-dec-str", "union", ["b-decimal", "string"]),
    ("u-dec-str-enum", "u-dec-str", [("enumeration", "1.0"), ("enumeration", "abc")]),
    ("u-str-dec", "union", ["string", "b-decimal"]),
    ("u-str-dec-enum", "u-str-dec", [("enumeration", "1.0"), ("enumeration", "abc")]),
]

VALUES = {
    "string": ["", "a", " a ", "a" + chr(9) + "b", "line" + chr(10) + "break", "éé", "<&>", "x" * 50],
    "decimal": ["0", "-0", "+1.50", ".5", "5.", "1e5", "1,5", "", " 12 ", "123456789.1234567", "00012.300",
                "-999.99", "50", "50.00", "50.01", "1.5", "1.49", "0.0001", "abc", "12345", "123.456"],
    "integer": ["0", "-1", "1", "+7", "007", "1.0", "1.", "2147483647", "2147483648", "-2147483649",
                "9223372036854775807", "9223372036854775808", "18446744073709551615", "18446744073709551616",
                "127", "128", "-128", "-129", "255", "256", "32767", "65536", "-5", "5", "6", "999", "1000"],
    "double": ["0", "-0", "1e5", "1.e5", " 1e5 ", "+INF", "INF", "-INF", "NaN", "nan", "1E400", "1e-400", ".5e1",
               "1e", "e1", "1.5E+3", "-1e3", "-1001", "3.4028235e38", "3.4028236e38", "1e-46", "1.4e-45",
               "0x1", "100", "1e2", "abc"],
    "boolean": ["true", "false", "1", "0", "TRUE", "yes", " true ", ""],
    "dateTime": ["2026-10-21T12:00:00", "2026-10-21T24:00:00", "2026-10-21T24:00:01", "2026-10-21T12:00:00Z",
                 "2026-10-21T12:00:00.123+02:00", "2026-10-21T12:00", "2026-10-21", "0000-01-01T00:00:00",
                 "-0001-01-01T00:00:00", "12026-10-21T00:00:00", "02026-10-21T00:00:00", "2026-10-21T12:60:00",
                 "2026-10-21T12:00:00+14:00", "2026-10-21T12:00:00-14:01", "2026-10-21T12:00:00.", "abc"],
    "date": ["2026-10-21", "2024-02-29", "2026-02-29", "1900-02-29", "2000-02-29", "2026-13-01", "2026-00-10",
             "2026-01-00", "2026-04-31", "0000-01-01", "-0001-12-31", "2026-10-21Z", "2026-10-21+01:00",
             "2026-1-21", "26-10-21", " 2026-10-21 ", "1999-12-31", "2100-01-01", "2099-12-31", "2000-01-01Z"],
    "time": ["12:00:00", "24:00:00", "23:59:59.999", "23:59:60", "12:00", "12:00:00Z", "12:00:00+05:30", "7:00:00"],
    "gYearMonth": ["2013-10", "2021-05", "2013-13", "2013-1", "2013-10Z", "-2013-10", "2013", "2013-10-01"],
    "gYear": ["2026", "0000", "-0001", "26", "2026Z", "12026"],
    "gMonthDay": ["--02-29", "--02-30", "--12-31", "--13-01", "02-29", "--1-01"],
    "gDay": ["---31", "---32", "---00", "--31", "---31Z"],
    "gMonth": ["--12", "--13", "--00", "-12", "--12Z", "--12--"],
    "hexBinary": ["", "00", "0a0B", "ABC", "GG", "0F0F", " 0f "],
    "base64Binary": ["", "QUJD", "QUJD RA==", "QUJ", "QUJD===", "QQ==", "QR==", "QUE=", "QUF=", "Q U J D", "QUJD\n", "!!!!"],
    "anyURI": ["", "http://example.org/a?b#c", "http://a b", "::", "a:b", "1a:b", "urn:isbn:123", "%41", "%4", "%zz",
               "#a#b", "/rel/path", "mailto:info@example.org", "ä", "http://x/" + "y" * 20],
    "name": ["a", "a:b", ":a", "1a", "-a", "a-b.c", "_x", "é", "·a", "a·", "⁰", "a b", "",
             "̀a", "\U0001F600", "abc", "x1", "ABC", "xyz", "ab"],
    "language": ["de", "de-DE", "de-DE-x", "x-klingon", "toolonglang", "de-", "-de", "1de", "de-1999", ""],
}

# extra values for single types (findings of reviews, checked by Xerces)
EXTRA = {
    "enum123max2": ["5", "2", "3", "1.0"],
    "max5len3": ["abcdef", "abcd", "abc", "ab"],
    "frac1tot3": ["1234.56", "12.5", "123.4", "1.25"],
    "timeMax": ["02:00:00Z", "02:00:01Z", "02:00:00.5Z", "01:59:59Z", "16:00:30", "16:00:31", "02:00:30Z",
                "02:00:31Z"],
    "timeMinZ": ["16:00:30", "16:00:31", "16:00:00", "15:59:59", "12:00:00", "02:00:00Z", "01:59:59Z"],
    "dateEnumNeg": ["-0001-03-01", "-0001-02-29", "-0004-02-29", "-0400-02-29", "-0005-02-29", "-0004-03-01"],
    "uriEnum": ["a b", "a  b", "a	b", " a b ", "c  d", " c  d ", "c d"],
    "uriPatEnum": ["a b", "a  b", " a   b "],
    "uriLen4": ["a  b", "a b", " a b "],
    "b64enum": ["QUJD", "Q U J D", "QUJE", "QU JD"],
    "floatMin1": ["1", "1.00000005960464477539062500000001", "1.000000059604644775390625",
                  "1.0000000596046447753906249", "1.000000059604644775390625e00000000000000000000", "10.00000059604644775390625e-1", "1.0000001", "0.99999997"],
    "len3": ["ab😀", "a😀", "😀😀"],
    "uriMax": ["😀" * 6, "😀" * 5],
    "b-date": ["2147483647-01-01", "-2147483648-01-01", "2147483648-01-01", "-0400-02-29", "-0004-02-29",
               "-0005-02-29", "-0001-02-29"],
    "b-anyURI": ["http:", "a:", "urn:", "mailto:", "a:#", "s:#x", "///", "//?x", "//#x", "http://?x", "//",
                 "http://", "a[1]", "/[", "./[", "http://x/a[1]", "http://x/a]", "é[", "http://[abc]/",
                 "http://[::1]x/", "http://[::1]:abc/", "s://[::1]@x/", "http://[::1]:80/", "http://[2001:db8::1]/",
                 "http://[::ffff:1.2.3.4]/", "http://[1::2::3]/", "http://[::g]/", "http://[1.2.3.4]/",
                 "http://[1:2:3:4:5:6:7:8:9]/", "http://[1:2:3:4:5:6:7:8]/", "http://u@[::1]/", "http://x@y@[::1]/", "urn:a[1]", "a:[",
                 "data:,[", "http://x/?a[1]", "http://x/#a[1]", "{|}", "a b", "x%41y", "x%4y"],
}

GROUP = {
    "string": "string", "normalizedString": "string", "token": "string", "language": "language", "Name": "name",
    "NCName": "name", "ID": "name", "IDREF": "name", "NMTOKEN": "name", "boolean": "boolean", "decimal": "decimal",
    "float": "double", "double": "double", "dateTime": "dateTime", "time": "time", "date": "date",
    "gYearMonth": "gYearMonth", "gYear": "gYear", "gMonthDay": "gMonthDay", "gDay": "gDay", "gMonth": "gMonth",
    "hexBinary": "hexBinary", "base64Binary": "base64Binary", "anyURI": "anyURI",
}
for t in ["integer", "nonPositiveInteger", "negativeInteger", "long", "int", "short", "byte", "nonNegativeInteger",
          "unsignedLong", "unsignedInt", "unsignedShort", "unsignedByte", "positiveInteger"]:
    GROUP[t] = "integer"


def builtin_of(type_id):
    """The built-in type at the bottom of a type id."""
    for tid, base, _ in TYPES:
        if tid == type_id:
            if base == "union":
                return "union"
            return builtin_of(base) if base in [t[0] for t in TYPES] else base
    return type_id


def values_for(type_id, rng):
    b = builtin_of(type_id)
    if b == "union":
        vals = VALUES["string"] + VALUES["integer"][:8] + ["Yes", "No", "a  b", "a b", " Yes ", "1.0", "1.00",
                                                           "abc", " abc", "7", "1e0"]
    else:
        vals = list(VALUES[GROUP[b]])
        if GROUP[b] in ("string", "name"):
            vals += VALUES["name"] + ["Yes", "No", "a  b", " a ", "a b", " Yes ", "12345678901234567", "0", "007",
                                      "123456789012345678", "DE89370400440532013000", "de89", "abc", "x1"]
            vals += ["".join(rng.choice("ab 0129-:") for _ in range(rng.randint(0, 8))) for _ in range(5)]
        if GROUP[b] == "decimal":
            vals += VALUES["integer"]
    vals += EXTRA.get(type_id, [])
    out = []
    for v in vals:
        if v not in out:
            out.append(v)
    return out


def xsd_name(type_id):
    return "T_" + type_id.replace("-", "_")


def schema_text():
    lines = ['<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">']
    ids = [t[0] for t in TYPES]
    for tid, base, facets in TYPES:
        if base == "union":
            members = " ".join(xsd_name(m) if m in ids else "xs:" + m for m in facets)
            lines.append('<xs:simpleType name="%s"><xs:union memberTypes="%s"/></xs:simpleType>'
                         % (xsd_name(tid), members))
            continue
        b = xsd_name(base) if base in ids else "xs:" + base
        inner = "".join('<xs:%s value="%s"/>' % (f, escape(v, {'"': "&quot;"})) for f, v in facets)
        lines.append('<xs:simpleType name="%s"><xs:restriction base="%s">%s</xs:restriction></xs:simpleType>'
                     % (xsd_name(tid), b, inner))
    lines.append('<xs:element name="r"><xs:complexType><xs:choice minOccurs="0" maxOccurs="unbounded">')
    for tid, _, _ in TYPES:
        lines.append('<xs:element name="%s" type="%s"/>' % (xsd_name(tid), xsd_name(tid)))
    lines.append("</xs:choice></xs:complexType></xs:element></xs:schema>")
    return "\n".join(lines)


def xml_text(s):
    out = []
    for ch in s:
        if ch in "<&>":
            out.append({"<": "&lt;", "&": "&amp;", ">": "&gt;"}[ch])
        elif ord(ch) < 32:
            out.append("&#%d;" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def field(s):
    if all(32 <= ord(c) <= 126 for c in s) and not s.startswith("hex:"):
        return s
    return "hex:" + s.encode("utf-8").hex().upper()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--classes", required=True, help="folder with the compiled XsdOracle class")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    cases = []
    for tid, _, _ in TYPES:
        for v in values_for(tid, rng):
            cases.append((tid, v))
    work = tempfile.mkdtemp()
    xsd = os.path.join(work, "types.xsd")
    xml = os.path.join(work, "values.xml")
    with open(xsd, "w", encoding="utf-8") as f:
        f.write(schema_text())
    with open(xml, "w", encoding="utf-8", newline="\n") as f:
        f.write("<r>\n")  # line 1; case i is on line i + 2
        for tid, v in cases:
            f.write("<%s>%s</%s>\n" % (xsd_name(tid), xml_text(v), xsd_name(tid)))
        f.write("</r>\n")
    out = subprocess.run([args.java, "-cp", args.classes, "XsdOracle", xsd, xml],
                         capture_output=True, encoding="utf-8")
    if out.returncode != 0:
        sys.exit("oracle failed:\n" + out.stderr)
    codes = {}
    for line in out.stdout.splitlines():
        _, lineno, _, code, _ = line.split("\t", 4)
        idx = int(lineno) - 2
        # follow-up errors of element validation, and document-wide ID checks
        if code in ("cvc-type.3.1.3", "cvc-complex-type.2.2") or code.startswith("cvc-id.") or idx in codes:
            continue
        codes[idx] = code
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "types.txt"), "w", encoding="ascii", newline="\n") as f:
        for tid, base, facets in TYPES:
            if base == "union":
                f.write("\t".join([tid, "union"] + facets) + "\n")
            else:
                f.write("\t".join([tid, base] + ["%s=%s" % (k, field(v)) for k, v in facets]) + "\n")
    with open(os.path.join(OUT, "cases.txt"), "w", encoding="ascii", newline="\n") as f:
        for i, (tid, v) in enumerate(cases):
            f.write("%s\t%s\t%s\n" % (tid, field(v), codes.get(i, "")))
    print("%d cases, %d invalid" % (len(cases), len(codes)))


if __name__ == "__main__":
    main()
