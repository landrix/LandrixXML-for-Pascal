<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:d="urn:doc" queryBinding="xslt2" defaultPhase="some">
  <phase id="some">
    <!-- documentation is not looked into: E stays inactive -->
    <d:example><active pattern="E"/></d:example>
    <include href="parts/phase-active.sch"/>
  </phase>
  <!-- not active and without rules: no svrl:active-pattern -->
  <pattern id="E"><title>empty</title></pattern>
  <pattern id="A"><rule context="a"><assert test="b">b</assert></rule></pattern>
</schema>
