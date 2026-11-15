<?xml version="1.0" encoding="UTF-8"?>
<!-- xml:base in a stylesheet: the static base URI of the instructions
     below it (static-base-uri(), resolve-uri()), nested and relative
     values, the base URI of a temporary tree (the instruction that makes
     it), an xml:base copied with a literal result element. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xml:base="http://example.org/a/">
  <xsl:template match="/">
    <out>
      <static><xsl:value-of select="static-base-uri()"/></static>
      <resolved><xsl:value-of select="resolve-uri('x.xml')"/></resolved>
      <nested xml:base="b/"><xsl:value-of select="static-base-uri()"/></nested>
      <xsl:call-template name="inner"/>
      <xsl:variable name="tree" xml:base="http://example.com/t/"><t/></xsl:variable>
      <tree><xsl:value-of select="base-uri($tree)"/></tree>
      <copied><xsl:value-of select="base-uri(($tree/t, .)[1])"/></copied>
    </out>
  </xsl:template>
  <xsl:template name="inner" xml:base="../c/">
    <inner><xsl:value-of select="static-base-uri(), resolve-uri('y')"/></inner>
  </xsl:template>
</xsl:stylesheet>
