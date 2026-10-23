<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2">
  <pattern id="A"><rule context="a">
    <assert test="document('no-such-file.xml')/codes">b</assert>
  </rule></pattern>
</schema>
