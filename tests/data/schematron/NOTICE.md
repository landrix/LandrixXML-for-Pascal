# Third-party material in tests/data/schematron

This folder is test data only; nothing here is part of the library.

## Rule files (`rules/`)

Compiled with `tools/gen-schematron-rules.py` (which calls `tools/sch-compile.py`
and checks the result against the KoSIT validator's XSLT with
`tools/sch-crosscheck.py`) from:

| File | Source | Package | License |
|---|---|---|---|
| `en16931-ubl.xml` | `EN16931-UBL-validation-preprocessed.sch` (SHA-256 268d4f7a2688676695e6c69cba6fba69a6802604fee12cb544a6b30ff09555a3) | [en16931-ubl-1.3.16.zip](https://github.com/ConnectingEurope/eInvoicing-EN16931/releases/download/validation-1.3.16/en16931-ubl-1.3.16.zip) (SHA-256 bafada015efbc5248bf5e05ad2191e1d9833ef96e9dd5f4bce420a747342da85) | EUPL-1.2 |
| `en16931-cii.xml` | `EN16931-CII-validation-preprocessed.sch` (SHA-256 54e0dc6d06cd7f17d268bb9696ff56f58d386ee28961c9bbef0a56718c400c89) | [en16931-cii-1.3.16.zip](https://github.com/ConnectingEurope/eInvoicing-EN16931/releases/download/validation-1.3.16/en16931-cii-1.3.16.zip) (SHA-256 1cd53cb8a84d38aedc82c0caede217da983a7934dd663f793a092fd66443c561) | EUPL-1.2 |
| `xrechnung-ubl.xml` | `XRechnung-UBL-validation.sch` with `common.sch` (SHA-256 e143facbe9e6a39cc89d68de0576e81806f21a64830b102250c706a524f35ee6) | [xrechnung-3.0.2-schematron-2.6.0.zip](https://projekte.kosit.org/api/v4/projects/356/packages/maven/de/xeinkauf/xrechnung-3.0.2-schematron/2.6.0/xrechnung-3.0.2-schematron-2.6.0.zip) (SHA-256 ca5e07afd04e72cd283d581590ffff3a15f4aac9d2f40c993345d78e67ea22b4) | Apache-2.0 |
| `xrechnung-cii.xml` | `XRechnung-CII-validation.sch` with `common.sch` (SHA-256 53bb5c0664fc603bbaaddeed26eb59525a05d3359d1a63f148876b2f2eedde1d) | same | Apache-2.0 |

The EN16931 validation artefacts are published by CEN/TC 434 under the
European Union Public Licence (EUPL) version 1.2; the XRechnung Schematron
by the Koordinierungsstelle für IT-Standards (KoSIT) under the Apache License
2.0. The rule files keep the rule texts and identifiers unchanged; they are
a different format of the same rules.

One test is replaced: the EN16931 CII source defines CII-SR-282 twice
(`not(ram:SellerTaxRepresentativeTradeParty/ram:ID)` and
`not(ram:BuyerTaxRepresentativeTradeParty)`); the KoSIT validator runs the
second one, so the rule file has it (with the first as `original`).

## Documents (`ubl/`, `cii/`)

The files without `mut-` prefix are example invoices of the EN16931 packages
above (EUPL-1.2). The `mut-` files are copies of them changed at random
(values, removed and duplicated elements, attributes) to provoke failed
asserts and dynamic errors.

## Expected results (`expected-*.txt`)

Generated with `tools/gen-schematron-testdata.py`: the XSLT of the KoSIT
validator configuration for XRechnung 3.0.2 (SchXslt 1.10.1), run with
Saxon HE 12.9 on each document.
