<?xml version="1.0" encoding="UTF-8"?>
<!-- a name in cdata-section-elements of xsl:result-document that is no QName -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <xsl:result-document cdata-section-elements="a 1b"><out/></xsl:result-document>
  </xsl:template>
</xsl:stylesheet>
