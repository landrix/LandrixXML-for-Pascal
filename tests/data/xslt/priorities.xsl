<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:include href="_order.xsl"/>
  <xsl:template match="/"><out><xsl:apply-templates select="//*"/></out></xsl:template>
  <xsl:template match="element(a)[@x]">a-with-x;</xsl:template>
  <xsl:template match="a">a;</xsl:template>
  <xsl:template match="c">c-main;</xsl:template>
  <xsl:template match="processing-instruction(p)">pi;</xsl:template>
  <xsl:template match="Item">Item;</xsl:template>
  <xsl:template match="item" mode="M">wrong</xsl:template>
  <xsl:template match="item">item;<xsl:apply-templates select="." mode="m"/></xsl:template>
  <xsl:template match="item" mode="m">mode-m;</xsl:template>
  <xsl:template name="Named">N</xsl:template>
  <xsl:template name="named">n</xsl:template>
</xsl:stylesheet>
