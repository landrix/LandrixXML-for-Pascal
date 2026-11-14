<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text"/>
  <xsl:template match="/"><xsl:value-of select="'a&lt;b'"/><xsl:text>&#10;</xsl:text><xsl:apply-templates/></xsl:template>
</xsl:stylesheet>
