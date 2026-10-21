# LandrixXML for Pascal

A small, fast and dependency-free XML library for **Delphi 6 through
Delphi 13** and **Free Pascal 3.2+**: a pull reader, a streaming writer, a
DOM and locale-independent conversion helpers for XML Schema values.

> **Status:** version 0.2.0. The API may still change in details before
> 1.0; see the [CHANGELOG](CHANGELOG.md).

## Features

- **No dependencies:** only `SysUtils`, `Classes` and `Contnrs`. One code
  base for Ansi Delphi (6 to 2007), Unicode Delphi (2009 to 13, Win32 and
  Win64) and Free Pascal (Windows, Linux, macOS).
- **XML 1.0 with namespaces:** well-formedness is checked strictly, errors
  carry an error code, line, column and byte offset.
- **Input encodings:** UTF-8, UTF-16 LE/BE, ISO-8859-1, ISO-8859-15,
  Windows-1252 and US-ASCII; everything is converted to UTF-8 internally.
- **Pull reader** (`TLandrixXmlReader`) for large files, with zero-copy
  access to names and values.
- **Streaming writer** (`TLandrixXmlWriter`) with correct escaping, namespace
  checks, optional indentation that never alters mixed content, and base64
  output for attachments.
- **DOM** (`TLandrixXmlDocument`) with search by namespace and local name,
  mixed content (GAEB long texts), line and column per node, and saving
  through the writer.
- **Conversion helpers** for `xs:decimal` (`Currency`, `Double`), integers,
  `xs:boolean`, `xs:date`, `xs:dateTime`, `xs:time`, the CII date formats
  102 and 610, and base64 – all independent of locale settings.
- **Safe by default:** no DTD processing, no expansion of entities declared
  in a DTD (the five predefined entities and character references are
  supported), no external resources, no network access, nesting depth
  limit (256 by default).

## Units

| Unit | Contents |
|---|---|
| `LandrixXmlBase` | string types, UTF-8/UTF-16 conversion, `ELandrixXmlError`, byte buffer, base64 |
| `LandrixXmlEncoding` | input encoding detection and conversion (used by the reader) |
| `LandrixXmlReader` | pull reader `TLandrixXmlReader`, push adapter `TLandrixXmlHandler` |
| `LandrixXmlWriter` | streaming writer `TLandrixXmlWriter` |
| `LandrixXmlDom` | `TLandrixXmlDocument`, `TLandrixXmlNode` |
| `LandrixXmlConvert` | `xs:*` value conversion |
| `LandrixXmlDecimal` | exact `xs:decimal`/`xs:integer` arithmetic with Saxon-compatible division (first of the optional validation units; the units above do not use it) |
| `LandrixXmlDouble` | `xs:double` in software (IEEE 754 bit pattern, Saxon-compatible string value), optional validation unit |
| `LandrixXmlRegex` | XSD and XPath regular expressions, linear-time matching, optional validation unit |
| `LandrixXmlUnicode` | Unicode 6.2.0 general categories, code point strings, optional validation unit |
| `LandrixXmlXsdTypes` | XML Schema simple types and facets, optional validation unit |
| `LandrixXmlXsdContent` | XML Schema content models (sequence, choice, occurrence bounds, wildcards), optional validation unit |

Add the `source` folder to the search path (Delphi: unit and include path;
Free Pascal: `-Fusource -Fisource`).

## Examples

The examples below are taken from
[examples/LandrixXmlExamples.dpr](examples/LandrixXmlExamples.dpr), which is
compiled and run with every supported compiler.

### Writing an invoice with the streaming writer

```pascal
Writer := TLandrixXmlWriter.Create;   { or CreateFile('invoice.xml') }
try
  Writer.Indent := True;
  Writer.StartElementNs(NsInvoice, '', 'Invoice');
  Writer.DeclareNamespace('cac', NsCac);
  Writer.DeclareNamespace('cbc', NsCbc);
  Writer.ElementUtf8('cbc:ID', 'R-2026-0042');
  Writer.ElementUtf8('cbc:IssueDate', LandrixXmlFormatDate(EncodeDate(2026, 10, 15)));
  Writer.StartElement('cac:LegalMonetaryTotal');
  Writer.StartElement('cbc:PayableAmount');
  Writer.AttributeUtf8('currencyID', 'EUR');
  Writer.TextUtf8(LandrixXmlFormatCurrency(119, 2));
  Writer.EndElement;
  Writer.EndElement;
  Writer.EndElement;
  Writer.EndDocument;
  Result := Writer.AsUtf8;
finally
  Writer.Free;
end;
```

The XML declaration `<?xml version="1.0" encoding="UTF-8"?>` is written
automatically. A call that would produce invalid XML (an undeclared
prefix, a control character, `--` in a comment, ...) raises
`ELandrixXmlError` and leaves the output unchanged.

### Reading it back with the pull reader

```pascal
Reader := TLandrixXmlReader.Create;
try
  Reader.LoadFromFile('invoice.xml');
  while Reader.Read do
    case Reader.TokenType of
      xttStartElement:
        if Reader.NamespaceUriUtf8 = NsCbc then
        begin
          if Reader.LocalNameUtf8 = 'ID' then
            Number := Reader.ReadElementText   { the text inside }
          else if Reader.LocalNameUtf8 = 'IssueDate' then
            Issued := LandrixXmlParseDate(Reader.ReadElementTextUtf8)
          else if InTotal and (Reader.LocalNameUtf8 = 'PayableAmount') then
            Amount := LandrixXmlParseCurrency(Reader.ReadElementTextUtf8);
        end
        else if (Reader.NamespaceUriUtf8 = NsCac) and
          (Reader.LocalNameUtf8 = 'LegalMonetaryTotal') then
          InTotal := True;
      xttEndElement:
        if Reader.LocalNameUtf8 = 'LegalMonetaryTotal' then
          InTotal := False;
    end;
finally
  Reader.Free;
end;
```

Elements are matched by namespace URI and local name, so the prefixes
used in the document do not matter. `ReadElementText` reads the text of a
simple element up to its end tag: text and CDATA are joined, comments and PIs
are ignored, and a child element raises `xecUnexpectedElement` (the reader stays
on the child, so it can be skipped). `Reader.Skip` skips a whole subtree.
`Reader.ElementPath` gives the path of the current element, such as
`/Invoice/cac:InvoiceLine/cbc:ID`, for messages about skipped elements;
after an `ELandrixXmlError` it still tells in which element the error
occurred.

### Reading GAEB long texts (mixed content) with the DOM

```pascal
Doc := TLandrixXmlDocument.Create;
try
  Doc.LoadFromFile('bill.x86');
  Body := Doc.Root.FindChild(NsGaeb, 'Award').FindChild(NsGaeb, 'BoQ')
    .FindChild(NsGaeb, 'BoQBody');
  Item := Body.FirstChildElement;
  while Item <> nil do
  begin
    Qty := LandrixXmlParseDouble(Item.ChildTextUtf8(NsGaeb, 'Qty'));
    Text := Item.FindDescendant(NsGaeb, 'Text');
    LongText := Text.Text;            { all text of the paragraphs and spans }
    Item := Item.NextSiblingElement;
  end;
finally
  Doc.Free;
end;
```

Text, elements, CDATA sections, comments and processing instructions are
separate child nodes, so formatted long texts (`<p>`, `<span>`, tables)
are kept exactly. `FindChildLocal('Item')` matches the local name in any
namespace. Missing children give `nil`, missing attributes and child texts
an empty string.

### Building and saving a document with the DOM

```pascal
Doc := TLandrixXmlDocument.Create;
try
  Doc.Indent := True;
  Doc.LineBreak := xlbCRLF;
  Root := Doc.AddElement(NsGaeb, '', 'GAEB');
  Item := Root.AddElement('Award').AddElement('Item');
  Item.SetAttribute('ID', '1');
  Item.AddElement('Qty').TextUtf8 := LandrixXmlFormatDouble(12.5, 3);
  Doc.SaveToFile('bill.x86');
finally
  Doc.Free;
end;
```

`AddElement('prefix:name')` resolves the prefix through the declarations in
scope; `AddElement(Uri, Prefix, LocalName)` declares it where needed.

### Errors

```pascal
try
  Doc.LoadFromString('<Invoice><ID>1</Invoice>');
except
  on E: ELandrixXmlError do
    { E.Code = xecSyntax, E.Line = 1, E.Column = 17 (the wrong end tag name) }
end;
```

Every error raises `ELandrixXmlError` with `Code` (`TLandrixXmlErrorCode`),
`Line` and `Column` (1-based, 0 = unknown) and `Offset` (0-based byte offset
in the original file, -1 = unknown). Messages are English diagnostics; use
`Code` to react programmatically. A failed load leaves the document empty.

## Strings

All text is stored internally as UTF-8. Text is available in three forms:

| Accessor | Type | Lossless |
|---|---|---|
| `...Utf8` | `TLandrixXmlUtf8` (`AnsiString` on Delphi 6-2007, `UTF8String` elsewhere) | yes |
| `...W` | `TLandrixXmlWide` (`WideString` on Delphi 6-2007, `UnicodeString` elsewhere) | yes |
| no suffix | native `string` | Delphi 2009+: yes. Delphi 6-2007: converted to the system code page, characters outside it become `?`. Free Pascal: passed through when the code page is UTF-8, otherwise converted by the RTL (on Unix add the `cwstring` unit to your program). |

Names, namespace URIs and other parameters are passed as
`TLandrixXmlUtf8`; string literals work everywhere. Values passed to the
writer and the DOM come in the same three forms (`TextUtf8`, `TextW`,
`Text`).

**Delphi 6 to 2007:** use the `...W` accessors (or `...Utf8`) for text
that may contain characters outside the system code page, e.g. Polish or
Czech names on a German Windows. The native `string` accessors are
convenient but lossy there.

Invalid Unicode (malformed UTF-8, unpaired UTF-16 surrogates) is never
replaced silently; it raises `ELandrixXmlError`.

## Conversion helpers

`LandrixXmlConvert` converts between XML Schema lexical forms and Pascal
values without looking at `DecimalSeparator`, date formats or any other
locale setting. Every type has `LandrixXmlFormatX`, `LandrixXmlParseX`
(raises `ELandrixXmlError` with `xecConversion`) and `LandrixXmlTryParseX`,
and the parsers also take a pointer and a length (`...Buf`).

- `xs:decimal` for `Currency` is exact: `'0.12345'` is rejected unless
  rounding is requested (`AllowRounding = True`). Rounding is half away
  from zero; `LandrixXmlFormatCurrency(1.005, 2)` gives `1.01`.
- `Double` values are parsed correctly rounded for up to 15 significant
  digits and formatted as written (`2.675` with two decimals gives
  `2.68`).
- Dates and times keep their time zone in `TLandrixXmlDateTime`; the
  `TDateTime` variants return the value as written, without converting to
  UTC.

## Limitations

- **No DTD processing.** A `<!DOCTYPE>` is skipped and reported, but not
  checked; entities declared in it are not expanded, and references to them
  are errors. No external entities or DTDs are ever read.
- **Encodings** other than the ones listed above are rejected with a clear
  error.
- **XML 1.1** documents are read with XML 1.0 rules.
- **Nesting depth** is limited to 256 by default (`MaxDepth`).
- **Saving keeps the content, not the bytes:** a document saved from the
  DOM reads back with the same nodes, but quotes, character references and
  line ends may be written differently.
- **White-space dropping** (`WhitespaceMode := xwmDropBetweenElements`) is
  lossy by design: in `<p><span>A</span> <span>B</span></p>` the space
  between the spans is dropped. The default keeps everything. In indented
  files it removes about half of the nodes and a quarter of the memory.

## Conformance and tests

- The [W3C XML conformance test suite](https://www.w3.org/XML/Test/) is
  run with `tools/run-xmlconf.py` and cross-checked against Python's expat:
  1965 applicable tests, 1482 pass, 0 unexplained failures; the rest are
  the documented DTD and encoding decisions. Every accepted test document
  is also written back through the writer and through the DOM and must
  read back unchanged.
- About 135 test cases with more than 9000 checks, including generated
  conversion cases with Python's `decimal` module as an independent oracle.
- Real-world XRechnung, ZUGFeRD and GAEB files (kept locally, not in the
  repository) are round-tripped through the DOM, and damaged copies must be
  rejected cleanly.
- `tools/fuzz.py` derives randomly damaged documents from the test files
  and compares the verdict with expat; every variant must either be read
  or be rejected with `ELandrixXmlError`, and accepted ones must survive
  the writer and DOM round trips. 50,000 variants per run, built with range
  and overflow checking: no crash, no other exception, no unexplained
  difference.

## Performance

Measured with `tools/perf.ps1` on a 47 MB indented GAEB-like document
(3.8 million tokens):

| | Delphi 13 Win64 | Free Pascal 3.2.2 Win64 | Delphi 6 |
|---|---|---|---|
| Pull reader | 0.3 s | 0.5 s | 0.3 s |
| DOM load | 1.1 s | 1.6 s | 1.4 s |
| DOM save | 1.1 s | 1.4 s | 1.1 s |
| Peak memory with the DOM | 448 MB | 445 MB | 320 MB |

The peaks include the generated test document in memory several times
(source, reader input, saved output). The peak of a run with the pull
reader only was about 110 MB, most of it the generated document itself.

## Supported compilers

Tested, also with overflow and range checking enabled:

- Delphi 6, Delphi 7, Delphi 13 (Win32 and Win64); Delphi 13 macOS ARM64
  compiles without warnings (not run)
- Free Pascal 3.2.2 on Windows (i386, x86_64), Linux (aarch64; x86_64 in
  CI)
- Free Pascal 3.2.4 on Linux (aarch64) and macOS (aarch64)
- Free Pascal 3.3.1 on Windows (aarch64) and Linux (aarch64)

Delphi 2007 and Delphi 2009 to 12 are expected to work but are not tested.

## Building the tests

```powershell
./tools/build.ps1          # minimum set: FPC 3.2.2, Delphi 6, Delphi 13 Win32
./tools/build.ps1 all      # every local toolchain
```

Or directly with Free Pascal:

```bash
mkdir -p build/fpc
fpc -B -Fusource -Fisource -FUbuild/fpc -FEbuild/fpc tests/LandrixXmlTests.dpr
./build/fpc/LandrixXmlTests
```

## License

MIT, see [LICENSE](LICENSE).
