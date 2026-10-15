# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
