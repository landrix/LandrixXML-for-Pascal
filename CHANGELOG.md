# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `LandrixXmlDecimal`: exact decimal arithmetic for `xs:decimal` and
  `xs:integer` with arbitrary precision (add, subtract, multiply, divide,
  `idiv`, `mod`, comparison, rounding modes, Int64 conversion, the digit
  counts of the `totalDigits`/`fractionDigits` facets). Division follows
  Saxon, the XSLT engine of the KoSIT validator, so that sum checks give
  the same results. First building block of the planned XSD and
  Schematron validation; the existing units do not depend on it.
- `LandrixXmlDecimalMultiplyPow10`: exact multiplication by a power of ten.
- `LandrixXmlDouble`: `xs:double` computed in software on the IEEE 754 bit
  pattern (`TLandrixXmlDouble`): arithmetic, `mod`, comparison, rounding,
  parsing with correct rounding, exact conversion to and from `xs:decimal`,
  and the XPath string value with the digits Saxon writes. Results are the
  same on every compiler and CPU and never raise floating-point exceptions.
- `tools/gen-double-testdata.py`: generates the double test cases and
  optionally checks them against Saxon.
- `LandrixXmlRegex`: regular expressions in the XML Schema and XPath
  dialects (`Matches`, `Replace`, `Tokenize`), matched by a Pike VM in
  time linear in the input per match, so untrusted input cannot cause
  catastrophic backtracking. Hyphens in character classes follow XML
  Schema 1.0 in XSD mode (as Xerces) and 1.1 in XPath mode (as Saxon).
  Programs are limited to about 100000 instructions and a nesting depth of 1000
  (`xecLimit`, raised before anything oversized is built).
  Unsupported constructs (flags, back-references, reluctant quantifiers,
  block escapes) raise the new error code `xecUnsupported`, invalid
  patterns the new code `xecRegex`.
- `LandrixXmlUnicode`: Unicode 6.2.0 general categories (the version
  Saxon uses for regular expressions) and code point conversion;
  `tools/gen-unicode-tables.py` generates the table.
- `tools/gen-regex-testdata.py`: regular expression test cases with
  results from Saxon.
- New error code `xecArithmetic` (division by zero, exponent out of range).
- `tools/gen-decimal-testdata.py`: generates the decimal test cases and
  optionally checks them against Saxon.

### Fixed
- Delphi 13 macOS ARM64: no more W1072 warnings where `TStream.Read`
  returns a 64-bit `Longint`.
- Free Pascal on macOS AArch64: no more note about `Move` not being inlined
  in `ElementPath`, which appeared depending on the order units are
  compiled in.

## [0.2.0] - 2026-10-15

### Added
- `TLandrixXmlReader.ReadElementText` (`Utf8`, `W` and native variants):
  reads the text content of a simple element up to its end tag. Text and
  CDATA are joined, comments and processing instructions are ignored. A
  child element raises the new error code `xecUnexpectedElement`; the
  reader stays usable and stands on the child's start tag.
- `TLandrixXmlReader.ElementPath` (`Utf8`, `W` and native variants): the
  path of the current element with qualified names and without indices,
  e.g. `/Invoice/cac:InvoiceLine/cbc:ID`; also available after an error,
  for the element in which it occurred.
- `tools/fuzz.py`: differential fuzzing against expat.

### Changed
- DOM nodes are smaller: text, CDATA and comment nodes take 56 instead of
  112 bytes on Delphi 13 Win64 (48 instead of 104 on Free Pascal Win64),
  elements 88 instead of 112 (80 instead of 104). A loaded indented
  document needs about a third less memory. The public API is unchanged;
  internally, elements, the document, PIs and the DOCTYPE are instances of
  the new descendant `TLandrixXmlContainerNode`, which
  `TLandrixXmlDocument` now derives from, and `TLandrixXmlNode.CreateNode`
  raises `xecInvalidArgument` when class and node type do not fit.

## [0.1.0] - 2026-10-15

First release.

### Added
- `LandrixXml.inc`: central compiler switches for Delphi 6 to Delphi 13 and
  Free Pascal.
- `LandrixXmlBase`: string types `TLandrixXmlUtf8` and `TLandrixXmlWide`,
  strict UTF-8/UTF-16 coding including surrogate pairs, conversions between
  UTF-8, UTF-16 and the native `string`, `ELandrixXmlError` with error code
  and position, and the growable byte buffer `TLandrixXmlBuffer`.
- Dependency-free console test runner (`tests/LandrixXmlTests.dpr`).
- `tools/check-forbidden.py`: checks sources for language features and units
  that Delphi 6 does not support.
- `tools/build.ps1`: builds and runs the tests with all local toolchains.
- GitHub Actions CI with Free Pascal on Linux.
- `LandrixXmlEncoding`: `TLandrixXmlInput` detects the input encoding (byte
  order mark, XML declaration) and normalizes UTF-8, UTF-16 LE/BE,
  ISO-8859-1, Windows-1252, ISO-8859-15 and US-ASCII to UTF-8. Strict by
  default; opt-in repair via `FallbackEncoding` and `Latin1AsWindows1252`.
  Error positions refer to the original bytes. Shared XML declaration
  scanner `LandrixXmlScanDeclaration`.
- `TLandrixXmlBuffer.Extend`.
- Encoding test files generated with Python's codecs as an independent
  oracle (`tools/gen-encoding-testdata.py`).
- `LandrixXmlReader`: pull reader `TLandrixXmlReader` for well-formed XML 1.0
  with namespaces (zero-copy spans plus UTF-8, wide and native accessors,
  `Skip`, lazy line/column, `MaxDepth`), push adapter `TLandrixXmlHandler`.
  DOCTYPE is skipped and reported; DTD entities are not expanded.
- `LandrixXmlWriter`: streaming writer `TLandrixXmlWriter` (UTF-8 output to
  memory, a stream or a file). Automatic XML declaration, optional BOM,
  lexical namespaces with scope checks plus `...Ns` methods that declare
  prefixes automatically, escaping that survives a read-back unchanged,
  errors for characters and constructs that XML 1.0 cannot represent,
  atomic calls (a rejected call changes nothing), optional indentation that
  never touches mixed content, base64 output from buffers and streams.
- `LandrixXmlBase`: XML name checks, FNV-1a hash and base64 encoder shared
  by reader and writer; the namespace constants moved here from the reader.
- The W3C conformance run also copies every accepted document through the
  writer and checks that it reads back identically.
- `LandrixXmlConvert`: locale-independent conversion of xs:decimal
  (Currency exact via its scaled integer, Double correctly rounded up to 15
  significant digits), xs:long/xs:int, xs:boolean, xs:date, xs:dateTime,
  xs:time (parts record with time zone, or TDateTime as written) and the
  CII date formats 102 and 610. Rounding is half away from zero.
- `LandrixXmlBase`: strict base64 decoder into a buffer or a stream, and
  the error code `xecConversion`.
- Conversion test data generated with Python's decimal and struct modules
  as an independent oracle (`tools/gen-convert-testdata.py`).
- `LandrixXmlDom`: document object model `TLandrixXmlDocument` /
  `TLandrixXmlNode` built from the pull reader and saved through the
  streaming writer. Interned names, search by namespace and local name
  (or local name only), mixed content, line and column per node, optional
  dropping of white space between elements, comments and PIs, building
  and moving nodes with namespace handling, subtrees taken over from a
  reader, freeing and saving without recursion.
- The W3C conformance run also loads, saves and reloads every accepted
  document through the DOM.
- README with examples, string strategy, limitations and measurements;
  the examples are compiled and run as `examples/LandrixXmlExamples.dpr`
  (also in CI).
- Performance measurement `tests/LandrixXmlPerf.dpr` with
  `tools/perf.ps1` (times and peak memory for reader and DOM).
- The DOM shares identical white-space text values while loading, which
  lowers the memory of indented documents.
- Real-world test: files placed in the git-ignored `tests/data/local`
  (XRechnung, ZUGFeRD, GAEB) are round-tripped through the DOM, damaged
  copies must be rejected cleanly, and `tools/check-local.py` cross-checks
  the classification with expat.

[Unreleased]: https://github.com/LandrixSoftware/LandrixXML-for-Pascal/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/LandrixSoftware/LandrixXML-for-Pascal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/LandrixSoftware/LandrixXML-for-Pascal/releases/tag/v0.1.0
