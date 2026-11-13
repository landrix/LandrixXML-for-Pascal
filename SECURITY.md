# Security policy

## Supported versions

LandrixXml is before 1.0: security fixes go into the latest release
only.

| Version | Supported |
|---|---|
| 0.4.x | yes |
| older | no |

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub:
**Security** tab of this repository, **Report a vulnerability**. Include
the compiler and version, the unit and entry point you call, and a
minimal input that shows the problem (no real invoices or other
personal data).

You will get an answer within a week. A fix is published as a new
release with a security advisory that credits the reporter, unless you
ask otherwise.

## Scope

LandrixXml reads untrusted documents by design, so these count as
vulnerabilities:

- a crash, hang, unbounded memory use or access violation on any input
  to the reader, the DOM, the XML Schema or the Schematron units;
- a document that the reader accepts although it is not well-formed,
  where that changes what an application sees;
- a validation result (XML Schema or Schematron) that accepts a document
  the reference validators (Xerces, Saxon with the KoSIT configuration)
  reject, caused by a defect rather than a documented deviation (README).

By design the library does not expand user-defined entities in document
content, does not read external DTDs or `xsi:schemaLocation` hints and
opens no network connections. To check `xs:ENTITY` values, the XML
Schema validator reads the entity declarations of the internal DTD
subset, including internal parameter entities, with limits on their
nesting and total size. Schemas and Schematron files are trusted input
chosen by the application.
