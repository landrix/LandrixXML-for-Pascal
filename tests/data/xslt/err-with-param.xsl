<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><xsl:call-template name="t"><xsl:with-param name="nope" select="1"/></xsl:call-template></xsl:template>
  <xsl:template name="t"><x/></xsl:template>
</xsl:stylesheet>
