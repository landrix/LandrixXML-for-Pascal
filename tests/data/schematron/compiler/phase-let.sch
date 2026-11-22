<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2" defaultPhase="some">
  <phase id="some">
    <let name="limit" value="3"/>
    <active pattern="A"/>
  </phase>
  <pattern id="A"><rule context="a"><assert test="b">b</assert></rule></pattern>
</schema>
