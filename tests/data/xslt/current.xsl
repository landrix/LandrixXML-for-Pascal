<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:for-each select="1 to 2"><i v="{current() * 10}"><xsl:value-of select="(5, 6)[. = current() + 4]"/></i></xsl:for-each><xsl:apply-templates/></out></xsl:template>
  <xsl:template match="a[current()/@x = '1']">x1</xsl:template>
</xsl:stylesheet>
