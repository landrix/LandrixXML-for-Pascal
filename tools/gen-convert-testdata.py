#!/usr/bin/env python3
"""Generate the conversion test data in tests/data/convert/.

Python's decimal module (ROUND_HALF_UP = half away from zero) and struct
(IEEE 754 bit patterns) serve as independent oracles for
LandrixXmlConvert:

  currency.txt       input TAB decimals TAB expected   (parse + format)
  double-format.txt  input TAB decimals TAB expected   (parse + format,
                     inputs with at most 15 significant digits)
  double-bits.txt    input TAB 16 hex digits of the IEEE 754 double

The files are committed; rerun this script only when the set changes.
Usage: python tools/gen-convert-testdata.py
"""

import os
import random
import struct
from decimal import Decimal, ROUND_HALF_UP

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "convert")


def rounded(text, decimals):
    q = Decimal(text).quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP)
    s = format(q, "f")
    if s.startswith("-") and Decimal(s) == 0:
        s = s[1:]
    return s


def random_decimal(rng, max_int_digits, max_frac_digits):
    int_digits = rng.randint(0, max_int_digits)
    frac_digits = rng.randint(0, max_frac_digits)
    if int_digits == 0 and frac_digits == 0:
        int_digits = 1
    ip = "".join(rng.choice("0123456789") for _ in range(int_digits))
    fp = "".join(rng.choice("0123456789") for _ in range(frac_digits))
    # half of the cases end in 5 at a rounding position
    if fp and rng.random() < 0.5:
        fp = fp[:-1] + "5"
    s = ip if ip else "0"
    if fp:
        s += "." + fp
    if rng.random() < 0.3:
        s = "-" + s
    return s


def significant_digits(text):
    digits = text.lstrip("-").replace(".", "").lstrip("0")
    return len(digits.rstrip("0")) if digits else 0


def write(name, lines):
    with open(os.path.join(OUT, name), "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20261015)

    cur = []
    edges = ["0", "-0", "0.00005", "-0.00005", "2.675", "1.005", "0.125", "-2.5",
             "922337203685477.5807", "-922337203685477.5808", "999.9999", "-999.9999",
             "0.0001", "-0.0001", "123456789012345.6789"]
    for s in edges:
        for d in range(0, 7):
            if len(s.split(".")[-1]) > 4 and "." in s:
                continue
            cur.append("%s\t%d\t%s" % (s, d, rounded(s, d)))
    for _ in range(1500):
        s = random_decimal(rng, 14, 4)
        d = rng.randint(0, 6)
        cur.append("%s\t%d\t%s" % (s, d, rounded(s, d)))
    write("currency.txt", cur)

    dbl = []
    for s in ["2.675", "1.005", "0.125", "-2.675", "0.5", "1.5", "2.5", "-0.5",
              "0.045", "1.0005", "123456789012.345", "0.000123456789012345",
              "99999999999999.9", "0.1", "0.3"]:
        for d in range(0, 6):
            dbl.append("%s\t%d\t%s" % (s, d, rounded(s, d)))
    while len(dbl) < 2000:
        s = random_decimal(rng, 9, 8)
        if significant_digits(s) > 15:
            continue
        d = rng.randint(0, 6)
        dbl.append("%s\t%d\t%s" % (s, d, rounded(s, d)))
    write("double-format.txt", dbl)

    bits = []
    for s in ["0", "1", "0.1", "0.2", "0.3", "2.675", "123456789012345",
              "9007199254740992", "0.000000000000000000001", "1000000000000000000000",
              "4.35", "-17.0625", "3.141592653589793",
              # double rounding traps on x87 (80-bit intermediate)
              "64.6843154590428", "7802.86703335016", "0.00000945605510789287",
              "11029295.879923"]:
        bits.append("%s\t%016X" % (s, struct.unpack("<Q", struct.pack("<d", float(s)))[0]))
    while len(bits) < 2000:
        mantissa = rng.randint(1, 2 ** 53)
        exp = rng.randint(-22, 22)
        digits = str(mantissa)
        if exp >= 0:
            s = digits + "0" * exp
        else:
            if len(digits) <= -exp:
                digits = "0" * (-exp - len(digits) + 1) + digits
            s = digits[:exp] + "." + digits[exp:]
        if rng.random() < 0.3:
            s = "-" + s
        bits.append("%s\t%016X" % (s, struct.unpack("<Q", struct.pack("<d", float(s)))[0]))
    write("double-bits.txt", bits)
    print("wrote %d + %d + %d cases to %s" % (len(cur), len(dbl), len(bits), OUT))


if __name__ == "__main__":
    main()
