<?xml version="1.0" encoding="UTF-8"?>
<!-- XPTY0004: the second argument of document() is no single node. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out><xsl:copy-of select="document('x.xml', (/, /))"/></out>
  </xsl:template>
</xsl:stylesheet>
