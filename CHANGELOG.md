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
