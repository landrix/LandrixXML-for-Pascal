<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:comment select="'a--b-'"/><xsl:processing-instruction name="p" select="'x?>y'"/><xsl:comment>--</xsl:comment></out></xsl:template>
</xsl:stylesheet>
