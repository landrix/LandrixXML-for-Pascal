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
| `LandrixXmlDouble` | `xs:double` and `xs:float` in software (IEEE 754 bit pattern, Saxon-compatible string value), optional validation unit |
| `LandrixXmlRegex` | XSD and XPath regular expressions, linear-time matching, optional validation unit |
| `LandrixXmlUnicode` | Unicode 6.2.0 general categories, code point strings, optional validation unit |
| `LandrixXmlNormalize` | Unicode normalization NFC, NFD, NFKC, NFKD (Unicode 15.0.0), optional validation unit |
| `LandrixXmlXsdTypes` | XML Schema simple types and facets, optional validation unit |
| `LandrixXmlXsdContent` | XML Schema content models (sequence, choice, occurrence bounds, wildcards), optional validation unit |
| `LandrixXmlXsdSchema` | loaded XML Schema components, optional validation unit |
| `LandrixXmlXsdSchemaLoader` | loads XML Schema documents (include, import, redefine), optional validation unit |
| `LandrixXmlXsdValidator` | validates documents (reader or DOM) against a loaded schema, optional validation unit |
| `LandrixXmlXPathTree` | read-only document tree for XPath (from reader or DOM), optional validation unit |
| `LandrixXmlXPath` | XPath 2.0 parser (the subset the e-invoice rule sets use), optional validation unit |
| `LandrixXmlXPathEval` | evaluates XPath 2.0 expressions on the tree, as XPath 2.0 specifies or as Saxon HE runs them (two profiles), optional validation unit |
| `LandrixXmlSchematron` | Schematron validation (EN16931, XRechnung, Peppol BIS, Factur-X), SVRL output, optional validation unit |
| `LandrixXmlSchematronCompiler` | compiles ISO Schematron (`.sch`) into rule files, optional validation unit |
| `LandrixXmlSha256` | SHA-256, used for the source fingerprint of compiled rules |

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
      else
        { text, comments, ...: nothing to do }
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

### Validating with Schematron

```pascal
Rules := TLandrixXmlSchematronRules.Create;
try
  Rules.LoadFromSchematronFile('EN16931-UBL-validation.sch');
  Validator := TLandrixXmlSchematronValidator.Create(Rules);
  try
    Valid := Validator.ValidateFile('invoice.xml');
    for I := 0 to Validator.ResultCount - 1 do
      WriteLn(Validator.Results[I].Id, ' ', Validator.Results[I].Flag, ' ',
        Validator.Results[I].Location, ': ', Validator.Results[I].Message);
    Validator.SaveSvrlToFile('invoice.svrl');   { optional }
  finally
    Validator.Free;
  end;
finally
  Rules.Free;
end;
```

ISO Schematron with the `xslt2` query binding is compiled when it is
loaded (`LoadFromSchematronFile`); `tools/sch-compile.py` or
`TLandrixXmlSchematronCompiler` can also compile it once into a rule file
for `LoadFromFile`. A validation ends in one of four ways:

| Outcome | How it shows |
|---|---|
| valid | `ValidateFile` returns `True`. `Results` may still hold failed asserts and reports flagged `warning` or `information`. |
| invalid | `False`, `Incomplete = False`: at least one failed assert or successful report with another flag (`fatal`, `error`, none). |
| incomplete | `False`, `Incomplete = True`: an expression raised a dynamic error (an invalid cast, a type error), shown as a result of kind `xsrDynamicError` with `ErrorCode`. The other rules were still checked. Saxon, and so the KoSIT validator, stops with no result here; `AbortOnDynamicError := True` stops at the first error too. |
| not checked | the document is not well-formed: `ValidateFile` raises `ELandrixXmlError` as the DOM does, and there are no results. |

A Schematron file that does not compile raises `ELandrixXmlError`:
`xecSchema` for invalid Schematron, `xecUnsupported` for a construct the
compiler does not implement (it is never ignored), an XPath error for an
expression, each with file and line; the reader's errors for malformed
XML; a file that cannot be opened raises the RTL's stream error. A loaded
`TLandrixXmlSchematronRules` is read-only and can be shared by validators
in several threads; each validator belongs to one thread.

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

### XML Schema: Xerces, not the letter of the specification

For the constructs it supports (the others are rejected as unsupported,
see the W3C XML Schema Test Suite below), the XML Schema validator aims at
the results of Xerces in the Java runtime, the validator behind the KoSIT
and Mustang validators: the same verdicts, error codes, messages and
order. Where Xerces departs from XML Schema 1.0 or from the expectations
of the W3C XML Schema Test Suite, LandrixXml follows Xerces on purpose,
so that a document gets the same verdict as with the official
validators. A profile that follows the specification instead may be
added as an option later; there is none yet. The known cases (with the
test suite's names; in the source code each place is marked with a
comment `Xerces deviation:` and these names, and every new case gets
both the mark and an entry here):

- Name characters of `Name`, `NCName`, `ID`, `IDREF` and `NMTOKEN` are
  those of XML 1.0 Fourth Edition, as in Xerces; the suite's XML 1.1 /
  Fifth Edition tests expect the newer ones (`xv001`, `xv002`, `xv004`,
  `xv009`).
- `gMonth` also accepts the form `--MM--` of XML Schema 1.0 before its
  errata, also in facet values (`gMonth_pattern001_1274`,
  `gMonth_enumeration002_203`, `gMonth_maxInclusive002_205`,
  `gMonth_maxExclusive002_208`, `gMonth_minInclusive002_210`,
  `gMonth_minExclusive002_213`, `gMonth_enumeration001_1275`,
  `gMonth_enumeration002_1276`, `gMonth_enumeration003_1277`,
  `gMonth_enumeration004_1278`, `gMonth_maxInclusive001_1279`,
  `gMonth_maxInclusive002_1280`, `gMonth_maxInclusive003_1281`,
  `gMonth_maxExclusive001_1282`, `gMonth_maxExclusive002_1283`,
  `gMonth_maxExclusive003_1284`, `gMonth_minInclusive001_1285`,
  `gMonth_minInclusive002_1286`, `gMonth_minInclusive003_1287`,
  `gMonth_minInclusive004_1288`, `gMonth_minInclusive005_1289`,
  `gMonth_minExclusive001_1290`, `gMonth_minExclusive002_1291`,
  `gMonth_minExclusive003_1292`, `gMonth_minExclusive004_1293`,
  `gMonth_minExclusive005_1294`).
- An exclusive bound only has to be a valid value of the base type, so
  `maxExclusive="1"` on `positiveInteger` is accepted though no value is
  left (`positiveInteger_maxExclusive001_1834`,
  `positiveInteger_maxExclusive002_1835`).
- An `xs:import` with `namespace=""` is accepted (`schZ014_a`,
  `schZ014_b`).
- An `IDREF`/`IDREFS` attribute value supplied by a default or fixed
  value of the schema is not checked as a reference, and a key field that
  selects an attribute matched by a lax or skip wildcard is accepted
  (`idZ012`, `idZ015`).
- A field `@*` matches the first attribute of an element only, so an
  element with two attributes (one of them `xsi:nil`) gives one value
  (`idL100`).
- An element whose content model is an empty `xs:choice` may be empty
  (`complex022`).
- A prohibited attribute use with a fixed value (`use="prohibited"
  fixed="37"`) does not allow the attribute, unless an attribute wildcard
  does; the suite expects the attribute with that value to be valid under
  XML Schema 1.0 (`attP031`).
- The regular expression forms `\p{IsHighSurrogates}`,
  `\p{IsLowSurrogates}` and `[a-z--[b-z]]` are errors (`reF56`, `reM77`,
  `reN75`, `HighSurrogates`).
- A missing type (also the item type of a list) or substitution group
  head is an error when the schema is loaded, also if nothing uses it;
  the suite expects the error only when the component is needed
  (`missing001`, `missing002`, `missing003`, `missing006`).
- The XSD 1.1 version attributes (`vc:minVersion` and the like) are not
  evaluated, so XSD 1.1 constructs they would exclude are errors (`vc001`,
  `vc002`, `vc024`).
- The XSD 1.1 wildcard attributes `notNamespace` and `notQName` are errors
  (`s3_10_1ii08`, `s3_10_1ii09`, `s3_10_6ii01`, `s3_10_6ii02`, `s3_10_6ii04`).
- A default or fixed value is not allowed on an element whose type is a
  union with an `ID` member, as for `ID` itself (`stE072`); a complex type
  with `ID` content does not count (Xerces never marks one).
- Unique Particle Attribution is checked on the content model as Xerces
  rewrites it: where its validator counts the bounds of an element, the
  element stands for any number of repetitions, so for example a sequence
  of `a` (exactly twice), `a` and a repeated choice is ambiguous, though
  XML Schema 1.0 allows it.
- The `final` of a simple type also forbids the extension by a complex
  type with simple content when it is `#all` or comes from a
  `finalDefault` that names `extension`; XML Schema 1.0 limits the
  `{final}` of simple types to restriction, list and union (no test of
  the suite covers this; in the source code the mark reads
  `Xerces deviation, not in the test suite`).
- A component that two documents redefine (two `xs:redefine` of the
  same document) is an error (`sch-props-correct.2`), as Xerces sees
  two components of the same name; the suite expects the schema to load
  (`schU3`, `schU4`, `schU5`).
- The particles of a restriction are checked as Xerces checks them, so
  some restrictions the suite expects to load are rejected: a sequence
  whose only element has `maxOccurs="0"` stays an empty sequence, which
  cannot restrict an element (`mgE014`); a wildcard in a group that
  restricts a wildcard must fit the occurrence range of that wildcard
  (`particlesHa080`, `particlesHa084`); and an element repeated without
  bound does not restrict a repeated choice of elements that occur once,
  which only XML Schema 1.1 allows (`particlesZ001`).
- Empty content may restrict a complex type with simple content, as
  Xerces compares only the particles; XML Schema 1.0 requires the base
  to have empty or emptiable element content (`particlesZ039`).
- A union that is a member type of another union stands for its own
  member types, so the facets of a restricted union are dropped there
  (no test of the suite covers this; in the source code the mark reads
  `Xerces deviation, not in the test suite`).
- The prefix `xmlns` is bound in QName values, as `xml` is, so
  `xmlns:xsi` is a valid `xs:QName` (`QName009_2092`).
- The versioning attributes of XML Schema 1.1 (`vc:typeAvailable` and
  the like) are not read, so a reference to a type that only XML Schema
  1.1 has (`xs:error`) is an error (`vc014`).
- A restriction that has or inherits a `length` may give `minLength` or
  `maxLength` only if its base type has the same one; the errata of XML
  Schema 1.0 allow more (`errF001`).
- `xs:duration` follows Xerces: the numbers of years, months, days,
  hours and minutes may not exceed 2147483647, seconds may start with the
  point (`PT.5S`), and the order of durations is computed with Xerces'
  arithmetic, whose int sums wrap around and whose quotients are floats,
  so very large durations compare wrongly (62914619 minutes count as
  more than 1048576 hours and 59 minutes, the same duration) (no test
  of the suite covers these; in the source code the mark reads
  `Xerces deviation, not in the test suite`).
- An `xs:time` of 24:00:00 is 00:00:00 of the next day, as Xerces gives
  every time the same placeholder date: it differs from 00:00:00 and
  comes after 23:59:59 (in enumerations, ranges, fixed values and
  identity constraints), and a default or fixed value of 24:00:00
  becomes 00:00:00 (its canonical form); XML Schema 1.0 makes 24:00:00
  the same time of day as 00:00:00. For `xs:dateTime` both agree:
  T24:00:00 equals 00:00:00 of the next day (no test of the suite covers
  this; in the source code the mark reads `Xerces deviation, not in the
  test suite`).
- A value that fails a facet other than pattern is still the value of
  identity constraints (a failed list item gives its own value, or that
  of the item before it; a union no member type matches gives that of
  the last member type that had one), so equal invalid values are
  duplicates; XML Schema gives an invalid value no actual value (no test
  of the suite covers this; in the source code the mark reads
  `Xerces deviation, not in the test suite`).
- `xsi:schemaLocation` and `xsi:noNamespaceSchemaLocation` hints in
  documents are never read: the schema is the one given to the loader, as
  with a preloaded schema in Xerces (the setup of the KoSIT validator), so
  tests that rely on hints fail (`schA1`, `ctL021`, `attgD034`,
  `particlesB013`, ElemDecl `targetNS00101m1_p`,
  `ST_targetNS00101m2_p`).

Differences from Xerces, also on purpose:

- Every `xs:import` of a namespace is loaded; Xerces loads only the first
  one.
- The seconds of dates, times and durations are exact decimals; Xerces
  uses doubles, so values with more than about 15 significant digits may
  compare differently.
- An `xs:ENTITY` value must name an unparsed entity declared in the
  internal subset of the document's DOCTYPE (also through an internal
  parameter entity); the external subset is never
  read (no DTD processing), so an entity declared only there is reported
  as undeclared, and attribute defaults of the DTD are not added. The
  internal subset is read when the first ENTITY value is checked: a
  parameter entity that refers to itself raises `xecSyntax`, one that
  nests deeper than 64 levels or expands to more than 1 MiB `xecLimit`.
- The loader checks each schema document against the schema for schemas
  (attributes, their values, children and their order) and the facets of
  each simple type against each other and against its base type (as
  Xerces, also fixed facets), Unique Particle Attribution of content
  models, the rules of element and attribute declarations (value
  constraints, ID types, consistent element types) and of type
  derivations (`final`, the content types of extensions and restrictions,
  the attributes, attribute wildcards and particles of restrictions) and
  of references, imports and redefinitions; schemas that Xerces rejects
  for a schema component constraint it does not check may load (the
  target schemas are valid for Xerces).

## Conformance and tests

- The [W3C XML conformance test suite](https://www.w3.org/XML/Test/) is
  run with `tools/run-xmlconf.py` and cross-checked against Python's expat:
  1965 applicable tests, 1482 pass, 0 unexplained failures; the rest are
  the documented DTD and encoding decisions. Every accepted test document
  is also written back through the writer and through the DOM and must
  read back unchanged.
- The [W3C XPath/XQuery test suite QT3](https://github.com/w3c/qt3tests)
  measures how much of XPath 2.0 the evaluator covers (`tools/run-qt3.py`,
  pinned suite revision): of 15,149 applicable XPath 2.0 cases 15,125
  pass (99.8 %) and 9 more raise an error where one is expected, but
  with another code.
  The passing cases are a baseline: the CI fails if one of them stops
  passing. The evaluator has two profiles
  (`TLandrixXmlXPathStaticContext.Profile`): `xppXPath20` (the default)
  follows XPath 2.0 where Saxon, which runs XPath 2.0 rule sets as XPath
  3.1, differs, e.g. `round` with two arguments is an error;
  `xppSaxon` behaves as Saxon in the KoSIT validator and is what the
  Schematron validator uses. Both profiles have a QT3 baseline; the
  differences are tested in `tests/data/xpath/profiles.txt`.
- The [KoSIT XRechnung test suite](https://github.com/itplr-kosit/xrechnung-testsuite)
  (`tools/run-kosit-suite.py`, pinned release 2026-08-31 with the
  matching KoSIT validator configuration): all 86 invoices are validated
  with the UBL or CII XML schema and the EN16931 and XRechnung rule sets
  of the scenario the KoSIT validator chooses. The schema verdict with
  error codes and positions is the KoSIT validator's, and fired rules,
  failed asserts, reports, messages and locations match Saxon with the
  validator's XSLT line by line, for all 86 invoices. All of them are
  schema-valid, so schema errors are not exercised here; the W3C XML
  Schema Test Suite below covers them. The full KoSIT
  report (assessment, custom levels) is not part of this library.
- The [W3C XML Schema Test Suite](https://github.com/w3c/xsdtests)
  (`tools/run-xsts.py`, pinned revision) checks the XML Schema
  validation: of its 39,336 applicable XSD 1.0 tests (schemas that must
  load or be rejected, documents that must be valid or invalid) 39,227
  pass and none uses a construct this library does not support (such a
  construct, a selector with an attribute step before its last step, is
  reported as unsupported, never accepted silently). Of the 106 failures,
  102 are the cases of the list above, where the result of Xerces is
  given on purpose; 3 are XML 1.1 documents, read with the rules of
  XML 1.0 (`xv003`, `xv006`, `xv008`); and one has a schema whose
  verdict the suite itself disputes (`ste110`, a circular union, which
  XML Schema 1.0 and Xerces reject). 3 more stop at the resource limit
  of the content model check. The passing tests are a baseline for the
  CI.
- The XML Schema reference data (simple types, validator cases, content
  models, Unique Particle Attribution, the schema rules in
  `tests/data/xsdschema/rules.txt`) comes from the validator of the Java
  runtime, the one the KoSIT validator uses; `tests/data/xerces-oracle.txt`
  names the runtime. `tools/check-xerces-drift.py --jdk DIR` regenerates
  it with another JDK and reports what changed, so a new Java version
  that changes Xerces' results is noticed.
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

MIT, see [LICENSE](LICENSE). The generated Unicode, XML 1.0 and case
tables and the Xerces-compatible XML Schema validation are derived from
third-party material; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
