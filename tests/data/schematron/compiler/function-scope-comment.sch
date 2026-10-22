<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" queryBinding="xslt2">
  <ns prefix="f" uri="urn:f"/>
  <xsl:function name="f:f">
    <xsl:choose>
      <xsl:when test="(: ' :) $v = 7">
        <xsl:variable name="v" select="7"/>
        <xsl:sequence select="true()"/>
      </xsl:when>
      <xsl:otherwise><xsl:sequence select="false()"/></xsl:otherwise>
    </xsl:choose>
  </xsl:function>
</schema>
