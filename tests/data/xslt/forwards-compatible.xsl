<?xml version="1.0" encoding="UTF-8"?>
<!-- forwards compatible processing (a version above 3.0): an unknown
     declaration is ignored with its content, an unknown instruction runs
     its xsl:fallback, unknown attributes of XSLT elements are ignored;
     the version of an inner element or of a literal result element
     (xsl:version) decides -->
<xsl:stylesheet version="4.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:frobnicate expand-text="yes" foo="1"><xsl:bogus/><xsl:value-of select="1 +"/></xsl:frobnicate>
  <xsl:output method="xml" frob="1"/>
  <xsl:decimal-format frob="a" pattern-separator=";"/>
  <xsl:template match="/" newattr="1" xsl:foo="bar">
    <out>
      <a><xsl:newthing><xsl:fallback>fallback</xsl:fallback></xsl:newthing></a>
      <b><xsl:value-of select="1" foo="bar"/><xsl:number value="3" frob="x"/></b>
      <c><xsl:if test="false()"><xsl:newer><xsl:fallback/></xsl:newer></xsl:if></c>
      <d xsl:version="2.0"><xsl:value-of select="'2.0 inside'"/></d>
      <e><xsl:new><xsl:value-of select="1 +"/><xsl:fallback>only the fallback is compiled</xsl:fallback></xsl:new></e>
      <f><xsl:attribute name="g" use-attribute-sets="none">h</xsl:attribute><xsl:value-of select="format-number(-1, '#;(#)')"/></f>
    </out>
  </xsl:template>
</xsl:stylesheet>
