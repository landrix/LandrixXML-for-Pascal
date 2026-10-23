<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:d="urn:documentation" queryBinding="xslt2">
  <d:example><xsl:variable name="v" select="1" static="yes"/></d:example>
  <p class="x" other="y">documentation</p>
  <pattern id="A"><rule context="a"><assert test="true()">b</assert></rule></pattern>
</schema>
