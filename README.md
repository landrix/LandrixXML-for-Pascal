# LandrixXML for Pascal

A small, fast and dependency-free XML library (parser, DOM, writer) for
**Delphi 6 through Delphi 13** and **Free Pascal 3.2+**.

> **Status:** early development. The base layer (string types, UTF-8
> handling, buffer, error class) is in place; the parser, DOM and writer are
> being built. The API is not stable yet.

## Goals

- No dependencies: only `SysUtils`, `Classes` and `Contnrs`.
- One code base for Ansi Delphi (6 to 2007), Unicode Delphi (2009 to 13,
  Win32 and Win64) and Free Pascal (Windows, Linux, macOS).
- Well-formed XML 1.0 with namespaces and mixed content, a SAX-style reader,
  a DOM and a streaming writer.
- Safe by default: no DTD processing, no external entities, no network
  access, nesting depth limit.
- Locale-independent conversion helpers for `xs:decimal`, `xs:date`,
  `xs:dateTime` and `xs:boolean`.

## Strings

All text is stored internally as UTF-8. Every text property is available in
three forms:

| Accessor | Type | Lossless |
|---|---|---|
| `...Utf8` | `TLandrixXmlUtf8` (`AnsiString` on Delphi 6-2007, `UTF8String` elsewhere) | yes |
| `...W` | `TLandrixXmlWide` (`WideString` on Delphi 6-2007, `UnicodeString` elsewhere) | yes |
| no suffix | native `string` | Delphi 2009+: yes. Delphi 6-2007: converted to the system code page, characters outside it become `?`. Free Pascal: passed through when the code page is UTF-8, otherwise converted by the RTL (on Unix add the `cwstring` unit to your program). |

Invalid Unicode (malformed UTF-8, unpaired UTF-16 surrogates) is never
replaced silently; it raises `ELandrixXmlError`.

## Errors

All errors raise `ELandrixXmlError` with `Code`, `Line`, `Column` (1-based,
0 = unknown) and `Offset` (0-based byte offset in the original input,
-1 = unknown). Messages are English diagnostics; use `Code` to react
programmatically.

## Supported compilers

Tested: Delphi 6, Delphi 7, Delphi 13 (Win32, Win64), Free Pascal 3.2.2,
3.2.4 and 3.3.1 on Windows (i386, x86_64, aarch64), Linux (aarch64, x86_64
in CI) and macOS (aarch64).

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
