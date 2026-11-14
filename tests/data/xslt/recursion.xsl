<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:call-template name="sum"><xsl:with-param name="n" select="990"/></xsl:call-template></out></xsl:template>
  <xsl:template name="sum"><xsl:param name="n"/><xsl:param name="acc" select="0"/>
    <xsl:choose><xsl:when test="$n = 0"><xsl:value-of select="$acc"/></xsl:when>
    <xsl:otherwise><xsl:call-template name="sum"><xsl:with-param name="n" select="$n - 1"/><xsl:with-param name="acc" select="$acc + $n"/></xsl:call-template></xsl:otherwise></xsl:choose>
  </xsl:template>
</xsl:stylesheet>
