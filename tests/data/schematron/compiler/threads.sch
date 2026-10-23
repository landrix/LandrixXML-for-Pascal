<?xml version="1.0" encoding="UTF-8"?>
<!-- Schematron.Threads: the string value of elements with several text
     nodes in an embedded document, once per context node -->
<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2">
  <pattern id="mixed">
    <rule context="a">
      <assert id="T1" test="string(document('parts/mixed.xml')/r/v[@k = current()/@k]) = 'ABC'">value <value-of select="document('parts/mixed.xml')/r/v[@k = current()/@k]"/></assert>
    </rule>
  </pattern>
</schema>
