<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2">
  <ns prefix="f" uri="http://www.w3.org/2005/xpath-functions"/>
  <ns prefix="p" uri="urn:p"/>
  <pattern id="A"><rule context="p:a">
    <assert id="A1" test="f:document('parts/alias-codes.xml')/codes/c = @code">code</assert>
  </rule></pattern>
</schema>
