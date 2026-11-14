<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out><xsl:apply-templates><xsl:with-param name="p" select="'passed'"/></xsl:apply-templates></out></xsl:template>
  <xsl:template match="b"><xsl:param name="p" select="'default'"/><b p="{$p}"/></xsl:template>
</xsl:stylesheet>
