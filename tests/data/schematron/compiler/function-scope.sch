<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" queryBinding="xslt2">
  <ns prefix="f" uri="urn:f"/>
  <xsl:function name="f:f">
    <xsl:param name="n"/>
    <xsl:choose>
      <xsl:when test="$v = 1">
        <xsl:variable name="v" select="$n"/>
        <xsl:sequence select="true()"/>
      </xsl:when>
      <xsl:otherwise><xsl:sequence select="false()"/></xsl:otherwise>
    </xsl:choose>
  </xsl:function>
</schema>
