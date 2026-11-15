<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE0920: a namespace prefix that is no NCName. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out><xsl:namespace name="{'p:q'}">urn:a</xsl:namespace></out>
  </xsl:template>
</xsl:stylesheet>
