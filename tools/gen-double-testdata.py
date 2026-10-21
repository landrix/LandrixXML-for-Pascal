#!/usr/bin/env python3
"""Generate the xs:double test data in tests/data/double/cases.txt.

Python floats are IEEE 754 binary64 with round half to even, like Java, so
Python serves as the oracle for LandrixXmlDouble: float() parses with
correct rounding, + - * / follow IEEE, math.fmod is Java's %, and
Decimal(float) is the exact value (Saxon's cast xs:decimal(xs:double)).
The XPath string value is built from repr() (shortest round-trip digits)
with Saxon's layout: plain notation for 1E-6 <= |x| < 1E6, else d.dddE[-]n.

With --saxon every case is also evaluated by Saxon HE 12 (the engine of the
KoSIT validator) and the script stops on the first difference:

  python tools/gen-double-testdata.py --java PATH/java.exe --saxon PATH/saxon-he-12.9.jar

Two documented deviations are not compared with Saxon: the string value of
subnormal doubles and xs:integer() of doubles >= 2^53. Saxon uses Java's
Double.toString for both, which on Java 17 (bundled with the KoSIT
validator) is not always the shortest form; this library and this script
use the shortest digits there.

Line format (TAB separated): op, a, b, expected. Doubles are written as 16
hex digits of their bit pattern.
  parse                 a is a lexical form; expected bits or "error"
  format                a bits; expected XPath string
  todecimal tointeger   a bits; expected decimal / integer or "error"
  fromdecimal           a is an xs:decimal lexical form; expected bits
  add sub mul div mod   a, b bits; expected bits
  cmp                   a, b bits; expected -1, 0, 1 or 2 (unordered)
  round rhe             a bits, b precision; expected bits
  floor ceiling         a bits; expected bits

The file is committed; rerun this script only when the set changes.
"""

import argparse
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
from decimal import Decimal, localcontext, ROUND_FLOOR, ROUND_CEILING, ROUND_HALF_EVEN, \
    ROUND_HALF_UP, ROUND_HALF_DOWN

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "double")
NAN_BITS = 0x7FF8000000000000


def bits(x):
    if math.isnan(x):
        return NAN_BITS
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def from_bits(b):
    return struct.unpack("<d", struct.pack("<Q", b))[0]


def hexbits(x):
    return "%016X" % bits(x)


def shortest_digits(x):
    """Shortest round-trip digits of abs(x) as (digits, k), x = 0.digits * 10^k."""
    t = Decimal(repr(abs(x))).as_tuple()
    digits = "".join(map(str, t.digits))
    k = len(digits) + t.exponent
    stripped = digits.lstrip("0")
    k -= len(digits) - len(stripped)
    return stripped.rstrip("0"), k


def saxon_digits(x):
    """Saxon HE 12 FloatingPointConverter (Steele and White variant) for a
    normal double: equal gaps on both sides, inclusive boundary when the
    exponent is raised, exclusive boundaries and ties to the lower digit
    when generating digits."""
    b = bits(abs(x))
    f = (b & ((1 << 52) - 1)) | (1 << 52)
    e2 = ((b >> 52) & 0x7FF) - 1075
    if e2 >= 0:
        r, s, m = f << e2, 1, 1 << e2
    else:
        r, s, m = f, 1 << -e2, 1
    k = 0
    while 10 * r < s:
        k -= 1
        r *= 10
        m *= 10
    while 2 * r + m >= 2 * s:
        s *= 10
        k += 1
    digits = ""
    while True:
        r *= 10
        m *= 10
        d, r = divmod(r, s)
        low = 2 * r < m
        high = 2 * r + m > 2 * s
        if high and (not low or 2 * r > s):
            d += 1
        digits += str(d)
        if low or high:
            return digits, k


def xpath_string(x):
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "INF" if x > 0 else "-INF"
    if x == 0:
        return "-0" if math.copysign(1, x) < 0 else "0"
    sign = "-" if x < 0 else ""
    if abs(x) == 1.7976931348623157e308:
        return sign + "1.7976931348623157E308"
    if abs(x) == 5e-324:
        return sign + "4.9E-324"
    if abs(x) < 2.2250738585072014e-308:
        digits, k = shortest_digits(x)  # Saxon uses Java's Double.toString here
    else:
        digits, k = saxon_digits(x)
    if 1e-6 <= abs(x) < 1e6:
        if k <= 0:
            text = "0." + "0" * -k + digits
        elif k >= len(digits):
            text = digits + "0" * (k - len(digits))
        else:
            text = digits[:k] + "." + digits[k:]
    else:
        text = digits[0] + "." + (digits[1:] or "0") + "E" + str(k - 1)
    return sign + text


def plain_decimal(d):
    """XPath string of an exact Decimal."""
    if d == 0:
        return "0"
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def lexical_ok(text):
    s = text.strip(" \t\r\n")
    if s in ("NaN", "INF", "+INF", "-INF"):
        return True
    body = s[1:] if s[:1] in "+-" else s
    mant, e, exp = body.partition("e") if "e" in body else body.partition("E")
    if e:
        if exp[:1] in "+-":
            exp = exp[1:]
        if not exp or not exp.isdigit() or not exp.isascii():
            return False
    if mant.count(".") > 1 or not mant.replace(".", ""):
        return False
    return all(c in "0123456789." for c in mant)


def parse(text):
    s = text.strip(" \t\r\n")
    if not lexical_ok(text):
        return None
    if s in ("INF", "+INF"):
        return math.inf
    if s == "-INF":
        return -math.inf
    if s == "NaN":
        return math.nan
    return float(s)


def round_double(x, p, mode):
    if math.isnan(x) or math.isinf(x) or x == 0:
        return x
    with localcontext() as ctx:
        ctx.prec = 2000
        d = Decimal(x)
        q = Decimal(1).scaleb(-p)
        if mode == "halfceiling":
            r = d.quantize(q, rounding=ROUND_HALF_UP if d > 0 else ROUND_HALF_DOWN)
        else:
            r = d.quantize(q, rounding={"halfeven": ROUND_HALF_EVEN, "floor": ROUND_FLOOR,
                                        "ceiling": ROUND_CEILING}[mode])
        y = float(r)
    if y == 0:
        y = math.copysign(0.0, x)
    return y


def py_div(a, b):
    try:
        return a / b
    except ZeroDivisionError:
        if math.isnan(a) or a == 0:
            return math.nan
        return math.copysign(math.inf, a) * math.copysign(1, b)


def py_mod(a, b):
    if math.isnan(a) or math.isnan(b) or math.isinf(a) or b == 0:
        return math.nan
    if math.isinf(b):
        return a
    return math.fmod(a, b)


def to_integer(x):
    """The cast xs:integer(double): exact below 2^53, else the shortest
    digits padded with zeros (Saxon uses Java 17's Double.toString there,
    which sometimes has one digit more; see LandrixXmlDoubleToInteger)."""
    if abs(x) < 2.0 ** 53:
        return plain_decimal(Decimal(x).to_integral_value("ROUND_DOWN"))
    digits, k = shortest_digits(x)
    return ("-" if x < 0 else "") + digits + "0" * (k - len(digits))


def compare(a, b):
    if math.isnan(a) or math.isnan(b):
        return 2
    return (a > b) - (a < b)


def random_double(rng):
    kind = rng.random()
    if kind < 0.25:
        # money-like decimals
        digits = rng.randint(1, 9)
        frac = rng.choice([0, 1, 2, 2, 2, 3, 4])
        n = rng.randint(0, 10 ** digits)
        x = n / 10 ** frac
    elif kind < 0.45:
        x = float(rng.randint(-10 ** 6, 10 ** 6))
    elif kind < 0.75:
        # random bit pattern over all exponents
        b = rng.getrandbits(64)
        x = from_bits(b)
        if math.isnan(x):
            x = math.inf
    elif kind < 0.85:
        # subnormals and tiny values
        x = from_bits(rng.getrandbits(52)) * rng.choice([1, 1, 4096])
    elif kind < 0.92:
        x = rng.choice([0.1, 0.2, 0.3, 1e6, 999999.9999999999, 1e-6, 9.999999999999999e-7, 2.0 ** 53,
                        2.0 ** 52 + 0.5, 5e-324, 2.2250738585072014e-308, 2.225073858507201e-308,
                        1.7976931348623157e308, 0.5, 2.5, 1.5, 123456.7, 1e21, 1e22, 1e23, 9007199254740993,
                        4.35, 1.255, 2.675, 1.005, math.inf, -math.inf, math.nan, 0.0, -0.0])
    else:
        x = 2.0 ** rng.randint(-1074, 1023)
    x = float(x)
    if rng.random() < 0.3:
        x = -x
    return x


def random_lexical(rng):
    kind = rng.random()
    if kind < 0.3:
        x = random_double(rng)
        return xpath_string(x) if not math.isnan(x) else "NaN"
    if kind < 0.5:
        # halfway between two adjacent doubles, written exactly
        x = abs(random_double(rng))
        if math.isinf(x) or math.isnan(x):
            x = 1.0
        y = math.nextafter(x, math.inf)
        if math.isinf(y):
            return repr(x)
        with localcontext() as ctx:
            ctx.prec = 2000
            mid = (Decimal(x) + Decimal(y)) / 2
        s = format(mid, "f")
        if rng.random() < 0.3:
            s = s + "0001" if "." in s else s + ".0001"
        return s
    if kind < 0.7:
        mant = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 30)))
        if rng.random() < 0.5:
            p = rng.randint(0, len(mant))
            mant = mant[:p] + "." + mant[p:]
        return mant + rng.choice(["", "e", "E"]) + (str(rng.randint(-340, 320)) if rng.random() < 0.6 else "")
    if kind < 0.8:
        return rng.choice(["1e400", "-1e400", "1e-400", "-1e-400", "2.4703282292062327e-324",
                           "2.4703282292062328e-324", "4.9e-324", "1.7976931348623158e308",
                           "1.7976931348623159e308", " 12 ", "+1", "1.", ".5", "-.5e1", "+INF", "-INF",
                           "INF", "NaN", "-NaN", "inf", "1e", "e5", ".", "", "1.2.3", "0x10", "1E+5",
                           "1e-0", "-0", "-0.0e10", "00012.5000"])
    return repr(random_double(rng))


def build_cases(seed, count):
    rng = random.Random(seed)
    cases = []
    for _ in range(count):
        text = random_lexical(rng)
        if "\t" in text or "\n" in text:
            continue
        v = parse(text)
        cases.append(("parse", text, "-", "error" if v is None else hexbits(v)))
        a, b = random_double(rng), random_double(rng)
        if rng.random() < 0.3:
            b = rng.choice([a, -a, a * 2, 0.0, -0.0, 1.0, 3.0, 0.1])
        cases.append(("format", hexbits(a), "-", xpath_string(a)))
        if math.isnan(a) or math.isinf(a):
            cases.append(("todecimal", hexbits(a), "-", "error"))
            cases.append(("tointeger", hexbits(a), "-", "error"))
        else:
            cases.append(("todecimal", hexbits(a), "-", plain_decimal(Decimal(a))))
            cases.append(("tointeger", hexbits(a), "-", to_integer(a)))
        dec = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 25)))
        p = rng.randint(0, len(dec))
        dec = rng.choice(["", "-"]) + (dec[:p] or "0") + ("." + dec[p:] if dec[p:] else "")
        # xs:decimal has no negative zero
        cases.append(("fromdecimal", dec, "-", hexbits(float(Decimal(dec)) + 0.0)))
        cases.append(("add", hexbits(a), hexbits(b), hexbits(a + b) if not (math.isinf(a) and math.isinf(b) and a != b) else hexbits(math.nan)))
        cases.append(("sub", hexbits(a), hexbits(b), hexbits(a - b) if not (math.isinf(a) and math.isinf(b) and a == b) else hexbits(math.nan)))
        try:
            prod = a * b
        except OverflowError:
            prod = math.copysign(math.inf, a) * math.copysign(1, b)
        cases.append(("mul", hexbits(a), hexbits(b), hexbits(prod)))
        cases.append(("div", hexbits(a), hexbits(b), hexbits(py_div(a, b))))
        cases.append(("mod", hexbits(a), hexbits(b), hexbits(py_mod(a, b))))
        cases.append(("cmp", hexbits(a), hexbits(b), str(compare(a, b))))
        prec = rng.choice([0, 0, 0, 1, 2, 2, 3, -1, -2])
        cases.append(("round", hexbits(a), str(prec), hexbits(round_double(a, prec, "halfceiling"))))
        cases.append(("rhe", hexbits(a), str(prec), hexbits(round_double(a, prec, "halfeven"))))
        cases.append(("floor", hexbits(a), "-", hexbits(round_double(a, 0, "floor"))))
        cases.append(("ceiling", hexbits(a), "-", hexbits(round_double(a, 0, "ceiling"))))
    return cases


def xq_string(s):
    return '"' + s.replace("&", "&amp;").replace('"', '""') + '"'


def xq_double(h):
    x = from_bits(int(h, 16))
    if math.isnan(x):
        return "xs:double('NaN')"
    if math.isinf(x):
        return "xs:double('%s')" % ("INF" if x > 0 else "-INF")
    if x == 0:
        return "xs:double('%s')" % ("-0" if math.copysign(1, x) < 0 else "0")
    return "xs:double('%s')" % repr(x)


def is_subnormal_hex(h):
    b = int(h, 16) & 0x7FFFFFFFFFFFFFFF
    return 0 < b < (1 << 52)


def compared_with_saxon(case):
    """False for the two documented deviations from Saxon on Java 17."""
    op, a, b, expected = case
    if op == "tointeger" and expected != "error" and abs(from_bits(int(a, 16))) >= 2.0 ** 53:
        return False  # Java 17 Double.toString digits, see LandrixXmlDoubleToInteger
    if op == "format" and is_subnormal_hex(a):
        return False  # Java 17 Double.toString digits for subnormals
    if op in ("parse", "fromdecimal", "add", "sub", "mul", "div", "mod", "round", "rhe", "floor",
              "ceiling") and expected != "error" and is_subnormal_hex(expected):
        return False  # the result is compared as a string, same reason
    return True


def saxon_case(op, a, b, expected):
    """XQuery expression and the string Saxon must produce."""
    def s(h):
        return xpath_string(from_bits(int(h, 16)))
    if op == "parse":
        q = xq_string(a)
        return ("if (%s castable as xs:double) then string(xs:double(%s)) else 'error'" % (q, q),
                expected if expected == "error" else s(expected))
    if op == "format":
        return "string(%s)" % xq_double(a), expected
    if op in ("todecimal", "tointeger"):
        t = "xs:decimal" if op == "todecimal" else "xs:integer"
        return "try { string(%s(%s)) } catch * { 'error' }" % (t, xq_double(a)), expected
    if op == "fromdecimal":
        return "string(xs:double(xs:decimal(%s)))" % xq_string(a), s(expected)
    if op in ("add", "sub", "mul", "div", "mod"):
        sym = {"add": "+", "sub": "-", "mul": "*", "div": "div", "mod": "mod"}[op]
        return "string(%s %s %s)" % (xq_double(a), sym, xq_double(b)), s(expected)
    if op == "cmp":
        x, y = xq_double(a), xq_double(b)
        return ("string(if (%s lt %s) then -1 else if (%s gt %s) then 1 else if (%s eq %s) then 0 else 2)"
                % (x, y, x, y, x, y)), expected
    if op == "round":
        return "string(round(%s, %s))" % (xq_double(a), b), s(expected)
    if op == "rhe":
        return "string(round-half-to-even(%s, %s))" % (xq_double(a), b), s(expected)
    if op in ("floor", "ceiling"):
        return "string(%s(%s))" % (op, xq_double(a)), s(expected)
    raise ValueError(op)


def check_with_saxon(cases, java, saxon):
    exprs = [saxon_case(*c) for c in cases]
    lines = ["declare option saxon:output 'method=text';", "string-join(("]
    lines.append(",\n".join(e for e, _ in exprs))
    lines.append("), '&#10;')")
    with tempfile.NamedTemporaryFile("w", suffix=".xq", delete=False, encoding="utf-8") as f:
        f.write("\n".join(lines))
        query = f.name
    try:
        out = subprocess.run([java, "-cp", saxon, "net.sf.saxon.Query", "-q:" + query],
                             capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(query)
    if out.returncode != 0:
        sys.exit("Saxon failed:\n" + out.stderr[-3000:])
    got = out.stdout.split("\n")
    if got and got[-1] == "":
        got.pop()
    if len(got) != len(cases):
        sys.exit("Saxon returned %d lines for %d cases" % (len(got), len(cases)))
    bad = 0
    skipped = 0
    for case, (_, want), actual in zip(cases, exprs, got):
        if not compared_with_saxon(case):
            skipped += 1
            continue
        if want != actual:
            bad += 1
            if bad <= 30:
                print("MISMATCH %s %r %r: python %r, saxon %r" % (case[0], case[1], case[2], want, actual))
    if bad:
        sys.exit("%d mismatches" % bad)
    print("Saxon agrees on all %d cases (%d not compared: subnormal output, xs:integer of doubles >= 2^53)"
          % (len(cases) - skipped, skipped))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java")
    ap.add_argument("--saxon")
    ap.add_argument("--count", type=int, default=600)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    cases = build_cases(args.seed, args.count)
    if args.java and args.saxon:
        check_with_saxon(cases, args.java, args.saxon)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "cases.txt"), "w", encoding="ascii", newline="\n") as f:
        for op, a, b, expected in cases:
            f.write("%s\t%s\t%s\t%s\n" % (op, a, b, expected))
    print("%d cases written" % len(cases))


if __name__ == "__main__":
    main()
