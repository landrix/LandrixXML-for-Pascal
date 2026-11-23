<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- typed="yes" and an untyped node -->
<xsl:mode name="m:t" typed="yes"/><xsl:template match="doc"><xsl:apply-templates select="a" mode="m:t"/></xsl:template>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
