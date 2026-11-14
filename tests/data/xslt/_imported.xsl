<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:variable name="v" select="'imported'"/>
  <xsl:variable name="only" select="'only-imported'"/>
  <xsl:template match="x">imported-x</xsl:template>
  <xsl:template match="y">imported-y</xsl:template>
  <xsl:template name="t">imported-t</xsl:template>
</xsl:stylesheet>
