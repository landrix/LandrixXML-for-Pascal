#!/usr/bin/env python3
"""Generate the encoding test files in tests/data/encoding/.

Every input file NAME.xml gets a companion NAME.utf8 with the expected
normalized result: UTF-8, byte order mark removed, otherwise unchanged (the
XML declaration still names the original encoding; line ends are not
touched, that is the tokenizer's job).

Python's codecs serve as an independent oracle for the conversion tables.
For Windows-1252 the five bytes Python leaves undefined (0x81, 0x8D, 0x8F,
0x90, 0x9D) map to U+0081 etc., as decided (WHATWG / Windows best fit).

The files are committed; rerun this script only when the set changes.
Usage: python tools/gen-encoding-testdata.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "encoding")

# Characters: a-umlaut, o-umlaut, u-umlaut, sharp s, euro sign, emoji.
LATIN = "äöüß"
EURO = "€"
EMOJI = "\U0001F600"
HIGH = bytes(range(0x80, 0x100))


def decl(encoding):
    if encoding is None:
        return '<?xml version="1.0"?>'
    return '<?xml version="1.0" encoding="%s"?>' % encoding


def doc(encoding, text):
    return decl(encoding) + "\r\n<r a=\"%s\">%s</r>\n" % (text, text)


def cp1252(data):
    out = []
    for b in data:
        try:
            out.append(bytes([b]).decode("cp1252"))
        except UnicodeDecodeError:
            out.append(chr(b))
    return "".join(out)


def text_case(name, encoding, text, codec, bom=b""):
    """A document whose text is encoded with a Python codec."""
    content = doc(encoding, text)
    return name, bom + content.encode(codec), content


def bytes_case(name, encoding, raw, decoder):
    """A document with raw high bytes; expected text via decoder(raw)."""
    head = (decl(encoding) + "\n<r>").encode("ascii")
    tail = "</r>\n".encode("ascii")
    expected = decl(encoding) + "\n<r>" + decoder(raw) + "</r>\n"
    return name, head + raw + tail, expected


CASES = [
    text_case("utf8", "UTF-8", LATIN + EURO + EMOJI, "utf-8"),
    text_case("utf8-bom", "UTF-8", LATIN + EURO + EMOJI, "utf-8", b"\xef\xbb\xbf"),
    text_case("utf8-nodecl", None, LATIN + EURO + EMOJI, "utf-8"),
    text_case("utf8-bom-nodecl", None, LATIN + EURO + EMOJI, "utf-8", b"\xef\xbb\xbf"),
    text_case("utf8-lowercase", "utf-8", LATIN + EURO + EMOJI, "utf-8"),
    text_case("utf16le-bom", "UTF-16", LATIN + EURO + EMOJI, "utf-16-le", b"\xff\xfe"),
    text_case("utf16be-bom", "UTF-16", LATIN + EURO + EMOJI, "utf-16-be", b"\xfe\xff"),
    text_case("utf16le-bom-nodecl", None, LATIN + EURO + EMOJI, "utf-16-le", b"\xff\xfe"),
    text_case("utf16le-bom-le-decl", "UTF-16LE", LATIN + EMOJI, "utf-16-le", b"\xff\xfe"),
    text_case("utf16le-nobom", "UTF-16LE", LATIN + EURO + EMOJI, "utf-16-le"),
    text_case("utf16be-nobom", "UTF-16BE", LATIN + EURO + EMOJI, "utf-16-be"),
    text_case("iso-8859-1", "ISO-8859-1", LATIN + " ÿ", "latin-1"),
    text_case("latin1-alias", "latin1", LATIN, "latin-1"),
    text_case("windows-1252", "windows-1252", LATIN + EURO + "„“", "cp1252"),
    text_case("cp1252-alias", "CP1252", LATIN + EURO, "cp1252"),
    text_case("iso-8859-15", "ISO-8859-15", LATIN + EURO, "iso8859_15"),
    text_case("latin9-alias", "Latin-9", LATIN + EURO, "iso8859_15"),
    text_case("ascii", "US-ASCII", "abc", "ascii"),
    bytes_case("iso-8859-1-all", "ISO-8859-1", HIGH, lambda r: r.decode("latin-1")),
    bytes_case("windows-1252-all", "windows-1252", HIGH, cp1252),
    bytes_case("iso-8859-15-all", "ISO-8859-15", HIGH, lambda r: r.decode("iso8859_15")),
    # Strict reading: 0x80 in ISO-8859-1 is U+0080 (Latin1AsWindows1252 off).
    bytes_case("latin1-with-0x80", "ISO-8859-1", b"\x80\xe4", lambda r: r.decode("latin-1")),
    # Faulty: declared UTF-8, written as Windows-1252. The expected file is
    # the result with FallbackEncoding = Windows-1252.
    bytes_case("utf8-declared-cp1252", "UTF-8", LATIN.encode("cp1252") + b"\x80", cp1252),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, raw, expected in CASES:
        with open(os.path.join(OUT, name + ".xml"), "wb") as f:
            f.write(raw)
        with open(os.path.join(OUT, name + ".utf8"), "wb") as f:
            f.write(expected.encode("utf-8"))
    print("%d cases written to %s" % (len(CASES), OUT))


if __name__ == "__main__":
    main()
