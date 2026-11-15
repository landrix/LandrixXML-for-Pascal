<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE0420: a namespace node in a document node. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <xsl:variable name="v"><xsl:namespace name="p">urn:a</xsl:namespace></xsl:variable><out><xsl:copy-of select="$v"/></out>
  </xsl:template>
</xsl:stylesheet>
