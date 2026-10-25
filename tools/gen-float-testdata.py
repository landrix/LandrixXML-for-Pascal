#!/usr/bin/env python3
"""Generate the xs:float test data in tests/data/double/float-cases.txt.

The oracle is independent of LandrixXmlDouble: values are exact fractions
(fractions.Fraction) rounded to the nearest binary32 value, ties to even,
in this script. The XPath string value follows Saxon HE 12: plain
notation from the float nearest to 1E-6 to below 1E6, else d.dddE[-]n;
the digits of Saxon's free-format algorithm at float precision (the gap
above and below always 2^e, the decimal exponent raised while the upper
boundary is reached inclusively, digits generated with exclusive
boundaries, a tie between two final digits to the lower); subnormal
floats with Java's Float.toString digits (the closest of the shortest that
read back, at least two).

With --saxon the format and parse cases are also evaluated by Saxon (the
KoSIT validator's, tools/XPathOracle.java) and the script stops on a
difference:

  javac -cp validator-1.6.3-standalone.jar -d OUT tools/XPathOracle.java
  python tools/gen-float-testdata.py --saxon --java PATH/java.exe --classes OUT --jar validator-1.6.3-standalone.jar

Saxon converts a string and an xs:decimal to xs:float through xs:double
(rounding twice): its parse results are compared with that model, while
parse and fromdecimal hold the single rounding of XPath 2.0 and XML
Schema (as Xerces).

Line format (TAB separated, as cases.txt): op, a, b, expected; values as
16 hex digits of the double bit pattern.
  roundtofloat  a bits; expected bits
  isfloat       a bits; expected true or false
  parse         a is a lexical form; expected bits or "error"
  fromdecimal   a is an xs:decimal lexical form; expected bits
  format        a bits (rounded to float first); expected XPath string
"""

import argparse
import os
import random
import re
import struct
import subprocess
import sys
import tempfile
from fractions import Fraction

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "double", "float-cases.txt")
NAN_BITS = 0x7FF8000000000000
INF_BITS = 0x7FF0000000000000
SIGN = 1 << 63
LEXICAL = re.compile(r"^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$")


def double_bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def bits_value(b):
    """A finite double bit pattern as (negative, Fraction)."""
    e = (b >> 52) & 2047
    m = b & ((1 << 52) - 1)
    if e == 0:
        v = Fraction(m) * Fraction(2) ** -1074
    else:
        v = Fraction(m | (1 << 52)) * Fraction(2) ** (e - 1075)
    return bool(b & SIGN), v


def floor_log2(a):
    e = a.numerator.bit_length() - a.denominator.bit_length()
    while Fraction(2) ** e > a:
        e -= 1
    while Fraction(2) ** (e + 1) <= a:
        e += 1
    return e


def nearest_float(negative, a):
    """Bits of the double equal to the binary32 value nearest to +-a."""
    sign = SIGN if negative else 0
    if a == 0:
        return sign
    e = max(floor_log2(a), -126)
    ulp = Fraction(2) ** (e - 23)
    n = round(a / ulp)  # Fraction rounds half to even
    v = n * ulp
    if v >= Fraction(2) ** 128:
        return sign | INF_BITS
    return sign | double_bits(float(v))


def round_to_float(b):
    if (b >> 52) & 2047 == 2047:
        return NAN_BITS if b & ((1 << 52) - 1) else b
    neg, v = bits_value(b)
    return nearest_float(neg, v)


def parse(text):
    t = text.strip(" \t\r\n")
    if t == "NaN":
        return NAN_BITS
    if t in ("INF", "+INF"):
        return INF_BITS
    if t == "-INF":
        return SIGN | INF_BITS
    if not LEXICAL.match(t):
        return None
    neg = t.startswith("-")
    t = t.lstrip("+-")
    mant, _, exp = t.lower().partition("e")
    ip, _, fp = mant.partition(".")
    n = int((ip + fp) or "0")
    e = (int(exp) if exp else 0) - len(fp)
    # beyond 10^50 or below 10^-50 only the side matters (floats lie
    # between 2^-150 and 2^128); this keeps huge exponents cheap
    size = e + len(str(n))
    if n and size > 50:
        v = Fraction(10) ** 50
    elif n == 0 or size < -50:
        v = Fraction(0)
    else:
        v = Fraction(n) * Fraction(10) ** e
    return nearest_float(neg, v)


def saxon_parse(text):
    """The double nearest to text (Python's float() rounds correctly)."""
    t = text.strip(" \t\r\n")
    if t in ("NaN", "INF", "-INF"):
        return parse(t)
    return double_bits(float(t))


def float_parts(b):
    """24-bit mantissa and exponent of a positive finite non-zero float value."""
    _, v = bits_value(b)
    e = max(floor_log2(v), -126) - 23
    return int(v / Fraction(2) ** e), e


def saxon_digits(m, e2):
    if e2 >= 0:
        r, s, mm = m << e2, 1, 1 << e2
    else:
        r, s, mm = m, 1 << -e2, 1
    k = 0
    while r * 10 < s:
        k -= 1
        r *= 10
        mm *= 10
    while 2 * r + mm >= 2 * s:
        s *= 10
        k += 1
    digits = ""
    while True:
        r *= 10
        mm *= 10
        d, r = divmod(r, s)
        low = 2 * r < mm
        high = 2 * r + mm > 2 * s
        if high and (not low or 2 * r > s):
            d += 1
        digits += str(d)
        if low or high:
            return digits, k


def java_digits(b):
    _, exact = bits_value(b)
    k = 0
    while exact >= Fraction(10) ** k:
        k += 1
    while exact < Fraction(10) ** (k - 1):
        k -= 1
    for p in range(2, 10):
        n = round(exact * Fraction(10) ** (p - k))
        ds, kk = str(n), k
        if len(ds) > p:
            ds, kk = ds[:-1], k + 1
        if parse("0.%se%d" % (ds, kk)) == b:
            return ds.rstrip("0") or "0", kk
    raise AssertionError(hex(b))


def format_float(b):
    b = round_to_float(b)
    if b == NAN_BITS:
        return "NaN"
    neg = "-" if b & SIGN else ""
    b &= ~SIGN
    if b == INF_BITS:
        return neg + "INF"
    if b == 0:
        return neg + "0"
    if b < 0x3810000000000000:
        digits, k = java_digits(b)
    else:
        digits, k = saxon_digits(*float_parts(b))
    if 0x3EB0C6F7A0000000 <= b < 0x412E848000000000:
        if k <= 0:
            t = "0." + "0" * -k + digits
        elif k >= len(digits):
            t = digits + "0" * (k - len(digits))
        else:
            t = digits[:k] + "." + digits[k:]
    else:
        t = digits[0] + "." + (digits[1:] or "0") + "E" + str(k - 1)
    return neg + t


def hex16(b):
    return "%016X" % b


def float_bits(rnd):
    """A random binary32 value as double bits."""
    f = rnd.getrandbits(32)
    if (f >> 23) & 255 == 255:
        f &= ~(1 << 30)
    return double_bits(struct.unpack("<f", struct.pack("<I", f))[0])


def exact_text(v):
    """A positive Fraction with a power-of-two denominator as decimal text."""
    d = v.denominator
    k = 0
    while d > 1:
        d //= 2
        k += 1
    n = v.numerator * 5 ** k
    s = str(n).rjust(k + 1, "0")
    return (s[:len(s) - k] + "." + s[len(s) - k:]).rstrip("0").rstrip(".") if k else s


def generate(rnd):
    cases = []
    specials = [0, SIGN, INF_BITS, SIGN | INF_BITS, NAN_BITS]
    # round to float: random doubles, floats, neighbours of float values and ties
    for _ in range(600):
        cases.append(("roundtofloat", rnd.getrandbits(64)))
    for _ in range(300):
        b = float_bits(rnd)
        delta = rnd.choice([1, 2, 1 << 28, (1 << 28) - 1, (1 << 28) + 1, 1 << 29])
        cases.append(("roundtofloat", b))
        if b & ((1 << 52) - 1) >= delta:
            cases.append(("roundtofloat", b - delta))
        cases.append(("roundtofloat", b + delta))
    for e in (-150, -149, -127, -126, 127, 128):
        p = double_bits(2.0 ** e)
        cases += [("roundtofloat", p), ("roundtofloat", p - 1), ("roundtofloat", p + 1)]
    cases += [("roundtofloat", double_bits(3.4028235677973366e38)),
              ("roundtofloat", double_bits(3.4028235677973362e38)),
              ("roundtofloat", double_bits(3.4028234663852886e38))]
    cases += [("roundtofloat", b) for b in specials]
    for _ in range(200):
        cases.append(("isfloat", float_bits(rnd)))
        cases.append(("isfloat", rnd.getrandbits(64)))
    cases += [("isfloat", b) for b in specials]
    # parse: float values written with few or many digits, ties, limits
    texts = ["0", "-0", "1", "0.1", "1e23", "3.4028235e38", "3.4028236e38", "1.4e-45", "7e-46", "7.1e-46",
             "1e-46", "1e39", "-1e39", "INF", "+INF", "-INF", "NaN", " 1.5 ", "1.", ".5", "1e", "", "+", "e1",
             "1.00000005960464477539062500000001", "1.000000059604644775390625",
             "16777217", "16777219", "33554435", "1e-6", "1e6", "999999.94", "1e400", "1e-400"]
    for _ in range(500):
        b = float_bits(rnd)
        if (b >> 52) & 2047 == 2047:
            continue
        neg, v = bits_value(b)
        sign = "-" if neg else ""
        texts.append(sign + "%.*e" % (rnd.randint(0, 11), float(v)))
    for _ in range(300):
        # halfway between two floats, and just beside it
        b = float_bits(rnd) & ~SIGN
        if b == 0 or (b >> 52) & 2047 == 2047:
            continue
        m, e2 = float_parts(b)
        mid = (Fraction(2 * m + 1) * Fraction(2) ** e2) / 2
        t = exact_text(mid)
        texts.append(t)
        texts.append(t + "000001")
        if t.endswith("5"):
            texts.append(t[:-1] + "49999")
    # long inputs: the parser keeps 800 significant digits and remembers
    # whether a dropped one was not zero
    m, e2 = float_parts(double_bits(1.0))
    tie = exact_text(Fraction(2 * m + 1) * Fraction(2) ** e2 / 2)  # 1 + 2^-24
    texts += ["1" + "0" * 1000 + "e-1001", "-0." + "0" * 49 + "1", tie + "0" * 900, tie + "0" * 900 + "1",
              tie[:-1] + "4" + "9" * 900, "0." + "0" * 40 + "1", "1" + "0" * 39, "3" + "0" * 38 + "e-1",
              "1e-999999999", "1e999999999", "-1e-999999999"]
    cases += [("parse", t) for t in texts]
    # from decimal: the same numbers as xs:decimal, without exponents
    for t in texts:
        t = t.strip()
        if re.match(r"^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$", t) and len(t) < 120:
            cases.append(("fromdecimal", t))
    # format: random floats, decades, limits, subnormals, plain notation limits
    for _ in range(1500):
        cases.append(("format", float_bits(rnd)))
    for _ in range(300):
        f = rnd.getrandbits(23) | (rnd.getrandbits(1) << 31)
        cases.append(("format", double_bits(struct.unpack("<f", struct.pack("<I", f))[0])))
    for p in range(-45, 39):
        cases.append(("format", parse("1e%d" % p)))
    for t in ["1e-6", "9.9999994e-7", "1.0000001e-6", "1e6", "999999.94", "1000000.06", "1e23", "8.589973e9",
              "3.4028235e38", "1.17549435e-38", "1.1754942e-38", "16777216", "0.3", "100"]:
        cases.append(("format", parse(t)))
    cases += [("format", b) for b in specials]
    cases += [("format", double_bits(0.1)), ("format", double_bits(1e300))]
    return cases


def expected(op, a):
    if op == "roundtofloat":
        return hex16(round_to_float(a))
    if op == "isfloat":
        return "true" if round_to_float(a) == (NAN_BITS if (a >> 52) & 2047 == 2047 and a & ((1 << 52) - 1) else a) \
            else "false"
    if op == "parse":
        b = parse(a)
        return "error" if b is None else hex16(b)
    if op == "fromdecimal":
        # xs:decimal has no negative zero; a negative value below the
        # smallest float still gives -0
        b = parse(a)
        if b == SIGN and not a.strip("+-0."):
            b = 0
        return hex16(b)
    if op == "format":
        return format_float(a)
    raise AssertionError(op)


def saxon_check(lines, args):
    """Saxon's string of xs:float for every format and parse case."""
    checks = []
    for op, a, _, exp in lines:
        if op == "format":
            checks.append(("string(xs:float(xs:double('%r')))" % struct.unpack("<d", struct.pack("<Q", int(a, 16)))[0]
                           if (int(a, 16) >> 52) & 2047 != 2047 else None, exp))
        elif op == "parse" and exp != "error" and "+INF" not in a:
            # Saxon parses a double and rounds it to float
            checks.append(("string(xs:float('%s'))" % a.strip(), format_float(round_to_float(saxon_parse(a)))))
    checks = [c for c in checks if c[0]]
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "d.xml"), "w") as f:
            f.write("<r/>")
        with open(os.path.join(tmp, "c.txt"), "w") as f:
            for expr, _ in checks:
                f.write("expr " + expr + "\n")
        out = subprocess.run([args.java, "-cp", os.pathsep.join([args.classes, args.jar]), "XPathOracle",
                              os.path.join(tmp, "d.xml"), os.path.join(tmp, "c.txt")], capture_output=True)
    if out.returncode != 0:
        sys.exit("oracle failed:\n" + out.stderr.decode("utf-8", "replace")[-2000:])
    got = [l.split(" ", 1)[1] for l in out.stdout.decode("utf-8").splitlines() if not l.startswith("# ")]
    if len(got) != len(checks):
        sys.exit("oracle returned %d results for %d cases" % (len(got), len(checks)))
    bad = [(e, w, g) for (e, w), g in zip(checks, got) if w != g]
    for e, w, g in bad[:20]:
        print("differs: %s model %s saxon %s" % (e, w, g))
    if bad:
        sys.exit("%d of %d differ from Saxon" % (len(bad), len(checks)))
    print("Saxon: %d cases equal" % len(checks))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--saxon", action="store_true")
    ap.add_argument("--java")
    ap.add_argument("--classes")
    ap.add_argument("--jar")
    args = ap.parse_args()
    rnd = random.Random(args.seed)
    lines = []
    for op, a in generate(rnd):
        text = a if isinstance(a, str) else hex16(a)
        lines.append((op, text, "-", expected(op, a if isinstance(a, str) else a)))
    if args.saxon:
        saxon_check(lines, args)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        for line in lines:
            f.write("\t".join(line) + "\n")
    print("%d cases" % len(lines))


if __name__ == "__main__":
    main()
