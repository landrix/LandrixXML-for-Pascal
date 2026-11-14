<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><xsl:choose><xsl:when test="true()">a</xsl:when><xsl:otherwise>b</xsl:otherwise><xsl:otherwise>c</xsl:otherwise></xsl:choose></xsl:template>
</xsl:stylesheet>
