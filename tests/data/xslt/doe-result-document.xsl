<?xml version="1.0" encoding="UTF-8"?>
<!-- raw text in the principal result made by xsl:result-document -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <xsl:result-document><out>a<xsl:text disable-output-escaping="yes">&lt;p/&gt;</xsl:text>b<xsl:value-of select="'&amp;'"/></out></xsl:result-document>
  </xsl:template>
</xsl:stylesheet>
