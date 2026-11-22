<?xml version="1.0" encoding="UTF-8"?>
<!-- the simple map operator "!" (XPath 3.0, as Saxon runs it in a 2.0
     stylesheet): in expressions, and in a pattern predicate, where a
     boolean right operand is no number (a failed earlier predicate on a
     sibling does not drop the later ones) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
  <xsl:output method="text"/>
  <xsl:template match="/">
    <xsl:value-of select="r/a ! (@k * 10)"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="tokenize(r/b, ' ') ! upper-case(.)" separator="-"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="count((r, r) ! .)"/>
    <xsl:text>|</xsl:text>
    <xsl:apply-templates select="r/a"/>
    <xsl:text>|</xsl:text>
    <xsl:apply-templates select="r/c"/>
    <xsl:text>|</xsl:text>
    <xsl:apply-templates select="r/d"/>
  </xsl:template>
  <xsl:template match="a[if (@k = '3') then error() else true()][@k ! (. = '4')]">
    <xsl:value-of select="'match', @k"/>
  </xsl:template>
  <xsl:template match="a"/>
  <xsl:template match="c[if (@k = '3') then error() else true()][number(@k) ! (. = 4)]">
    <xsl:value-of select="'match', @k"/>
  </xsl:template>
  <xsl:template match="c"/>
  <xsl:template match="d[if (@k = '3') then error() else true()][number(@k) ! (let $b := . = 4 return $b)][number(@k) ! (. ! (. = 4))][xs:integer(@k) ! remove(true(), .)]">
    <xsl:value-of select="'match', @k"/>
  </xsl:template>
  <xsl:template match="d"/>
</xsl:stylesheet>
