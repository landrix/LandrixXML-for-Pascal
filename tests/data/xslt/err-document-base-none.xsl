<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE1162: the base node has no base URI to resolve a relative URI. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <xsl:variable name="t" as="text()"><xsl:text>x</xsl:text></xsl:variable>
    <out><xsl:copy-of select="document('x.xml', $t)"/></out>
  </xsl:template>
</xsl:stylesheet>
