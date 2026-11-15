<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0010: xsl:attribute-set contains xsl:attribute only. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:attribute-set name="a">
    <xsl:variable name="v" select="1"/>
    <xsl:attribute name="x" select="$v"/>
  </xsl:attribute-set>
  <xsl:template match="/">
    <out xsl:use-attribute-sets="a"/>
  </xsl:template>
</xsl:stylesheet>
