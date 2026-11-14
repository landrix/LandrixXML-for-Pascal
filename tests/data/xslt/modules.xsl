<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:import href="_imported.xsl"/>
  <xsl:include href="_included.xsl"/>
  <xsl:variable name="v" select="'main'"/>
  <xsl:template match="/"><out><xsl:value-of select="$v"/>;<xsl:apply-templates select="r/*"/>;<xsl:call-template name="t"/></out></xsl:template>
  <xsl:template match="y" priority="-5">main-y</xsl:template>
  <xsl:template name="t">main-t</xsl:template>
</xsl:stylesheet>
