<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE0925: the xml prefix with another namespace. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out><xsl:namespace name="xml">urn:a</xsl:namespace></out>
  </xsl:template>
</xsl:stylesheet>
