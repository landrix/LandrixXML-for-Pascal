<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:f="urn:f" queryBinding="xslt2" xml:space="preserve">
  <xsl:function name="f:g" as="xs:boolean"><xsl:sequence select="true()"/></xsl:function>
  <pattern id="A"><rule context="a"><assert test="f:g()">b</assert></rule></pattern>
</schema>
