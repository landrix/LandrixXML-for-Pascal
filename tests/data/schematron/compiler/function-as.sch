<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" queryBinding="xslt2">
  <ns prefix="f" uri="urn:f"/>
  <xsl:function name="f:f">
    <xsl:variable name="v" as=""><xsl:sequence select="1"/></xsl:variable>
    <xsl:sequence select="$v"/>
  </xsl:function>
</schema>
