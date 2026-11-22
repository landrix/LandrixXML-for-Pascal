<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:d="urn:doc" queryBinding="xslt2" defaultPhase="some">
  <phase id="some">
    <!-- documentation is not looked into -->
    <d:example><let name="ignored" value="1"/></d:example>
    <active pattern="A"/>
    <include href="parts/phase-let.sch"/>
  </phase>
  <pattern id="A"><rule context="a"><assert test="b">b</assert></rule></pattern>
</schema>
