<?xml version="1.0" encoding="UTF-8"?>
<schema xmlns="http://purl.oclc.org/dsdl/schematron" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:doc="urn:doc" queryBinding="xslt2">
  <title>Small   test
    rules</title>
  <doc:note>documentation is ignored</doc:note>
  <ns prefix="p" uri="urn:p"/>
  <ns prefix="f" uri="urn:f"/>
  <ns prefix="p" uri="urn:p"/>
  <let name="total" value="sum(//p:a/@n)"/>
  <xsl:function name="f:size" as="xs:string">
    <xsl:param name="n"/>
    <xsl:variable name="limit">10</xsl:variable>
    <xsl:variable name="limit-twice" select="for $limit in ($limit, $limit) return $limit"/>
    <xsl:choose>
      <xsl:when test="$n &gt; $limit">
        <xsl:variable name="big" as="xs:string" select="'big'"/>
        <xsl:sequence select="$big"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:sequence select="'small'"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>
  <include href="parts/pattern.sch"/>
  <pattern id="B">
    <doc:note>ignored</doc:note>
    <let name="half" value="$total div 2"/>
    <rule context="p:r">
      <report id="R1" flag="information" role="info" test="$total = 24">total <value-of select="$total"/>,
        half <emph>of <value-of select="$half"/></emph> in <name/></report>
    </rule>
  </pattern>
</schema>
