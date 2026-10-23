<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2">
  <pattern id="A"><rule context="a"><assert test="b">b</assert></rule></pattern>
  <group id="G"><rule context="b"><assert test="c">c</assert></rule></group>
</schema>
