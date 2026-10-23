<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2">
  <let name="f" value="'codes.xml'"/>
  <pattern id="A"><rule context="a"><assert test="document($f)/codes">b</assert></rule></pattern>
</schema>
