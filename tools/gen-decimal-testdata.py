#!/usr/bin/env python3
"""Generate the decimal arithmetic test data in tests/data/decimal/ops.txt.

Python's fractions module serves as an exact oracle for LandrixXmlDecimal.
The division rules follow Saxon HE 12 (the XSLT engine of the KoSIT
validator):

  decimal div decimal   rounded half down (ties towards zero) to
                        max(18, scale(a) - scale(b) + 18) fraction digits;
                        the scale of an xs:decimal is taken after removing
                        trailing zeros, so 2000 has scale -3
  integer div integer   if both are in 0..2^31-1: exact quotient as
                        xs:integer if the division is exact, else a decimal
                        division with both scales 0; otherwise a decimal
                        division on the normalized values

With --saxon the script also evaluates every case with Saxon and stops on
the first difference, so the committed file is checked against the real
engine:

  python tools/gen-decimal-testdata.py --java PATH/java.exe --saxon PATH/saxon-he-12.9.jar

Line format (TAB separated): op, a, b, expected
  add sub mul div cmp idiv mod   a and b are xs:decimal values
  decintdiv intdecdiv            xs:decimal div xs:integer and xs:integer div
                                 xs:decimal (an xs:integer operand has scale 0)
  intdiv                         a and b are xs:integer values; expected is
                                 "value i" (xs:integer) or "value d" (xs:decimal)
  round rhe                      b is the precision (fn:round / fn:round-half-to-even)
  floor ceiling trunc            b is "-"; trunc = cast to xs:integer
  parse                          a is a lexical form; expected is the XPath
                                 string or "error"
Errors (division by zero) are written as "error".

The file is committed; rerun this script only when the set changes.
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile
from fractions import Fraction

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "decimal")


def parse(text):
    """xs:decimal lexical form -> Fraction, or None."""
    s = text.strip(" \t\r\n")
    sign = 1
    if s[:1] in ("+", "-"):
        sign = -1 if s[0] == "-" else 1
        s = s[1:]
    if s.count(".") > 1 or not s or s == ".":
        return None
    if any(c not in "0123456789." for c in s):
        return None
    ip, _, fp = s.partition(".")
    value = Fraction(int(ip or "0")) + (Fraction(int(fp), 10 ** len(fp)) if fp else 0)
    return sign * value


def scale(value):
    """Scale of the value with trailing zeros removed (Java stripTrailingZeros)."""
    if value == 0:
        return 0
    k = 0
    while (value * 10 ** k).denominator != 1:
        k += 1
    if k > 0:
        return k
    n = abs(value.numerator)
    while n % 10 == 0:
        n //= 10
        k -= 1
    return k


def fmt(value):
    """XPath string of a terminating decimal."""
    if value.denominator == 1:
        return str(value.numerator)
    k = scale(value)
    n = abs(value * 10 ** k)
    assert n.denominator == 1
    digits = str(n.numerator).rjust(k + 1, "0")
    text = digits[:-k] + "." + digits[-k:]
    return ("-" if value < 0 else "") + text


def round_frac(value, precision, mode):
    unit = Fraction(1, 10 ** precision) if precision >= 0 else Fraction(10 ** -precision)
    x = value / unit
    lo = x.numerator // x.denominator  # floor
    rest = x - lo
    if rest == 0:
        q = lo
    elif mode == "floor":
        q = lo
    elif mode == "ceiling":
        q = lo + 1
    elif mode == "down":
        q = lo if x >= 0 else lo + 1
    else:
        half = Fraction(1, 2)
        if rest > half:
            q = lo + 1
        elif rest < half:
            q = lo
        elif mode == "halfceiling":
            q = lo + 1
        elif mode == "halfeven":
            q = lo if lo % 2 == 0 else lo + 1
        elif mode == "halfdown":  # ties towards zero
            q = lo if x >= 0 else lo + 1
        else:
            raise ValueError(mode)
    return q * unit


def decimal_divide(a, b, sa, sb):
    s = max(18, sa - sb + 18)
    return round_frac(a / b, s, "halfdown")


def integer_divide(a, b):
    small = 0 <= a < 2 ** 31 and 0 <= b < 2 ** 31
    if small:
        if a % b == 0:
            return a // b, "i"
        return decimal_divide(a, b, 0, 0), "d"
    return decimal_divide(a, b, scale(a), scale(b)), "d"


def random_decimal(rng):
    kind = rng.random()
    if kind < 0.08:
        return rng.choice(["0", "1", "-1", "2000", "0.5", "-0.5", "1.50", "100", "0.001"])
    int_digits = rng.choice([0, 1, 1, 2, 3, 5, 8, 12, 20, 25])
    frac_digits = rng.choice([0, 0, 1, 2, 2, 3, 4, 6, 10, 18, 22])
    if int_digits == 0 and frac_digits == 0:
        int_digits = 1
    ip = "".join(rng.choice("0123456789") for _ in range(int_digits))
    fp = "".join(rng.choice("0123456789") for _ in range(frac_digits))
    if fp and rng.random() < 0.3:
        fp = fp[:-1] + "5"
    if rng.random() < 0.15:
        ip = ip + "000"
    if fp and rng.random() < 0.15:
        fp = fp + "00"
    s = ip if ip else "0"
    if fp:
        s += "." + fp
    if rng.random() < 0.35:
        s = "-" + s
    return s


def random_integer(rng):
    kind = rng.random()
    if kind < 0.15:
        return rng.choice(["0", "1", "2", "3", "7", "-1", "-7", "2147483647", "2147483648",
                           "-2147483648", "2000000000000000000", "4294967296", "1000"])
    digits = rng.choice([1, 1, 2, 3, 4, 6, 9, 10, 12, 19, 25])
    s = str(rng.randint(10 ** (digits - 1) if digits > 1 else 0, 10 ** digits - 1))
    if rng.random() < 0.2:
        s += "000"
    if rng.random() < 0.3:
        s = "-" + s
    return s


LEXICAL = ["1", "-1", "+1", "1.", ".5", "-.5", "+.5", "0.0", "-0", "-0.00", "007.500",
           " 12 ", "  -3.25  ", "1e5", "1.2.3", "", " ", ".", "-", "+", "-.", "1 2",
           "0x10", "12a", "00000000000000000000000000001", "123456789012345678901234567890.123456789"]


INTDIV_FIXED = [
    ("2147483647", "2147483647"), ("2147483648", "2147483648"), ("2147483647", "1"),
    ("2147483648", "1"), ("-6", "2"), ("6", "-2"), ("0", "2147483647"), ("0", "2147483648"),
    ("-2147483648", "1"), ("7", "3000"), ("-7", "3000"), ("7", "3000000000000000000"),
    ("2147483646", "2"), ("2147483647", "7"), ("4294967294", "2"),
]


def build_cases(seed, count):
    rng = random.Random(seed)
    cases = []
    for text in LEXICAL:
        v = parse(text)
        cases.append(("parse", text, "-", "error" if v is None else fmt(v)))
    # the 0..2^31-1 boundary of Saxon's integer division fast path
    for ia, ib in INTDIV_FIXED:
        v, kind = integer_divide(Fraction(int(ia)), Fraction(int(ib)))
        cases.append(("intdiv", ia, ib, fmt(v) + " " + kind))
    for _ in range(count):
        a, b = random_decimal(rng), random_decimal(rng)
        fa, fb = parse(a), parse(b)
        cases.append(("add", a, b, fmt(fa + fb)))
        cases.append(("sub", a, b, fmt(fa - fb)))
        cases.append(("mul", a, b, fmt(fa * fb)))
        cases.append(("cmp", a, b, str((fa > fb) - (fa < fb))))
        if fb == 0:
            cases.append(("div", a, b, "error"))
            cases.append(("idiv", a, b, "error"))
            cases.append(("mod", a, b, "error"))
        else:
            cases.append(("div", a, b, fmt(decimal_divide(fa, fb, scale(fa), scale(fb)))))
            q = round_frac(fa / fb, 0, "down")
            cases.append(("idiv", a, b, fmt(q)))
            cases.append(("mod", a, b, fmt(fa - fb * q)))
        p = rng.choice([0, 0, 0, 1, 2, 2, 3, -1, -2, 5])
        cases.append(("round", a, str(p), fmt(round_frac(fa, p, "halfceiling"))))
        cases.append(("rhe", a, str(p), fmt(round_frac(fa, p, "halfeven"))))
        cases.append(("floor", a, "-", fmt(round_frac(fa, 0, "floor"))))
        cases.append(("ceiling", a, "-", fmt(round_frac(fa, 0, "ceiling"))))
        cases.append(("trunc", a, "-", fmt(round_frac(fa, 0, "down"))))
        ia, ib = random_integer(rng), random_integer(rng)
        fia, fib = Fraction(int(ia)), Fraction(int(ib))
        if fib == 0:
            cases.append(("decintdiv", a, ib, "error"))
        else:
            cases.append(("decintdiv", a, ib, fmt(decimal_divide(fa, fib, scale(fa), 0))))
        if fb == 0:
            cases.append(("intdecdiv", ia, b, "error"))
        else:
            cases.append(("intdecdiv", ia, b, fmt(decimal_divide(fia, fb, 0, scale(fb)))))
        if int(ib) == 0:
            cases.append(("intdiv", ia, ib, "error"))
        else:
            v, kind = integer_divide(Fraction(int(ia)), Fraction(int(ib)))
            cases.append(("intdiv", ia, ib, fmt(v) + " " + kind))
    return cases


def xq_string(s):
    return '"' + s.replace("&", "&amp;").replace('"', '""') + '"'


def saxon_expr(op, a, b):
    da = "xs:decimal(%s)" % xq_string(a)
    db = "xs:decimal(%s)" % xq_string(b)
    if op == "parse":
        s = xq_string(a)
        return "if (%s castable as xs:decimal) then string(xs:decimal(%s)) else 'error'" % (s, s)
    if op in ("add", "sub", "mul", "div", "idiv", "mod"):
        sym = {"add": "+", "sub": "-", "mul": "*", "div": "div", "idiv": "idiv", "mod": "mod"}[op]
        return "try { string(%s %s %s) } catch * { 'error' }" % (da, sym, db)
    if op == "cmp":
        return "string(if (%s lt %s) then -1 else if (%s gt %s) then 1 else 0)" % (da, db, da, db)
    if op == "round":
        return "string(round(%s, %s))" % (da, b)
    if op == "rhe":
        return "string(round-half-to-even(%s, %s))" % (da, b)
    if op in ("floor", "ceiling"):
        return "string(%s(%s))" % (op, da)
    if op == "trunc":
        return "string(xs:integer(%s))" % da
    if op == "decintdiv":
        return "try { string(%s div xs:integer(%s)) } catch * { 'error' }" % (da, xq_string(b))
    if op == "intdecdiv":
        return "try { string(xs:integer(%s) div %s) } catch * { 'error' }" % (xq_string(a), db)
    if op == "intdiv":
        ia = "xs:integer(%s)" % xq_string(a)
        ib = "xs:integer(%s)" % xq_string(b)
        return ("try { let $r := %s div %s return string($r) || ' ' || "
                "(if ($r instance of xs:integer) then 'i' else 'd') } catch * { 'error' }") % (ia, ib)
    raise ValueError(op)


def check_with_saxon(cases, java, saxon):
    lines = ["declare option saxon:output 'method=text';", "string-join(("]
    lines.append(",\n".join(saxon_expr(op, a, b) for op, a, b, _ in cases))
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
    for (op, a, b, expected), actual in zip(cases, got):
        if expected != actual:
            bad += 1
            if bad <= 20:
                print("MISMATCH %s %r %r: python %r, saxon %r" % (op, a, b, expected, actual))
    if bad:
        sys.exit("%d mismatches" % bad)
    print("Saxon agrees on all %d cases" % len(cases))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java")
    ap.add_argument("--saxon")
    ap.add_argument("--count", type=int, default=400)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    cases = build_cases(args.seed, args.count)
    if args.java and args.saxon:
        check_with_saxon(cases, args.java, args.saxon)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "ops.txt"), "w", encoding="ascii", newline="\n") as f:
        for op, a, b, expected in cases:
            assert "\t" not in a + b + expected and "\n" not in a + b + expected
            f.write("%s\t%s\t%s\t%s\n" % (op, a, b, expected))
    print("%d cases written" % len(cases))


if __name__ == "__main__":
    main()
