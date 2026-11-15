<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0910: xsl:namespace with select and content. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out><xsl:namespace name="p" select="'urn:a'">urn:b</xsl:namespace></out>
  </xsl:template>
</xsl:stylesheet>
