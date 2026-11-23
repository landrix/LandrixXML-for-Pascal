<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- on-multiple-match="fail" for xsl:apply-imports -->
<xsl:import href="_mode-multiple-imported.xsl"/>
<xsl:mode on-multiple-match="fail"/>
<xsl:template match="a"><A/><xsl:apply-imports/></xsl:template>
<xsl:template match="doc"><xsl:apply-templates select="a"/></xsl:template>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
