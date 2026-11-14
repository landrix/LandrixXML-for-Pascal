<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:import href="_d1.xsl"/>
  <xsl:import href="_d2.xsl"/>
  <xsl:template match="/"><out><xsl:value-of select="$common, $d1, $d2"/></out></xsl:template>
</xsl:stylesheet>
