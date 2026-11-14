<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:variable name="a" select="$b"/><xsl:variable name="b" select="$a"/>
  <xsl:template match="/"><out><xsl:value-of select="$a"/></out></xsl:template>
</xsl:stylesheet>
